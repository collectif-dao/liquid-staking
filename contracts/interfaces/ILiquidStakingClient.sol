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
	 * @notice Triggers changeBeneficiary Miner actor call
	 * @param minerId Miner actor ID
	 * @param targetPool LSP smart contract address
	 * @param quota Total beneficiary quota
	 * @param expiration Expiration epoch
	 */
	function forwardChangeBeneficiary(uint64 minerId, address targetPool, uint256 quota, int64 expiration) external;
}
