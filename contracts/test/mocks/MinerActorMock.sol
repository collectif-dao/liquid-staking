// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {MinerTypes} from "filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Bytes} from "../../libraries/Bytes.sol";

/**
 * @title Miner actor mock contract
 * @author Collective DAO
 */
contract MinerActorMock {
	using SafeTransferLib for *;
	using Bytes for *;

	receive() external payable virtual {}

	function withdrawBalance(
		bytes memory miner,
		MinerTypes.WithdrawBalanceParams memory params
	) public returns (MinerTypes.WithdrawBalanceReturn memory response) {
		require(keccak256(miner) == keccak256(abi.encodePacked(address(this))), "INVALID_ADDRESS");

		uint256 amount = Bytes.toUint256(params.amount_requested, 0);

		msg.sender.safeTransferETH(amount);

		response.amount_withdrawn = Bytes.toBytes(amount);
	}
}

interface IMinerActorMock {
	function withdrawBalance(
		bytes memory miner,
		MinerTypes.WithdrawBalanceParams memory params
	) external returns (MinerTypes.WithdrawBalanceReturn memory response);
}
