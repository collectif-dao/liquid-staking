// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILiquidStaking {
	/**
	 * @notice Emitted when user is staked wFIL to the Liquid Staking
	 * @param user User's address
	 * @param owner Original owner of clFIL tokens
	 * @param assets Total wFIL amount unstaked
	 * @param shares Total clFIL amount unstaked
	 */
	event Unstaked(address indexed user, address indexed owner, uint256 assets, uint256 shares);

	/**
	 * @notice Emitted when storage provider is withdrawing FIL for pledge
	 * @param ownerId Storage Provider's owner ID
	 * @param minerId Storage Provider's miner actor ID
	 * @param amount Total FIL amount to pledge
	 */
	event Pledge(uint64 ownerId, uint64 minerId, uint256 amount);

	/**
	 * @notice Emitted when storage provider's pledge is returned back to the LSP
	 * @param ownerId Storage Provider's owner ID
	 * @param minerId Storage Provider's miner actor ID
	 * @param amount Total FIL amount of repayment
	 */
	event PledgeRepayment(uint64 ownerId, uint64 minerId, uint256 amount);

	/**
	 * @notice Emitted when storage provider has been reported to accure slashing
	 * @param ownerId Storage Provider's owner ID
	 * @param minerId Storage Provider's miner actor ID
	 * @param slashingAmount Slashing amount
	 */
	event ReportSlashing(uint64 ownerId, uint64 minerId, uint256 slashingAmount);

	/**
	 * @notice Emitted when storage provider has been reported to recover slashed sectors
	 * @param ownerId Storage Provider's owner ID
	 * @param minerId Storage Provider's miner actor ID
	 */
	event ReportRecovery(uint64 ownerId, uint64 minerId);

	/**
	 * @notice Emitted when collateral address is updated
	 * @param collateral StorageProviderCollateral contract address
	 */
	event SetCollateralAddress(address indexed collateral);

	/**
	 * @notice Emitted when registry address is updated
	 * @param registry StorageProviderRegistry contract address
	 */
	event SetRegistryAddress(address indexed registry);

	/**
	 * @notice Emitted when profit sharing is update for SP
	 * @param ownerId SP owner ID
	 * @param prevShare Previous profit sharing value
	 * @param profitShare New profit share percentage
	 */
	event ProfitShareUpdate(uint64 ownerId, uint256 prevShare, uint256 profitShare);

	/**
	 * @notice Emitted when admin fee is updated
	 * @param adminFee New admin fee
	 */
	event UpdateAdminFee(uint256 adminFee);

	/**
	 * @notice Emitted when base profit sharing is updated
	 * @param profitShare New base profit sharing ratio
	 */
	event UpdateBaseProfitShare(uint256 profitShare);

	/**
	 * @notice Emitted when reward collector address is updated
	 * @param rewardsCollector New rewards collector address
	 */
	event UpdateRewardCollector(address rewardsCollector);

	/**
	 * @notice Stake FIL to the Liquid Staking pool and get clFIL in return
	 * native FIL is wrapped into WFIL and deposited into LiquidStaking
	 *
	 * @notice msg.value is the amount of FIL to stake
	 */
	function stake() external payable returns (uint256 shares);

	/**
	 * @notice Unstake wFIL from the Liquid Staking pool and burn clFIL tokens
	 * @param shares Total clFIL amount to burn (unstake)
	 * @param owner Original owner of clFIL tokens
	 * @dev Please note that unstake amount has to be clFIL shares (not wFIL assets)
	 */
	function unstake(uint256 shares, address owner) external returns (uint256 assets);

	/**
	 * @notice Unstake wFIL from the Liquid Staking pool and burn clFIL tokens
	 * @param assets Total FIL amount to unstake
	 * @param owner Original owner of clFIL tokens
	 */
	function unstakeAssets(uint256 assets, address owner) external returns (uint256 shares);

	/**
	 * @notice Pledge FIL assets from liquid staking pool to miner pledge for one or multiple sectors
	 * @param amount Amount of FIL to pledge from Liquid Staking Pool
	 */
	function pledge(uint256 amount) external;

	/**
	 * @notice Withdraw initial pledge from Storage Provider's Miner Actor by `ownerId`
	 * This function is triggered when sector is not extended by miner actor and initial pledge unlocked
	 * @param ownerId Storage provider owner ID
	 * @param amount Initial pledge amount
	 */
	function withdrawPledge(uint64 ownerId, uint256 amount) external;

	/**
	 * @notice Report slashing of SP accured on the Filecoin network
	 * This function is triggered when SP get continiously slashed by faulting it's sectors
	 * @param _ownerId Storage provider owner ID
	 * @param _slashingAmt Slashing amount
	 *
	 * @dev Please note that slashing amount couldn't exceed the total amount of collateral provided by SP.
	 * If sector has been slashed for 42 days and automatically terminated both operations
	 * would take place after one another: slashing report and initial pledge withdrawal
	 * which is the remaining pledge for a terminated sector.
	 */
	function reportSlashing(uint64 _ownerId, uint256 _slashingAmt) external;

	/**
	 * @notice Report recovery of previously slashed sectors for SP with `_ownerId`
	 * @param _ownerId Storage provider owner ID
	 */
	function reportRecovery(uint64 _ownerId) external;

	/**
	 * @dev Updates profit sharing requirements for SP with `_ownerId` by `_profitShare` percentage
	 * @notice Only triggered by Liquid Staking admin or registry contract while registering SP
	 * @param _ownerId Storage provider owner ID
	 * @param _profitShare Percentage of profit sharing
	 */
	function updateProfitShare(uint64 _ownerId, uint256 _profitShare) external;

	/**
	 * @notice Returns pool usage ratio to determine what percentage of FIL
	 * is pledged compared to the total amount of FIL staked.
	 */
	function getUsageRatio() external view returns (uint256);

	/**
	 * @notice Updates StorageProviderCollateral contract address
	 * @param newAddr StorageProviderCollateral contract address
	 */
	function setCollateralAddress(address newAddr) external;

	/**
	 * @notice Returns the amount of WFIL available on the liquid staking contract
	 */
	function totalFilAvailable() external view returns (uint256);

	/**
	 * @notice Returns total amount of fees held by LSP for a specific SP with `_ownerId`
	 * @param _ownerId Storage Provider owner ID
	 */
	function totalFees(uint64 _ownerId) external view returns (uint256);

	/**
	 * @notice Updates StorageProviderRegistry contract address
	 * @param newAddr StorageProviderRegistry contract address
	 */
	function setRegistryAddress(address newAddr) external;

	/**
	 * @notice Updates admin fee for the protocol revenue
	 * @param fee New admin fee
	 * @dev Make sure that admin fee is not greater than 20%
	 */
	function updateAdminFee(uint256 fee) external;

	/**
	 * @notice Updates base profit sharing ratio
	 * @param share New base profit sharing ratio
	 * @dev Make sure that profit sharing is not greater than 80%
	 */
	function updateBaseProfitShare(uint256 share) external;

	/**
	 * @notice Updates reward collector address of the protocol revenue
	 * @param collector New rewards collector address
	 */
	function updateRewardsCollector(address collector) external;

	/**
	 * @notice Triggers changeBeneficiary Miner actor call
	 * @param minerId Miner actor ID
	 * @param targetPool LSP smart contract address
	 * @param quota Total beneficiary quota
	 * @param expiration Expiration epoch
	 */
	function forwardChangeBeneficiary(uint64 minerId, address targetPool, uint256 quota, int64 expiration) external;
}
