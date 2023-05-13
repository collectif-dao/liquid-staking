// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IResolverClient} from "./interfaces/IResolverClient.sol";
import {IBeneficiaryManager} from "./interfaces/IBeneficiaryManager.sol";
import {IStorageProviderRegistryClient as IRegistryClient} from "./interfaces/IStorageProviderRegistryClient.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MinerAPI, MinerTypes} from "filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import {FilAddresses} from "filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {BigInts, CommonTypes} from "filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import {FilAddress} from "fevmate/utils/FilAddress.sol";
import {PrecompilesAPI} from "filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";

/**
 * @title BeneficiaryManager allows SP to update their beneficiary addresses on Miner actors
 * as well as accept beneficiary from the Liquid Staking contract
 */
contract BeneficiaryManager is IBeneficiaryManager, Initializable, OwnableUpgradeable, UUPSUpgradeable {
	using FilAddress for address;

	error InvalidAccess();
	error InvalidParams();
	error InactiveActor();
	error InvalidOwner();
	error OwnerProposed();
	error InactiveSP();

	IResolverClient internal resolver;

	// Mapping of beneficiary status to miner IDs
	mapping(uint64 => bool) public beneficiaryStatus;

	/**
	 * @dev Contract initializer function.
	 */
	function initialize(address _resolver) public initializer {
		__Ownable_init();
		__UUPSUpgradeable_init();

		resolver = IResolverClient(_resolver);
	}

	/**
	 * @notice Triggers changeBeneficiary call on Miner actor as SP
	 *
	 * @dev This function could be triggered by miner owner address
	 */
	function changeBeneficiaryAddress() external virtual {
		address ownerAddr = msg.sender.normalize();

		(bool isID, uint64 ownerId) = ownerAddr.getActorID();
		if (!isID) revert InactiveActor();

		(, bool onboarded, address targetPool, uint64 minerId, int64 lastEpoch) = IRegistryClient(
			resolver.getRegistry()
		).storageProviders(ownerId);

		if (!onboarded) revert InactiveSP();

		uint256 quota = IRegistryClient(resolver.getRegistry()).getRepayment(ownerId);
		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(minerId);

		MinerTypes.GetOwnerReturn memory ownerReturn = MinerAPI.getOwner(actorId);
		if (keccak256(ownerReturn.proposed.data) != keccak256(bytes(""))) revert OwnerProposed();

		uint64 actualOwnerId = PrecompilesAPI.resolveAddress(ownerReturn.owner);
		if (ownerId != actualOwnerId) revert InvalidOwner();

		_executeChangeBeneficiary(actorId, quota, lastEpoch);

		emit BeneficiaryAddressUpdated(msg.sender, minerId, targetPool, quota, lastEpoch);
	}

	/**
	 * @notice Executes a changeBeneficiary call on MinerAPI
	 */
	function _executeChangeBeneficiary(
		CommonTypes.FilActorId minerId,
		uint256 quota,
		int64 expiration
	) internal virtual {
		MinerTypes.ChangeBeneficiaryParams memory params;
		params.new_beneficiary = FilAddresses.fromEthAddress(resolver.getRewardCollector());
		params.new_quota = BigInts.fromUint256(quota);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(expiration);

		MinerAPI.changeBeneficiary(minerId, params);
	}

	/**
	 * @notice Triggers update of beneficiary status for SP with `minerId`
	 * @param minerId SP miner ID (not owner)
	 * @param status Beneficiary status to indicate wether beneficiary address is synced with actual repayments
	 *
	 * @dev This function could be triggered by StorageProviderRegistry or RewardCollector contracts
	 */
	function updateBeneficiaryStatus(uint64 minerId, bool status) external virtual {
		if (msg.sender != resolver.getRegistry() && msg.sender != resolver.getRewardCollector()) revert InvalidAccess();
		if (status == beneficiaryStatus[minerId]) revert InvalidParams();

		beneficiaryStatus[minerId] = status;

		emit BeneficiaryStatusUpdated(minerId, status);
	}

	/**
	 * @notice UUPS Upgradeable function to update the liquid staking pool implementation
	 * @dev Only triggered by contract admin
	 */
	function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

	/**
	 * @notice Returns the version of clFIL token contract
	 */
	function version() external pure virtual returns (string memory) {
		return "v1";
	}

	/**
	 * @notice Returns the implementation contract
	 */
	function getImplementation() external view returns (address) {
		return _getImplementation();
	}
}
