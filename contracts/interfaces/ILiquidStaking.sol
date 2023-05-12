// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILiquidStaking {
	/**
	 * @notice Emitted when user is staked wFIL to the Liquid Staking
	 * @param user User's address
	 * @param owner Owner of clFIL tokens
	 * @param assets Total wFIL amount staked
	 * @param shares Total clFIL amount staked
	 */
	event Stake(address indexed user, address indexed owner, uint256 assets, uint256 shares);

	/**
	 * @notice Emitted when user is unstaked wFIL from the Liquid Staking
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
	 * @param amount Total FIL amount of repayment
	 */
	event PledgeRepayment(uint256 amount);

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
	 * @notice Restakes `assets` for a specified `target` address
	 * @param assets Amount of assets to restake
	 * @param receiver f4 address to receive clFIL tokens
	 */
	function restake(uint256 assets, address receiver) external returns (uint256 shares);

	/**
	 * @notice Triggered when pledge is repaid on the Reward Collector
	 * @param amount Amount of pledge repayment
	 */
	function repayPledge(uint256 amount) external;

	/**
	 * @notice Returns pool usage ratio to determine what percentage of FIL
	 * is pledged compared to the total amount of FIL staked.
	 */
	function getUsageRatio() external view returns (uint256);

	/**
	 * @notice Returns the amount of WFIL available on the liquid staking contract
	 */
	function totalFilAvailable() external view returns (uint256);

	/**
	 * @notice Returns total amount of fees held by LSP for a specific SP with `_ownerId`
	 * @param _ownerId Storage Provider owner ID
	 */
	function totalFees(uint64 _ownerId) external view returns (uint256);
}
