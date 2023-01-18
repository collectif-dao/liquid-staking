// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "fei-protocol/erc4626/ERC4626RouterBase.sol";
import "./interfaces/IStakingRouter.sol";

/**
 * @title StakingRouter contract allows users to perform multi-call operations in a similar manner like Uniswap V3
 *
 * Base implementation of StakingRouter doesn't perform wrap/unwrap
 * and approve/permit on the deposit/withdraw operations. 
 
 * To use the router effectively please use the following multi-call pattern:
 *
 * For Deposits with wrapping:
 *     bytes[] memory data = new bytes[](2);
 *     data[0] = abi.encodeWithSelector(PeripheryPayments.wrapWFIL.selector);
 *     data[1] = abi.encodeWithSelector(StakingRouter.deposit.selector, wfilVault, address(this), amount, amount);
 *     router.multicall{value: amount}(data);
 *
 * For Withdrawals with unwrapping:
 *     bytes[] memory data = new bytes[](2);
 *     data[0] = abi.encodeWithSelector(StakingRouter.withdraw.selector, wfilVault, address(router), amount, amount);
 *     data[1] = abi.encodeWithSelector(PeripheryPayments.unwrapWFIL.selector, amount, address(this));
 *     router.multicall{value: amount}(data);
 */
contract StakingRouter is IStakingRouter, ERC4626RouterBase {
	using SafeTransferLib for ERC20;

	/**
	 * @dev Contract constructor function.
	 * @param name Human readable name of the router
	 * @param wFIL Address of WFIL token implementation
	 *
	 */
	constructor(string memory name, IWETH9 wFIL) PeripheryPayments(wFIL) {}

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
	) external payable override returns (uint256 sharesOut) {
		pullToken(ERC20(vault.asset()), amount, address(this));
		return deposit(vault, to, amount, minSharesOut);
	}

	/**
	 * @notice Redeems the maximum amount of shares for staker
	 * @param vault ERC4626 vault implementation
	 * @param to Receiver of withdrawn shares (converted into assets)
	 * @param minAmountOut Minimal amount of assets expected to be received by the user, reverts if actual amount less
	 */
	function redeemMax(
		IERC4626 vault,
		address to,
		uint256 minAmountOut
	) public payable override returns (uint256 amountOut) {
		uint256 shareBalance = vault.balanceOf(msg.sender);
		uint256 maxRedeem = vault.maxRedeem(msg.sender);
		uint256 amountShares = maxRedeem < shareBalance ? maxRedeem : shareBalance;
		return redeem(vault, to, amountShares, minAmountOut);
	}
}
