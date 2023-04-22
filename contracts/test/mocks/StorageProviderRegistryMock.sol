// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../StorageProviderRegistry.sol";
import {MinerMockAPI as MockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {FilAddresses} from "filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Storage Provider Registry Mock contract that works with mock Filecoin Miner API
 * @author Collective DAO
 */
contract StorageProviderRegistryMock is StorageProviderRegistry, MockAPI {
	using Counters for Counters.Counter;
	using Address for address;

	bytes32 private constant REGISTRY_ADMIN = keccak256("REGISTRY_ADMIN");
	uint64 public ownerId;
	uint64 public sampleSectorSize = 32 << 30;

	/**
	 * @dev Contract constructor function.
	 * @param _maxStorageProviders Number of maximum storage providers allowed to use liquid staking
	 * @param _maxAllocation Number of maximum FIL allocated to a single storage provider
	 * @param _minTimePeriod Minimal time period for storage provider allocation
	 * @param _minTimePeriod Maximum time period for storage provider allocation
	 *
	 */
	constructor(
		bytes memory _minerOwner,
		uint64 _ownerId,
		uint256 _maxStorageProviders,
		uint256 _maxAllocation,
		uint256 _minTimePeriod,
		uint256 _maxTimePeriod
	)
		StorageProviderRegistry(_maxStorageProviders, _maxAllocation, _minTimePeriod, _maxTimePeriod)
		MockAPI(_minerOwner)
	{
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		grantRole(REGISTRY_ADMIN, msg.sender);
		ownerId = _ownerId;
	}

	/**
	 * @notice Register storage provider with `_minerId`, desired `_allocationLimit` and `_targetPool`
	 * @param _minerId Storage Provider miner ID in Filecoin network
	 * @param _targetPool Target liquid staking strategy
	 * @param _allocationLimit FIL allocation for storage provider
	 * @dev Only triggered by Storage Provider owner
	 */
	function register(
		uint64 _minerId,
		address _targetPool,
		uint256 _allocationLimit
	) public override validActorID(_minerId) {
		require(_allocationLimit <= maxAllocation, "INVALID_ALLOCATION");
		require(_targetPool.isContract(), "INVALID_TARGET_POOL");

		MinerTypes.GetOwnerReturn memory ownerReturn = MockAPI.getOwner();
		require(keccak256(ownerReturn.proposed.data) == keccak256(bytes("0x00")), "PROPOSED_NEW_OWNER");

		bytes memory senderBytes = Leb128.encodeUnsignedLeb128FromUInt64(ownerId).buf;
		bytes memory ownerBytes = FilAddresses.fromBytes(ownerReturn.owner.data).data;
		require(keccak256(senderBytes) == keccak256(ownerBytes), "INVALID_MINER_OWNERSHIP");

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[ownerId];
		storageProvider.minerId = _minerId;
		storageProvider.targetPool = _targetPool;
		storageProvider.allocationLimit = _allocationLimit;

		sectorSizes[ownerId] = sampleSectorSize;

		totalStorageProviders.increment();
		totalInactiveStorageProviders.increment();

		emit StorageProviderRegistered(ownerReturn.owner.data, ownerId, _minerId, _targetPool, _allocationLimit);
	}

	/**
	 * @notice Onboard storage provider with `_minerId`, desired `_allocationLimit`, `_repayment` amount
	 * @param _minerId Storage Provider miner ID in Filecoin network
	 * @param _allocationLimit FIL allocation for storage provider
	 * @param _repayment FIL repayment for storage provider
	 * @param _lastEpoch Last epoch for FIL allocation utilization
	 * @dev Only triggered by owner contract
	 */
	function onboardStorageProvider(
		uint64 _minerId,
		uint256 _allocationLimit,
		uint256 _repayment,
		int64 _lastEpoch
	) public virtual override validActorID(_minerId) {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");
		require(_repayment > _allocationLimit, "INCORRECT_REPAYMENT");
		require(_allocationLimit <= maxAllocation, "INCORRECT_ALLOCATION");
		MinerTypes.GetOwnerReturn memory ownerReturn = MockAPI.getOwner();
		require(keccak256(ownerReturn.proposed.data) == keccak256(bytes("0x00")), "PROPOSED_NEW_OWNER");

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[ownerId];
		require(storageProvider.targetPool != address(0x0), "INVALID_TARGET_POOL");

		storageProvider.repayment = _repayment;
		storageProvider.allocationLimit = _allocationLimit;
		storageProvider.lastEpoch = _lastEpoch;

		emit StorageProviderOnboarded(ownerId, _minerId, _allocationLimit, _repayment, _lastEpoch);
	}

	/**
	 * @notice Transfer beneficiary address of a miner to the target pool
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 */
	function changeBeneficiaryAddress(address _beneficiaryAddress) public override {
		require(_beneficiaryAddress.isContract(), "INVALID_CONTRACT");

		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[ownerId];
		require(storageProvider.targetPool == _beneficiaryAddress, "INVALID_ADDRESS");

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = FilAddresses.fromEthAddress(_beneficiaryAddress);
		params.new_quota = BigInts.fromUint256(storageProvider.allocationLimit);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(storageProvider.lastEpoch);

		MockAPI.changeBeneficiary(params);

		emit StorageProviderBeneficiaryAddressUpdated(_beneficiaryAddress);
	}

	/**
	 * @notice Accept beneficiary address transfer and activate FIL allocation
	 * @param _ownerId Storage Provider owner ID
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 * @dev Only triggered by owner contract
	 */
	function acceptBeneficiaryAddress(uint64 _ownerId, address _beneficiaryAddress) public override {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");
		require(_beneficiaryAddress.isContract(), "INVALID_CONTRACT");

		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_ownerId];

		MinerTypes.ChangeBeneficiaryParams memory params;
		params.new_beneficiary = FilAddresses.fromEthAddress(_beneficiaryAddress);
		params.new_quota = BigInts.fromUint256(storageProvider.allocationLimit);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(storageProvider.lastEpoch);

		storageProviders[_ownerId].active = true;
		totalInactiveStorageProviders.decrement();

		MockAPI.changeBeneficiary(params);

		emit StorageProviderBeneficiaryAddressAccepted(_ownerId);
	}

	/**
	 * @notice Request storage provider's FIL allocation update with `_allocationLimit`
	 * @param _allocationLimit New FIL allocation for storage provider
	 * @dev Only triggered by Storage Provider owner
	 */
	function requestAllocationLimitUpdate(uint256 _allocationLimit) public virtual override {
		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[ownerId];

		require(storageProvider.active, "INACTIVE_STORAGE_PROVIDER");
		require(storageProvider.allocationLimit != _allocationLimit, "SAME_ALLOCATION_LIMIT");
		require(_allocationLimit <= maxAllocation, "ALLOCATION_OVERFLOW");

		allocationRequests[ownerId] = _allocationLimit;

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = FilAddresses.fromEthAddress(storageProvider.targetPool);
		params.new_quota = BigInts.fromUint256(_allocationLimit);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(storageProvider.lastEpoch);

		MockAPI.changeBeneficiary(params);

		emit StorageProviderAllocationLimitRequest(ownerId, _allocationLimit);
	}

	/**
	 * @notice Update storage provider FIL allocation with `_allocationLimit`
	 * @param _ownerId Storage provider owner ID
	 * @param _allocationLimit New FIL allocation for storage provider
	 * @param _repaymentAmount New FIL repayment amount for storage provider
	 * @dev Only triggered by owner contract
	 */
	function updateAllocationLimit(
		uint64 _ownerId,
		uint256 _allocationLimit,
		uint256 _repaymentAmount
	) public virtual override activeStorageProvider(_ownerId) {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");
		require(allocationRequests[_ownerId] == _allocationLimit, "INVALID_ALLOCATION");
		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_ownerId];
		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = FilAddresses.fromEthAddress(storageProvider.targetPool);
		params.new_quota = BigInts.fromUint256(_allocationLimit);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(storageProvider.lastEpoch);

		MockAPI.changeBeneficiary(params);

		storageProviders[_ownerId].allocationLimit = _allocationLimit;
		storageProviders[_ownerId].repayment = _repaymentAmount;

		delete allocationRequests[_ownerId];

		emit StorageProviderAllocationLimitUpdate(_ownerId, _allocationLimit);
	}

	/**
	 * @notice Update storage provider's restaking ratio
	 * @param _restakingRatio Restaking ratio for Storage Provider
	 * @param _restakingAddress Restaking address (f4 address) for Storage Provider
	 * @dev Only triggered by Storage Provider
	 */
	function setRestaking(uint256 _restakingRatio, address _restakingAddress) public virtual override {
		require(_restakingRatio <= 10000, "INVALID_RESTAKING_RATIO");
		require(_restakingAddress != address(0), "INVALID_ADDRESS");

		StorageProviderTypes.SPRestaking storage restaking = restakings[ownerId];
		restaking.restakingRatio = _restakingRatio;
		restaking.restakingAddress = _restakingAddress;

		emit StorageProviderMinerRestakingRatioUpdate(ownerId, _restakingRatio, _restakingAddress);
	}
}

/**
 * @title Storage Provider Registry Caller Mock contract that routes calls to StorageProviderRegistry
 * @author Collective DAO
 */
contract StorageProviderRegistryCallerMock {
	IStorageProviderRegistry public registry;

	/**
	 * @dev Contract constructor function.
	 * @param _registry StorageProviderRegistry address to route calls
	 *
	 */
	constructor(address _registry) {
		registry = IStorageProviderRegistry(_registry);
	}

	/**
	 * @notice Increase collected rewards by Storage Provider
	 * @param _ownerId Storage Provider owner ID
	 * @param _accuredRewards Unlocked portion of rewards, that available for withdrawal
	 * @param _lockedRewards Locked portion of rewards, that not available for withdrawal
	 */
	function increaseRewards(uint64 _ownerId, uint256 _accuredRewards, uint256 _lockedRewards) external {
		registry.increaseRewards(_ownerId, _accuredRewards, _lockedRewards);
	}

	/**
	 * @notice Increase used allocation for Storage Provider
	 * @param _ownerId Storage Provider owner ID
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function increaseUsedAllocation(uint64 _ownerId, uint256 _allocated) external {
		registry.increaseUsedAllocation(_ownerId, _allocated);
	}
}
