// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// contract TestParams {
// 	bytes public owner;

// 	uint256 private aliceKey = 0xBEEF;
// 	address private alice = address(0x122);
// 	bytes private aliceBytesAddress = abi.encodePacked(alice);
// 	address private aliceRestaking = address(0x123412);
// 	address private aliceOwnerAddr = address(0x12341214212);
// 	uint64 public aliceOwnerId = 1508;
// 	uint64 public aliceMinerId = 16121;

// 	address private bob = address(0x123);
// 	uint64 public bobOwnerId = 1521;
// 	uint64 private oldMinerId = 1648;

// 	uint256 private adminFee = 1000;
// 	uint256 private profitShare = 2000;
// 	address private rewardCollector = address(0x12523);

// 	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
// 	uint256 private constant MAX_ALLOCATION = 10000 ether;
// 	uint256 private constant MIN_TIME_PERIOD = 90 days;
// 	uint256 private constant MAX_TIME_PERIOD = 360 days;
// 	uint256 private constant SAMPLE_DAILY_ALLOCATION = MAX_ALLOCATION / 30;

// 	uint256 public collateralRequirements = 1500;
// 	uint256 public constant BASIS_POINTS = 10000;
// 	uint256 private constant genesisEpoch = 56576;
// 	uint256 private constant preCommitDeposit = 95700000000000000;
// 	uint256 private constant initialPledge = 151700000000000000;

// 	bytes32 public constant ORACLE_REPORTER = keccak256("ORACLE_REPORTER");
// }
