// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {MinerAPI, MinerTypes, CommonTypes} from "filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import {PrecompilesAPI} from "filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";
import {StorageProviderTypes} from "./types/StorageProviderTypes.sol";
import {FilAddress} from "fevmate/utils/FilAddress.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {BokkyPooBahsDateTimeLibrary} from "./libraries/DateTimeLibraryCompressed.sol";
import {IStorageProviderRegistry} from "./interfaces/IStorageProviderRegistry.sol";
import {ILiquidStakingClient} from "./interfaces/ILiquidStakingClient.sol";
import {IStorageProviderCollateralClient} from "./interfaces/IStorageProviderCollateralClient.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

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

	// Mapping of liquid staking pools to it addresses
	mapping(address => bool) public pools;

	bytes32 private constant REGISTRY_ADMIN = keccak256("REGISTRY_ADMIN");

	uint256 public maxAllocation;

	IStorageProviderCollateralClient public collateral;

	modifier activeStorageProvider(uint64 _ownerId) {
		require(storageProviders[_ownerId].active, "INACTIVE_STORAGE_PROVIDER");
		_;
	}

	modifier onlyAdmin() {
		require(hasRole(REGISTRY_ADMIN, msg.sender), "INVALID_ACCESS");
		_;
	}

	/**
	 * @dev Contract initializer function.
	 * @param _maxAllocation Number of maximum FIL allocated to a single storage provider
	 */
	function initialize(uint256 _maxAllocation) public initializer {
		__AccessControl_init();
		__ReentrancyGuard_init();
		__UUPSUpgradeable_init();

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setRoleAdmin(REGISTRY_ADMIN, DEFAULT_ADMIN_ROLE);
		grantRole(REGISTRY_ADMIN, msg.sender);
		maxAllocation = _maxAllocation;
	}

	struct RegisterLocalVars {
		address ownerAddr;
		bool isID;
		uint64 msgSenderId;
		uint64 ownerId;
		uint64 sectorSize;
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
	) public virtual override nonReentrant {
		require(_allocationLimit > 0 && _allocationLimit <= maxAllocation, "INCORRECT_ALLOCATION");
		require(_dailyAllocation > 0 && _dailyAllocation <= _allocationLimit, "INCORRECT_DAILY_ALLOCATION");
		require(pools[_targetPool], "INVALID_TARGET_POOL");

		RegisterLocalVars memory vars;

		vars.ownerAddr = msg.sender.normalize();
		(vars.isID, vars.msgSenderId) = vars.ownerAddr.getActorID();
		require(vars.isID, "INACTIVE_ACTOR_ID");

		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(_minerId);

		MinerTypes.GetOwnerReturn memory ownerReturn = MinerAPI.getOwner(actorId);
		require(keccak256(ownerReturn.proposed.data) == keccak256(bytes("")), "PROPOSED_NEW_OWNER");

		vars.ownerId = PrecompilesAPI.resolveAddress(ownerReturn.owner);
		require(vars.ownerId == vars.msgSenderId, "INVALID_MINER_OWNERSHIP");
		require(!storageProviders[vars.ownerId].onboarded, "ALREADY_REGISTERED");

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[vars.ownerId];
		storageProvider.minerId = _minerId;
		storageProvider.targetPool = _targetPool;

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[vars.ownerId];
		spAllocation.allocationLimit = _allocationLimit;
		spAllocation.dailyAllocation = _dailyAllocation;

		vars.sectorSize = MinerAPI.getSectorSize(actorId);
		sectorSizes[vars.ownerId] = vars.sectorSize;

		collateral.updateCollateralRequirements(vars.ownerId, 0);
		ILiquidStakingClient(_targetPool).updateProfitShare(vars.ownerId, 0);

		emit StorageProviderRegistered(
			ownerReturn.owner.data,
			vars.ownerId,
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
	) public virtual onlyAdmin nonReentrant {
		require(_allocationLimit > 0 && _allocationLimit <= maxAllocation, "INCORRECT_ALLOCATION");
		require(_dailyAllocation > 0 && _dailyAllocation <= _allocationLimit, "INCORRECT_DAILY_ALLOCATION");
		require(_repayment > _allocationLimit, "INCORRECT_REPAYMENT");

		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(_minerId);

		MinerTypes.GetOwnerReturn memory ownerReturn = MinerAPI.getOwner(actorId);
		require(keccak256(bytes("")) == keccak256(ownerReturn.proposed.data), "PROPOSED_NEW_OWNER");

		uint64 ownerId = PrecompilesAPI.resolveAddress(ownerReturn.owner);

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
	function changeBeneficiaryAddress() public virtual override nonReentrant {
		address ownerAddr = msg.sender.normalize();
		(bool isID, uint64 ownerId) = ownerAddr.getActorID();
		require(isID, "INACTIVE_ACTOR_ID");

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
	 * @dev Only triggered by registry admin
	 */
	function acceptBeneficiaryAddress(uint64 _ownerId) public virtual override onlyAdmin nonReentrant {
		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_ownerId];
		require(storageProvider.onboarded, "NON_ONBOARDED_SP");

		ILiquidStakingClient(storageProviders[_ownerId].targetPool).forwardChangeBeneficiary(
			storageProvider.minerId,
			storageProvider.targetPool,
			allocations[_ownerId].repayment,
			storageProvider.lastEpoch
		);

		storageProviders[_ownerId].active = true;

		emit StorageProviderBeneficiaryAddressAccepted(_ownerId);
	}

	/**
	 * @notice Deactive storage provider with ID `_ownerId`
	 * @param _ownerId Storage Provider owner ID
	 * @dev Only triggered by registry admin
	 */
	function deactivateStorageProvider(uint64 _ownerId) public onlyAdmin activeStorageProvider(_ownerId) {
		storageProviders[_ownerId].active = false;

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
	) public virtual onlyAdmin activeStorageProvider(_ownerId) {
		uint64 prevMiner = storageProviders[_ownerId].minerId;
		require(prevMiner != _minerId, "SAME_MINER");

		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(_minerId);

		MinerTypes.GetOwnerReturn memory ownerReturn = MinerAPI.getOwner(actorId);
		require(keccak256(ownerReturn.proposed.data) == keccak256(bytes("")), "PROPOSED_NEW_OWNER");

		uint64 ownerId = PrecompilesAPI.resolveAddress(ownerReturn.owner);
		require(ownerId == _ownerId, "INVALID_MINER_OWNERSHIP");

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
		require(_allocationLimit > 0 && _allocationLimit <= maxAllocation, "INCORRECT_ALLOCATION");
		require(_dailyAllocation > 0 && _dailyAllocation <= _allocationLimit, "INCORRECT_DAILY_ALLOCATION");
		address ownerAddr = msg.sender.normalize();
		(bool isID, uint64 ownerId) = ownerAddr.getActorID();
		require(isID, "INACTIVE_ACTOR_ID");

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
	 * @dev Only triggered by registry admin
	 */
	function updateAllocationLimit(
		uint64 _ownerId,
		uint256 _allocationLimit,
		uint256 _dailyAllocation,
		uint256 _repaymentAmount
	) public virtual override onlyAdmin activeStorageProvider(_ownerId) nonReentrant {
		require(_allocationLimit > 0 && _allocationLimit <= maxAllocation, "INCORRECT_ALLOCATION");
		require(_dailyAllocation > 0 && _dailyAllocation <= _allocationLimit, "INCORRECT_DAILY_ALLOCATION");
		require(_repaymentAmount > _allocationLimit, "INCORRECT_REPAYMENT");

		StorageProviderTypes.AllocationRequest memory allocationRequest = allocationRequests[_ownerId];

		if (allocationRequest.allocationLimit > 0) {
			// If SP requested allocation update should fulfil their request first
			require(allocationRequest.allocationLimit == _allocationLimit, "INVALID_ALLOCATION");
			require(allocationRequest.dailyAllocation == _dailyAllocation, "INVALID_DAILY_ALLOCATION");
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
		uint64 ownerId = PrecompilesAPI.resolveEthAddress(msg.sender);

		require(_restakingRatio <= 10000, "INVALID_RESTAKING_RATIO");
		require(_restakingAddress != address(0), "INVALID_ADDRESS");

		StorageProviderTypes.SPRestaking storage restaking = restakings[ownerId];
		restaking.restakingRatio = _restakingRatio;
		restaking.restakingAddress = _restakingAddress;

		emit StorageProviderMinerRestakingRatioUpdate(ownerId, _restakingRatio, _restakingAddress);
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
		require(msg.sender == address(collateral), "INVALID_ACCESS");

		(uint year, uint month, uint day) = BokkyPooBahsDateTimeLibrary.timestampToDate(_timestamp);
		bytes32 dateHash = keccak256(abi.encodePacked(year, month, day));

		uint256 usedDailyAlloc = dailyUsages[dateHash];
		uint256 totalDailyUsage = usedDailyAlloc + _allocated;

		StorageProviderTypes.SPAllocation storage spAllocation = allocations[_ownerId];

		require(totalDailyUsage <= spAllocation.dailyAllocation, "DAILY_ALLOCATION_OVERFLOW");
		// require(spAllocation.usedAllocation + _allocated <= spAllocation.allocationLimit, "TOTAL_ALLOCATION_OVERFLOW");

		spAllocation.usedAllocation = spAllocation.usedAllocation + _allocated;
		dailyUsages[dateHash] += _allocated;

		emit StorageProviderAllocationUsed(_ownerId, _allocated);
	}

	/**
	 * @notice Update StorageProviderCollateral smart contract
	 * @param _collateral StorageProviderCollateral smart contract address
	 * @dev Only triggered by registry admin
	 */
	function setCollateralAddress(address _collateral) public onlyAdmin {
		require(_collateral != address(0), "INVALID_ADDRESS");

		address prevCollateral = address(collateral);
		require(prevCollateral != _collateral, "SAME_ADDRESS");

		collateral = IStorageProviderCollateralClient(_collateral);

		emit CollateralAddressUpdated(_collateral);
	}

	/**
	 * @notice Register new liquid staking pool
	 * @param _pool Address of pool smart contract
	 * @dev Only triggered by registry admin
	 */
	function registerPool(address _pool) public onlyAdmin {
		require(_pool != address(0), "INVALID_ADDRESS");
		require(!pools[_pool], "ALREADY_ACTIVE_POOL");

		pools[_pool] = true;

		emit LiquidStakingPoolRegistered(_pool);
	}

	/**
	 * @notice Updates maximum allocation amount for SP
	 * @param allocation New max allocation per SP
	 */
	function updateMaxAllocation(uint256 allocation) public onlyAdmin {
		require(allocation > 0, "INVALID_ALLOCATION");

		uint256 prevAllocation = maxAllocation;
		require(allocation != prevAllocation, "SAME_ALLOCATION");

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
