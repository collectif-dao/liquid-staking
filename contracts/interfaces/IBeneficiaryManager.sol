// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBeneficiaryManager {
	/**
	 * @notice Emitted when beneficiary address has been updated
	 * @param caller Caller address
	 * @param minerId Miner actor ID
	 * @param targetPool Beneficiary address
	 * @param quota Beneficiary quota
	 * @param expiration Expiration epoch
	 */
	event BeneficiaryAddressUpdated(
		address indexed caller,
		uint64 minerId,
		address targetPool,
		uint256 quota,
		int64 expiration
	);

	/**
	 * @notice Triggers changeBeneficiary call on Miner actor as SP
	 *
	 * @dev This function could be triggered by miner owner address
	 */
	function changeBeneficiaryAddress() external;
}
