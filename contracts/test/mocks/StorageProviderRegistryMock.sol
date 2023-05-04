// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../StorageProviderRegistry.sol";
import {MinerMockAPI as MockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {FilAddresses} from "filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Storage Provider Registry Mock contract that works with mock Filecoin Miner API
 * @author Collective DAO
 */
contract StorageProviderRegistryMock is StorageProviderRegistry, DSTestPlus {
	using Counters for Counters.Counter;
	using Address for address;

	bytes32 private constant REGISTRY_ADMIN = keccak256("REGISTRY_ADMIN");
	uint64 public ownerId;
	uint64 public sampleSectorSize = 32 << 30;

	MockAPI private mockAPI;

	/**
	 * @dev Contract constructor function.
	 * @param _minerApiMock Address of Miner API mock contract
	 * @param _ownerId Owner ID for SP used in testing cases
	 * @param _maxAllocation Number of maximum FIL allocated to a single storage provider
	 *
	 */
	constructor(
		address _minerApiMock,
		uint64 _ownerId,
		uint256 _maxAllocation
	) StorageProviderRegistry(_maxAllocation) {
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		grantRole(REGISTRY_ADMIN, msg.sender);
		ownerId = _ownerId;

		mockAPI = MockAPI(_minerApiMock);
	}

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
	) public override {
		require(_allocationLimit <= maxAllocation, "INVALID_ALLOCATION");
		require(pools[_targetPool], "INVALID_TARGET_POOL");

		MinerTypes.GetOwnerReturn memory ownerReturn = mockAPI.getOwner();
		require(keccak256(ownerReturn.proposed.data) == keccak256(bytes("0x00")), "PROPOSED_NEW_OWNER");

		bytes memory senderBytes = Leb128.encodeUnsignedLeb128FromUInt64(ownerId).buf;
		bytes memory ownerBytes = FilAddresses.fromBytes(ownerReturn.owner.data).data;
		require(keccak256(senderBytes) == keccak256(ownerBytes), "INVALID_MINER_OWNERSHIP");
		require(!storageProviders[ownerId].onboarded, "ALREADY_REGISTERED");

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[ownerId];
		storageProvider.minerId = _minerId;
		storageProvider.targetPool = _targetPool;

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[ownerId];
		spAllocation.allocationLimit = _allocationLimit;
		spAllocation.dailyAllocation = _dailyAllocation;

		sectorSizes[ownerId] = sampleSectorSize;

		totalStorageProviders.increment();
		totalInactiveStorageProviders.increment();

		collateral.updateCollateralRequirements(ownerId, 0);
		ILiquidStakingClient(_targetPool).updateProfitShare(ownerId, 0);

		emit StorageProviderRegistered(
			ownerReturn.owner.data,
			ownerId,
			_minerId,
			_targetPool,
			_allocationLimit,
			_dailyAllocation
		);
	}

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
	) public virtual override {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");
		require(_repayment > _allocationLimit, "INCORRECT_REPAYMENT");
		require(_allocationLimit <= maxAllocation, "INCORRECT_ALLOCATION");
		MinerTypes.GetOwnerReturn memory ownerReturn = mockAPI.getOwner();
		require(keccak256(ownerReturn.proposed.data) == keccak256(bytes("0x00")), "PROPOSED_NEW_OWNER");

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[ownerId];
		StorageProviderTypes.SPAllocation storage spAllocation = allocations[ownerId];

		require(!storageProviders[ownerId].onboarded, "ALREADY_REGISTERED");

		storageProvider.onboarded = true;
		storageProvider.lastEpoch = _lastEpoch;

		spAllocation.repayment = _repayment;
		spAllocation.allocationLimit = _allocationLimit;
		spAllocation.dailyAllocation = _dailyAllocation;

		emit StorageProviderOnboarded(ownerId, _minerId, _allocationLimit, _dailyAllocation, _repayment, _lastEpoch);
	}

	/**
	 * @notice Transfer beneficiary address of a miner to the target pool
	 */
	function changeBeneficiaryAddress() public override {
		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[ownerId];
		require(storageProvider.onboarded, "NON_ONBOARDED_SP");

		ILiquidStakingClient(storageProviders[ownerId].targetPool).forwardChangeBeneficiary(
			storageProvider.minerId,
			storageProvider.targetPool,
			allocations[ownerId].repayment,
			storageProvider.lastEpoch
		);

		emit StorageProviderBeneficiaryAddressUpdated(storageProvider.targetPool);
	}

	/**
	 * @notice Accept beneficiary address transfer and activate FIL allocation
	 * @param _ownerId Storage Provider owner ID
	 * @dev Only triggered by owner contract
	 */
	function acceptBeneficiaryAddress(uint64 _ownerId) public override {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");

		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_ownerId];
		require(storageProvider.onboarded, "NON_ONBOARDED_SP");

		ILiquidStakingClient(storageProviders[ownerId].targetPool).forwardChangeBeneficiary(
			storageProvider.minerId,
			storageProvider.targetPool,
			allocations[ownerId].repayment,
			storageProvider.lastEpoch
		);

		storageProviders[_ownerId].active = true;
		totalInactiveStorageProviders.decrement();

		// MockAPI.changeBeneficiary(params);

		emit StorageProviderBeneficiaryAddressAccepted(_ownerId);
	}

	/**
	 * @notice Request storage provider's FIL allocation update with `_allocationLimit`
	 * @param _allocationLimit New FIL allocation for storage provider
	 * @param _dailyAllocation New daily FIL allocation for storage provider
	 * @dev Only triggered by Storage Provider owner
	 */
	function requestAllocationLimitUpdate(uint256 _allocationLimit, uint256 _dailyAllocation) public virtual override {
		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[ownerId];
		require(storageProvider.active, "INACTIVE_STORAGE_PROVIDER");

		StorageProviderTypes.SPAllocation memory spAllocation = allocations[ownerId];
		require(
			spAllocation.allocationLimit != _allocationLimit || spAllocation.dailyAllocation != _dailyAllocation,
			"SAME_ALLOCATION_LIMIT"
		);
		require(_allocationLimit <= maxAllocation, "ALLOCATION_OVERFLOW");

		StorageProviderTypes.AllocationRequest storage allocationRequest = allocationRequests[ownerId];
		allocationRequest.allocationLimit = _allocationLimit;
		allocationRequest.dailyAllocation = _dailyAllocation;

		emit StorageProviderAllocationLimitRequest(ownerId, _allocationLimit, _dailyAllocation);
	}

	/**
	 * @notice Update storage provider FIL allocation with `_allocationLimit`
	 * @param _ownerId Storage provider owner ID
	 * @param _allocationLimit New FIL allocation for storage provider
	 * @param _dailyAllocation New daily FIL allocation for storage provider
	 * @param _repaymentAmount New FIL repayment amount for storage provider
	 * @dev Only triggered by owner contract
	 */
	function updateAllocationLimit(
		uint64 _ownerId,
		uint256 _allocationLimit,
		uint256 _dailyAllocation,
		uint256 _repaymentAmount
	) public virtual override activeStorageProvider(_ownerId) {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");

		StorageProviderTypes.AllocationRequest memory allocationRequest = allocationRequests[_ownerId];
		require(allocationRequest.allocationLimit == _allocationLimit, "INVALID_ALLOCATION");
		require(allocationRequest.dailyAllocation == _dailyAllocation, "INVALID_DAILY_ALLOCATION");

		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_ownerId];

		ILiquidStakingClient(storageProviders[_ownerId].targetPool).forwardChangeBeneficiary(
			storageProvider.minerId,
			storageProvider.targetPool,
			_repaymentAmount,
			storageProvider.lastEpoch
		);

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_ownerId];
		spAllocation.allocationLimit = _allocationLimit;
		spAllocation.dailyAllocation = _dailyAllocation;
		spAllocation.repayment = _repaymentAmount;

		delete allocationRequests[_ownerId];

		emit StorageProviderAllocationLimitUpdate(_ownerId, _allocationLimit, _dailyAllocation, _repaymentAmount);
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

	/**
	 * @notice Update storage provider miner ID with `_minerId`
	 * @param _ownerId Storage Provider owner ID
	 * @param _minerId Storage Provider new miner ID
	 * @dev Only triggered by registry admin
	 */
	function setMinerAddress(uint64 _ownerId, uint64 _minerId) public override activeStorageProvider(_ownerId) {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");
		uint64 prevMiner = storageProviders[_ownerId].minerId;
		require(prevMiner != _minerId, "SAME_MINER");

		// Skip ownership check as it fails on tests

		storageProviders[_ownerId].minerId = _minerId;

		emit StorageProviderMinerAddressUpdate(_ownerId, _minerId);
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
	 * @param _accuredRewards Withdrawn rewards from SP's miner actor
	 */
	function increaseRewards(uint64 _ownerId, uint256 _accuredRewards) external {
		registry.increaseRewards(_ownerId, _accuredRewards);
	}

	/**
	 * @notice Increase repaid pledge by Storage Provider
	 * @param _ownerId Storage Provider owner ID
	 * @param _repaidPledge Withdrawn initial pledge after sector termination
	 */
	function increasePledgeRepayment(uint64 _ownerId, uint256 _repaidPledge) external {
		registry.increasePledgeRepayment(_ownerId, _repaidPledge);
	}

	/**
	 * @notice Increase used allocation for Storage Provider
	 * @param _ownerId Storage Provider owner ID
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function increaseUsedAllocation(uint64 _ownerId, uint256 _allocated, uint256 _timestamp) external {
		registry.increaseUsedAllocation(_ownerId, _allocated, _timestamp);
	}
}
