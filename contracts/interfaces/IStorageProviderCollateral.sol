// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IStorageProviderCollateral {
	event StorageProviderCollateralDeposit(address indexed provider, uint256 amount);
	event StorageProviderCollateralWithdraw(address indexed provider, uint256 amount);

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
	 * @param _provider WFIL recipient address
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function lock(address _provider, uint256 _allocated) external;

	/**
	 * @notice Return Storage Provider Collateral information with `_provider` address
	 */
	function getCollateral(address _provider) external view returns (uint256, uint256);

	/**
	 * @notice Return Storage Provider Available Collateral information with `_provider` address
	 */
	function getAvailableCollateral(address _provider) external view returns (uint256);

	/**
	 * @notice Return Storage Provider Locked Collateral information with `_provider` address
	 */
	function getLockedCollateral(address _provider) external view returns (uint256);
}
