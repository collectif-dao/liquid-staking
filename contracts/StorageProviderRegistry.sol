// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {MinerAPI} from "filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import {MinerTypes} from "filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import {CommonTypes} from "filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import {FilAddresses} from "filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {PrecompilesAPI} from "filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";
import {BigInts} from "filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import {StorageProviderTypes} from "./types/StorageProviderTypes.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {BokkyPooBahsDateTimeLibrary} from "./libraries/DateTimeLibraryCompressed.sol";
import "./interfaces/IStorageProviderRegistry.sol";
import "./interfaces/ILiquidStakingClient.sol";

/**
 * @title Storage Provider Registry contract allows storage providers to register
 * in liquid staking protocol and ask for a FIL allocation.
 *
 * Once Storage Provider is registered and signaled their desired FIL allocation
 * it needs to transfer
 *
 */
contract StorageProviderRegistry is IStorageProviderRegistry, AccessControl {
	using Counters for Counters.Counter;
	using Address for address;

	// Mapping of storage provider IDs to their storage provider info
	mapping(uint64 => StorageProviderTypes.StorageProvider) public storageProviders;

	// Mapping of storage provider IDs to their restaking info
	mapping(uint64 => StorageProviderTypes.SPAllocation) public allocations;

	// Mapping of storage provider IDs to their restaking info
	mapping(uint64 => StorageProviderTypes.SPRestaking) public restakings;

	// Mapping of storage provider IDs to their allocation update requests
	mapping(uint64 => StorageProviderTypes.AllocationRequest) public allocationRequests;

	// Mapping of storage provider IDs to their sector sizes
	mapping(uint64 => uint64) public sectorSizes;

	// Mapping of storage providers daily allocation usage to date hashes
	mapping(bytes32 => uint256) public dailyUsages;

	mapping(address => bool) public pools;

	Counters.Counter public totalStorageProviders;
	Counters.Counter public totalInactiveStorageProviders;

	bytes32 private constant REGISTRY_ADMIN = keccak256("REGISTRY_ADMIN");

	uint256 public maxStorageProviders;
	uint256 public maxAllocation;
	uint256 public minTimePeriod;
	uint256 public maxTimePeriod;

	address public collateral;

	modifier validActorID(uint64 _id) {
		CommonTypes.FilAddress memory addr = FilAddresses.fromActorID(_id);
		require(FilAddresses.validate(addr), "INVALID_ID");
		_;
	}

	modifier activeStorageProvider(uint64 _ownerId) {
		require(storageProviders[_ownerId].active, "INACTIVE_STORAGE_PROVIDER");
		_;
	}

	/**
	 * @dev Contract constructor function.
	 * @param _maxStorageProviders Number of maximum storage providers allowed to use liquid staking
	 * @param _maxAllocation Number of maximum FIL allocated to a single storage provider
	 * @param _minTimePeriod Minimal time period for storage provider allocation
	 * @param _minTimePeriod Maximum time period for storage provider allocation
	 *
	 */
	constructor(uint256 _maxStorageProviders, uint256 _maxAllocation, uint256 _minTimePeriod, uint256 _maxTimePeriod) {
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		grantRole(REGISTRY_ADMIN, msg.sender);
		maxStorageProviders = _maxStorageProviders;
		maxAllocation = _maxAllocation;
		minTimePeriod = _minTimePeriod;
		maxTimePeriod = _maxTimePeriod;
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
	) public virtual override validActorID(_minerId) {
		require(_allocationLimit <= maxAllocation, "INVALID_ALLOCATION");
		require(_targetPool.isContract(), "INVALID_TARGET_POOL");

		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(_minerId);

		MinerTypes.GetOwnerReturn memory ownerReturn = MinerAPI.getOwner(actorId);
		require(keccak256(ownerReturn.proposed.data) == keccak256(bytes("0x00")), "PROPOSED_NEW_OWNER");

		uint64 ownerId = PrecompilesAPI.resolveAddress(ownerReturn.owner);
		uint64 msgSenderId = PrecompilesAPI.resolveEthAddress(msg.sender);
		require(ownerId == msgSenderId, "INVALID_MINER_OWNERSHIP");

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[ownerId];
		storageProvider.minerId = _minerId;
		storageProvider.targetPool = _targetPool;

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[ownerId];
		spAllocation.allocationLimit = _allocationLimit;
		spAllocation.dailyAllocation = _dailyAllocation;

		uint64 sectorSize = MinerAPI.getSectorSize(actorId);
		sectorSizes[ownerId] = sectorSize;

		totalStorageProviders.increment();
		totalInactiveStorageProviders.increment();

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
	 * @dev Only triggered by registry admin
	 */
	function onboardStorageProvider(
		uint64 _minerId,
		uint256 _allocationLimit,
		uint256 _dailyAllocation,
		uint256 _repayment,
		int64 _lastEpoch
	) public virtual validActorID(_minerId) {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");
		require(_repayment > _allocationLimit, "INCORRECT_REPAYMENT");
		require(_allocationLimit <= maxAllocation, "INCORRECT_ALLOCATION");
		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(_minerId);

		MinerTypes.GetOwnerReturn memory ownerReturn = MinerAPI.getOwner(actorId);
		require(keccak256(bytes("")) == keccak256(ownerReturn.proposed.data), "PROPOSED_NEW_OWNER");

		uint64 ownerId = PrecompilesAPI.resolveAddress(ownerReturn.owner);

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[ownerId];
		StorageProviderTypes.SPAllocation storage spAllocation = allocations[ownerId];
		require(storageProvider.targetPool != address(0x0), "INVALID_TARGET_POOL");

		storageProvider.lastEpoch = _lastEpoch;

		spAllocation.repayment = _repayment;
		spAllocation.allocationLimit = _allocationLimit;
		spAllocation.dailyAllocation = _dailyAllocation;

		emit StorageProviderOnboarded(ownerId, _minerId, _allocationLimit, _dailyAllocation, _repayment, _lastEpoch);
	}

	/**
	 * @notice Transfer beneficiary address of a miner to the target pool
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 */
	function changeBeneficiaryAddress(address _beneficiaryAddress) public virtual override {
		require(_beneficiaryAddress.isContract(), "INVALID_CONTRACT");
		uint64 ownerId = PrecompilesAPI.resolveEthAddress(msg.sender);

		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[ownerId];
		CommonTypes.FilActorId minerId = CommonTypes.FilActorId.wrap(storageProvider.minerId);
		require(storageProvider.targetPool == _beneficiaryAddress, "INVALID_ADDRESS");

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = FilAddresses.fromEthAddress(_beneficiaryAddress);
		params.new_quota = BigInts.fromUint256(allocations[ownerId].allocationLimit);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(storageProvider.lastEpoch);

		MinerAPI.changeBeneficiary(minerId, params);

		emit StorageProviderBeneficiaryAddressUpdated(_beneficiaryAddress);
	}

	/**
	 * @notice Accept beneficiary address transfer and activate FIL allocation
	 * @param _ownerId Storage Provider owner ID
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 * @dev Only triggered by registry admin
	 */
	function acceptBeneficiaryAddress(uint64 _ownerId, address _beneficiaryAddress) public virtual override {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");
		require(_beneficiaryAddress.isContract(), "INVALID_CONTRACT");

		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_ownerId];
		CommonTypes.FilActorId minerId = CommonTypes.FilActorId.wrap(storageProvider.minerId);

		MinerTypes.ChangeBeneficiaryParams memory params;
		params.new_beneficiary = FilAddresses.fromEthAddress(_beneficiaryAddress);
		params.new_quota = BigInts.fromUint256(allocations[_ownerId].allocationLimit);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(storageProvider.lastEpoch);

		storageProviders[_ownerId].active = true;
		totalInactiveStorageProviders.decrement();

		MinerAPI.changeBeneficiary(minerId, params);

		emit StorageProviderBeneficiaryAddressAccepted(_ownerId);
	}

	/**
	 * @notice Deactive storage provider with ID `_ownerId`
	 * @param _ownerId Storage Provider owner ID
	 * @dev Only triggered by registry admin
	 */
	function deactivateStorageProvider(uint64 _ownerId) public activeStorageProvider(_ownerId) {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");
		storageProviders[_ownerId].active = false;
		totalInactiveStorageProviders.increment();

		emit StorageProviderDeactivated(_ownerId);
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
	) public activeStorageProvider(_ownerId) validActorID(_minerId) {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");
		uint64 prevMiner = storageProviders[_ownerId].minerId;
		require(prevMiner != _minerId, "SAME_MINER");

		// TODO: Add native call to set new miner address

		storageProviders[_ownerId].minerId = _minerId;

		emit StorageProviderMinerAddressUpdate(_ownerId, _minerId);
	}

	/**
	 * @notice Request storage provider's FIL allocation update with `_allocationLimit`
	 * @param _allocationLimit New FIL allocation for storage provider
	 * @param _dailyAllocation New daily FIL allocation for storage provider
	 * @dev Only triggered by Storage Provider owner
	 */
	function requestAllocationLimitUpdate(uint256 _allocationLimit, uint256 _dailyAllocation) public virtual override {
		uint64 ownerId = PrecompilesAPI.resolveEthAddress(msg.sender);
		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[ownerId];
		require(storageProvider.active, "INACTIVE_STORAGE_PROVIDER");

		StorageProviderTypes.SPAllocation memory spAllocation = allocations[ownerId];
		require(
			spAllocation.allocationLimit != _allocationLimit || spAllocation.dailyAllocation != _dailyAllocation,
			"SAME_ALLOCATION_LIMIT"
		);
		require(_allocationLimit <= maxAllocation, "ALLOCATION_OVERFLOW");

		CommonTypes.FilActorId minerId = CommonTypes.FilActorId.wrap(storageProvider.minerId);

		StorageProviderTypes.AllocationRequest storage allocationRequest = allocationRequests[ownerId];
		allocationRequest.allocationLimit = _allocationLimit;
		allocationRequest.dailyAllocation = _dailyAllocation;

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = FilAddresses.fromEthAddress(storageProvider.targetPool);
		params.new_quota = BigInts.fromUint256(_allocationLimit);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(storageProvider.lastEpoch);

		MinerAPI.changeBeneficiary(minerId, params);

		emit StorageProviderAllocationLimitRequest(ownerId, _allocationLimit);
	}

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
	) public virtual override activeStorageProvider(_ownerId) {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");

		StorageProviderTypes.AllocationRequest memory allocationRequest = allocationRequests[_ownerId];
		require(allocationRequest.allocationLimit == _allocationLimit, "INVALID_ALLOCATION");
		require(allocationRequest.dailyAllocation == _dailyAllocation, "INVALID_DAILY_ALLOCATION");

		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_ownerId];
		CommonTypes.FilActorId minerId = CommonTypes.FilActorId.wrap(storageProvider.minerId);

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = FilAddresses.fromEthAddress(storageProvider.targetPool);
		params.new_quota = BigInts.fromUint256(_allocationLimit);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(storageProvider.lastEpoch);

		MinerAPI.changeBeneficiary(minerId, params);

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_ownerId];
		spAllocation.allocationLimit = _allocationLimit;
		spAllocation.dailyAllocation = _dailyAllocation;
		spAllocation.repayment = _repaymentAmount;

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
		uint64 ownerId = PrecompilesAPI.resolveEthAddress(msg.sender);
		uint256 totalFees = ILiquidStakingClient(storageProviders[ownerId].targetPool).totalFees();

		require(_restakingRatio <= 10000 - totalFees, "INVALID_RESTAKING_RATIO");
		require(_restakingAddress != address(0), "INVALID_ADDRESS");

		StorageProviderTypes.SPRestaking storage restaking = restakings[ownerId];
		restaking.restakingRatio = _restakingRatio;
		restaking.restakingAddress = _restakingAddress;

		emit StorageProviderMinerRestakingRatioUpdate(ownerId, _restakingRatio, _restakingAddress);
	}

	/**
	 * @notice Return total number of storage providers in liquid staking
	 */
	function getTotalStorageProviders() public view returns (uint256) {
		return totalStorageProviders.current();
	}

	/**
	 * @notice Return total number of currently active storage providers
	 */
	function getTotalActiveStorageProviders() public view returns (uint256) {
		return totalStorageProviders.current() - totalInactiveStorageProviders.current();
	}

	/**
	 * @notice Return Storage Provider information with `_ownerId`
	 */
	function getStorageProvider(uint64 _ownerId) public view returns (bool, address, uint64, int64) {
		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_ownerId];
		return (storageProvider.active, storageProvider.targetPool, storageProvider.minerId, storageProvider.lastEpoch);
	}

	/**
	 * @notice Return a boolean flag of Storage Provider activity
	 */
	function isActiveProvider(uint64 _ownerId) external view returns (bool status) {
		status = storageProviders[_ownerId].active;
	}

	/**
	 * @notice Increase collected rewards by Storage Provider
	 * @param _ownerId Storage Provider owner ID
	 * @param _accuredRewards Withdrawn rewards from SP's miner actor
	 */
	function increaseRewards(uint64 _ownerId, uint256 _accuredRewards) external {
		require(pools[msg.sender], "INVALID_ACCESS");

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_ownerId];
		spAllocation.accruedRewards = spAllocation.accruedRewards + _accuredRewards;

		emit StorageProviderAccruedRewards(_ownerId, _accuredRewards);
	}

	/**
	 * @notice Increase repaid pledge by Storage Provider
	 * @param _ownerId Storage Provider owner ID
	 * @param _repaidPledge Withdrawn initial pledge after sector termination
	 */
	function increasePledgeRepayment(uint64 _ownerId, uint256 _repaidPledge) external {
		require(pools[msg.sender], "INVALID_ACCESS");

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_ownerId];
		spAllocation.repaidPledge = spAllocation.repaidPledge + _repaidPledge;
		require(spAllocation.repaidPledge <= spAllocation.usedAllocation, "PLEDGE_REPAYMENT_OVERFLOW");

		emit StorageProviderRepaidPledge(_ownerId, _repaidPledge);
	}

	/**
	 * @notice Increase used allocation for Storage Provider
	 * @param _ownerId Storage Provider owner ID
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 * @param _timestamp Transaction timestamp
	 */
	function increaseUsedAllocation(uint64 _ownerId, uint256 _allocated, uint256 _timestamp) external {
		require(msg.sender == collateral, "INVALID_ACCESS");

		(uint year, uint month, uint day) = BokkyPooBahsDateTimeLibrary.timestampToDate(_timestamp);
		bytes32 dateHash = keccak256(abi.encodePacked(year, month, day));

		uint256 usedDailyAlloc = dailyUsages[dateHash];
		uint256 totalDailyUsage = usedDailyAlloc + _allocated;

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_ownerId];

		require(totalDailyUsage <= spAllocation.dailyAllocation, "DAILY_ALLOCATION_OVERFLOW");

		spAllocation.usedAllocation = spAllocation.usedAllocation + _allocated;
		dailyUsages[dateHash] += _allocated;

		emit StorageProviderAllocationUsed(_ownerId, _allocated);
	}

	/**
	 * @notice Update StorageProviderCollateral smart contract
	 * @param _collateral StorageProviderCollateral smart contract address
	 * @dev Only triggered by registry admin
	 */
	function setCollateralAddress(address _collateral) public {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");

		address prevCollateral = collateral;
		require(prevCollateral != _collateral, "SAME_ADDRESS");

		collateral = _collateral;

		emit CollateralAddressUpdated(_collateral);
	}

	/**
	 * @notice Register new liquid staking pool
	 * @param _pool Address of pool smart contract
	 * @dev Only triggered by registry admin
	 */
	function registerPool(address _pool) public {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");

		pools[_pool] = true;

		emit LiquidStakingPoolRegistered(_pool);
	}

	/**
	 * @notice Return a boolean flag whether `_pool` is active or not
	 */
	function isActivePool(address _pool) external view returns (bool) {
		return pools[_pool];
	}
}
