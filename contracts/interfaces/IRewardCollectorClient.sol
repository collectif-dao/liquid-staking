// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRewardCollectorClient {
	/**
	 * @notice Triggers changeBeneficiary Miner actor call
	 * @param minerId Miner actor ID
	 * @param beneficiaryActorId Beneficiary address to be setup (Actor ID)
	 * @param quota Total beneficiary quota
	 * @param expiration Expiration epoch
	 */
	function forwardChangeBeneficiary(
		uint64 minerId,
		uint64 beneficiaryActorId,
		uint256 quota,
		int64 expiration
	) external;
}
