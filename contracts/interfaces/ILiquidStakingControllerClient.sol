// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILiquidStakingControllerClient {
	/**
	 * @dev Updates profit sharing requirements for SP with `_ownerId` by `_profitShare` percentage
	 * @notice Only triggered by Liquid Staking admin or registry contract while registering SP
	 * @param _ownerId Storage provider owner ID
	 * @param _profitShare Percentage of profit sharing
	 * @param _pool Address of liquid staking pool
	 */
	function updateProfitShare(uint64 _ownerId, uint256 _profitShare, address _pool) external;

	/**
	 * @notice Returns total amount of fees held by LSP for a specific SP with `_ownerId`
	 * @param _ownerId Storage Provider owner ID
	 * @param _pool Liquid Staking contract address
	 */
	function totalFees(uint64 _ownerId, address _pool) external view returns (uint256);

	/**
	 * @notice Returns profit sharing ratio on Liquid Staking for SP with `_ownerId` at `_pool`
	 * @param _ownerId Storage Provider owner ID
	 * @param _pool Liquid Staking contract address
	 */
	function getProfitShares(uint64 _ownerId, address _pool) external view returns (uint256);

	/**
	 * @notice Returns the admin fees on Liquid Staking
	 */
	function adminFee() external view returns (uint256);

	/**
	 * @notice Returns the base profit sharing ratio on Liquid Staking
	 */
	function baseProfitShare() external view returns (uint256);

	/**
	 * @notice Returns the liquidity cap for Liquid Staking
	 */
	function liquidityCap() external view returns (uint256);

	/**
	 * @notice Returns wether witdrawals are activated
	 */
	function withdrawalsActivated() external view returns (bool);
}
