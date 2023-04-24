// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILiquidStaking {
	/**
	 * @notice Emitted when user is staked wFIL to the Liquid Staking
	 * @param user User's address
	 * @param owner Original owner of clFIL tokens
	 * @param assets Total wFIL amount unstaked
	 * @param shares Total clFIL amount unstaked
	 */
	event Unstaked(address indexed user, address indexed owner, uint256 assets, uint256 shares);

	/**
	 * @notice Emitted when storage provider is withdrawing FIL for pledge
	 * @param ownerId Storage Provider's owner ID
	 * @param minerId Storage Provider's miner actor ID
	 * @param amount Total FIL amount to pledge
	 */
	event Pledge(uint64 ownerId, uint64 minerId, uint256 amount);

	/**
	 * @notice Emitted when storage provider's pledge is returned back to the LSP
	 * @param ownerId Storage Provider's owner ID
	 * @param minerId Storage Provider's miner actor ID
	 * @param amount Total FIL amount of repayment
	 */
	event PledgeRepayment(uint64 ownerId, uint64 minerId, uint256 amount);

	/**
	 * @notice Emitted when storage provider has been reported to accure slashing
	 * @param ownerId Storage Provider's owner ID
	 * @param minerId Storage Provider's miner actor ID
	 * @param slashingAmount Slashing amount
	 */
	event ReportSlashing(uint64 ownerId, uint64 minerId, uint256 slashingAmount);

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
	 * @notice Pledge FIL assets from liquid staking pool to miner pledge for one or multiple sectors
	 * @param amount Amount of FIL to pledge from Liquid Staking Pool
	 */
	function pledge(uint256 amount) external;

	/**
	 * @notice Withdraw initial pledge from Storage Provider's Miner Actor by `ownerId`
	 * This function is triggered when sector is not extended by miner actor and initial pledge unlocked
	 * @param ownerId Storage provider owner ID
	 * @param amount Initial pledge amount
	 */
	function withdrawPledge(uint64 ownerId, uint256 amount) external;

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
	function reportSlashing(uint64 _ownerId, uint256 _slashingAmt) external;

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
