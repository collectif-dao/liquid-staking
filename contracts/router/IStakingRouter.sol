// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC4626} from "fei-protocol/erc4626/interfaces/IERC4626.sol";

interface IStakingRouter {
	/**
	 * @notice Deposits staker's WFIL into a selected vault (strategy)
	 * @param vault ERC4626 vault implementation
	 * @param to Receiver of assets deposit (either a liquid staking or direct OTC deal)
	 * @param minSharesOut Minimal amount of shares expected to be minted for the user, reverts if actual amount less
	 */
	function depositToVault(
		IERC4626 vault,
		address to,
		uint256 amount,
		uint256 minSharesOut
	) external payable returns (uint256 sharesOut);

	/**
	 * @notice Redeems the maximum amount of shares for staker
	 * @param vault ERC4626 vault implementation
	 * @param to Receiver of withdrawn shares (converted into assets)
	 * @param minAmountOut Minimal amount of assets expected to be received by the user, reverts if actual amount less
	 */
	function redeemMax(IERC4626 vault, address to, uint256 minAmountOut) external payable returns (uint256 amountOut);
}
