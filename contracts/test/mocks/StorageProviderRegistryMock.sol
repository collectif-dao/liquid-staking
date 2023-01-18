// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../../StorageProviderRegistry.sol";
import {MinerAPI as MockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerAPI.sol";
import {Bytes} from "../../libraries/Bytes.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title Storage Provider Registry Mock contract that works with mock Filecoin Miner API
 * @author Collective DAO
 */
contract StorageProviderRegistryMock is StorageProviderRegistry, MockAPI {
	using Counters for Counters.Counter;

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
	 * @notice Transfer beneficiary address of a miner to the target pool
	 * @param _beneficiaryAddress Beneficiary address like a pool strategy (i.e liquid staking pool)
	 */
	function changeBeneficiaryAddress(bytes memory _beneficiaryAddress) public override {
		address beneficiaryAddress = address(uint160(bytes20(_beneficiaryAddress)));

		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[msg.sender];
		address targetPool = storageProvider.targetPool;

		require(targetPool == beneficiaryAddress, "INVALID_ADDRESS");

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = _beneficiaryAddress;
		params.new_quota = BigIntCBOR.deserializeBigNum(Bytes.toBytes(storageProvider.allocationLimit));
		params.new_expiration = SafeCastLib.safeCastTo64(storageProvider.maxRedeemablePeriod);

		MockAPI.changeBeneficiary(params);

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
	) public override validBytes(_beneficiaryAddress) {
		address provider = address(uint160(bytes20(_provider)));
		StorageProviderTypes.StorageProvider memory storageProvider = storageProviders[provider];

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = _beneficiaryAddress;
		params.new_quota = BigIntCBOR.deserializeBigNum(Bytes.toBytes(storageProvider.allocationLimit));
		params.new_expiration = SafeCastLib.safeCastTo64(storageProvider.maxRedeemablePeriod);

		storageProviders[provider].active = true;
		totalInactiveStorageProviders.decrement();

		MockAPI.changeBeneficiary(params);

		emit StorageProviderBeneficiaryAddressAccepted(provider);
	}
}
