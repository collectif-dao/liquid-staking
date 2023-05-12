// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Resolver} from "../Resolver.sol";
import {ERC1967Proxy} from "@oz/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

contract ResolverTest is DSTestPlus {
	Resolver public resolver;

	address private alice = address(0x122);

	bytes32 private constant SAMPLE_ADDRESS = "SAMPLE_ADDRESS";
	bytes32 private constant LIQUID_STAKING = "LIQUID_STAKING";
	bytes32 private constant REGISTRY = "REGISTRY";
	bytes32 private constant COLLATERAL = "COLLATERAL";
	bytes32 private constant REWARD_COLLECTOR = "REWARD_COLLECTOR";

	function setUp() public {
		Resolver resolverImpl = new Resolver();
		ERC1967Proxy resolverProxy = new ERC1967Proxy(address(resolverImpl), "");
		resolver = Resolver(address(resolverProxy));
		resolver.initialize();
	}

	function testSetAddress(bytes32 id, address newAddr) public {
		hevm.assume(id > 0 && newAddr != address(0));
		resolver.setAddress(id, newAddr);

		require(resolver.getAddress(id) == newAddr, "INVALID_ADDRESS_SET");
	}

	function testSetAddressReverts(address newAddr) public {
		hevm.assume(newAddr != address(0));

		hevm.prank(alice);
		hevm.expectRevert("Ownable: caller is not the owner");
		resolver.setAddress(SAMPLE_ADDRESS, newAddr);

		require(resolver.getAddress(SAMPLE_ADDRESS) == address(0), "INVALID_ADDRESS_SET");

		hevm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
		resolver.setAddress(SAMPLE_ADDRESS, address(0));
		require(resolver.getAddress(SAMPLE_ADDRESS) == address(0), "INVALID_ADDRESS_SET");
	}

	function testSetRegistryAddress(address newAddr) public {
		hevm.assume(newAddr != address(0));

		resolver.setRegistryAddress(newAddr);
		require(resolver.getAddress(REGISTRY) == newAddr, "INVALID_ADDRESS_SET");

		// expect revert on set the same address
		hevm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
		resolver.setAddress(REGISTRY, newAddr);
	}

	function testSetRegistryAddressReverts(address newAddr) public {
		hevm.assume(newAddr != address(0));

		hevm.prank(alice);
		hevm.expectRevert("Ownable: caller is not the owner");
		resolver.setRegistryAddress(newAddr);
		require(resolver.getAddress(REGISTRY) == address(0), "INVALID_ADDRESS_SET");

		hevm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
		resolver.setAddress(REGISTRY, address(0));
		require(resolver.getAddress(REGISTRY) == address(0), "INVALID_ADDRESS_SET");
	}

	function testSetCollateralAddress(address newAddr) public {
		hevm.assume(newAddr != address(0));

		resolver.setCollateralAddress(newAddr);
		require(resolver.getAddress(COLLATERAL) == newAddr, "INVALID_ADDRESS_SET");

		// expect revert on set the same address
		hevm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
		resolver.setAddress(COLLATERAL, newAddr);
	}

	function testSetCollateralAddressReverts(address newAddr) public {
		hevm.assume(newAddr != address(0));

		hevm.prank(alice);
		hevm.expectRevert("Ownable: caller is not the owner");
		resolver.setCollateralAddress(newAddr);
		require(resolver.getAddress(COLLATERAL) == address(0), "INVALID_ADDRESS_SET");

		hevm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
		resolver.setCollateralAddress(address(0));
		require(resolver.getAddress(COLLATERAL) == address(0), "INVALID_ADDRESS_SET");
	}

	function testSetLiquidStakingAddress(address newAddr) public {
		hevm.assume(newAddr != address(0));

		resolver.setLiquidStakingAddress(newAddr);
		require(resolver.getAddress(LIQUID_STAKING) == newAddr, "INVALID_ADDRESS_SET");

		// expect revert on set the same address
		hevm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
		resolver.setAddress(LIQUID_STAKING, newAddr);
	}

	function testSetLiquidStakingAddressReverts(address newAddr) public {
		hevm.assume(newAddr != address(0));

		hevm.prank(alice);
		hevm.expectRevert("Ownable: caller is not the owner");
		resolver.setLiquidStakingAddress(newAddr);
		require(resolver.getAddress(LIQUID_STAKING) == address(0), "INVALID_ADDRESS_SET");

		hevm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
		resolver.setLiquidStakingAddress(address(0));
		require(resolver.getAddress(LIQUID_STAKING) == address(0), "INVALID_ADDRESS_SET");
	}

	function testSetRewardCollectorAddress(address newAddr) public {
		hevm.assume(newAddr != address(0));

		resolver.setRewardCollectorAddress(newAddr);
		require(resolver.getRewardCollector() == newAddr, "INVALID_ADDRESS_SET");

		// expect revert on set the same address
		hevm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
		resolver.setAddress(REWARD_COLLECTOR, newAddr);
	}

	function testSetRewardCollectorAddressReverts(address newAddr) public {
		hevm.assume(newAddr != address(0));

		hevm.prank(alice);
		hevm.expectRevert("Ownable: caller is not the owner");
		resolver.setRewardCollectorAddress(newAddr);
		require(resolver.getRewardCollector() == address(0), "INVALID_ADDRESS_SET");

		hevm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
		resolver.setRewardCollectorAddress(address(0));
		require(resolver.getRewardCollector() == address(0), "INVALID_ADDRESS_SET");
	}
}
