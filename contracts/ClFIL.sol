// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IWFIL} from "./libraries/tokens/IWFIL.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC4626Upgradeable, ERC20Upgradeable, IERC20Upgradeable, MathUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {FilAddress} from "fevmate/utils/FilAddress.sol";

/**
 * @title clFIL token contract is the main wrapper over staked FIL in the liquid staking system
 *
 * Staking strategies could include the following:
 *     - Liquid Staking Pool
 *     - Direct OTC under-collateralized loans
 *     - Self-stake by Storage Providers
 *
 * @notice The clFIL token vault works with wrapped version of Filecoin (FIL)
 * as it's an ultimate requirement of the ERC4626 standard.
 */
abstract contract ClFILToken is ERC4626Upgradeable {
	using FilAddress for *;
	IWFIL public WFIL; // WFIL implementation

	/**
	 * @dev Contract initializer function.
	 * @param _wFIL WFIL token implementation
	 */
	function initialize(address _wFIL) public onlyInitializing {
		__ERC20_init("Collective Staked FIL", "clFIL");
		__ERC4626_init(IERC20Upgradeable(_wFIL));

		WFIL = IWFIL(_wFIL);
	}

	/**
	 * @notice Returns total amount of assets backing clFIL, that includes
	 * buffered capital in the pool and pledged capital to the SPs.
	 */
	function totalAssets() public view virtual override returns (uint256) {}

	/** @dev See {IERC4626-maxWithdraw}. */
	function maxWithdraw(address owner) public view virtual override returns (uint256) {
		owner = owner.normalize();

		return _convertToAssets(balanceOf(owner), MathUpgradeable.Rounding.Down);
	}

	/** @dev See {IERC4626-maxRedeem}. */
	function maxRedeem(address owner) public view virtual override returns (uint256) {
		owner = owner.normalize();

		return balanceOf(owner);
	}

	/** @dev See {IERC4626-deposit}. */
	function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
		receiver = receiver.normalize();
		require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

		uint256 shares = previewDeposit(assets);
		require(shares != 0, "ZERO_SHARES");

		_deposit(_msgSender(), receiver, assets, shares);

		return shares;
	}

	/** @dev See {IERC4626-mint}.
	 *
	 * As opposed to {deposit}, minting is allowed even if the vault is in a state where the price of a share is zero.
	 * In this case, the shares will be minted without requiring any assets to be deposited.
	 */
	function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
		receiver = receiver.normalize();
		require(shares <= maxMint(receiver), "ERC4626: mint more than max");

		uint256 assets = previewMint(shares);
		require(assets != 0, "ZERO_ASSETS");
		_deposit(_msgSender(), receiver, assets, shares);

		return assets;
	}

	/** @dev See {IERC4626-withdraw}. */
	function withdraw(uint256 assets, address receiver, address owner) public virtual override returns (uint256) {
		receiver = receiver.normalize();
		owner = owner.normalize();
		require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

		uint256 shares = previewWithdraw(assets);
		_withdraw(_msgSender(), receiver, owner, assets, shares);

		return shares;
	}

	/** @dev See {IERC4626-redeem}. */
	function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {
		receiver = receiver.normalize();
		owner = owner.normalize();
		require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

		uint256 assets = previewRedeem(shares);
		_withdraw(_msgSender(), receiver, owner, assets, shares);

		return assets;
	}

	/**
	 * @dev See {IERC20-balanceOf}.
	 */
	function balanceOf(
		address account
	) public view virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
		account = account.normalize();
		return super.balanceOf(account);
	}

	/**
	 * @dev See {IERC20-transfer}.
	 *
	 * Requirements:
	 *
	 * - `to` cannot be the zero address.
	 * - the caller must have a balance of at least `amount`.
	 */
	function transfer(
		address to,
		uint256 amount
	) public virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
		address owner = _msgSender();
		to = to.normalize();
		owner = owner.normalize();

		_transfer(owner, to, amount);
		return true;
	}

	/**
	 * @dev See {IERC20-allowance}.
	 */
	function allowance(
		address owner,
		address spender
	) public view virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
		owner = owner.normalize();
		spender = spender.normalize();

		return super.allowance(owner, spender);
	}

	/**
	 * @dev See {IERC20-approve}.
	 *
	 * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
	 * `transferFrom`. This is semantically equivalent to an infinite approval.
	 *
	 * Requirements:
	 *
	 * - `spender` cannot be the zero address.
	 */
	function approve(
		address spender,
		uint256 amount
	) public virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
		address owner = _msgSender();
		spender = spender.normalize();
		owner = owner.normalize();

		_approve(owner, spender, amount);
		return true;
	}

	/**
	 * @dev See {IERC20-transferFrom}.
	 *
	 * Emits an {Approval} event indicating the updated allowance. This is not
	 * required by the EIP. See the note at the beginning of {ERC20}.
	 *
	 * NOTE: Does not update the allowance if the current allowance
	 * is the maximum `uint256`.
	 *
	 * Requirements:
	 *
	 * - `from` and `to` cannot be the zero address.
	 * - `from` must have a balance of at least `amount`.
	 * - the caller must have allowance for ``from``'s tokens of at least
	 * `amount`.
	 */
	function transferFrom(
		address from,
		address to,
		uint256 amount
	) public virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
		address spender = _msgSender();
		from = from.normalize();
		to = to.normalize();
		spender = spender.normalize();

		_spendAllowance(from, spender, amount);
		_transfer(from, to, amount);
		return true;
	}

	/**
	 * @dev Atomically increases the allowance granted to `spender` by the caller.
	 *
	 * This is an alternative to {approve} that can be used as a mitigation for
	 * problems described in {IERC20-approve}.
	 *
	 * Emits an {Approval} event indicating the updated allowance.
	 *
	 * Requirements:
	 *
	 * - `spender` cannot be the zero address.
	 */
	function increaseAllowance(
		address spender,
		uint256 addedValue
	) public virtual override(ERC20Upgradeable) returns (bool) {
		address owner = _msgSender();
		spender = spender.normalize();
		owner = owner.normalize();

		_approve(owner, spender, allowance(owner, spender) + addedValue);
		return true;
	}

	/**
	 * @dev Atomically decreases the allowance granted to `spender` by the caller.
	 *
	 * This is an alternative to {approve} that can be used as a mitigation for
	 * problems described in {IERC20-approve}.
	 *
	 * Emits an {Approval} event indicating the updated allowance.
	 *
	 * Requirements:
	 *
	 * - `spender` cannot be the zero address.
	 * - `spender` must have allowance for the caller of at least
	 * `subtractedValue`.
	 */
	function decreaseAllowance(
		address spender,
		uint256 subtractedValue
	) public virtual override(ERC20Upgradeable) returns (bool) {
		address owner = _msgSender();
		spender = spender.normalize();
		owner = owner.normalize();

		uint256 currentAllowance = allowance(owner, spender);
		require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
		unchecked {
			_approve(owner, spender, currentAllowance - subtractedValue);
		}

		return true;
	}
}
