// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStorageProviderRegistry {
	event StorageProviderRegistered(
		bytes owner,
		uint64 ownerId,
		uint64 minerId,
		address targetPool,
		uint256 allocationLimit,
		uint256 dailyAllocation
	);
	event StorageProviderOnboarded(
		uint64 ownerId,
		uint64 minerId,
		uint256 allocationLimit,
		uint256 dailyAllocation,
		uint256 repayment,
		int64 lastEpoch
	);
	event StorageProviderDeactivated(uint64 ownerId);
	event StorageProviderBeneficiaryAddressUpdated(address beneficiaryAddress);
	event StorageProviderBeneficiaryAddressAccepted(uint64 ownerId);
	event StorageProviderMinerAddressUpdate(uint64 ownerId, uint64 miner);

	event StorageProviderLastEpochUpdate(uint64 ownerId, int64 lastEpoch);

	event StorageProviderAllocationLimitRequest(uint64 ownerId, uint256 allocationLimit);
	event StorageProviderAllocationLimitUpdate(uint64 ownerId, uint256 allocationLimit);
	event StorageProviderAllocationUsed(uint64 ownerId, uint256 usedAllocation);

	event StorageProviderMinerRestakingRatioUpdate(uint64 ownerId, uint256 restakingRatio, address restakingAddress);

	event StorageProviderLockedRewards(uint64 ownerId, uint256 rewards);
	event StorageProviderAccruedRewards(uint64 ownerId, uint256 rewards);

	event CollateralAddressUpdated(address collateral);
	event LiquidStakingPoolRegistered(address pool);

	/**
	 * @notice Register storage provider with `_minerId`, desired `_allocationLimit` and `_targetPool`
	 * @param _minerId Storage Provider miner ID in Filecoin network
	 * @param _targetPool Target liquid staking strategy
	 * @param _allocationLimit FIL allocation for storage provider
	 * @param _dailyAllocation Daily FIL allocation for storage provider
	 * @dev Only triggered by Storage Provider owner
	 */
	function register(
		uint64 _minerId,
		address _targetPool,
		uint256 _allocationLimit,
		uint256 _dailyAllocation
	) external;

	/**
	 * @notice Onboard storage provider with `_minerId`, desired `_allocationLimit`, `_repayment` amount
	 * @param _minerId Storage Provider miner ID in Filecoin network
	 * @param _allocationLimit FIL allocation for storage provider
	 * @param _dailyAllocation Daily FIL allocation for storage provider
	 * @param _repayment FIL repayment for storage provider
	 * @param _lastEpoch Last epoch for FIL allocation utilization
	 * @dev Only triggered by owner contract
	 */
	function onboardStorageProvider(
		uint64 _minerId,
		uint256 _allocationLimit,
		uint256 _dailyAllocation,
		uint256 _repayment,
		int64 _lastEpoch
	) external;

	/**
	 * @notice Transfer beneficiary address of a miner to the target pool
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 */
	function changeBeneficiaryAddress(address _beneficiaryAddress) external;

	/**
	 * @notice Accept beneficiary address transfer and activate FIL allocation
	 * @param _ownerId Storage Provider owner ID
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 * @dev Only triggered by owner contract
	 */
	function acceptBeneficiaryAddress(uint64 _ownerId, address _beneficiaryAddress) external;

	/**
	 * @notice Deactive storage provider with ID `_ownerId`
	 * @param _ownerId Storage Provider owner ID
	 * @dev Only triggered by owner contract
	 */
	function deactivateStorageProvider(uint64 _ownerId) external;

	/**
	 * @notice Update storage provider miner ID with `_minerId`
	 * @param _ownerId Storage Provider owner ID
	 * @param _minerId Storage Provider new miner ID
	 * @dev Only triggered by owner contract
	 */
	function setMinerAddress(uint64 _ownerId, uint64 _minerId) external;

	/**
	 * @notice Request storage provider's FIL allocation update with `_allocationLimit`
	 * @param _allocationLimit New FIL allocation for storage provider
	 * @param _dailyAllocation New daily FIL allocation for storage provider
	 * @dev Only triggered by Storage Provider owner
	 */
	function requestAllocationLimitUpdate(uint256 _allocationLimit, uint256 _dailyAllocation) external;

	/**
	 * @notice Update storage provider FIL allocation with `_allocationLimit`
	 * @param _ownerId Storage provider owner ID
	 * @param _allocationLimit New FIL allocation for storage provider
	 * @param _dailyAllocation New daily FIL allocation for storage provider
	 * @param _repaymentAmount New FIL repayment amount for storage provider
	 * @dev Only triggered by registry admin
	 */
	function updateAllocationLimit(
		uint64 _ownerId,
		uint256 _allocationLimit,
		uint256 _dailyAllocation,
		uint256 _repaymentAmount
	) external;

	/**
	 * @notice Update storage provider's restaking ratio
	 * @param _restakingRatio Restaking ratio for Storage Provider
	 * @param _restakingAddress Restaking address (f4 address) for Storage Provider
	 * @dev Only triggered by Storage Provider
	 */
	function setRestaking(uint256 _restakingRatio, address _restakingAddress) external;

	/**
	 * @notice Return total number of storage providers in liquid staking
	 */
	function getTotalStorageProviders() external view returns (uint256);

	/**
	 * @notice Return total number of currently active storage providers
	 */
	function getTotalActiveStorageProviders() external view returns (uint256);

	/**
	 * @notice Return Storage Provider information with `_ownerId`
	 */
	function getStorageProvider(uint64 _ownerId) external view returns (bool, address, uint64, int64);

	/**
	 * @notice Return a boolean flag of Storage Provider activity
	 */
	function isActiveProvider(uint64 _ownerId) external view returns (bool);

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
	 * @param _timestamp Transaction timestamp
	 */
	function increaseUsedAllocation(uint64 _ownerId, uint256 _allocated, uint256 _timestamp) external;

	/**
	 * @notice Update StorageProviderCollateral smart contract
	 * @param _collateral StorageProviderCollateral smart contract address
	 * @dev Only triggered by owner contract
	 */
	function setCollateralAddress(address _collateral) external;

	/**
	 * @notice Register new liquid staking pool
	 * @param _pool Address of pool smart contract
	 * @dev Only triggered by owner contract
	 */
	function registerPool(address _pool) external;

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
}
