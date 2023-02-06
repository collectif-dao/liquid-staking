// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPledgeOracleClient {
	function getPledgeFees() external view returns (uint256);
}
