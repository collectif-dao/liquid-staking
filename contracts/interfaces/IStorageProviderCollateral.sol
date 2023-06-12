// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStorageProviderCollateral {
	event StorageProviderCollateralDeposit(uint64 _ownerId, uint256 amount);
	event StorageProviderCollateralWithdraw(uint64 _ownerId, uint256 amount);
	event StorageProviderCollateralRebalance(
		uint64 _ownerId,
		uint256 lockedCollateral,
		uint256 availableCollateral,
		bool isUnlock
	);
	event StorageProviderCollateralSlash(uint64 _ownerId, uint256 slashingAmt, address pool);
	event StorageProviderCollateralUpdate(uint64 _ownerId, uint256 prevRequirements, uint256 requirements);
	event UpdateBaseCollateralRequirements(uint256 baseCollateralRequirements);
	event SetRegistryAddress(address registry);

	/**
	 * @notice Emitted when storage provider has been reported to accure slashing
	 * @param ownerId Storage Provider's owner ID
	 * @param slashingAmount Slashing amount
	 */
	event ReportSlashing(uint64 ownerId, uint256 slashingAmount);

	/**
	 * @notice Emitted when storage provider has been reported to recover slashed sectors
	 * @param ownerId Storage Provider's owner ID
	 */
	event ReportRecovery(uint64 ownerId);

	/**
	 * @dev Deposit `msg.value` FIL funds by the msg.sender into collateral
	 * @notice Wrapps of FIL into WFIL token internally
	 */
	function deposit() external payable;

	/**
	 * @dev Withdraw `_amount` of FIL funds by the `msg.sender` from the collateral system
	 * @notice Unwraps of FIL into WFIL token internally and
	 * delivers maximum amount of FIL available for withdrawal if `_amount` is bigger.
	 */
	function withdraw(uint256 _amount) external;

	/**
	 * @dev Locks required collateral amount based on `_allocated` FIL to pledge
	 * @notice Increases the total amount of locked collateral for storage provider
	 * @param _ownerId Storage provider owner ID
	 * @param _minerId Storage provider miner ID
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function lock(uint64 _ownerId, uint64 _minerId, uint256 _allocated) external;

	/**
	 * @dev Fits collateral amounts based on SP pledge usage, distributed rewards and pledge paybacks
	 * @notice Rebalances the total locked and available collateral amounts
	 * @param _ownerId Storage provider owner ID
	 */
	function fit(uint64 _ownerId) external;

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
	 * @notice Return Storage Provider Collateral information with `_provider` address
	 */
	function getCollateral(uint64 _ownerId) external view returns (uint256, uint256);

	/**
	 * @notice Return Storage Provider Available Collateral information with `_provider` address
	 */
	function getAvailableCollateral(uint64 _ownerId) external view returns (uint256);

	/**
	 * @notice Return Storage Provider Locked Collateral information with `_provider` address
	 */
	function getLockedCollateral(uint64 _ownerId) external view returns (uint256);

	/**
	 * @dev Updates collateral requirements for SP with `_ownerId` by `requirements` percentage
	 * @notice Only triggered by Collateral admin or registry contract while registering SP
	 * @param _ownerId Storage provider owner ID
	 * @param requirements Percentage of collateral requirements
	 */
	function updateCollateralRequirements(uint64 _ownerId, uint256 requirements) external;

	/**
	 * @notice Updates base collateral requirements amount for Storage Providers
	 * @param requirements New base collateral requirements for SP
	 */
	function updateBaseCollateralRequirements(uint256 requirements) external;
}
