// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ClFILToken} from "./ClFIL.sol";
import {Multicall} from "fei-protocol/erc4626/external/Multicall.sol";
import {SelfPermit} from "fei-protocol/erc4626/external/SelfPermit.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {MinerAPI} from "filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import {MinerTypes} from "filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import {SendAPI} from "filecoin-solidity/contracts/v0.8/SendAPI.sol";
import "./libraries/Bytes.sol";

import "./interfaces/ILiquidStaking.sol";
import "./interfaces/IStorageProviderCollateralClient.sol";
import "./interfaces/IStorageProviderRegistryClient.sol";
import "./interfaces/IPledgeOracleClient.sol";

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
contract LiquidStaking is ILiquidStaking, ClFILToken, Multicall, SelfPermit, ReentrancyGuard {
	using SafeTransferLib for *;

	event OwnershipTransferred(address indexed user, address indexed newOwner);

	/// @notice The current total amount of FIL that is allocated to SPs.
	uint256 public totalFilPledged;
	uint256 private constant BASIS_POINTS = 10000;

	IStorageProviderCollateralClient internal collateral;
	IStorageProviderRegistryClient internal registry;
	IPledgeOracleClient internal oracle;

	address public owner;

	constructor(address _wFIL, address _oracle) ClFILToken(_wFIL) {
		oracle = IPledgeOracleClient(_oracle);
		owner = msg.sender;

		emit OwnershipTransferred(address(0), msg.sender);
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
	 * @param sectorNumber Sector number to be sealed
	 * @param proof Sector proof for sealing
	 */
	function pledge(uint64 sectorNumber, bytes memory proof) external virtual nonReentrant {
		uint256 assets = oracle.getPledgeFees();
		require(assets <= totalAssets(), "PLEDGE_WITHDRAWAL_OVERFLOW");

		bytes memory provider = abi.encodePacked(msg.sender);
		collateral.lock(provider, assets);

		(, , bytes memory miner, , , , , ) = registry.getStorageProvider(provider);

		emit Pledge(miner, assets, sectorNumber);

		WFIL.withdraw(assets);

		totalFilPledged += assets;

		SendAPI.send(miner, assets); // send FIL to the miner actor
	}

	/**
	 * @notice Pledge FIL assets from liquid staking pool to miner pledge for multiple sectors
	 * @param sectorNumbers Sector number to be sealed
	 * @param proofs Sector proof for sealing
	 */
	function pledgeAggregate(uint64[] memory sectorNumbers, bytes[] memory proofs) external virtual nonReentrant {
		require(sectorNumbers.length == proofs.length, "INVALID_PARAMS");
		uint256 pledgePerSector = oracle.getPledgeFees();
		uint256 totalPledge = pledgePerSector * sectorNumbers.length;

		require(totalPledge <= totalAssets(), "PLEDGE_WITHDRAWAL_OVERFLOW");

		bytes memory provider = abi.encodePacked(msg.sender);
		collateral.lock(provider, totalPledge);

		(, , bytes memory miner, , , , , ) = registry.getStorageProvider(provider);

		for (uint256 i = 0; i < sectorNumbers.length; i++) {
			emit Pledge(miner, pledgePerSector, sectorNumbers[i]);
		}

		WFIL.withdraw(totalPledge);

		totalFilPledged += totalPledge;

		SendAPI.send(miner, totalPledge); // send FIL to the miner actor
	}

	function withdrawRewards(bytes memory miner, uint256 amount) external virtual nonReentrant {
		MinerTypes.WithdrawBalanceParams memory params;
		params.amount_requested = Bytes.toBytes(amount);

		MinerTypes.WithdrawBalanceReturn memory response = MinerAPI.withdrawBalance(miner, params);

		uint256 withdrawn = Bytes.toUint256(response.amount_withdrawn, 0);
		require(withdrawn == amount, "INCORRECT_WITHDRAWAL_AMOUNT");

		WFIL.deposit{value: withdrawn}();
		// TODO: Increase rewards, recalculate locked rewards
		registry.increaseRewards(miner, withdrawn, 0);
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
		_onlyOwner();
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
		_onlyOwner();
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

	function _onlyOwner() private view {
		require(msg.sender == owner, "UNAUTHORIZED");
	}

	function transferOwnership(address newOwner) public virtual {
		_onlyOwner();
		owner = newOwner;

		emit OwnershipTransferred(msg.sender, newOwner);
	}
}
