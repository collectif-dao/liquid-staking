// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IClFILTokenClient {
	/**
	 * @notice Returns total amount of assets backing clFIL, that includes
	 * buffered capital in the pool and pledged capital to the SPs.
	 */
	function totalAssets() external view returns (uint256 balance);

	/**
	 * @notice Returns balance of clFIL tokens for `owner`
	 */
	function balanceOf(address owner) external view returns (uint256 balance);

	/**
	 * @dev Mints shares Vault shares to receiver by depositing exactly amount of underlying tokens.
	 *
	 * - MUST emit the Deposit event.
	 * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
	 *   deposit execution, and are accounted for during deposit.
	 * - MUST revert if all of assets cannot be deposited (due to deposit limit being reached, slippage, the user not
	 *   approving enough underlying tokens to the Vault contract, etc).
	 *
	 * NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
	 */
	function deposit(uint256 assets, address receiver) external returns (uint256 shares);

	/**
	 * @dev Mints exactly shares Vault shares to receiver by depositing amount of underlying tokens.
	 *
	 * - MUST emit the Deposit event.
	 * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the mint
	 *   execution, and are accounted for during mint.
	 * - MUST revert if all of shares cannot be minted (due to deposit limit being reached, slippage, the user not
	 *   approving enough underlying tokens to the Vault contract, etc).
	 *
	 * NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
	 */
	function mint(uint256 shares, address receiver) external returns (uint256 assets);

	/**
	 * @dev Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver,
	 * through a deposit call.
	 *
	 * - MUST return a limited value if receiver is subject to some deposit limit.
	 * - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of assets that may be deposited.
	 * - MUST NOT revert.
	 */
	function maxDeposit(address receiver) external view returns (uint256 maxAssets);

	/**
	 * @dev Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given
	 * current on-chain conditions.
	 *
	 * - MUST return as close to and no more than the exact amount of Vault shares that would be minted in a deposit
	 *   call in the same transaction. I.e. deposit should return the same or more shares as previewDeposit if called
	 *   in the same transaction.
	 * - MUST NOT account for deposit limits like those returned from maxDeposit and should always act as though the
	 *   deposit would be accepted, regardless if the user has enough tokens approved, etc.
	 * - MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
	 * - MUST NOT revert.
	 *
	 * NOTE: any unfavorable discrepancy between convertToShares and previewDeposit SHOULD be considered slippage in
	 * share price or some other type of condition, meaning the depositor will lose assets by depositing.
	 */
	function previewDeposit(uint256 assets) external view returns (uint256 shares);

	/**
	 * @dev Burns shares from owner and sends exactly assets of underlying tokens to receiver.
	 *
	 * - MUST emit the Withdraw event.
	 * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
	 *   withdraw execution, and are accounted for during withdraw.
	 * - MUST revert if all of assets cannot be withdrawn (due to withdrawal limit being reached, slippage, the owner
	 *   not having enough shares, etc).
	 *
	 * Note that some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
	 * Those methods should be performed separately.
	 */
	function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

	/**
	 * @dev Returns the maximum amount of the underlying asset that can be withdrawn from the owner balance in the
	 * Vault, through a withdraw call.
	 *
	 * - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
	 * - MUST NOT revert.
	 */
	function maxWithdraw(address owner) external view returns (uint256 maxAssets);

	/**
	 * @dev Allows an on-chain or off-chain user to simulate the effects of their withdrawal at the current block,
	 * given current on-chain conditions.
	 *
	 * - MUST return as close to and no fewer than the exact amount of Vault shares that would be burned in a withdraw
	 *   call in the same transaction. I.e. withdraw should return the same or fewer shares as previewWithdraw if
	 *   called
	 *   in the same transaction.
	 * - MUST NOT account for withdrawal limits like those returned from maxWithdraw and should always act as though
	 *   the withdrawal would be accepted, regardless if the user has enough shares, etc.
	 * - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
	 * - MUST NOT revert.
	 *
	 * NOTE: any unfavorable discrepancy between convertToShares and previewWithdraw SHOULD be considered slippage in
	 * share price or some other type of condition, meaning the depositor will lose assets by depositing.
	 */
	function previewWithdraw(uint256 assets) external view returns (uint256 shares);

	/**
	 * @dev Returns the maximum amount of Vault shares that can be redeemed from the owner balance in the Vault,
	 * through a redeem call.
	 *
	 * - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
	 * - MUST return balanceOf(owner) if owner is not subject to any withdrawal limit or timelock.
	 * - MUST NOT revert.
	 */
	function maxRedeem(address owner) external view returns (uint256 maxShares);

	/**
	 * @dev Allows an on-chain or off-chain user to simulate the effects of their redeemption at the current block,
	 * given current on-chain conditions.
	 *
	 * - MUST return as close to and no more than the exact amount of assets that would be withdrawn in a redeem call
	 *   in the same transaction. I.e. redeem should return the same or more assets as previewRedeem if called in the
	 *   same transaction.
	 * - MUST NOT account for redemption limits like those returned from maxRedeem and should always act as though the
	 *   redemption would be accepted, regardless if the user has enough shares, etc.
	 * - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
	 * - MUST NOT revert.
	 *
	 * NOTE: any unfavorable discrepancy between convertToAssets and previewRedeem SHOULD be considered slippage in
	 * share price or some other type of condition, meaning the depositor will lose assets by redeeming.
	 */
	function previewRedeem(uint256 shares) external view returns (uint256 assets);

	/**
	 * @dev Burns exactly shares from owner and sends assets of underlying tokens to receiver.
	 *
	 * - MUST emit the Withdraw event.
	 * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
	 *   redeem execution, and are accounted for during redeem.
	 * - MUST revert if all of shares cannot be redeemed (due to withdrawal limit being reached, slippage, the owner
	 *   not having enough shares, etc).
	 *
	 * NOTE: some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
	 * Those methods should be performed separately.
	 */
	function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

	/**
	 * @notice Mints number of tokens in `shares` to a `recepient`
	 * @dev Only triggered by staking pool
	 */
	function mintShares(address recepient, uint256 shares) external;

	/**
	 * @notice Burns number of tokens in `shares` from the `owner`
	 * @dev Only triggered by staking pool
	 */
	function burnShares(address owner, uint256 shares) external;

	/**
	 * @notice Triggered to spend allowance for an `owner` by `spender` with `amount` of tokens
	 * @dev Only triggered by staking pool
	 */
	function spendAllowance(address owner, address spender, uint256 amount) external;
}
