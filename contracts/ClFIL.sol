// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IWFIL} from "./libraries/tokens/IWFIL.sol";
import {ILiquidStakingClient} from "./interfaces/ILiquidStakingClient.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC4626Upgradeable, IERC20Upgradeable, SafeERC20Upgradeable, FilAddress} from "./libraries/tokens/ERC4626Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title clFIL token contract is the main wrapper over staked FIL in the liquid staking system
 *
 * @notice The clFIL token vault works with wrapped version of Filecoin (FIL)
 * as it's an ultimate requirement of the ERC4626 standard.
 */
contract ClFILToken is Initializable, ERC4626Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
	using FilAddress for address;
	ILiquidStakingClient public pool;
	IWFIL public WFIL; // WFIL implementation

	error InvalidAccess();

	modifier onlyAdmin() {
		if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert InvalidAccess();
		_;
	}

	modifier onlyMinter() {
		if (msg.sender != address(pool)) revert InvalidAccess();
		_;
	}

	/**
	 * @dev Contract initializer function.
	 * @param _wFIL WFIL token implementation
	 */
	function initialize(address _wFIL, address _pool) public initializer {
		if (_pool == address(0) || _wFIL == address(0)) revert InvalidParams();
		__ERC20_init("Collective Staked FIL", "clFIL");
		__ERC4626_init(IERC20Upgradeable(_wFIL));
		__AccessControl_init();
		__UUPSUpgradeable_init();

		pool = ILiquidStakingClient(_pool);
		WFIL = IWFIL(_wFIL);

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
	}

	/**
	 * @notice Returns total amount of assets backing clFIL, that includes
	 * buffered capital in the pool and pledged capital to the SPs.
	 */
	function totalAssets() public view virtual override returns (uint256 balance) {
		return WFIL.balanceOf(address(pool)) + pool.totalFilPledged();
	}

	/**
	 * @notice Mints number of tokens in `shares` to a `recepient`
	 * @dev Only triggered by staking pool
	 */
	function mintShares(address recepient, uint256 shares) external virtual onlyMinter {
		_mint(recepient, shares);
	}

	/**
	 * @notice Burns number of tokens in `shares` from the `owner`
	 * @dev Only triggered by staking pool
	 */
	function burnShares(address owner, uint256 shares) external virtual onlyMinter {
		_burn(owner, shares);
	}

	/**
	 * @notice Triggered to spend allowance for an `owner` by `spender` with `amount` of tokens
	 * @dev Only triggered by staking pool
	 */
	function spendAllowance(address owner, address spender, uint256 amount) external virtual onlyMinter {
		_spendAllowance(owner, spender, amount);
	}

	/**
	 * @notice UUPS Upgradeable function to update the token implementation
	 * @dev Only triggered by contract admin
	 */
	function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}

	/**
	 * @notice Returns the version of clFIL token contract
	 */
	function version() external pure virtual returns (string memory) {
		return "v1";
	}

	/**
	 * @notice Returns the implementation contract
	 */
	function getImplementation() external view returns (address) {
		return _getImplementation();
	}
}
