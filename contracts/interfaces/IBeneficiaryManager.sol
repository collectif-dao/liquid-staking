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
	 * @notice Emitted when beneficiary status has been updated
	 * @param minerId SP miner ID (not owner)
	 * @param status Beneficiary status to indicate wether beneficiary address is synced with actual repayments
	 */
	event BeneficiaryStatusUpdated(uint64 minerId, bool status);

	/**
	 * @notice Triggers changeBeneficiary call on Miner actor as SP
	 *
	 * @dev This function could be triggered by miner owner address
	 */
	function changeBeneficiaryAddress() external;

	/**
	 * @notice Triggers update of beneficiary status for SP with `minerId`
	 * @param minerId SP miner ID (not owner)
	 * @param status Beneficiary status to indicate wether beneficiary address is synced with actual repayments
	 *
	 * @dev This function could be triggered by StorageProviderRegistry or RewardCollector contracts
	 */
	function updateBeneficiaryStatus(uint64 minerId, bool status) external;
}
