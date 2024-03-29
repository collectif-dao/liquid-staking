// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {StorageProviderRegistry, IStorageProviderRegistry, FilAddress, EnumerableSetUpgradeable, MinerTypes, IResolverClient, IStakingControllerClient, IStorageProviderCollateralClient, IRewardCollectorClient, StorageProviderTypes} from "../../StorageProviderRegistry.sol";
import {MinerMockAPI as MockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {FilAddresses} from "filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

interface IStorageProviderRegistryExtended is IStorageProviderRegistry {
	function forwardChangeBeneficiary(
		uint64 minerId,
		uint64 beneficiaryActorId,
		uint256 quota,
		int64 expiration
	) external;
}

/**
 * @title Storage Provider Registry Mock contract that works with mock Filecoin Miner API
 * @author Collective DAO
 */
contract StorageProviderRegistryMock is StorageProviderRegistry {
	using FilAddress for address;
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

	bytes32 private constant REGISTRY_ADMIN = keccak256("REGISTRY_ADMIN");
	uint64 public ownerId;
	uint64 public sampleSectorSize;
	uint64 public beneficiaryId;

	MockAPI private mockAPI;

	/**
	 * @dev Contract initializer function.
	 * @param _maxAllocation Number of maximum FIL allocated to a single storage provider
	 */
	function initialize(
		address _minerApiMock,
		uint64 _ownerId,
		uint64 _beneficiaryId,
		uint256 _maxAllocation,
		address _resolver
	) public initializer {
		__AccessControl_init();
		__ReentrancyGuard_init();
		__UUPSUpgradeable_init();

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setRoleAdmin(REGISTRY_ADMIN, DEFAULT_ADMIN_ROLE);
		grantRole(REGISTRY_ADMIN, msg.sender);
		maxAllocation = _maxAllocation;

		ownerId = _ownerId;
		beneficiaryId = _beneficiaryId;
		mockAPI = MockAPI(_minerApiMock);
		resolver = IResolverClient(_resolver);

		sampleSectorSize = 32 << 30;
	}

	/**
	 * @notice Register storage provider with `_minerId`, desired `_allocationLimit`
	 * @param _minerId Storage Provider miner ID in Filecoin network
	 * @param _allocationLimit FIL allocation for storage provider
	 * @param _dailyAllocation Daily FIL allocation for storage provider
	 * @dev Only triggered by Storage Provider owner
	 */
	function register(uint64 _minerId, uint256 _allocationLimit, uint256 _dailyAllocation) public override {
		if (_allocationLimit == 0 || _allocationLimit > maxAllocation) revert InvalidAllocation();
		if (_dailyAllocation == 0 || _dailyAllocation > _allocationLimit) revert InvalidDailyAllocation();

		MinerTypes.GetOwnerReturn memory ownerReturn = mockAPI.getOwner();
		if (keccak256(ownerReturn.proposed.data) != keccak256(bytes("0x00"))) revert OwnerProposed();

		bytes memory senderBytes = Leb128.encodeUnsignedLeb128FromUInt64(ownerId).buf;
		bytes memory ownerBytes = FilAddresses.fromBytes(ownerReturn.owner.data).data;
		if (keccak256(senderBytes) != keccak256(ownerBytes)) revert InvalidOwner();
		if (storageProviders[_minerId].onboarded) revert RegisteredSP();

		address targetPool = resolver.getLiquidStaking();

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[_minerId];
		storageProvider.ownerId = ownerId;
		storageProvider.targetPool = targetPool;

		EnumerableSetUpgradeable.UintSet storage set = minerIds[ownerId];
		set.add(_minerId);

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_minerId];
		spAllocation.allocationLimit = _allocationLimit;
		spAllocation.dailyAllocation = _dailyAllocation;

		sectorSizes[_minerId] = sampleSectorSize;

		IStorageProviderCollateralClient(resolver.getCollateral()).updateCollateralRequirements(ownerId, 0);
		IStakingControllerClient(resolver.getLiquidStakingController()).updateProfitShare(ownerId, 0, targetPool);

		emit StorageProviderRegistered(
			ownerReturn.owner.data,
			ownerId,
			_minerId,
			targetPool,
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
	) public virtual override onlyAdmin {
		if (_allocationLimit == 0 || _allocationLimit > maxAllocation) revert InvalidAllocation();
		if (_dailyAllocation == 0 || _dailyAllocation > _allocationLimit) revert InvalidDailyAllocation();
		if (_repayment <= _allocationLimit) revert InvalidRepayment();

		MinerTypes.GetOwnerReturn memory ownerReturn = mockAPI.getOwner();
		if (keccak256(ownerReturn.proposed.data) != keccak256(bytes("0x00"))) revert OwnerProposed();

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[_minerId];
		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_minerId];

		if (storageProviders[_minerId].onboarded) revert RegisteredSP();

		storageProvider.onboarded = true;
		storageProvider.lastEpoch = _lastEpoch;

		spAllocation.repayment = _repayment;
		spAllocation.allocationLimit = _allocationLimit;
		spAllocation.dailyAllocation = _dailyAllocation;

		emit StorageProviderOnboarded(ownerId, _minerId, _allocationLimit, _dailyAllocation, _repayment, _lastEpoch);
	}

	/**
	 * @notice Accept beneficiary address transfer and activate FIL allocation
	 * @param _minerId Storage Provider miner ID
	 * @dev Only triggered by registry admin
	 */
	function acceptBeneficiaryAddress(uint64 _minerId) public override onlyAdmin {
		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_minerId];
		if (!storageProvider.onboarded) revert InactiveSP();

		IRewardCollectorClient(resolver.getRewardCollector()).forwardChangeBeneficiary(
			_minerId,
			beneficiaryId,
			allocations[_minerId].repayment,
			storageProvider.lastEpoch
		);

		storageProviders[_minerId].active = true;
		syncedBeneficiary[_minerId] = true;

		emit StorageProviderBeneficiaryAddressAccepted(_minerId);
	}

	/**
	 * @notice Request storage provider's FIL allocation update with `_allocationLimit`
	 * @param _minerId Storage Provider miner ID
	 * @param _allocationLimit New FIL allocation for storage provider
	 * @param _dailyAllocation New daily FIL allocation for storage provider
	 * @dev Only triggered by Storage Provider owner
	 */
	function requestAllocationLimitUpdate(
		uint64 _minerId,
		uint256 _allocationLimit,
		uint256 _dailyAllocation
	) public virtual override {
		if (_allocationLimit == 0 || _allocationLimit > maxAllocation) revert InvalidAllocation();
		if (_dailyAllocation == 0 || _dailyAllocation > _allocationLimit) revert InvalidDailyAllocation();

		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_minerId];
		if (!storageProvider.active) revert InactiveSP();

		StorageProviderTypes.SPAllocation memory spAllocation = allocations[_minerId];
		if (spAllocation.allocationLimit == _allocationLimit && spAllocation.dailyAllocation == _dailyAllocation)
			revert InvalidParams();

		StorageProviderTypes.AllocationRequest storage allocationRequest = allocationRequests[_minerId];
		allocationRequest.allocationLimit = _allocationLimit;
		allocationRequest.dailyAllocation = _dailyAllocation;

		emit StorageProviderAllocationLimitRequest(_minerId, _allocationLimit, _dailyAllocation);
	}

	/**
	 * @notice Update storage provider's restaking ratio
	 * @param _restakingRatio Restaking ratio for Storage Provider
	 * @param _restakingAddress Restaking address (f4 address) for Storage Provider
	 * @dev Only triggered by Storage Provider
	 */
	function setRestaking(uint256 _restakingRatio, address _restakingAddress) public virtual override {
		address ownerAddr = msg.sender.normalize();

		if (_restakingRatio > 10000) revert InvalidParams();
		if (_restakingAddress == address(0)) revert InvalidAddress();

		StorageProviderTypes.SPRestaking storage restaking = restakings[ownerId];
		restaking.restakingRatio = _restakingRatio;
		restaking.restakingAddress = _restakingAddress;

		emit StorageProviderMinerRestakingRatioUpdate(ownerId, _restakingRatio, _restakingAddress);
	}

	/**
	 * @notice Forwards the changeBeneficiary call to RewardCollector
	 * @param minerId Miner actor ID
	 * @param beneficiaryActorId Beneficiary address to be setup (Actor ID)
	 * @param quota Total beneficiary quota
	 * @param expiration Expiration epoch
	 */
	function forwardChangeBeneficiary(
		uint64 minerId,
		uint64 beneficiaryActorId,
		uint256 quota,
		int64 expiration
	) public {
		IRewardCollectorClient(resolver.getRewardCollector()).forwardChangeBeneficiary(
			minerId,
			beneficiaryActorId,
			quota,
			expiration
		);
	}
}

/**
 * @title Storage Provider Registry Caller Mock contract that routes calls to StorageProviderRegistry
 * @author Collective DAO
 */
contract StorageProviderRegistryCallerMock {
	IStorageProviderRegistryExtended public registry;

	/**
	 * @dev Contract constructor function.
	 * @param _registry StorageProviderRegistry address to route calls
	 *
	 */
	constructor(address _registry) {
		registry = IStorageProviderRegistryExtended(_registry);
	}

	/**
	 * @notice Increase collected rewards by Storage Provider
	 * @param _minerId Storage Provider miner ID
	 * @param _accuredRewards Withdrawn rewards from SP's miner actor
	 */
	function increaseRewards(uint64 _minerId, uint256 _accuredRewards) external {
		registry.increaseRewards(_minerId, _accuredRewards);
	}

	/**
	 * @notice Increase repaid pledge by Storage Provider
	 * @param _minerId Storage Provider miner ID
	 * @param _repaidPledge Withdrawn initial pledge after sector termination
	 */
	function increasePledgeRepayment(uint64 _minerId, uint256 _repaidPledge) external {
		registry.increasePledgeRepayment(_minerId, _repaidPledge);
	}

	/**
	 * @notice Increase used allocation for Storage Provider
	 * @param _minerId Storage Provider miner ID
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function increaseUsedAllocation(uint64 _minerId, uint256 _allocated, uint256 _timestamp) external {
		registry.increaseUsedAllocation(_minerId, _allocated, _timestamp);
	}

	/**
	 * @notice Forwards the changeBeneficiary Miner actor call as RewardCollector
	 * @param minerId Miner actor ID
	 * @param beneficiaryActorId Beneficiary address to be setup (Actor ID)
	 * @param quota Total beneficiary quota
	 * @param expiration Expiration epoch
	 */
	function forwardChangeBeneficiary(
		uint64 minerId,
		uint64 beneficiaryActorId,
		uint256 quota,
		int64 expiration
	) public {
		registry.forwardChangeBeneficiary(minerId, beneficiaryActorId, quota, expiration);
	}
}
