// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface ILiquidStaking {
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

	/**
	 * @notice Emitted when registry address is updated
	 * @param registry StorageProviderRegistry contract address
	 */
	event SetRegistryAddress(address indexed registry);

	/**
	 * @notice Stake FIL to the Liquid Staking pool and get clFIL in return
	 * native FIL is wrapped into WFIL and deposited into LiquidStaking
	 *
	 * @notice msg.value is the amount of FIL to stake
	 */
	function stake() external payable returns (uint256 shares);

	/**
	 * @notice Unstake wFIL from the Liquid Staking pool and burn clFIL tokens
	 * @param shares Total clFIL amount to burn (unstake)
	 * @dev Please note that unstake amount has to be clFIL shares (not wFIL assets)
	 */
	function unstake(uint256 shares) external returns (uint256 assets);

	/**
	 * @notice Unstake wFIL from the Liquid Staking pool and burn clFIL tokens
	 * @param assets Total FIL amount to unstake
	 */
	function unstakeAssets(uint256 assets) external returns (uint256 shares);

	/**
	 * @notice Pledge FIL assets from liquid staking pool to miner pledge
	 * @param assets Total FIL amount to pledge
	 */
	function pledge(uint256 assets) external;

	/**
	 * @notice Returns pool usage ratio to determine what percentage of FIL
	 * is pledged compared to the total amount of FIL staked.
	 */
	function getUsageRatio() external view returns (uint256);

	/**
	 * @notice Updates StorageProviderCollateral contract address
	 * @param newAddr StorageProviderCollateral contract address
	 */
	function setCollateralAddress(address newAddr) external;

	/**
	 * @notice Returns the amount of WFIL available on the liquid staking contract
	 */
	function totalFilAvailable() external view returns (uint256);

	/**
	 * @notice Updates StorageProviderRegistry contract address
	 * @param newAddr StorageProviderRegistry contract address
	 */
	function setRegistryAddress(address newAddr) external;
}
