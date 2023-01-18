// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract WFIL is ERC20("Wrapped Filecoin", "WFIL", 18) {
	using SafeTransferLib for address;

	event Deposit(address indexed from, uint256 amount);

	event Withdrawal(address indexed to, uint256 amount);

	function deposit() public payable virtual {
		_mint(msg.sender, msg.value);

		emit Deposit(msg.sender, msg.value);
	}

	function withdraw(uint256 amount) public virtual {
		_burn(msg.sender, amount);

		emit Withdrawal(msg.sender, amount);

		msg.sender.safeTransferETH(amount);
	}

	receive() external payable virtual {
		deposit();
	}
}
