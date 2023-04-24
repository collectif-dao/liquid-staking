// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStorageProviderCollateral {
	event StorageProviderCollateralDeposit(uint64 _ownerId, uint256 amount);
	event StorageProviderCollateralWithdraw(uint64 _ownerId, uint256 amount);
	event StorageProviderCollateralLock(uint64 _ownerId, uint256 allocation, uint256 lockAmount);
	event StorageProviderCollateralFit(uint64 _ownerId, uint256 adjustment, bool isUnlock);

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
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function lock(uint64 _ownerId, uint256 _allocated) external;

	/**
	 * @dev Fits collateral amounts based on SP pledge usage, distributed rewards and pledge paybacks
	 * @notice Rebalances the total locked and available collateral amounts
	 * @param _ownerId Storage provider owner ID
	 */
	function fit(uint64 _ownerId) external;

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
}
