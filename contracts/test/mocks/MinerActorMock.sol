// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CommonTypes} from "filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import {BigIntCBOR} from "filecoin-solidity/contracts/v0.8/cbor/BigIntCbor.sol";
import {BigInts} from "filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/**
 * @title Miner actor mock contract
 * @author Collective DAO
 */
contract MinerActorMock {
	using SafeTransferLib for *;

	receive() external payable virtual {}

	function withdrawBalance(
		CommonTypes.FilActorId target,
		CommonTypes.BigInt memory amount
	) public returns (CommonTypes.BigInt memory withdrawn) {
		(uint256 withdraw, bool abort) = BigInts.toUint256(amount);
		require(!abort, "INCORRECT_BIG_NUM");

		msg.sender.safeTransferETH(withdraw);

		withdrawn = BigInts.fromUint256(withdraw);
	}
}

interface IMinerActorMock {
	function withdrawBalance(
		CommonTypes.FilActorId target,
		CommonTypes.BigInt memory amount
	) external returns (CommonTypes.BigInt memory);
}
