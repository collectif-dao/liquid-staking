// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStorageProviderRegistryClient {
	/**
	 * @notice Return Storage Provider information with `_ownerId`
	 */
	function getStorageProvider(uint64 _ownerId) external view returns (bool, address, uint64, int64);

	/**
	 * @notice Increase collected rewards by Storage Provider
	 * @param _ownerId Storage Provider owner ID
	 * @param _accuredRewards Withdrawn rewards from SP's miner actor
	 */
	function increaseRewards(uint64 _ownerId, uint256 _accuredRewards) external;

	/**
	 * @notice Increase repaid pledge by Storage Provider
	 * @param _ownerId Storage Provider owner ID
	 * @param _repaidPledge Withdrawn initial pledge after sector termination
	 */
	function increasePledgeRepayment(uint64 _ownerId, uint256 _repaidPledge) external;

	/**
	 * @notice Increase used allocation for Storage Provider
	 * @param _ownerId Storage Provider owner ID
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 * @param _timestamp Transaction timestamp
	 */
	function increaseUsedAllocation(uint64 _ownerId, uint256 _allocated, uint256 _timestamp) external;

	/**
	 * @notice Return a boolean flag of Storage Provider activity
	 */
	function isActiveProvider(uint64 _ownerId) external view returns (bool);

	/**
	 * @notice Return a boolean flag if `_ownerId` has registered any miner ids
	 */
	function isActiveOwner(uint64 _ownerId) external view returns (bool);

	/**
	 * @notice Return a boolean flag if `_ownerId` owns the specific `_minerId`
	 */
	function isActualOwner(uint64 _ownerId, uint64 _minerId) external view returns (bool);

	/**
	 * @notice Return a boolean flag whether `_pool` is active or not
	 */
	function isActivePool(address _pool) external view returns (bool);

	/**
	 * @notice Return a restaking information for a storage provider
	 */
	function restakings(uint64 ownerId) external view returns (uint256, address);

	/**
	 * @notice Return allocation information for a storage provider
	 */
	function allocations(uint64 ownerId) external view returns (uint256, uint256, uint256, uint256, uint256, uint256);

	function getAllocations(uint64 _ownerId) external returns (uint256, uint256);

	/**
	 * @notice Return a repayment amount for Storage Provider
	 */
	function getRepayment(uint64 ownerId) external view returns (uint256);

	/**
	 * @notice Return a repayment amount for Storage Provider
	 */
	function storageProviders(uint64 ownerId) external view returns (bool, bool, address, uint64, int64);
}
