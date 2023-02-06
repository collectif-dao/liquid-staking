// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStorageProviderRegistry {
	event StorageProviderRegistered(
		bytes provider,
		bytes miner,
		address targetPool,
		uint256 allocationLimit,
		uint256 maxPeriod
	);
	event StorageProviderDeactivated(bytes provider);
	event StorageProviderBeneficiaryAddressUpdated(address _beneficiaryAddress);
	event StorageProviderBeneficiaryAddressAccepted(bytes _provider);
	event StorageProviderMinerAddressUpdate(bytes provider, bytes miner);
	event StorageProviderMaxRedeemablePeriodUpdate(bytes provider, uint256 period);

	event StorageProviderAllocationLimitUpdate(bytes provider, uint256 allocationLimit);
	event StorageProviderAllocationUsed(bytes provider, uint256 usedAllocation);

	event StorageProviderLockedRewards(bytes provider, uint256 rewards);
	event StorageProviderAccruedRewards(bytes provider, uint256 rewards);

	event CollateralAddressUpdated(address collateral);
	event LiquidStakingPoolRegistered(address pool);

	/**
	 * @notice Register storage provider with miner address `_miner` and desired `_allocationLimit`
	 * @param _miner Storage Provider miner address in Filecoin network
	 * @param _targetPool Target pool to work with
	 * @param _allocationLimit FIL allocation for storage provider
	 * @param _period Max redeemable period for FIL allocation
	 */
	function register(bytes memory _miner, address _targetPool, uint256 _allocationLimit, uint256 _period) external;

	/**
	 * @notice Transfer beneficiary address of a miner to the target pool
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 */
	function changeBeneficiaryAddress(address _beneficiaryAddress) external;

	/**
	 * @notice Accept beneficiary address transfer and activate FIL allocation
	 * @param _provider Storage Provider owner address
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 */
	function acceptBeneficiaryAddress(bytes memory _provider, address _beneficiaryAddress) external;

	/**
	 * @notice Deactive storage provider with address `_provider`
	 * @param _provider Storage Provider owner address
	 * @dev Only triggered by owner contract
	 */
	function deactivateStorageProvider(bytes memory _provider) external;

	/**
	 * @notice Update storage provider miner address with `_miner`
	 * @param _provider Storage Provider owner address
	 * @param _miner Storage Provider new miner address
	 * @dev Only triggered by owner contract
	 */
	function setMinerAddress(bytes memory _provider, bytes memory _miner) external;

	/**
	 * @notice Update storage provider FIL allocation with `_allocationLimit`
	 * @param _provider Storage provider owner address
	 * @param _allocationLimit New FIL allocation for storage provider
	 * @dev Only triggered by owner contract
	 */
	function setAllocationLimit(bytes memory _provider, uint256 _allocationLimit) external;

	/**
	 * @notice Update max redeemable period of FIL allocation for `_provider`
	 * @param _provider Storage provider owner address
	 * @param _period New max redeemable period
	 * @dev Only triggered by owner contract
	 */
	function setMaxRedeemablePeriod(bytes memory _provider, uint256 _period) external;

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
		bytes memory _provider
	) external view returns (bool, address, bytes memory, uint256, uint256, uint256, uint256, uint256);

	/**
	 * @notice Return a boolean flag of Storage Provider activity
	 */
	function isActiveProvider(bytes memory _provider) external view returns (bool);

	/**
	 * @notice Increase collected rewards by Storage Provider
	 * @param _provider Storage Provider owner address
	 * @param _accuredRewards Unlocked portion of rewards, that available for withdrawal
	 * @param _lockedRewards Locked portion of rewards, that not available for withdrawal
	 */
	function increaseRewards(bytes memory _provider, uint256 _accuredRewards, uint256 _lockedRewards) external;

	/**
	 * @notice Increase used allocation for Storage Provider
	 * @param _provider Storage Provider owner address
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function increaseUsedAllocation(bytes memory _provider, uint256 _allocated) external;

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
}
