// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IStorageProviderRegistryClient {
	/**
	 * @notice Get information about storage provider with `_provider` address
	 */
	function getStorageProvider(
		bytes memory _provider
	) external view returns (bool, address, bytes memory, uint256, uint256, uint256, uint256, uint256);

	/**
	 * @notice Increase collected rewards by Storage Provider
	 * @param _provider Storage Provider owner address
	 * @param _accuredRewards Unlocked portion of rewards, that available for withdrawal
	 * @param _lockedRewards Locked portion of rewards, that not available for withdrawal
	 */
	function increaseRewards(bytes memory _provider, uint256 _accuredRewards, uint256 _lockedRewards) external;
}
