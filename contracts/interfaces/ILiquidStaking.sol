// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface ILiquidStaking {
	/**
	 * @notice Emitted when user is staked wFIL to the Liquid Staking
	 * @param user User's address
	 * @param user Original owner of clFIL tokens
	 * @param assets Total wFIL amount unstaked
	 * @param shares Total clFIL amount unstaked
	 */
	event Unstaked(address indexed user, address indexed owner, uint256 assets, uint256 shares);

	/**
	 * @notice Emitted when storage provider is withdrawing FIL for pledge
	 * @param miner Storage Provider address
	 * @param assets Total FIL amount to pledge
	 * @param sectorNumber Sector number to be sealed
	 */
	event Pledge(bytes miner, uint256 assets, uint64 sectorNumber);

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
	 * @param owner Original owner of clFIL tokens
	 * @dev Please note that unstake amount has to be clFIL shares (not wFIL assets)
	 */
	function unstake(uint256 shares, address owner) external returns (uint256 assets);

	/**
	 * @notice Unstake wFIL from the Liquid Staking pool and burn clFIL tokens
	 * @param assets Total FIL amount to unstake
	 * @param owner Original owner of clFIL tokens
	 */
	function unstakeAssets(uint256 assets, address owner) external returns (uint256 shares);

	/**
	 * @notice Pledge FIL assets from liquid staking pool to miner pledge
	 * @param assets Total FIL amount to pledge
	 * @param sectorNumber Sector number to be sealed
	 * @param proof Sector proof for sealing
	 */
	function pledge(uint256 assets, uint64 sectorNumber, bytes memory proof) external;

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
