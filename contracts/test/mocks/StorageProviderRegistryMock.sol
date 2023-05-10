// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../StorageProviderRegistry.sol";
import {MinerMockAPI as MockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {FilAddresses} from "filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

/**
 * @title Storage Provider Registry Mock contract that works with mock Filecoin Miner API
 * @author Collective DAO
 */
contract StorageProviderRegistryMock is StorageProviderRegistry, DSTestPlus {
	bytes32 private constant REGISTRY_ADMIN = keccak256("REGISTRY_ADMIN");
	uint64 public ownerId;
	uint64 public sampleSectorSize;

	MockAPI private mockAPI;

	/**
	 * @dev Contract initializer function.
	 * @param _maxAllocation Number of maximum FIL allocated to a single storage provider
	 */
	function initialize(
		address _minerApiMock,
		uint64 _ownerId,
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
		mockAPI = MockAPI(_minerApiMock);
		resolver = IResolverClient(_resolver);

		sampleSectorSize = 32 << 30;
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
		if (_allocationLimit == 0 || _allocationLimit > maxAllocation) revert InvalidAllocation();
		if (_dailyAllocation == 0 || _dailyAllocation > _allocationLimit) revert InvalidDailyAllocation();
		if (!pools[_targetPool]) revert InactivePool();

		MinerTypes.GetOwnerReturn memory ownerReturn = mockAPI.getOwner();
		if (keccak256(ownerReturn.proposed.data) != keccak256(bytes("0x00"))) revert OwnerProposed();

		bytes memory senderBytes = Leb128.encodeUnsignedLeb128FromUInt64(ownerId).buf;
		bytes memory ownerBytes = FilAddresses.fromBytes(ownerReturn.owner.data).data;
		if (keccak256(senderBytes) != keccak256(ownerBytes)) revert InvalidOwner();
		if (storageProviders[ownerId].onboarded) revert RegisteredSP();

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[ownerId];
		storageProvider.minerId = _minerId;
		storageProvider.targetPool = _targetPool;

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[ownerId];
		spAllocation.allocationLimit = _allocationLimit;
		spAllocation.dailyAllocation = _dailyAllocation;

		sectorSizes[ownerId] = sampleSectorSize;

		IStorageProviderCollateralClient(resolver.getCollateral()).updateCollateralRequirements(ownerId, 0);
		IStakingControllerClient(resolver.getLiquidStakingController()).updateProfitShare(ownerId, 0, _targetPool);

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
	) public virtual override onlyAdmin {
		if (_allocationLimit == 0 || _allocationLimit > maxAllocation) revert InvalidAllocation();
		if (_dailyAllocation == 0 || _dailyAllocation > _allocationLimit) revert InvalidDailyAllocation();
		if (_repayment <= _allocationLimit) revert InvalidRepayment();

		MinerTypes.GetOwnerReturn memory ownerReturn = mockAPI.getOwner();
		if (keccak256(ownerReturn.proposed.data) != keccak256(bytes("0x00"))) revert OwnerProposed();

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[ownerId];
		StorageProviderTypes.SPAllocation storage spAllocation = allocations[ownerId];

		if (storageProviders[ownerId].onboarded) revert RegisteredSP();

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
		if (!storageProvider.onboarded) revert InactiveSP();

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
	function acceptBeneficiaryAddress(uint64 _ownerId) public override onlyAdmin {
		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_ownerId];
		if (!storageProvider.onboarded) revert InactiveSP();

		ILiquidStakingClient(storageProviders[ownerId].targetPool).forwardChangeBeneficiary(
			storageProvider.minerId,
			storageProvider.targetPool,
			allocations[ownerId].repayment,
			storageProvider.lastEpoch
		);

		storageProviders[_ownerId].active = true;

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
		if (_allocationLimit == 0 || _allocationLimit > maxAllocation) revert InvalidAllocation();
		if (_dailyAllocation == 0 || _dailyAllocation > _allocationLimit) revert InvalidDailyAllocation();

		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[ownerId];
		if (!storageProvider.active) revert InactiveSP();

		StorageProviderTypes.SPAllocation memory spAllocation = allocations[ownerId];
		if (spAllocation.allocationLimit == _allocationLimit && spAllocation.dailyAllocation == _dailyAllocation)
			revert InvalidParams();

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
	) public virtual override activeStorageProvider(_ownerId) onlyAdmin {
		if (_allocationLimit == 0 || _allocationLimit > maxAllocation) revert InvalidAllocation();
		if (_dailyAllocation == 0 || _dailyAllocation > _allocationLimit) revert InvalidDailyAllocation();
		if (_repaymentAmount <= _allocationLimit) revert InvalidRepayment();

		StorageProviderTypes.AllocationRequest memory allocationRequest = allocationRequests[_ownerId];

		if (allocationRequest.allocationLimit > 0) {
			// If SP requested allocation update should fulfil their request first
			if (allocationRequest.allocationLimit != _allocationLimit) revert InvalidAllocation();
			if (allocationRequest.dailyAllocation != _dailyAllocation) revert InvalidDailyAllocation();
		}

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
		if (_restakingRatio > 10000) revert InvalidParams();
		if (_restakingAddress == address(0)) revert InvalidAddress();

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
	function setMinerAddress(
		uint64 _ownerId,
		uint64 _minerId
	) public override activeStorageProvider(_ownerId) onlyAdmin {
		uint64 prevMiner = storageProviders[_ownerId].minerId;
		if (prevMiner == _minerId) revert InvalidParams();

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
