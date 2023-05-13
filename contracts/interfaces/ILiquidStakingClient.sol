// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILiquidStakingClient {
	/**
	 * @notice Returns total amount of fees held by LSP for a specific SP with `_ownerId`
	 * @param _ownerId Storage Provider owner ID
	 */
	function totalFees(uint64 _ownerId) external view returns (uint256);

	/**
	 * @notice Returns the total amount of FIL pledged by SPs
	 */
	function totalFilPledged() external view returns (uint256);

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
}
