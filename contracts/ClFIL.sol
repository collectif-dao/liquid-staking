// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IWFIL} from "./libraries/tokens/IWFIL.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC4626Upgradeable, IERC20Upgradeable} from "./libraries/tokens/ERC4626Upgradeable.sol";

/**
 * @title clFIL token contract is the main wrapper over staked FIL in the liquid staking system
 *
 * @notice The clFIL token vault works with wrapped version of Filecoin (FIL)
 * as it's an ultimate requirement of the ERC4626 standard.
 */
abstract contract ClFILToken is Initializable, ERC4626Upgradeable {
	IWFIL public WFIL; // WFIL implementation

	/**
	 * @dev Contract initializer function.
	 * @param _wFIL WFIL token implementation
	 */
	function __ClFILToken_init(address _wFIL) internal onlyInitializing {
		__ERC20_init("Collective Staked FIL", "clFIL");
		__ERC4626_init(IERC20Upgradeable(_wFIL));
		WFIL = IWFIL(_wFIL);
	}

	/**
	 * @notice Returns total amount of assets backing clFIL, that includes
	 * buffered capital in the pool and pledged capital to the SPs.
	 */
	function totalAssets() public view virtual override returns (uint256) {}
}
