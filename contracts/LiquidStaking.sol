// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ClFILToken} from "./ClFIL.sol";
import {Multicall} from "fei-protocol/erc4626/external/Multicall.sol";
import {SelfPermit} from "fei-protocol/erc4626/external/SelfPermit.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned} from "solmate/auth/Owned.sol";
import "./interfaces/IStorageProviderCollateral.sol";
import "./interfaces/IStorageProviderRegistry.sol";

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
contract LiquidStaking is ClFILToken, Multicall, SelfPermit, ReentrancyGuard, Owned {
	using SafeTransferLib for *;

	/**
	 * @notice Emitted when user is staked wFIL to the Liquid Staking
	 * @param user User's address
	 * @param assets Total wFIL amount staked
	 * @param shares Total clFIL amount staked
	 */
	event Staked(address indexed user, uint256 assets, uint256 shares);

	/**
	 * @notice Emitted when user is staked wFIL to the Liquid Staking
	 * @param user User's address
	 * @param assets Total wFIL amount unstaked
	 * @param shares Total clFIL amount unstaked
	 */
	event Unstaked(address indexed user, uint256 assets, uint256 shares);

	/**
	 * @notice Emitted when storage provider is withdrawing FIL for pledge
	 * @param user Storage Provider address
	 * @param assets Total wFIL amount pledged
	 */
	event Pledge(address indexed user, uint256 assets);

	/**
	 * @notice Emitted when collateral address is updated
	 * @param collateral StorageProviderCollateral contract address
	 */
	event SetCollateralAddress(address indexed collateral);

	/// @notice The current total amount of FIL that is allocated to SPs.
	uint256 public totalFilPledged;

	/// @notice The current total amount of FIL that accrued as available rewards.
	uint256 public totalAvailableRewards;

	/// @notice The current total amount of FIL that accrued as locked rewards.
	uint256 public totalLockedRewards;

	uint256 public constant BASIS_POINTS = 10000;

	IStorageProviderCollateral public collateral;
	IStorageProviderRegistry public registry;

	/**
	 * @notice Maps staker's address to the total amount of wFIL staked.
	 * @dev Used to determine the amount of fees to be paid to the Liquid Staking pool
	 */
	mapping(address => uint256) public getTotalFilStaked;

	constructor(address _wFIL) ClFILToken(_wFIL) Owned(msg.sender) {}

	receive() external payable virtual {}

	fallback() external payable virtual {}

	/**
	 * @notice Stake wFIL to the Liquid Staking pool and get clFIL in return
	 * @param assets Total wFIL amount to stake
	 */
	function stake(uint256 assets) external nonReentrant returns (uint256 shares) {
		shares = deposit(assets, msg.sender);

		getTotalFilStaked[msg.sender] += assets;

		emit Staked(msg.sender, assets, shares);
	}

	/**
	 * @notice Unstake wFIL from the Liquid Staking pool and burn clFIL tokens
	 * @param shares Total clFIL amount to burn (unstake)
	 * @dev Please note that unstake amount has to be clFIL shares (not wFIL assets)
	 */
	function unstake(uint256 shares) external nonReentrant returns (uint256 assets) {
		require(shares <= maxRedeem(msg.sender), "INVALID_SHARES_AMOUNT");
		assets = previewRedeem(shares);

		redeem(shares, msg.sender, msg.sender);

		getTotalFilStaked[msg.sender] -= assets;

		emit Unstaked(msg.sender, assets, shares);
	}

	/**
	 * @notice Unstake wFIL from the Liquid Staking pool and burn clFIL tokens
	 * @param assets Total FIL amount to unstake
	 */
	function unstakeAssets(uint256 assets) external nonReentrant returns (uint256 shares) {
		require(assets <= maxWithdraw(msg.sender), "INVALID_ASSETS_AMOUNT");
		shares = previewWithdraw(assets);

		withdraw(assets, msg.sender, msg.sender);

		getTotalFilStaked[msg.sender] -= assets;

		emit Unstaked(msg.sender, assets, shares);
	}

	/**
	 * @notice Pledge FIL assets from liquid staking pool to miner pledge
	 * @param assets Total FIL amount to pledge
	 */
	function pledge(uint256 assets) external nonReentrant {
		require(assets <= totalAssets(), "PLEDGE_WITHDRAWAL_OVERFLOW");
		collateral.lock(msg.sender, assets);

		emit Pledge(msg.sender, assets);

		WFIL.withdraw(assets);

		totalFilPledged += assets;

		msg.sender.safeTransferETH(assets);

		// TODO: add prove commit sector logic for pledge operation
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
	function setCollateralAddress(address newAddr) public onlyOwner {
		collateral = IStorageProviderCollateral(newAddr);

		emit SetCollateralAddress(newAddr);
	}

	/**
	 * @notice Returns the amount of WFIL available on the liquid staking contract
	 */
	function totalFilAvailable() public view returns (uint256) {
		return asset.balanceOf(address(this));
	}

	/**
	 * @notice Updates StorageProviderCollateral contract address
	 * @param newAddr StorageProviderCollateral contract address
	 */
	function setRegistryAddress(address newAddr) public onlyOwner {
		registry = IStorageProviderRegistry(newAddr);

		emit SetCollateralAddress(newAddr);
	}
}
