// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title Storage provider account types for Solidity.
 * @author Collective DAO
 */
library StorageProviderTypes {
	struct StorageProvider {
		bool active;
		bool onboarded;
		address targetPool;
		uint64 ownerId; // Miner owner address
		int64 lastEpoch; // Max time period for accessing FIL from liquid staking
	}

	struct SPAllocation {
		uint256 allocationLimit; // FIL allocation
		uint256 repayment; // FIL repayment amount
		uint256 usedAllocation; // Used allocation in pledges
		uint256 dailyAllocation; // Daily FIL allocation for SP
		uint256 accruedRewards; // Storage Provider delivered rewards
		uint256 repaidPledge; // Storage Provider repaid initial pledge
	}

	struct SPRestaking {
		uint256 restakingRatio; // Percentage of FIL rewards that is going to be restaked into liquid staking pool
		address restakingAddress;
	}

	struct AllocationRequest {
		uint256 allocationLimit;
		uint256 dailyAllocation;
	}
}
