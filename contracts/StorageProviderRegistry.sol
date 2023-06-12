// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {MinerAPI, MinerTypes, CommonTypes} from "filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import {PrecompilesAPI} from "filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";
import {StorageProviderTypes} from "./types/StorageProviderTypes.sol";
import {FilAddress} from "fevmate/utils/FilAddress.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {BokkyPooBahsDateTimeLibrary} from "./libraries/DateTimeLibraryCompressed.sol";
import {IStorageProviderRegistry} from "./interfaces/IStorageProviderRegistry.sol";
import {IRewardCollectorClient} from "./interfaces/IRewardCollectorClient.sol";
import {IStorageProviderCollateralClient} from "./interfaces/IStorageProviderCollateralClient.sol";
import {IResolverClient} from "./interfaces/IResolverClient.sol";
import {ILiquidStakingControllerClient as IStakingControllerClient} from "./interfaces/ILiquidStakingControllerClient.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

/**
 * @title Storage Provider Registry contract allows storage providers to register
 * in liquid staking protocol and ask for a FIL allocation.
 *
 * Once Storage Provider is registered and signaled their desired FIL allocation
 * it needs to transfer
 *
 */
contract StorageProviderRegistry is
	Initializable,
	IStorageProviderRegistry,
	AccessControlUpgradeable,
	ReentrancyGuardUpgradeable,
	UUPSUpgradeable
{
	using FilAddress for address;
	using SafeCastLib for uint256;
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

	error InvalidAccess();
	error InvalidAddress();
	error ActivePool();
	error InactivePool();
	error InactiveSP();
	error RegisteredSP();
	error InactiveActor();
	error InvalidAllocation();
	error InvalidDailyAllocation();
	error InvalidRepayment();
	error InvalidOwner();
	error InvalidParams();
	error AllocationOverflow();
	error OwnerProposed();
	error InvalidBeneficiary();
	error AlreadyApproved();
	error NonSyncedBeneficiary();

	// Mapping of storage provider Miner IDs to their SP info
	mapping(uint64 => StorageProviderTypes.StorageProvider) public storageProviders;

	// Mapping of storage provider Miner IDs to their allocations
	mapping(uint64 => StorageProviderTypes.SPAllocation) public allocations;

	// Mapping of storage provider Owner IDs to their restaking info
	mapping(uint64 => StorageProviderTypes.SPRestaking) public restakings;

	// Mapping of storage provider Miner IDs to their allocation update requests
	mapping(uint64 => StorageProviderTypes.AllocationRequest) public allocationRequests;

	// Mapping of storage provider Miner IDs to their sector sizes
	mapping(uint64 => uint64) public sectorSizes;

	// Mapping of storage providers daily allocation usage to date hashes
	mapping(bytes32 => uint256) public dailyUsages;

	// Mapping of liquid staking pools status to it addresses
	mapping(address => bool) public pools;

	// Mapping of beneficiary status to miner IDs
	mapping(uint64 => bool) public syncedBeneficiary;

	// Mapping of all Miner IDs to Owner ID
	mapping(uint64 => EnumerableSetUpgradeable.UintSet) minerIds;

	bytes32 private constant REGISTRY_ADMIN = keccak256("REGISTRY_ADMIN");

	uint256 public maxAllocation;

	IResolverClient internal resolver;

	modifier activeStorageProvider(uint64 _minerId) {
		if (!storageProviders[_minerId].active) revert InactiveSP();
		_;
	}

	modifier onlyAdmin() {
		if (!hasRole(REGISTRY_ADMIN, msg.sender)) revert InvalidAccess();
		_;
	}

	/**
	 * @dev Contract initializer function.
	 * @param _maxAllocation Number of maximum FIL allocated to a single storage provider
	 */
	function initialize(uint256 _maxAllocation, address _resolver) public initializer {
		__AccessControl_init();
		__ReentrancyGuard_init();
		__UUPSUpgradeable_init();

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setRoleAdmin(REGISTRY_ADMIN, DEFAULT_ADMIN_ROLE);
		grantRole(REGISTRY_ADMIN, msg.sender);
		maxAllocation = _maxAllocation;
		resolver = IResolverClient(_resolver);
	}

	struct RegisterLocalVars {
		address ownerAddr;
		bool isID;
		uint64 msgSenderId;
		uint64 ownerId;
		uint64 sectorSize;
	}

	/**
	 * @notice Register storage provider with `_minerId`, desired `_allocationLimit`
	 * @param _minerId Storage Provider miner ID in Filecoin network
	 * @param _allocationLimit FIL allocation for storage provider
	 * @param _dailyAllocation Daily FIL allocation for storage provider
	 * @dev Only triggered by Storage Provider owner
	 */
	function register(
		uint64 _minerId,
		uint256 _allocationLimit,
		uint256 _dailyAllocation
	) public virtual override nonReentrant {
		if (_allocationLimit == 0 || _allocationLimit > maxAllocation) revert InvalidAllocation();
		if (_dailyAllocation == 0 || _dailyAllocation > _allocationLimit) revert InvalidDailyAllocation();

		RegisterLocalVars memory vars;

		vars.ownerAddr = msg.sender.normalize();
		(vars.isID, vars.msgSenderId) = vars.ownerAddr.getActorID();
		if (!vars.isID) revert InactiveActor();

		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(_minerId);

		MinerTypes.GetOwnerReturn memory ownerReturn = MinerAPI.getOwner(actorId);
		if (keccak256(ownerReturn.proposed.data) != keccak256(bytes(""))) revert OwnerProposed();

		vars.ownerId = PrecompilesAPI.resolveAddress(ownerReturn.owner);
		if (vars.ownerId != vars.msgSenderId) revert InvalidOwner();
		if (storageProviders[_minerId].onboarded) revert RegisteredSP();

		address targetPool = resolver.getLiquidStaking();
		storageProviders[_minerId].targetPool = targetPool;

		EnumerableSetUpgradeable.UintSet storage set = minerIds[vars.ownerId];
		set.add(_minerId);

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_minerId];
		spAllocation.allocationLimit = _allocationLimit;
		spAllocation.dailyAllocation = _dailyAllocation;

		vars.sectorSize = MinerAPI.getSectorSize(actorId);
		sectorSizes[_minerId] = vars.sectorSize;

		IStorageProviderCollateralClient(resolver.getCollateral()).updateCollateralRequirements(vars.ownerId, 0);
		IStakingControllerClient(resolver.getLiquidStakingController()).updateProfitShare(vars.ownerId, 0, targetPool);

		emit StorageProviderRegistered(
			ownerReturn.owner.data,
			vars.ownerId,
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
	 * @dev Only triggered by registry admin
	 */
	function onboardStorageProvider(
		uint64 _minerId,
		uint256 _allocationLimit,
		uint256 _dailyAllocation,
		uint256 _repayment,
		int64 _lastEpoch
	) public virtual onlyAdmin nonReentrant {
		if (_allocationLimit == 0 || _allocationLimit > maxAllocation) revert InvalidAllocation();
		if (_dailyAllocation == 0 || _dailyAllocation > _allocationLimit) revert InvalidDailyAllocation();
		if (_repayment <= _allocationLimit) revert InvalidRepayment();

		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(_minerId);

		MinerTypes.GetOwnerReturn memory ownerReturn = MinerAPI.getOwner(actorId);
		if (keccak256(ownerReturn.proposed.data) != keccak256(bytes(""))) revert OwnerProposed();

		uint64 ownerId = PrecompilesAPI.resolveAddress(ownerReturn.owner);
		if (!minerIds[ownerId].contains(_minerId)) revert InvalidOwner(); // To make sure that Owner ID after the registration hasn't been changed

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[_minerId];
		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_minerId];
		if (storageProvider.onboarded) revert RegisteredSP();

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
	function acceptBeneficiaryAddress(uint64 _minerId) public virtual override onlyAdmin nonReentrant {
		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[_minerId];
		if (!storageProvider.onboarded) revert InactiveSP();

		(bool isID, uint64 beneficiaryId) = resolver.getRewardCollector().getActorID();
		if (!isID) revert InactiveActor();

		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(_minerId);
		MinerTypes.GetBeneficiaryReturn memory beneficiary = MinerAPI.getBeneficiary(actorId);

		uint64 bActorId = PrecompilesAPI.resolveAddress(beneficiary.proposed.new_beneficiary);
		if (beneficiaryId != bActorId) revert InvalidBeneficiary();
		if (beneficiary.proposed.approved_by_nominee) revert AlreadyApproved();

		IRewardCollectorClient(resolver.getRewardCollector()).forwardChangeBeneficiary(
			_minerId,
			beneficiaryId,
			allocations[_minerId].repayment,
			storageProvider.lastEpoch
		);

		storageProvider.active = true;
		syncedBeneficiary[_minerId] = true;

		emit StorageProviderBeneficiaryAddressAccepted(_minerId);
	}

	/**
	 * @notice Deactivate storage provider and transfer beneficiary back to the SP owner
	 * @param _minerId Storage Provider miner ID
	 * @dev Only triggered by registry admin
	 */
	function deactivateStorageProvider(uint64 _minerId) public onlyAdmin activeStorageProvider(_minerId) {
		if (
			allocations[_minerId].accruedRewards + allocations[_minerId].repaidPledge != allocations[_minerId].repayment
		) revert InvalidRepayment();

		storageProviders[_minerId].active = false;
		delete syncedBeneficiary[_minerId];

		emit StorageProviderDeactivated(_minerId);
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
	) public virtual override activeStorageProvider(_minerId) {
		if (_allocationLimit == 0 || _allocationLimit > maxAllocation) revert InvalidAllocation();
		if (_dailyAllocation == 0 || _dailyAllocation > _allocationLimit) revert InvalidDailyAllocation();

		address ownerAddr = msg.sender.normalize();
		(bool isID, uint64 ownerId) = ownerAddr.getActorID();
		if (!isID) revert InactiveActor();

		if (!minerIds[ownerId].contains(_minerId)) revert InvalidOwner();

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
	 * @notice Update storage provider FIL allocation with `_allocationLimit`
	 * @param _minerId Storage provider miner ID
	 * @param _allocationLimit New FIL allocation for storage provider
	 * @param _dailyAllocation New daily FIL allocation for storage provider
	 * @param _repaymentAmount New FIL repayment amount for storage provider
	 * @dev Only triggered by registry admin
	 */
	function updateAllocationLimit(
		uint64 _minerId,
		uint256 _allocationLimit,
		uint256 _dailyAllocation,
		uint256 _repaymentAmount
	) public virtual override onlyAdmin activeStorageProvider(_minerId) nonReentrant {
		if (_allocationLimit == 0 || _allocationLimit > maxAllocation) revert InvalidAllocation();
		if (_dailyAllocation == 0 || _dailyAllocation > _allocationLimit) revert InvalidDailyAllocation();
		if (_repaymentAmount <= _allocationLimit) revert InvalidRepayment();

		StorageProviderTypes.AllocationRequest memory allocationRequest = allocationRequests[_minerId];

		if (allocationRequest.allocationLimit > 0) {
			// If SP requested allocation update should fulfil their request first
			if (allocationRequest.allocationLimit != _allocationLimit) revert InvalidAllocation();
			if (allocationRequest.dailyAllocation != _dailyAllocation) revert InvalidDailyAllocation();
		}

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_minerId];
		spAllocation.allocationLimit = _allocationLimit;
		spAllocation.dailyAllocation = _dailyAllocation;
		spAllocation.repayment = _repaymentAmount;

		syncedBeneficiary[_minerId] = false;
		delete allocationRequests[_minerId];

		emit StorageProviderAllocationLimitUpdate(_minerId, _allocationLimit, _dailyAllocation, _repaymentAmount);
	}

	/**
	 * @notice Update storage provider's restaking ratio
	 * @param _restakingRatio Restaking ratio for Storage Provider
	 * @param _restakingAddress Restaking address (f4 address) for Storage Provider
	 * @dev Only triggered by Storage Provider
	 */
	function setRestaking(uint256 _restakingRatio, address _restakingAddress) public virtual override {
		address ownerAddr = msg.sender.normalize();
		(bool isID, uint64 ownerId) = ownerAddr.getActorID();
		if (!isID) revert InactiveActor();

		if (_restakingRatio > 10000) revert InvalidParams();
		if (_restakingAddress == address(0)) revert InvalidAddress();

		StorageProviderTypes.SPRestaking storage restaking = restakings[ownerId];
		restaking.restakingRatio = _restakingRatio;
		restaking.restakingAddress = _restakingAddress;

		emit StorageProviderMinerRestakingRatioUpdate(ownerId, _restakingRatio, _restakingAddress);
	}

	/**
	 * @notice Return Storage Provider information with `_minerId`
	 */
	function getStorageProvider(uint64 _minerId) public view returns (bool, address, uint64, int64) {
		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_minerId];
		return (storageProvider.active, storageProvider.targetPool, storageProvider.ownerId, storageProvider.lastEpoch);
	}

	/**
	 * @notice Return a boolean flag of Storage Provider activity
	 */
	function isActiveProvider(uint64 _minerId) external view returns (bool status) {
		status = storageProviders[_minerId].active;
	}

	/**
	 * @notice Return a boolean flag if `_ownerId` has registered any miner ids
	 */
	function isActiveOwner(uint64 _ownerId) external view returns (bool) {
		return minerIds[_ownerId].length() > 0;
	}

	/**
	 * @notice Return a boolean flag if `_ownerId` owns the specific `_minerId`
	 */
	function isActualOwner(uint64 _ownerId, uint64 _minerId) external view returns (bool) {
		return minerIds[_ownerId].contains(_minerId);
	}

	/**
	 * @notice Return a repayment amount for Storage Provider
	 */
	function getRepayment(uint64 _minerId) external view returns (uint256) {
		return allocations[_minerId].repayment;
	}

	/**
	 * @notice Return a total used allocation and repaid pledge for Storage Provider with `_ownerId`
	 */
	function getAllocations(uint64 _ownerId) external returns (uint256, uint256) {
		EnumerableSetUpgradeable.UintSet storage set = minerIds[_ownerId];
		uint256 lastMinerIdx = set.length();

		uint256 totalUsedAllocation;
		uint256 totalRepaidPledge;

		for (uint256 i = 0; i < lastMinerIdx; i++) {
			uint64 minerId = set.at(i).safeCastTo64();

			totalUsedAllocation += allocations[minerId].usedAllocation;
			totalRepaidPledge += allocations[minerId].repaidPledge;
		}

		return (totalUsedAllocation, totalRepaidPledge);
	}

	/**
	 * @notice Increase collected rewards by Storage Provider
	 * @param _minerId Storage Provider miner ID
	 * @param _accuredRewards Withdrawn rewards from SP's miner actor
	 */
	function increaseRewards(uint64 _minerId, uint256 _accuredRewards) external {
		if (msg.sender != resolver.getRewardCollector()) revert InvalidAccess();

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_minerId];
		spAllocation.accruedRewards = spAllocation.accruedRewards + _accuredRewards;

		emit StorageProviderAccruedRewards(_minerId, _accuredRewards);
	}

	/**
	 * @notice Increase repaid pledge by Storage Provider
	 * @param _minerId Storage Provider owner ID
	 * @param _repaidPledge Withdrawn initial pledge after sector termination
	 */
	function increasePledgeRepayment(uint64 _minerId, uint256 _repaidPledge) external {
		if (msg.sender != resolver.getRewardCollector()) revert InvalidAccess();

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_minerId];
		spAllocation.repaidPledge = spAllocation.repaidPledge + _repaidPledge;
		if (spAllocation.repaidPledge > spAllocation.usedAllocation) revert AllocationOverflow();

		emit StorageProviderRepaidPledge(_minerId, _repaidPledge);
	}

	/**
	 * @notice Increase used allocation for Storage Provider
	 * @param _minerId Storage Provider miner ID
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 * @param _timestamp Transaction timestamp
	 */
	function increaseUsedAllocation(uint64 _minerId, uint256 _allocated, uint256 _timestamp) external {
		if (msg.sender != resolver.getCollateral()) revert InvalidAccess();
		if (!syncedBeneficiary[_minerId]) revert NonSyncedBeneficiary();

		(uint year, uint month, uint day) = BokkyPooBahsDateTimeLibrary.timestampToDate(_timestamp);
		bytes32 dateHash = keccak256(abi.encodePacked(year, month, day, _minerId));

		uint256 usedDailyAlloc = dailyUsages[dateHash];
		uint256 totalDailyUsage = usedDailyAlloc + _allocated;

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_minerId];

		if (totalDailyUsage > spAllocation.dailyAllocation) revert AllocationOverflow();
		if (spAllocation.usedAllocation + _allocated > spAllocation.allocationLimit) revert AllocationOverflow();

		spAllocation.usedAllocation = spAllocation.usedAllocation + _allocated;
		dailyUsages[dateHash] += _allocated;

		emit StorageProviderAllocationUsed(_minerId, _allocated);
	}

	/**
	 * @notice Register new liquid staking pool
	 * @param _pool Address of pool smart contract
	 * @dev Only triggered by registry admin
	 */
	function registerPool(address _pool) public onlyAdmin {
		if (_pool == address(0)) revert InvalidAddress();
		if (pools[_pool]) revert ActivePool();

		pools[_pool] = true;

		emit LiquidStakingPoolRegistered(_pool);
	}

	/**
	 * @notice Updates maximum allocation amount for SP
	 * @param allocation New max allocation per SP
	 */
	function updateMaxAllocation(uint256 allocation) public onlyAdmin {
		if (allocation == 0) revert InvalidAllocation();
		if (allocation == maxAllocation) revert InvalidAllocation();

		maxAllocation = allocation;

		emit UpdateMaxAllocation(allocation);
	}

	/**
	 * @notice Return a boolean flag whether `_pool` is active or not
	 */
	function isActivePool(address _pool) external view returns (bool) {
		return pools[_pool];
	}

	function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}

	function version() external pure virtual returns (string memory) {
		return "v1";
	}

	function getImplementation() external view returns (address) {
		return _getImplementation();
	}
}
