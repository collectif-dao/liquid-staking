// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IStorageProviderRegistry {
	event StorageProviderRegistered(
		address indexed provider,
		address worker,
		address targetPool,
		uint256 allocationLimit,
		uint256 maxPeriod
	);
	event StorageProviderDeactivated(address indexed provider);
	event StorageProviderBeneficiaryAddressUpdated(address _beneficiaryAddress);
	event StorageProviderBeneficiaryAddressAccepted(address _provider);
	event StorageProviderWorkerAddressUpdate(address indexed provider, address worker);
	event StorageProviderMaxRedeemablePeriodUpdate(address indexed provider, uint256 period);

	event StorageProviderAllocationLimitUpdate(address indexed provider, uint256 allocationLimit);
	event StorageProviderAllocationUsed(address indexed provider, uint256 usedAllocation);

	event StorageProviderLockedRewards(address indexed provider, uint256 rewards);
	event StorageProviderAccruedRewards(address indexed provider, uint256 rewards);

	event CollateralAddressUpdated(address collateral);

	/**
	 * @notice Register storage provider with worker address `_worker` and desired `_allocationLimit`
	 * @param _worker Storage Provider worker address in Filecoin
	 * @param _targetPool Target pool to work with
	 * @param _allocationLimit FIL allocation for storage provider
	 * @param _period Max redeemable period for FIL allocation
	 */
	function register(address _worker, address _targetPool, uint256 _allocationLimit, uint256 _period) external;

	/**
	 * @notice Transfer beneficiary address of a miner to the target pool
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 */
	function changeBeneficiaryAddress(bytes memory _beneficiaryAddress) external;

	/**
	 * @notice Accept beneficiary address transfer and activate FIL allocation
	 * @param _provider Storage Provider owner address
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 */
	function acceptBeneficiaryAddress(bytes memory _provider, bytes memory _beneficiaryAddress) external;

	/**
	 * @notice Deactive storage provider with address `_provider`
	 * @param _provider Storage Provider owner address
	 * @dev Only triggered by owner contract
	 */
	function deactivateStorageProvider(address _provider) external;

	/**
	 * @notice Update storage provider worker address with `_worker`
	 * @param _provider Storage Provider owner address
	 * @param _worker Storage Provider new worker address
	 * @dev Only triggered by owner contract
	 */
	function setWorkerAddress(address _provider, address _worker) external;

	/**
	 * @notice Update storage provider FIL allocation with `_allocationLimit`
	 * @param _provider Storage provider owner address
	 * @param _allocationLimit New FIL allocation for storage provider
	 * @dev Only triggered by owner contract
	 */
	function setAllocationLimit(address _provider, uint256 _allocationLimit) external;

	/**
	 * @notice Update max redeemable period of FIL allocation for `_provider`
	 * @param _provider Storage provider owner address
	 * @param _period New max redeemable period
	 * @dev Only triggered by owner contract
	 */
	function setMaxRedeemablePeriod(address _provider, uint256 _period) external;

	/**
	 * @notice Return total number of storage providers in liquid staking
	 */
	function getTotalStorageProviders() external view returns (uint256);

	/**
	 * @notice Return total number of currently active storage providers
	 */
	function getTotalActiveStorageProviders() external view returns (uint256);

	/**
	 * @notice Get information about storage provider with `_provider` address
	 */
	function getStorageProvider(
		address _provider
	) external view returns (bool, address, address, uint256, uint256, uint256, uint256, uint256);

	/**
	 * @notice Return a boolean flag of Storage Provider activity
	 */
	function isActiveProvider(address _provider) external view returns (bool);

	/**
	 * @notice Increase collected rewards by Storage Provider
	 * @param _provider Storage Provider owner address
	 * @param _accuredRewards Unlocked portion of rewards, that available for withdrawal
	 * @param _lockedRewards Locked portion of rewards, that not available for withdrawal
	 */
	function increaseRewards(address _provider, uint256 _accuredRewards, uint256 _lockedRewards) external;

	/**
	 * @notice Increase used allocation for Storage Provider
	 * @param _provider Storage Provider owner address
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function increaseUsedAllocation(address _provider, uint256 _allocated) external;
}
