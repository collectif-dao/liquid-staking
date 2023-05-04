// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {BigInts, CommonTypes} from "filecoin-solidity/contracts/v0.8/utils/BigInts.sol";

interface IBigInts {
	function toUint256(CommonTypes.BigInt memory bigInt) external view returns (uint256, bool);

	function fromUint256(uint256 value) external view returns (CommonTypes.BigInt memory);

	function toInt256(CommonTypes.BigInt memory bigInt) external view returns (int256, bool);

	function fromInt256(int256 value) external view returns (CommonTypes.BigInt memory);
}

contract BigIntsClient is IBigInts {
	using BigInts for *;

	function toUint256(CommonTypes.BigInt memory bigInt) external view returns (uint256, bool) {
		return bigInt.toUint256();
	}

	function fromUint256(uint256 value) external view returns (CommonTypes.BigInt memory) {
		return value.fromUint256();
	}

	function toInt256(CommonTypes.BigInt memory bigInt) external view returns (int256, bool) {
		return bigInt.toInt256();
	}

	function fromInt256(int256 value) external view returns (CommonTypes.BigInt memory) {
		return value.fromInt256();
	}
}
