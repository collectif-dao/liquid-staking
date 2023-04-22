// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {PledgeOracle} from "../oracle/PledgeOracle.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

contract PledgeOracleTest is DSTestPlus {
	PledgeOracle public oracle;

	uint256 private aliceKey = 0xBEEF;
	address private alice = address(0x122);
	uint256 private constant genesisEpoch = 56576;
	bytes32 public constant ORACLE_REPORTER = keccak256("ORACLE_REPORTER");

	function setUp() public {
		alice = hevm.addr(aliceKey);
		oracle = new PledgeOracle(genesisEpoch);
	}

	function testUpdateRecord(uint256 epoch, uint128 preCommitDeposit, uint128 initialPledge) external {
		hevm.assume(epoch >= genesisEpoch && preCommitDeposit > 0 && initialPledge > 0);
		oracle.updateRecord(epoch, preCommitDeposit, initialPledge);

		require(oracle.getLastPreCommitDeposit() == preCommitDeposit, "INVALID_PRE_COMMIT_DEPOSIT");
		require(oracle.getLastInitialPledge() == initialPledge, "INVALID_INITIAL_PLEDGE");
		require(oracle.getPledgeFees() == uint256(preCommitDeposit) + uint256(initialPledge), "INVALID_PLEDGE_FEES"); // uint128 -> uint256 conversion to reduce the risk of arithmetic over/underflow
	}

	function testUpdateRecordReverts(uint256 epoch, uint256 preCommitDeposit, uint256 initialPledge) external {
		hevm.assume(epoch >= genesisEpoch);

		hevm.prank(alice);
		hevm.expectRevert("INVALID_ACCESS");
		oracle.updateRecord(epoch, preCommitDeposit, initialPledge);
	}

	function testUpdateRecordWithNewReporter(uint256 epoch, uint128 preCommitDeposit, uint128 initialPledge) external {
		hevm.assume(epoch >= genesisEpoch && preCommitDeposit > 0 && initialPledge > 0);
		oracle.grantRole(ORACLE_REPORTER, alice);

		hevm.prank(alice);
		oracle.updateRecord(epoch, preCommitDeposit, initialPledge);

		require(oracle.getLastPreCommitDeposit() == preCommitDeposit, "INVALID_PRE_COMMIT_DEPOSIT");
		require(oracle.getLastInitialPledge() == initialPledge, "INVALID_INITIAL_PLEDGE");
		require(oracle.getPledgeFees() == uint256(preCommitDeposit) + uint256(initialPledge), "INVALID_PLEDGE_FEES"); // uint128 -> uint256 conversion to reduce the risk of arithmetic over/underflow
	}

	function testUpdateRecordRevertsWithPreviousEpoch(
		uint256 epoch,
		uint256 preCommitDeposit,
		uint256 initialPledge
	) external {
		hevm.assume(epoch < genesisEpoch);

		hevm.expectRevert("PREVIOUS_EPOCH_RECORD_ATTEMPT");
		oracle.updateRecord(epoch, preCommitDeposit, initialPledge);
	}

	function testUpdateRecordRevertsWithZeroFees(uint256 epoch) external {
		hevm.assume(epoch >= genesisEpoch);

		hevm.expectRevert("INVALID_FEES");
		oracle.updateRecord(epoch, 0, 0);

		hevm.expectRevert("INVALID_FEES");
		oracle.updateRecord(epoch, 0, 1);

		hevm.expectRevert("INVALID_FEES");
		oracle.updateRecord(epoch, 1, 0);
	}
}
