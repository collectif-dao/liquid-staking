// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStorageProviderCollateralClient {
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
	 * @dev Updates collateral requirements for SP with `_ownerId` by `requirements` percentage
	 * @notice Only triggered by Collateral admin or registry contract while registering SP
	 * @param _ownerId Storage provider owner ID
	 * @param requirements Percentage of collateral requirements
	 */
	function updateCollateralRequirements(uint64 _ownerId, uint256 requirements) external;

	/**
	 * @notice Return a slashing flag for a storage provider
	 */
	function activeSlashings(uint64 ownerId) external view returns (bool);
}
