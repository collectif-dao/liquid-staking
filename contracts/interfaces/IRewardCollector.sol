// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRewardCollector {
	/**
	 * @notice Emitted when pledge has been withdrawn
	 * @param ownerId SP owner ID
	 * @param minerId Miner actor ID
	 * @param amount Withdraw amount
	 */
	event WithdrawPledge(uint64 ownerId, uint64 minerId, uint256 amount);

	/**
	 * @notice Emitted when rewards has been withdrawn
	 * @param ownerId SP owner ID
	 * @param minerId Miner actor ID
	 * @param spShare Withdrawed amount for SP owner ID
	 * @param stakingProfit Withdrawed amount for LSP stakers
	 * @param protocolRevenue Withdrawed amount for protocol revenue
	 */
	event WithdrawRewards(
		uint64 ownerId,
		uint64 minerId,
		uint256 spShare,
		uint256 stakingProfit,
		uint256 protocolRevenue
	);

	/**
	 * @notice Emitted when beneficiary address is updated
	 * @param minerId Miner actor ID
	 * @param beneficiaryActorId Beneficiary address to be setup (Actor ID)
	 * @param quota Total beneficiary quota
	 * @param expiration Expiration epoch
	 */
	event BeneficiaryAddressUpdated(
		address beneficiary,
		uint64 beneficiaryActorId,
		uint64 minerId,
		uint256 quota,
		int64 expiration
	);

	/**
	 * @notice Withdraw initial pledge from Storage Provider's Miner Actor by `ownerId`
	 * This function is triggered when sector is not extended by miner actor and initial pledge unlocked
	 * @param ownerId Storage provider owner ID
	 * @param amount Initial pledge amount
	 * @dev Please note that pledge amount withdrawn couldn't exceed used allocation by SP
	 */
	function withdrawPledge(uint64 ownerId, uint256 amount) external;

	/**
	 * @notice Withdraw FIL assets from Storage Provider by `ownerId` and it's Miner actor
	 * and restake `restakeAmount` into the Storage Provider specified f4 address
	 * @param ownerId Storage provider owner ID
	 * @param amount Withdrawal amount
	 */
	function withdrawRewards(uint64 ownerId, uint256 amount) external;

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
