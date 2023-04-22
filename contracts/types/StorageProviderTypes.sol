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
		uint64 minerId; // Miner worker address
		uint256 allocationLimit; // FIL allocation
		uint256 repayment; // FIL repayment amount
		uint256 usedAllocation; // Used allocation in pledges
		uint256 accruedRewards; // Storage Provider delivered rewards
		uint256 lockedRewards; // Storage Provider locked rewards
		int64 lastEpoch; // Max time period for accessing FIL from liquid staking
	}

	struct SPRestaking {
		uint256 restakingRatio; // Percentage of FIL rewards that is going to be restaked into liquid staking pool
		address restakingAddress;
	}
}
