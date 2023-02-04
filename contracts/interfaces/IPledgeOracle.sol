// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IPledgeOracle {
	/**
	 * @notice Emitted new record with fees is reported on the PledgeOracle
	 * @param epoch Filecoin network Epoch number
	 * @param preCommitDeposit PreCommitDeposit fee
	 * @param initialPledge Initial pledge fee
	 */
	event RecordUpdated(uint256 epoch, uint256 preCommitDeposit, uint256 initialPledge);

	/**
	 * @notice Returns last reported epoch for PledgeOracle
	 */
	function lastEpochReport() external view returns (uint256);

	/**
	 * @notice Returns genesis epoch for PledgeOracle
	 */
	function genesisEpoch() external view returns (uint256);

	/**
	 * @notice Updates record with `epoch` and fees
	 * @param epoch Filecoin network Epoch number
	 * @param preCommitDeposit PreCommitDeposit fee
	 * @param initialPledge Initial pledge fee
	 *
	 * @notice Only triggered by address with `ORACLE_REPORTER` role
	 */
	function updateRecord(uint256 epoch, uint256 preCommitDeposit, uint256 initialPledge) external;

	/**
	 * @notice Return total amount of fees for PreCommitDeposit and Initial Pledge
	 */
	function getPledgeFees() external view returns (uint256);

	/**
	 * @notice Returns record information with PreCommitDeposit and Initial Pledge fees
	 */
	function getLastRecord() external view returns (uint256, uint256);

	/**
	 * @notice Returns historical record PreCommitDeposit and Initial Pledge fees for specific `epoch`
	 * @param epoch Filecoin network Epoch number
	 */
	function getHistoricalRecord(uint256 epoch) external view returns (uint256, uint256);

	/**
	 * @notice Returns last record for PreCommitDeposit fee
	 */
	function getLastPreCommitDeposit() external view returns (uint256);

	/**
	 * @notice Returns historical record for PreCommitDeposit fee with specified `epoch`
	 * @param epoch Filecoin network Epoch number
	 */
	function getHistoricalPreCommitDeposit(uint256 epoch) external view returns (uint256);

	/**
	 * @notice Returns last record for Initial Pledge fee
	 */
	function getLastInitialPledge() external view returns (uint256);

	/**
	 * @notice Returns historical record for Initial Pledge fee with specified `epoch`
	 * @param epoch Filecoin network Epoch number
	 */
	function getHistoricalInitialPledge(uint256 epoch) external view returns (uint256);
}
