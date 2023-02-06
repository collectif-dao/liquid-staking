// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IWETH9} from "fei-protocol/erc4626/external/PeripheryPayments.sol";

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
	IWETH9 public immutable WFIL; // WFIL implementation

	constructor(address _wFIL) ERC4626(ERC20(_wFIL), "Collective Staked FIL", "clFIL") {
		WFIL = IWETH9(_wFIL);
	}

	/**
	 * @notice Returns total amount of assets backing clFIL, that includes
	 * buffered capital in the pool and pledged capital to the SPs.
	 */
	function totalAssets() public view virtual override returns (uint256) {}
}
