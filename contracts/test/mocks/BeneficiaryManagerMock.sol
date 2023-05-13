// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../BeneficiaryManager.sol";
import {MinerMockAPI as MockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {FilAddresses} from "filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";

/**
 * @title Storage Provider Registry Mock contract that works with mock Filecoin Miner API
 * @author Collective DAO
 */
contract BeneficiaryManagerMock is BeneficiaryManager, DSTestPlus {
	uint64 public ownerId;

	MockAPI private mockAPI;

	/**
	 * @dev Contract initializer function.
	 */
	function initialize(address _minerApiMock, uint64 _ownerId, address _resolver) public initializer {
		__Ownable_init();
		__UUPSUpgradeable_init();

		resolver = IResolverClient(_resolver);

		ownerId = _ownerId;
		mockAPI = MockAPI(_minerApiMock);
		resolver = IResolverClient(_resolver);
	}

	function changeBeneficiaryAddress() external override {
		(, bool onboarded, address targetPool, uint64 minerId, int64 lastEpoch) = IRegistryClient(
			resolver.getRegistry()
		).storageProviders(ownerId);

		if (!onboarded) revert InactiveSP();

		uint256 quota = IRegistryClient(resolver.getRegistry()).getRepayment(ownerId);

		MinerTypes.GetOwnerReturn memory ownerReturn = mockAPI.getOwner();
		if (keccak256(ownerReturn.proposed.data) != keccak256(bytes("0x00"))) revert OwnerProposed();

		bytes memory senderBytes = Leb128.encodeUnsignedLeb128FromUInt64(ownerId).buf;
		bytes memory ownerBytes = FilAddresses.fromBytes(ownerReturn.owner.data).data;
		if (keccak256(senderBytes) != keccak256(ownerBytes)) revert InvalidOwner();

		_executeChangeBeneficiary(CommonTypes.FilActorId.wrap(minerId), quota, lastEpoch);
	}

	/**
	 * @notice Executes a changeBeneficiary call on MinerAPI
	 */
	function _executeChangeBeneficiary(
		CommonTypes.FilActorId minerId,
		uint256 quota,
		int64 expiration
	) internal override {
		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = FilAddresses.fromEthAddress(resolver.getRewardCollector());
		params.new_quota = BigInts.fromUint256(quota);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(expiration);

		mockAPI.changeBeneficiary(params);
	}
}

/**
 * @title Beneficiary Manager Caller Mock contract that routes calls to BeneficiaryManager
 * @author Collective DAO
 */
contract BeneficiaryManagerCallerMock {
	IBeneficiaryManager public manager;

	/**
	 * @dev Contract constructor function.
	 * @param _manager BeneficiaryManagerCallerMock address to route calls
	 *
	 */
	constructor(address _manager) {
		manager = IBeneficiaryManager(_manager);
	}

	/**
	 * @notice Triggers update of beneficiary status for SP with `minerId`
	 * @param minerId SP miner ID (not owner)
	 * @param status Beneficiary status to indicate wether beneficiary address is synced with actual repayments
	 *
	 * @dev This function could be triggered by StorageProviderRegistry or RewardCollector contracts
	 */
	function updateBeneficiaryStatus(uint64 minerId, bool status) external {
		manager.updateBeneficiaryStatus(minerId, status);
	}
}