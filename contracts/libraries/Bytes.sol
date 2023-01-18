// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

library Bytes {
	function toBytes(uint256 target) public pure returns (bytes memory b) {
		b = new bytes(32);
		assembly {
			mstore(add(b, 32), target)
		}
	}
}
