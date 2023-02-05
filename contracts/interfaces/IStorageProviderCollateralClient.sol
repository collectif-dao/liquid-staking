// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IStorageProviderCollateralClient {
	/**
	 * @dev Locks required collateral amount based on `_allocated` FIL to pledge
	 * @notice Increases the total amount of locked collateral for storage provider
	 * @param _provider WFIL recipient address
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function lock(bytes memory _provider, uint256 _allocated) external;
}
