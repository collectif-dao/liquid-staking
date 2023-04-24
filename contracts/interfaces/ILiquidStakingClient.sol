// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILiquidStakingClient {
	/**
	 * @notice Returns total amount of fees held by LSP
	 */
	function totalFees() external view returns (uint256);
}
