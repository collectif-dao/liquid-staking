// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IPledgeOracle.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Pledge Oracle allows to record PreCommitDeposit and InitialPledge
 * historical amounts. This oracle contract is used to determine the amount of FIL
 * required to send to Storage Provider's miner actors while staking system
 * pledges FIL. It accounts for both PreCommitDeposit and InitialPledge amounts.
 *
 * @notice Oracle is expected to be reported for each epoch. However, there are no
 * such big differences in those fees being in a short period of time. In the future iteration,
 * a time-weighted average fee amount could be used with some level of deviation.
 *
 * @notice For the time being only selected actors could report into the Oracle to minimize
 * the risk of incorrect reports being recorded.
 */
contract PledgeOracle is IPledgeOracle, AccessControl {
	struct Record {
		uint256 preCommitDeposit;
		uint256 initialPledge;
	}

	uint256 public lastEpochReport;
	uint256 private constant epochTime = 30 seconds;
	uint256 public immutable genesisEpoch;

	bytes32 private constant ORACLE_REPORTER = keccak256("ORACLE_REPORTER");
	bytes32 private constant ORACLE_ADMIN = keccak256("ORACLE_ADMIN");

	// Mapping of fee records for network epochs
	mapping(uint256 => Record) records;

	constructor(uint256 genesis) {
		genesisEpoch = genesis;
		lastEpochReport = genesis;
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

		_setRoleAdmin(ORACLE_REPORTER, ORACLE_ADMIN);
		grantRole(ORACLE_ADMIN, msg.sender);
		grantRole(ORACLE_REPORTER, msg.sender);
	}

	/**
	 * @notice Updates record with `epoch` and fees
	 * @param epoch Filecoin network Epoch number
	 * @param preCommitDeposit PreCommitDeposit fee
	 * @param initialPledge Initial pledge fee
	 *
	 * @notice Only triggered by address with `ORACLE_REPORTER` role
	 */
	function updateRecord(uint256 epoch, uint256 preCommitDeposit, uint256 initialPledge) external {
		require(hasRole(ORACLE_REPORTER, msg.sender), "INVALID_ACCESS");
		require(epoch >= lastEpochReport, "PREVIOUS_EPOCH_RECORD_ATTEMPT");
		require(preCommitDeposit > 0 && initialPledge > 0, "INVALID_FEES");

		Record memory record;
		record.preCommitDeposit = preCommitDeposit;
		record.initialPledge = initialPledge;

		records[epoch] = record;
		lastEpochReport = epoch;

		emit RecordUpdated(epoch, preCommitDeposit, initialPledge);
	}

	/**
	 * @notice Return total amount of fees for PreCommitDeposit and Initial Pledge
	 */
	function getPledgeFees() external view returns (uint256) {
		Record memory record = records[lastEpochReport];
		return (record.preCommitDeposit + record.initialPledge);
	}

	/**
	 * @notice Returns record information with PreCommitDeposit and Initial Pledge fees
	 */
	function getLastRecord() external view returns (uint256, uint256) {
		Record memory record = records[lastEpochReport];
		return (record.preCommitDeposit, record.initialPledge);
	}

	/**
	 * @notice Returns historical record PreCommitDeposit and Initial Pledge fees for specific `epoch`
	 * @param epoch Filecoin network Epoch number
	 */
	function getHistoricalRecord(uint256 epoch) external view returns (uint256, uint256) {
		Record memory record = records[epoch];
		return (record.preCommitDeposit, record.initialPledge);
	}

	/**
	 * @notice Returns last record for PreCommitDeposit fee
	 */
	function getLastPreCommitDeposit() external view returns (uint256) {
		return records[lastEpochReport].preCommitDeposit;
	}

	/**
	 * @notice Returns historical record for PreCommitDeposit fee with specified `epoch`
	 * @param epoch Filecoin network Epoch number
	 */
	function getHistoricalPreCommitDeposit(uint256 epoch) external view returns (uint256) {
		return records[epoch].preCommitDeposit;
	}

	/**
	 * @notice Returns last record for Initial Pledge fee
	 */
	function getLastInitialPledge() external view returns (uint256) {
		return records[lastEpochReport].initialPledge;
	}

	/**
	 * @notice Returns historical record for Initial Pledge fee with specified `epoch`
	 * @param epoch Filecoin network Epoch number
	 */
	function getHistoricalInitialPledge(uint256 epoch) external view returns (uint256) {
		return records[epoch].initialPledge;
	}
}
