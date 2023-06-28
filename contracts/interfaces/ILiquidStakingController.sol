// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILiquidStakingController {
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
	 * @notice Emitted when liquidity cap is updated
	 * @param cap New liquidity cap
	 */
	event UpdateLiquidityCap(uint256 cap);

	/**
	 * @notice Emitted when withdrawals are activated
	 */
	event WithdrawalsActivated();

	/**
	 * @dev Updates profit sharing requirements for SP with `_ownerId` by `_profitShare` percentage at `_pool`
	 * @notice Only triggered by Liquid Staking admin or registry contract while registering SP
	 * @param _ownerId Storage provider owner ID
	 * @param _profitShare Percentage of profit sharing
	 * @param _pool Address of liquid staking pool
	 */
	function updateProfitShare(uint64 _ownerId, uint256 _profitShare, address _pool) external;

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
	 * @notice Returns total amount of fees held by LSP for a specific SP with `_ownerId`
	 * @param _ownerId Storage Provider owner ID
	 * @param _pool Liquid Staking contract address
	 */
	function totalFees(uint64 _ownerId, address _pool) external view returns (uint256);

	/**
	 * @notice Updates liquidity cap for liquid staking protocol
	 * @param cap New admin liquidity cap
	 * @dev Make sure that new liquidity cap is not equal and higher than the prevous cap
	 */
	function updateLiquidityCap(uint256 cap) external;

	/**
	 * @notice Activates withdrawals for liquid staking protocol
	 * @dev This is a one way transaction that needs to take place after the initial activation period
	 */
	function activateWithdrawals() external;

	/**
	 * @notice Returns the liquidity cap for Liquid Staking
	 */
	function liquidityCap() external view returns (uint256);

	/**
	 * @notice Returns wether witdrawals are activated
	 */
	function withdrawalsActivated() external view returns (bool);
}
