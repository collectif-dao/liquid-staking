// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {MinerAPI} from "filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import {PrecompilesAPI} from "filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";
import {MinerTypes} from "filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import {CommonTypes} from "filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import {FilAddresses} from "filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {BigInts} from "filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import {FilAddress} from "fevmate/utils/FilAddress.sol";

contract MinerAPICallerMock {
	bytes public owner;
	bytes public proposed;
	uint64 public sectorSize;

	address public lastMsgSender;
	bytes public lastMsgSenderBytes;

	function getOwner(uint64 target) public {
		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(target);

		MinerTypes.GetOwnerReturn memory ownerReturn = MinerAPI.getOwner(actorId);

		owner = ownerReturn.owner.data;
		proposed = ownerReturn.proposed.data;
	}

	function getSectorSize(uint64 target) public {
		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(target);
		sectorSize = MinerAPI.getSectorSize(actorId);
	}

	function changeBeneficiary(uint64 target, uint256 allocationLimit, int64 lastEpoch) public {
		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(target);

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = FilAddresses.fromEthAddress(msg.sender);
		params.new_quota = BigInts.fromUint256(allocationLimit);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(lastEpoch);

		MinerAPI.changeBeneficiary(actorId, params);
	}

	function withdrawBalance(uint64 target, uint256 amount) public returns (uint256) {
		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(target);
		CommonTypes.BigInt memory amt = BigInts.fromUint256(amount);

		CommonTypes.BigInt memory withdrawn = MinerAPI.withdrawBalance(actorId, amt);

		(uint256 withdrawnAmt, bool abort) = BigInts.toUint256(withdrawn);
		require(!abort, "INVALID_CONVERSION");

		return withdrawnAmt;
	}

	function resolveAddressFromBytes(bytes memory target) public view returns (uint64) {
		CommonTypes.FilAddress memory fAddr = FilAddresses.fromBytes(target);
		return PrecompilesAPI.resolveAddress(fAddr);
	}

	function resolveAddressFromActorId(uint64 target) public view returns (uint64) {
		CommonTypes.FilAddress memory fAddr = FilAddresses.fromActorID(target);
		return PrecompilesAPI.resolveAddress(fAddr);
	}

	function resolveEthAddress(address target) public view returns (uint64) {
		CommonTypes.FilAddress memory fAddr = FilAddresses.fromEthAddress(target);
		return PrecompilesAPI.resolveAddress(fAddr);
	}

	function resolveEthAddress2(address target) public view returns (uint64) {
		return PrecompilesAPI.resolveEthAddress(target);
	}

	function resolveBLSAddress() public returns (uint64) {
		bytes memory addrBytes = abi.encodePacked(msg.sender);

		lastMsgSender = msg.sender;
		lastMsgSenderBytes = addrBytes;

		CommonTypes.FilAddress memory fAddr = FilAddresses.fromBytes(addrBytes);

		return PrecompilesAPI.resolveAddress(fAddr);
	}

	function normalizeAddress() public returns (address) {
		lastMsgSender = msg.sender;

		return FilAddress.normalize(msg.sender);
	}

	function checkOwnership(uint64 _minerId) public {
		address ownerAddr = FilAddress.normalize(msg.sender);
		(, uint64 msgSenderId) = FilAddress.getActorID(ownerAddr);

		CommonTypes.FilActorId actorId = CommonTypes.FilActorId.wrap(_minerId);

		MinerTypes.GetOwnerReturn memory ownerReturn = MinerAPI.getOwner(actorId);
		require(keccak256(ownerReturn.proposed.data) == keccak256(bytes("")), "PROPOSED_NEW_OWNER");

		uint64 ownerId = PrecompilesAPI.resolveAddress(ownerReturn.owner);
		require(ownerId == msgSenderId, "INVALID_MINER_OWNERSHIP");
	}

	function isIDAddress() public view returns (bool isID, uint64 idAddr) {
		(isID, idAddr) = FilAddress.isIDAddress(msg.sender);
	}

	function getActorID() public view returns (bool isID, uint64 idAddr) {
		(isID, idAddr) = FilAddress.getActorID(msg.sender);
	}
}
