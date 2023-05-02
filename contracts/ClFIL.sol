// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC4626} from "./libraries/tokens/ERC4626.sol";
import {ERC20} from "./libraries/tokens/ERC20.sol";
import {IWFIL} from "./libraries/tokens/IWFIL.sol";

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
contract ClFILToken is ERC4626 {
	IWFIL public immutable WFIL; // WFIL implementation

	constructor(address _wFIL) ERC4626(ERC20(_wFIL), "Collective Staked FIL", "clFIL") {
		WFIL = IWFIL(_wFIL);
	}

	/**
	 * @notice Returns total amount of assets backing clFIL, that includes
	 * buffered capital in the pool and pledged capital to the SPs.
	 */
	function totalAssets() public view virtual override returns (uint256) {}
}
