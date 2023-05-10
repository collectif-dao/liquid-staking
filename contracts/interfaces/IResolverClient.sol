// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IResolverClient {
	/**
	 * @notice Returns an address of a Storage Provider Registry contract
	 */
	function getRegistry() external view returns (address);

	/**
	 * @notice Returns an address of a Storage Provider Collateral contract
	 */
	function getCollateral() external view returns (address);

	/**
	 * @notice Returns an address of a Liquid Staking contract
	 */
	function getLiquidStaking() external view returns (address);

	/**
	 * @notice Returns an address of a Storage Provider Collateral contract
	 */
	function getBigInts() external view returns (address);

	/**
	 * @notice Returns an address of a Liquid Staking Controller contract
	 */
	function getLiquidStakingController() external view returns (address);
}
