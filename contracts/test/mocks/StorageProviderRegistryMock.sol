// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../../StorageProviderRegistry.sol";
import {MinerMockAPI as MockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {Bytes} from "../../libraries/Bytes.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Storage Provider Registry Mock contract that works with mock Filecoin Miner API
 * @author Collective DAO
 */
contract StorageProviderRegistryMock is StorageProviderRegistry, MockAPI {
	using Counters for Counters.Counter;
	using Address for address;

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
		uint256 _maxStorageProviders,
		uint256 _maxAllocation,
		uint256 _minTimePeriod,
		uint256 _maxTimePeriod
	)
		StorageProviderRegistry(_maxStorageProviders, _maxAllocation, _minTimePeriod, _maxTimePeriod)
		MockAPI(_minerOwner)
	{}

	/**
	 * @notice Register storage provider with worker address `_worker` and desired `_allocationLimit`
	 * @param _miner Storage Provider miner address in Filecoin network
	 * @param _targetPool Target liquid staking strategy
	 * @param _allocationLimit FIL allocation for storage provider
	 * @param _period Redeemable period for FIL allocation
	 */
	function register(
		bytes memory _miner,
		address _targetPool,
		uint256 _allocationLimit,
		uint256 _period
	) public override validBytes(_miner) {
		require(_allocationLimit <= maxAllocation, "INVALID_ALLOCATION");
		require(_period <= maxTimePeriod, "INVALID_PERIOD");
		require(_targetPool.isContract(), "INVALID_TARGET_POOL");

		MinerTypes.GetOwnerReturn memory actualOwner = MockAPI.getOwner();
		bytes memory owner = abi.encodePacked(msg.sender);

		require(keccak256(owner) == keccak256(actualOwner.owner), "INVALID_MINER_OWNERSHIP");
		// require(keccak256(bytes("")) == keccak256(actualOwner.proposed), "PROPOSED_NEW_OWNER"); // MockAPI uses "0x00" for proposed owner

		StorageProviderTypes.StorageProvider storage storageProvider = storageProviders[owner];
		storageProvider.miner = _miner;
		storageProvider.targetPool = _targetPool;
		storageProvider.allocationLimit = _allocationLimit;

		// TODO: convert timestamp to Filecoin epochs
		if (_period == 0) {
			storageProvider.maxRedeemablePeriod = block.timestamp + minTimePeriod;
		} else {
			require(_period >= minTimePeriod && _period <= maxTimePeriod, "INVALID_PERIOD");
			storageProvider.maxRedeemablePeriod = _period + block.timestamp;
		}

		totalStorageProviders.increment();
		totalInactiveStorageProviders.increment();

		emit StorageProviderRegistered(owner, _miner, _targetPool, _allocationLimit, _period + block.timestamp);
	}

	/**
	 * @notice Transfer beneficiary address of a miner to the target pool
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 */
	function changeBeneficiaryAddress(address _beneficiaryAddress) public override {
		require(_beneficiaryAddress.isContract(), "INVALID_CONTRACT");
		bytes memory provider = abi.encodePacked(msg.sender);

		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[provider];
		address targetPool = storageProvider.targetPool;

		require(targetPool == _beneficiaryAddress, "INVALID_ADDRESS");

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = abi.encodePacked(_beneficiaryAddress);
		params.new_quota = BigIntCBOR.deserializeBigInt(Bytes.toBytes(storageProvider.allocationLimit));
		params.new_expiration = SafeCastLib.safeCastTo64(storageProvider.maxRedeemablePeriod);

		MockAPI.changeBeneficiary(params);

		emit StorageProviderBeneficiaryAddressUpdated(_beneficiaryAddress);
	}

	/**
	 * @notice Accept beneficiary address transfer and activate FIL allocation
	 * @param _provider Storage Provider owner address
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 */
	function acceptBeneficiaryAddress(bytes memory _provider, address _beneficiaryAddress) public override {
		require(_beneficiaryAddress.isContract(), "INVALID_CONTRACT");

		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[_provider];
		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = abi.encodePacked(_beneficiaryAddress);
		params.new_quota = BigIntCBOR.deserializeBigInt(Bytes.toBytes(storageProvider.allocationLimit));
		params.new_expiration = SafeCastLib.safeCastTo64(storageProvider.maxRedeemablePeriod);

		storageProviders[_provider].active = true;
		totalInactiveStorageProviders.decrement();

		MockAPI.changeBeneficiary(params);

		emit StorageProviderBeneficiaryAddressAccepted(_provider);
	}
}
