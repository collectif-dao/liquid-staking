// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {MinerAPI} from "filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import {MinerTypes} from "filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import {BigIntCBOR} from "filecoin-solidity/contracts/v0.8/cbor/BigIntCbor.sol";
import {StorageProviderTypes} from "./types/StorageProviderTypes.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {Bytes} from "./libraries/Bytes.sol";

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IStorageProviderRegistry.sol";

/**
 * @title Storage Provider Registry contract allows storage providers to register
 * in liquid staking protocol and ask for a FIL allocation.
 *
 * Once Storage Provider is registered and signaled their desired FIL allocation
 * it needs to transfer
 *
 */
contract StorageProviderRegistry is IStorageProviderRegistry {
	using SafeCastLib for uint256;
	using Counters for Counters.Counter;
	using Address for address;

	// Mapping of storage provider addresses to their storage provider info
	mapping(address => StorageProviderTypes.StorageProvider) public storageProviders;

	Counters.Counter public totalStorageProviders;
	Counters.Counter public totalInactiveStorageProviders;

	uint256 public maxStorageProviders;
	uint256 public maxAllocation;
	uint256 public minTimePeriod;
	uint256 public maxTimePeriod;

	address public collateral;

	modifier validAddress(address _address) {
		require(_address != address(0), "EMPTY_ADDRESS");
		_;
	}

	modifier validBytes(bytes memory _bytes) {
		require(_bytes.length != 0, "INVALID_BYTES");
		_;
	}

	modifier activeStorageProvider(address _provider) {
		require(storageProviders[_provider].active, "INACTIVE_STORAGE_PROVIDER");
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
		maxStorageProviders = _maxStorageProviders;
		maxAllocation = _maxAllocation;
		minTimePeriod = _minTimePeriod;
		maxTimePeriod = _maxTimePeriod;
	}

	/**
	 * @notice Register storage provider with worker address `_worker` and desired `_allocationLimit`
	 * @param _worker Storage Provider worker address in Filecoin network
	 * @param _targetPool Target liquid staking strategy
	 * @param _allocationLimit FIL allocation for storage provider
	 * @param _period Redeemable period for FIL allocation
	 */
	function register(
		address _worker,
		address _targetPool,
		uint256 _allocationLimit,
		uint256 _period
	) public validAddress(_worker) {
		require(_allocationLimit <= maxAllocation, "INVALID_ALLOCATION");
		require(_period <= maxTimePeriod, "INVALID_PERIOD");
		require(_targetPool.isContract(), "INVALID_TARGET_POOL");

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[msg.sender];
		storageProvider.worker = _worker;
		storageProvider.targetPool = _targetPool;
		storageProvider.allocationLimit = _allocationLimit;

		if (_period == 0) {
			storageProvider.maxRedeemablePeriod = block.timestamp + minTimePeriod;
		} else {
			require(_period >= minTimePeriod && _period <= maxTimePeriod, "INVALID_PERIOD");
			storageProvider.maxRedeemablePeriod = _period + block.timestamp;
		}

		totalStorageProviders.increment();
		totalInactiveStorageProviders.increment();

		emit StorageProviderRegistered(msg.sender, _worker, _targetPool, _allocationLimit, _period + block.timestamp);
	}

	/**
	 * @notice Transfer beneficiary address of a miner to the target pool
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 */
	function changeBeneficiaryAddress(bytes memory _beneficiaryAddress) public virtual override {
		address beneficiaryAddress = address(uint160(bytes20(_beneficiaryAddress)));
		require(beneficiaryAddress.isContract(), "INVALID_CONTRACT");

		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[msg.sender];
		address targetPool = storageProvider.targetPool;

		require(targetPool == beneficiaryAddress, "INVALID_ADDRESS");

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = _beneficiaryAddress;
		params.new_quota = BigIntCBOR.deserializeBigNum(Bytes.toBytes(storageProvider.allocationLimit));
		params.new_expiration = SafeCastLib.safeCastTo64(storageProvider.maxRedeemablePeriod);

		MinerAPI.changeBeneficiary(abi.encodePacked(msg.sender), params);

		emit StorageProviderBeneficiaryAddressUpdated(beneficiaryAddress);
	}

	/**
	 * @notice Accept beneficiary address transfer and activate FIL allocation
	 * @param _provider Storage Provider owner address
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 */
	function acceptBeneficiaryAddress(
		bytes memory _provider,
		bytes memory _beneficiaryAddress
	) public virtual override validBytes(_beneficiaryAddress) {
		address provider = address(uint160(bytes20(_provider)));
		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[provider];

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = _beneficiaryAddress;
		params.new_quota = BigIntCBOR.deserializeBigNum(Bytes.toBytes(storageProvider.allocationLimit));
		params.new_expiration = SafeCastLib.safeCastTo64(storageProvider.maxRedeemablePeriod);

		storageProviders[provider].active = true;
		totalInactiveStorageProviders.decrement();

		MinerAPI.changeBeneficiary(_provider, params);

		emit StorageProviderBeneficiaryAddressAccepted(provider);
	}

	/**
	 * @notice Deactive storage provider with address `_provider`
	 * @param _provider Storage Provider owner address
	 * @dev Only triggered by owner contract
	 */
	function deactivateStorageProvider(address _provider) public validAddress(_provider) {
		storageProviders[_provider].active = false;
		totalInactiveStorageProviders.increment();

		emit StorageProviderDeactivated(_provider);
	}

	/**
	 * @notice Update storage provider worker address with `_worker`
	 * @param _provider Storage Provider owner address
	 * @param _worker Storage Provider new worker address
	 * @dev Only triggered by owner contract
	 */
	function setWorkerAddress(
		address _provider,
		address _worker
	) public activeStorageProvider(_provider) validAddress(_worker) {
		address prevWorker = storageProviders[_provider].worker;
		require(prevWorker != _worker, "SAME_WORKER");
		storageProviders[_provider].worker = _worker;

		emit StorageProviderWorkerAddressUpdate(_provider, _worker);
	}

	/**
	 * @notice Update storage provider FIL allocation with `_allocationLimit`
	 * @param _provider Storage provider owner address
	 * @param _allocationLimit New FIL allocation for storage provider
	 * @dev Only triggered by owner contract
	 */
	function setAllocationLimit(address _provider, uint256 _allocationLimit) public activeStorageProvider(_provider) {
		uint256 prevLimit = storageProviders[_provider].allocationLimit;
		require(prevLimit != _allocationLimit, "SAME_ALLOCATION_LIMIT");
		storageProviders[_provider].allocationLimit = _allocationLimit;

		emit StorageProviderAllocationLimitUpdate(_provider, _allocationLimit);
		// TODO: add allocation change on changeBeneficiary method (for MinerAPI)
	}

	/**
	 * @notice Update max redeemable period of FIL allocation for `_provider`
	 * @param _provider Storage provider owner address
	 * @param _period New max redeemable period
	 * @dev Only triggered by owner contract
	 */
	function setMaxRedeemablePeriod(address _provider, uint256 _period) public activeStorageProvider(_provider) {
		require(_period <= maxTimePeriod && _period >= minTimePeriod, "INVALID_PERIOD");

		uint256 prevPeriod = storageProviders[_provider].maxRedeemablePeriod;
		uint256 period = _period + block.timestamp;

		require(prevPeriod != period, "SAME_TIME_PERIOD");
		storageProviders[_provider].maxRedeemablePeriod = period;

		emit StorageProviderMaxRedeemablePeriodUpdate(_provider, period);
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
	 * @notice Return Storage Provider information with `_provider` address
	 */
	function getStorageProvider(
		address _provider
	) public view returns (bool, address, address, uint256, uint256, uint256, uint256, uint256) {
		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_provider];
		return (
			storageProvider.active,
			storageProvider.targetPool,
			storageProvider.worker,
			storageProvider.allocationLimit,
			storageProvider.usedAllocation,
			storageProvider.accruedRewards,
			storageProvider.lockedRewards,
			storageProvider.maxRedeemablePeriod
		);
	}

	/**
	 * @notice Return a boolean flag of Storage Provider activity
	 */
	function isActiveProvider(address _provider) external view returns (bool status) {
		status = storageProviders[_provider].active;
	}

	/**
	 * @notice Increase collected rewards by Storage Provider
	 * @param _provider Storage Provider owner address
	 * @param _accuredRewards Unlocked portion of rewards, that available for withdrawal
	 * @param _lockedRewards Locked portion of rewards, that not available for withdrawal
	 */
	function increaseRewards(address _provider, uint256 _accuredRewards, uint256 _lockedRewards) external {
		require(msg.sender == collateral, "INVALID_ACCESS");
		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[_provider];
		storageProvider.accruedRewards = storageProvider.accruedRewards + _accuredRewards;
		storageProvider.lockedRewards = storageProvider.lockedRewards + _lockedRewards;

		emit StorageProviderLockedRewards(_provider, _lockedRewards);
		emit StorageProviderAccruedRewards(_provider, _accuredRewards);
	}

	/**
	 * @notice Increase used allocation for Storage Provider
	 * @param _provider Storage Provider owner address
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function increaseUsedAllocation(address _provider, uint256 _allocated) external {
		require(msg.sender == collateral, "INVALID_ACCESS");
		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[_provider];
		storageProvider.usedAllocation = storageProvider.usedAllocation + _allocated;

		emit StorageProviderAllocationUsed(_provider, _allocated);
	}

	/**
	 * @notice Update StorageProviderCollateral smart contract
	 * @param _collateral StorageProviderCollateral smart contract address
	 * @dev Only triggered by owner contract
	 */
	function setCollateralAddress(address _collateral) public {
		collateral.isContract();
		address prevCollateral = collateral;
		require(prevCollateral != _collateral, "SAME_ADDRESS");
		collateral = _collateral;

		emit CollateralAddressUpdated(_collateral);
	}
}
