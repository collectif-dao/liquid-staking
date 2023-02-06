// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title Storage provider account types for Solidity.
 * @author Collective DAO
 */
library StorageProviderTypes {
	struct StorageProvider {
		bool active;
		address targetPool;
		bytes miner; // Miner worker address
		uint256 allocationLimit; // FIL allocation
		uint256 usedAllocation; // Used allocation in pledges
		uint256 accruedRewards; // Storage Provider delivered rewards
		uint256 lockedRewards; // Storage Provider locked rewards
		uint256 maxRedeemablePeriod; // Max time period for accessing FIL from liquid staking
	}
}
