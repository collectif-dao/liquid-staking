// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/**
 * Slightly modified Solmate ERC20 token implementation with Filecoin-safe address
 * conversions that allow this token to be transferred to f0/f1/f3/f4 addresses.
 */

import {FilAddress} from "fevmate/utils/FilAddress.sol";

/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
abstract contract ERC20 {
	using FilAddress for *;

	/*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

	event Transfer(address indexed from, address indexed to, uint256 amount);

	event Approval(address indexed owner, address indexed spender, uint256 amount);

	/*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

	string public name;

	string public symbol;

	uint8 public immutable decimals;

	/*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

	uint256 public totalSupply;

	mapping(address => uint256) balances;

	mapping(address => mapping(address => uint256)) allowances;

	/*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

	uint256 internal immutable INITIAL_CHAIN_ID;

	bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

	mapping(address => uint256) public nonces;

	/*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

	constructor(string memory _name, string memory _symbol, uint8 _decimals) {
		name = _name;
		symbol = _symbol;
		decimals = _decimals;

		INITIAL_CHAIN_ID = block.chainid;
		INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
	}

	/*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

	function approve(address spender, uint256 amount) public virtual returns (bool) {
		spender = spender.normalize();
		allowances[msg.sender][spender] = amount;

		emit Approval(msg.sender, spender, amount);

		return true;
	}

	function transfer(address to, uint256 amount) public virtual returns (bool) {
		to = to.normalize();

		balances[msg.sender] -= amount;

		// Cannot overflow because the sum of all user
		// balances can't exceed the max uint256 value.
		unchecked {
			balances[to] += amount;
		}

		emit Transfer(msg.sender, to, amount);

		return true;
	}

	function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
		from = from.normalize();
		to = to.normalize();

		uint256 allowed = allowances[from][msg.sender]; // Saves gas for limited approvals.

		if (allowed != type(uint256).max) allowances[from][msg.sender] = allowed - amount;

		balances[from] -= amount;

		// Cannot overflow because the sum of all user
		// balances can't exceed the max uint256 value.
		unchecked {
			balances[to] += amount;
		}

		emit Transfer(from, to, amount);

		return true;
	}

	/*//////////////////////////////////////
                 ERC-20 GETTERS
    //////////////////////////////////////*/

	function balanceOf(address a) public view virtual returns (uint) {
		return balances[a.normalize()];
	}

	function allowance(address owner, address spender) public view virtual returns (uint) {
		return allowances[owner.normalize()][spender.normalize()];
	}

	/*//////////////////////////////////////////////////////////////
                             EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

	function permit(
		address owner,
		address spender,
		uint256 value,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) public virtual {
		// permits only supported by f4 addresses no need to check the owner
		spender = spender.normalize();

		require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

		// Unchecked because the only math done is incrementing
		// the owner's nonce which cannot realistically overflow.
		unchecked {
			address recoveredAddress = ecrecover(
				keccak256(
					abi.encodePacked(
						"\x19\x01",
						DOMAIN_SEPARATOR(),
						keccak256(
							abi.encode(
								keccak256(
									"Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
								),
								owner,
								spender,
								value,
								nonces[owner]++,
								deadline
							)
						)
					)
				),
				v,
				r,
				s
			);

			require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");

			allowances[recoveredAddress][spender] = value;
		}

		emit Approval(owner, spender, value);
	}

	function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
		return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
	}

	function computeDomainSeparator() internal view virtual returns (bytes32) {
		return
			keccak256(
				abi.encode(
					keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
					keccak256(bytes(name)),
					keccak256("1"),
					block.chainid,
					address(this)
				)
			);
	}

	/*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

	function _mint(address to, uint256 amount) internal virtual {
		to = to.normalize();
		totalSupply += amount;

		// Cannot overflow because the sum of all user
		// balances can't exceed the max uint256 value.
		unchecked {
			balances[to] += amount;
		}

		emit Transfer(address(0), to, amount);
	}

	function _burn(address from, uint256 amount) internal virtual {
		from = from.normalize();
		balances[from] -= amount;

		// Cannot underflow because a user's balance
		// will never be larger than the total supply.
		unchecked {
			totalSupply -= amount;
		}

		emit Transfer(from, address(0), amount);
	}
}
