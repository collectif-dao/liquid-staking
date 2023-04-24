// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ClFILToken} from "./ClFIL.sol";
import {Multicall} from "fei-protocol/erc4626/external/Multicall.sol";
import {SelfPermit} from "fei-protocol/erc4626/external/SelfPermit.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {MinerAPI} from "filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import {CommonTypes} from "filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import {BigInts} from "filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import {PrecompilesAPI} from "filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";
import {SendAPI} from "filecoin-solidity/contracts/v0.8/SendAPI.sol";

import "./interfaces/ILiquidStaking.sol";
import "./interfaces/IStorageProviderCollateralClient.sol";
import "./interfaces/IStorageProviderRegistryClient.sol";

/**
 * @title LiquidStaking contract allows users to stake/unstake FIL to earn
 * Filecoin mining rewards. Staked FIL is allocated to Storage Providers (SPs) that
 * perform filecoin storage mining operations. This contract acts as a beneficiary address
 * for each SP that uses FIL capital for pledges.
 *
 * While staking FIL user would get clFIL token in exchange, the token follows ERC4626
 * standard and it's price is recalculated once mining rewards are distributed to the
 * liquid staking pool and once new FIL is deposited. Please note that LiquidStaking contract
 * only works with Wrapped Filecoin (wFIL) token, there for users could use Multicall contract
 * for wrap/unwrap operations.
 *
 * Please use the following multi-call pattern to wrap/unwrap FIL:
 *
 * For Deposits with wrapping:
 *     bytes[] memory data = new bytes[](2);
 *     data[0] = abi.encodeWithSelector(PeripheryPayments.wrapWFIL.selector);
 *     data[1] = abi.encodeWithSelector(LiquidStaking.stake.selector, amount);
 *     router.multicall{value: amount}(data);
 *
 * For Withdrawals with unwrapping:
 *     bytes[] memory data = new bytes[](2);
 *     data[0] = abi.encodeWithSelector(StakingRouter.unstake.selector, amount);
 *     data[1] = abi.encodeWithSelector(PeripheryPayments.unwrapWFIL.selector, amount, address(this));
 *     router.multicall{value: amount}(data);
 */
contract LiquidStaking is ILiquidStaking, ClFILToken, Multicall, SelfPermit, ReentrancyGuard, AccessControl {
	using SafeTransferLib for *;

	/// @notice The current total amount of FIL that is allocated to SPs.
	uint256 public totalFilPledged;
	uint256 private constant BASIS_POINTS = 10000;
	uint256 public adminFee;
	uint256 public profitShare;
	address public rewardCollector;

	IStorageProviderCollateralClient internal collateral;
	IStorageProviderRegistryClient internal registry;

	bytes32 private constant LIQUID_STAKING_ADMIN = keccak256("LIQUID_STAKING_ADMIN");
	bytes32 private constant FEE_DISTRIBUTOR = keccak256("FEE_DISTRIBUTOR");

	constructor(address _wFIL, uint256 _adminFee, uint256 _profitShare, address _rewardCollector) ClFILToken(_wFIL) {
		require(_adminFee <= 10000, "INVALID_ADMIN_FEE");
		require(_rewardCollector != address(0), "INVALID_REWARD_COLLECTOR");
		adminFee = _adminFee;
		profitShare = _profitShare;
		rewardCollector = _rewardCollector;

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		grantRole(LIQUID_STAKING_ADMIN, msg.sender);
		grantRole(FEE_DISTRIBUTOR, msg.sender);
	}

	receive() external payable virtual {}

	fallback() external payable virtual {}

	/**
	 * @notice Stake FIL to the Liquid Staking pool and get clFIL in return
	 * native FIL is wrapped into WFIL and deposited into LiquidStaking
	 *
	 * @notice msg.value is the amount of FIL to stake
	 */
	function stake() external payable nonReentrant returns (uint256 shares) {
		uint256 assets = msg.value;

		// Check for rounding error since we round down in previewDeposit.
		require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

		_wrapWETH9(address(this));

		_mint(msg.sender, shares);

		emit Deposit(msg.sender, msg.sender, assets, shares);

		afterDeposit(assets, shares);
	}

	/**
	 * @notice Unstake FIL from the Liquid Staking pool and burn clFIL tokens
	 * @param shares Total clFIL amount to burn (unstake)
	 * @param _owner Original owner of clFIL tokens
	 * @dev Please note that unstake amount has to be clFIL shares (not FIL assets)
	 */
	function unstake(uint256 shares, address _owner) external nonReentrant returns (uint256 assets) {
		if (msg.sender != _owner) {
			uint256 allowed = allowance[_owner][msg.sender]; // Saves gas for limited approvals.

			if (allowed != type(uint256).max) allowance[_owner][msg.sender] = allowed - shares;
		}

		// Check for rounding error since we round down in previewRedeem.
		require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

		beforeWithdraw(assets, shares);

		_burn(_owner, shares);

		emit Unstaked(msg.sender, _owner, assets, shares);

		WFIL.withdraw(assets);
		msg.sender.safeTransferETH(assets);
	}

	/**
	 * @notice Unstake FIL from the Liquid Staking pool and burn clFIL tokens
	 * @param assets Total FIL amount to unstake
	 * @param _owner Original owner of clFIL tokens
	 */
	function unstakeAssets(uint256 assets, address _owner) external nonReentrant returns (uint256 shares) {
		shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

		if (msg.sender != _owner) {
			uint256 allowed = allowance[_owner][msg.sender]; // Saves gas for limited approvals.

			if (allowed != type(uint256).max) allowance[_owner][msg.sender] = allowed - shares;
		}

		beforeWithdraw(assets, shares);

		_burn(_owner, shares);

		emit Unstaked(msg.sender, _owner, assets, shares);

		WFIL.withdraw(assets);
		msg.sender.safeTransferETH(assets);
	}

	/**
	 * @notice Pledge FIL assets from liquid staking pool to miner pledge for one sector
	 * @param amount Amount of FIL to pledge from Liquid Staking Pool
	 */
	function pledge(uint256 amount) external virtual nonReentrant {
		require(amount <= totalAssets(), "PLEDGE_WITHDRAWAL_OVERFLOW");

		uint64 ownerId = PrecompilesAPI.resolveEthAddress(msg.sender);
		collateral.lock(ownerId, amount);

		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);
		CommonTypes.FilActorId minerActorId = CommonTypes.FilActorId.wrap(minerId);

		emit Pledge(ownerId, minerId, amount);

		WFIL.withdraw(amount);

		totalFilPledged += amount;

		SendAPI.send(minerActorId, amount); // send FIL to the miner actor
	}

	/**
	 * @notice Withdraw FIL assets from Storage Provider by `ownerId` and it's Miner actor
	 * @param ownerId Storage provider owner ID
	 * @param amount Withdrawal amount
	 */
	function withdrawRewards(uint64 ownerId, uint256 amount) external virtual nonReentrant {
		require(hasRole(FEE_DISTRIBUTOR, msg.sender), "INVALID_ACCESS");
		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);
		CommonTypes.FilActorId minerActorId = CommonTypes.FilActorId.wrap(minerId);
		CommonTypes.BigInt memory amountBInt = BigInts.fromUint256(amount);

		CommonTypes.BigInt memory withdrawnBInt = MinerAPI.withdrawBalance(minerActorId, amountBInt);

		(uint256 withdrawn, bool abort) = BigInts.toUint256(withdrawnBInt);
		require(!abort, "INCORRECT_BIG_NUM");
		require(withdrawn == amount, "INCORRECT_WITHDRAWAL_AMOUNT");

		uint256 stakingProfit = (withdrawn * profitShare) / BASIS_POINTS;
		uint256 protocolFees = (withdrawn * adminFee) / BASIS_POINTS;
		uint256 spShare = withdrawn - (stakingProfit + protocolFees);

		WFIL.deposit{value: withdrawn}();
		// TODO: Add UNWRAP from WFIL to FIL operation
		SendAPI.send(CommonTypes.FilActorId.wrap(ownerId), spShare);
		WFIL.safeTransfer(rewardCollector, protocolFees);

		registry.increaseRewards(ownerId, stakingProfit, 0);
	}

	struct WithdrawAndRestakeLocalVars {
		uint256 restakingRatio;
		address restakingAddress;
		uint256 restakingAmt;
		uint256 targetWithdraw;
		uint256 withdrawn;
		bool abort;
		uint256 protocolFees;
		CommonTypes.FilActorId minerActorId;
		CommonTypes.BigInt amountBInt;
		CommonTypes.BigInt withdrawnBInt;
	}

	/**
	 * @notice Withdraw FIL assets from Storage Provider by `ownerId` and it's Miner actor
	 * and restake `restakeAmount` into the Storage Provider specified f4 address
	 * @param ownerId Storage provider owner ID
	 * @param amount Withdrawal amount
	 * @param totalRewards Total amount of rewards accured by SP - profit sharing
	 */
	function withdrawAndRestakeRewards(
		uint64 ownerId,
		uint256 amount,
		uint256 totalRewards
	) external virtual nonReentrant {
		require(hasRole(FEE_DISTRIBUTOR, msg.sender), "INVALID_ACCESS");
		WithdrawAndRestakeLocalVars memory vars;

		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);
		vars.minerActorId = CommonTypes.FilActorId.wrap(minerId);

		(vars.restakingRatio, vars.restakingAddress) = registry.restakings(ownerId);
		require(vars.restakingAddress != address(0), "RESTAKING_NOT_SET");
		vars.restakingAmt = (totalRewards * vars.restakingRatio) / BASIS_POINTS;

		vars.targetWithdraw = amount + vars.restakingAmt;
		vars.amountBInt = BigInts.fromUint256(vars.targetWithdraw);
		vars.withdrawnBInt = MinerAPI.withdrawBalance(vars.minerActorId, vars.amountBInt);

		(vars.withdrawn, vars.abort) = BigInts.toUint256(vars.withdrawnBInt);
		require(!vars.abort, "INCORRECT_BIG_NUM");
		require(vars.withdrawn == vars.targetWithdraw, "INCORRECT_WITHDRAWAL_AMOUNT");

		WFIL.deposit{value: vars.withdrawn}();

		vars.protocolFees = (amount * adminFee) / BASIS_POINTS;
		WFIL.safeTransfer(rewardCollector, vars.protocolFees);

		registry.increaseRewards(minerId, amount, 0);

		_restake(vars.restakingAmt, vars.restakingAddress);
	}

	/**
	 * @notice Restakes `assets` for a specified `target` address
	 * @param assets Amount of assets to restake
	 * @param target f4 address to receive clFIL tokens
	 */
	function _restake(uint256 assets, address target) internal returns (uint256 shares) {
		require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

		_mint(target, shares);

		emit Deposit(target, target, assets, shares);

		afterDeposit(assets, shares);
	}

	/**
	 * @notice Returns total amount of assets backing clFIL, that includes
	 * buffered capital in the pool and pledged capital to the SPs.
	 */
	function totalAssets() public view virtual override returns (uint256) {
		return totalFilAvailable() + totalFilPledged;
	}

	/**
	 * @notice Returns pool usage ratio to determine what percentage of FIL
	 * is pledged compared to the total amount of FIL staked.
	 */
	function getUsageRatio() public view virtual returns (uint256) {
		return (totalFilPledged * BASIS_POINTS) / (totalFilAvailable() + totalFilPledged);
	}

	/**
	 * @notice Updates StorageProviderCollateral contract address
	 * @param newAddr StorageProviderCollateral contract address
	 */
	function setCollateralAddress(address newAddr) public {
		require(hasRole(LIQUID_STAKING_ADMIN, msg.sender), "INVALID_ACCESS");
		collateral = IStorageProviderCollateralClient(newAddr);

		emit SetCollateralAddress(newAddr);
	}

	/**
	 * @notice Returns the amount of WFIL available on the liquid staking contract
	 */
	function totalFilAvailable() public view returns (uint256) {
		return asset.balanceOf(address(this));
	}

	/**
	 * @notice Updates StorageProviderRegistry contract address
	 * @param newAddr StorageProviderRegistry contract address
	 */
	function setRegistryAddress(address newAddr) public {
		require(hasRole(LIQUID_STAKING_ADMIN, msg.sender), "INVALID_ACCESS");
		registry = IStorageProviderRegistryClient(newAddr);

		emit SetRegistryAddress(newAddr);
	}

	/**
	 * @notice Wraps FIL into WFIL and transfers it to the `_recipient` address
	 * @param _recipient WFIL recipient address
	 */
	function _wrapWETH9(address _recipient) internal {
		uint256 amount = msg.value;
		WFIL.deposit{value: amount}();
		WFIL.safeTransfer(_recipient, amount);
	}

	/**
	 * @notice Unwraps `_amount` of WFIL into FIL and transfers it to the `_recipient` address
	 * @param _recipient WFIL recipient address
	 */
	function _unwrapWFIL(address _recipient, uint256 _amount) internal {
		uint256 balanceWETH9 = WFIL.balanceOf(address(this));
		require(balanceWETH9 >= _amount, "Insufficient WETH9");

		if (balanceWETH9 > 0) {
			WFIL.withdraw(_amount);
			_recipient.safeTransferETH(_amount);
		}
	}
}
