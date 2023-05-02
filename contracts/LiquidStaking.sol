// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ClFILToken} from "./ClFIL.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {MinerAPI} from "filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import {CommonTypes} from "filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import {MinerTypes} from "filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import {BigInts} from "filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import {FilAddresses} from "filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {FilAddress} from "fevmate/utils/FilAddress.sol";
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
 * performs wrapping of the native FIL into Wrapped Filecoin (WFIL) token.
 */
contract LiquidStaking is ILiquidStaking, ClFILToken, ReentrancyGuard, AccessControl {
	using SafeTransferLib for *;

	/// @notice The current total amount of FIL that is allocated to SPs.
	uint256 public totalFilPledged;
	uint256 private constant BASIS_POINTS = 10000;
	uint256 public adminFee;
	uint256 public baseProfitShare;
	address public rewardCollector;

	IStorageProviderCollateralClient internal collateral;
	IStorageProviderRegistryClient internal registry;

	bytes32 private constant LIQUID_STAKING_ADMIN = keccak256("LIQUID_STAKING_ADMIN");
	bytes32 private constant FEE_DISTRIBUTOR = keccak256("FEE_DISTRIBUTOR");
	bytes32 private constant SLASHING_AGENT = keccak256("SLASHING_AGENT");

	mapping(uint64 => uint256) public profitShares;
	mapping(uint64 => bool) public activeSlashings;

	constructor(
		address _wFIL,
		uint256 _adminFee,
		uint256 _baseProfitShare,
		address _rewardCollector
	) ClFILToken(_wFIL) {
		require(_adminFee <= 10000, "INVALID_ADMIN_FEE");
		require(_rewardCollector != address(0), "INVALID_REWARD_COLLECTOR");
		adminFee = _adminFee;
		baseProfitShare = _baseProfitShare;
		rewardCollector = _rewardCollector;

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		grantRole(LIQUID_STAKING_ADMIN, msg.sender);
		grantRole(FEE_DISTRIBUTOR, msg.sender);
		grantRole(SLASHING_AGENT, msg.sender);
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
	 * @param owner Original owner of clFIL tokens
	 * @dev Please note that unstake amount has to be clFIL shares (not FIL assets)
	 */
	function unstake(uint256 shares, address owner) external nonReentrant returns (uint256 assets) {
		if (msg.sender != owner) {
			uint256 allowed = allowances[owner][msg.sender]; // Saves gas for limited approvals.

			if (allowed != type(uint256).max) allowances[owner][msg.sender] = allowed - shares;
		}

		// Check for rounding error since we round down in previewRedeem.
		require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

		beforeWithdraw(assets, shares);

		_burn(owner, shares);

		emit Unstaked(msg.sender, owner, assets, shares);

		WFIL.withdraw(assets);
		msg.sender.safeTransferETH(assets);
	}

	/**
	 * @notice Unstake FIL from the Liquid Staking pool and burn clFIL tokens
	 * @param assets Total FIL amount to unstake
	 * @param owner Original owner of clFIL tokens
	 */
	function unstakeAssets(uint256 assets, address owner) external nonReentrant returns (uint256 shares) {
		shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

		if (msg.sender != owner) {
			uint256 allowed = allowances[owner][msg.sender]; // Saves gas for limited approvals.

			if (allowed != type(uint256).max) allowances[owner][msg.sender] = allowed - shares;
		}

		beforeWithdraw(assets, shares);

		_burn(owner, shares);

		emit Unstaked(msg.sender, owner, assets, shares);

		WFIL.withdraw(assets);
		msg.sender.safeTransferETH(assets);
	}

	/**
	 * @notice Pledge FIL assets from liquid staking pool to miner pledge for one sector
	 * @param amount Amount of FIL to pledge from Liquid Staking Pool
	 */
	function pledge(uint256 amount) external virtual nonReentrant {
		require(amount <= totalAssets(), "PLEDGE_WITHDRAWAL_OVERFLOW");

		address ownerAddr = FilAddress.normalize(msg.sender); // 0xFf0000000009b4 || 0xEthAddress
		(bool isID, uint64 ownerId) = FilAddress.getActorID(ownerAddr);
		require(isID, "INACTIVE_ACTOR_ID");
		require(!activeSlashings[ownerId], "ACTIVE_SLASHING");

		collateral.lock(ownerId, amount);

		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);
		CommonTypes.FilActorId minerActorId = CommonTypes.FilActorId.wrap(minerId);

		emit Pledge(ownerId, minerId, amount);

		WFIL.withdraw(amount);

		totalFilPledged += amount;

		SendAPI.send(minerActorId, amount); // send FIL to the miner actor
	}

	/**
	 * @notice Withdraw initial pledge from Storage Provider's Miner Actor by `ownerId`
	 * This function is triggered when sector is not extended by miner actor and initial pledge unlocked
	 * @param ownerId Storage provider owner ID
	 * @param amount Initial pledge amount
	 * @dev Please note that pledge amount withdrawn couldn't exceed used allocation by SP
	 */
	function withdrawPledge(uint64 ownerId, uint256 amount) external virtual nonReentrant {
		require(hasRole(FEE_DISTRIBUTOR, msg.sender), "INVALID_ACCESS");
		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);
		CommonTypes.FilActorId minerActorId = CommonTypes.FilActorId.wrap(minerId);

		CommonTypes.BigInt memory withdrawnBInt = MinerAPI.withdrawBalance(minerActorId, BigInts.fromUint256(amount));

		(uint256 withdrawn, bool abort) = BigInts.toUint256(withdrawnBInt);
		require(!abort, "INCORRECT_BIG_NUM");
		require(withdrawn == amount, "INCORRECT_WITHDRAWAL_AMOUNT");

		WFIL.deposit{value: withdrawn}();

		registry.increasePledgeRepayment(ownerId, amount);

		totalFilPledged -= amount;

		collateral.fit(ownerId);

		emit PledgeRepayment(ownerId, minerId, amount);
	}

	/**
	 * @notice Report slashing of SP accured on the Filecoin network
	 * This function is triggered when SP get continiously slashed by faulting it's sectors
	 * @param _ownerId Storage provider owner ID
	 * @param _slashingAmt Slashing amount
	 *
	 * @dev Please note that slashing amount couldn't exceed the total amount of collateral provided by SP.
	 * If sector has been slashed for 42 days and automatically terminated both operations
	 * would take place after one another: slashing report and initial pledge withdrawal
	 * which is the remaining pledge for a terminated sector.
	 */
	function reportSlashing(uint64 _ownerId, uint256 _slashingAmt) external virtual nonReentrant {
		require(hasRole(SLASHING_AGENT, msg.sender), "INVALID_ACCESS");
		(, , uint64 minerId, ) = registry.getStorageProvider(_ownerId);

		collateral.slash(_ownerId, _slashingAmt);

		activeSlashings[_ownerId] = true;

		emit ReportSlashing(_ownerId, minerId, _slashingAmt);
	}

	/**
	 * @notice Report recovery of previously slashed sectors for SP with `_ownerId`
	 * @param _ownerId Storage provider owner ID
	 */
	function reportRecovery(uint64 _ownerId) external virtual nonReentrant {
		require(hasRole(SLASHING_AGENT, msg.sender), "INVALID_ACCESS");
		require(activeSlashings[_ownerId], "NO_ACTIVE_SLASHINGS");
		(, , uint64 minerId, ) = registry.getStorageProvider(_ownerId);

		activeSlashings[_ownerId] = false;

		emit ReportRecovery(_ownerId, minerId);
	}

	struct WithdrawRewardsLocalVars {
		uint256 restakingRatio;
		address restakingAddress;
		uint256 withdrawn;
		bool abort;
		bool isRestaking;
		uint256 protocolFees;
		uint256 stakingProfit;
		uint256 restakingAmt;
		uint256 spShare;
		CommonTypes.FilActorId minerActorId;
		CommonTypes.BigInt withdrawnBInt;
	}

	/**
	 * @notice Withdraw FIL assets from Storage Provider by `ownerId` and it's Miner actor
	 * and restake `restakeAmount` into the Storage Provider specified f4 address
	 * @param ownerId Storage provider owner ID
	 * @param amount Withdrawal amount
	 */
	function withdrawRewards(uint64 ownerId, uint256 amount) external virtual nonReentrant {
		require(hasRole(FEE_DISTRIBUTOR, msg.sender), "INVALID_ACCESS");
		WithdrawRewardsLocalVars memory vars;

		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);
		vars.minerActorId = CommonTypes.FilActorId.wrap(minerId);

		vars.withdrawnBInt = MinerAPI.withdrawBalance(vars.minerActorId, BigInts.fromUint256(amount));

		(vars.withdrawn, vars.abort) = BigInts.toUint256(vars.withdrawnBInt);
		require(!vars.abort, "INCORRECT_BIG_NUM");
		require(vars.withdrawn == amount, "INCORRECT_WITHDRAWAL_AMOUNT");

		uint256 profitShare = profitShares[ownerId];

		vars.stakingProfit = (vars.withdrawn * profitShare) / BASIS_POINTS;
		vars.protocolFees = (vars.withdrawn * adminFee) / BASIS_POINTS;

		(vars.restakingRatio, vars.restakingAddress) = registry.restakings(ownerId);

		vars.isRestaking = vars.restakingRatio > 0 && vars.restakingAddress != address(0);

		if (vars.isRestaking) {
			vars.restakingAmt = (vars.withdrawn * vars.restakingRatio) / BASIS_POINTS;
		}

		vars.spShare = vars.withdrawn - (vars.stakingProfit + vars.protocolFees + vars.restakingAmt);

		WFIL.deposit{value: vars.withdrawn}();
		WFIL.safeTransfer(rewardCollector, vars.protocolFees);

		WFIL.withdraw(vars.spShare);
		SendAPI.send(CommonTypes.FilActorId.wrap(ownerId), vars.spShare);

		registry.increaseRewards(ownerId, vars.stakingProfit);
		collateral.fit(ownerId);

		if (vars.isRestaking) {
			_restake(vars.restakingAmt, vars.restakingAddress);
		}
	}

	/**
	 * @dev Updates profit sharing requirements for SP with `_ownerId` by `_profitShare` percentage
	 * @notice Only triggered by Liquid Staking admin or registry contract while registering SP
	 * @param _ownerId Storage provider owner ID
	 * @param _profitShare Percentage of profit sharing
	 */
	function updateProfitShare(uint64 _ownerId, uint256 _profitShare) external {
		require(hasRole(LIQUID_STAKING_ADMIN, msg.sender) || msg.sender == address(registry), "INVALID_ACCESS");

		if (_profitShare == 0) {
			profitShares[_ownerId] = baseProfitShare;

			emit ProfitShareUpdate(_ownerId, 0, baseProfitShare);
		} else {
			uint256 prevShare = profitShares[_ownerId];
			require(_profitShare <= 10000, "PROFIT_SHARE_OVERFLOW");
			require(_profitShare != prevShare, "SAME_PROFIT_SHARE");

			profitShares[_ownerId] = _profitShare;

			emit ProfitShareUpdate(_ownerId, prevShare, _profitShare);
		}
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
	 * @notice Returns total amount of fees held by LSP for a specific SP with `_ownerId`
	 * @param _ownerId Storage Provider owner ID
	 */
	function totalFees(uint64 _ownerId) external view virtual override returns (uint256) {
		return profitShares[_ownerId] + adminFee;
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
	 * @notice Triggers changeBeneficiary Miner actor call
	 * @param minerId Miner actor ID
	 * @param targetPool LSP smart contract address
	 * @param quota Total beneficiary quota
	 * @param expiration Expiration epoch
	 */
	function forwardChangeBeneficiary(
		uint64 minerId,
		address targetPool,
		uint256 quota,
		int64 expiration
	) external virtual {
		require(msg.sender == address(registry), "INVALID_ACCESS");
		require(targetPool == address(this), "INCORRECT_ADDRESS");

		CommonTypes.FilActorId filMinerId = CommonTypes.FilActorId.wrap(minerId);

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = FilAddresses.fromEthAddress(targetPool);
		params.new_quota = BigInts.fromUint256(quota);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(expiration);

		MinerAPI.changeBeneficiary(filMinerId, params);
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
