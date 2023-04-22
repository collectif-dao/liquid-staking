// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStorageProviderRegistryClient {
	/**
	 * @notice Return Storage Provider information with `_ownerId`
	 */
	function getStorageProvider(
		uint64 _ownerId
	) external view returns (bool, address, uint64, uint256, uint256, uint256, uint256, uint256, int64);

	/**
	 * @notice Increase collected rewards by Storage Provider
	 * @param _ownerId Storage Provider owner ID
	 * @param _accuredRewards Unlocked portion of rewards, that available for withdrawal
	 * @param _lockedRewards Locked portion of rewards, that not available for withdrawal
	 */
	function increaseRewards(uint64 _ownerId, uint256 _accuredRewards, uint256 _lockedRewards) external;

	/**
	 * @notice Increase used allocation for Storage Provider
	 * @param _ownerId Storage Provider owner ID
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function increaseUsedAllocation(uint64 _ownerId, uint256 _allocated) external;

	/**
	 * @notice Return a boolean flag of Storage Provider activity
	 */
	function isActiveProvider(uint64 _ownerId) external view returns (bool);

	/**
	 * @notice Return a boolean flag whether `_pool` is active or not
	 */
	function isActivePool(address _pool) external view returns (bool);

	/**
	 * @notice Return a restaking information for a storage provider
	 */
	function restakings(uint64 ownerId) external view returns (uint256, address);
}
