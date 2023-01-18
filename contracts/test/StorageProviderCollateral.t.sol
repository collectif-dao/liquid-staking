// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {WFIL} from "./mocks/WFIL.sol";
import {IERC4626} from "fei-protocol/erc4626/interfaces/IERC4626.sol";
import {IWETH9} from "fei-protocol/erc4626/external/PeripheryPayments.sol";

import {IStorageProviderCollateral, StorageProviderCollateral} from "../StorageProviderCollateral.sol";
import {StorageProviderRegistryMock} from "./mocks/StorageProviderRegistryMock.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

contract StorageProviderCollateralTest is DSTestPlus {
	StorageProviderCollateral public collateral;
	StorageProviderRegistryMock public registry;
	IERC4626 public staking;
	IWETH9 public wfil;

	address private alice = address(0x122);
	address private bob = address(0x123);

	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant MIN_TIME_PERIOD = 90 days;
	uint256 private constant MAX_TIME_PERIOD = 360 days;

	function setUp() public {
		wfil = IWETH9(address(new WFIL()));
		staking = IERC4626(address(new MockERC4626(wfil, "Collective FIL Liquid Staking", "clFIL")));

		registry = new StorageProviderRegistryMock(
			abi.encodePacked(alice),
			MAX_STORAGE_PROVIDERS,
			MAX_ALLOCATION,
			MIN_TIME_PERIOD,
			MAX_TIME_PERIOD
		);

		collateral = new StorageProviderCollateral(wfil, address(registry));
		registry.setCollateralAddress(address(collateral));

		hevm.prank(alice);
		registry.register(alice, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		bytes memory aliceBytes = abi.encodePacked(alice);
		bytes memory stakingBytes = abi.encodePacked(address(staking));
		registry.acceptBeneficiaryAddress(aliceBytes, stakingBytes);
	}

	function testDeposit(uint256 amount) public {
		hevm.assume(amount != 0 && amount != type(uint256).max);
		hevm.deal(alice, amount);

		hevm.prank(alice);
		collateral.deposit{value: amount}();

		uint256 availableCollateral = collateral.getAvailableCollateral(alice);

		assertEq(availableCollateral, amount);
		assertEq(collateral.getLockedCollateral(alice), 0);

		require(wfil.balanceOf(address(collateral)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testDepositReverts(uint256 amount) public {
		hevm.assume(amount != 0 && amount != type(uint256).max);
		hevm.deal(bob, amount);

		hevm.prank(bob);
		hevm.expectRevert("INACTIVE_STORAGE_PROVIDER");
		collateral.deposit{value: amount}();

		require(wfil.balanceOf(address(collateral)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testWithdraw(uint128 amount) public {
		hevm.assume(amount != 0 && amount < 2000000000 ether);
		hevm.deal(alice, amount);

		uint256 balanceBefore = amount;

		hevm.startPrank(alice);
		collateral.deposit{value: amount}();

		emit log_uint(amount);
		emit log_uint(wfil.balanceOf(address(collateral)));
		emit log_uint(wfil.balanceOf(alice));

		collateral.withdraw(amount);
		hevm.stopPrank();

		assertEq(collateral.getAvailableCollateral(alice), 0);
		assertEq(alice.balance, balanceBefore);

		emit log_uint(alice.balance);

		require(wfil.balanceOf(address(collateral)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testWithdrawMaxAmount(uint128 amount) public {
		hevm.assume(amount != 0 && amount < 2000000000 ether);
		hevm.deal(bob, amount);
		uint256 balanceBefore = amount;

		hevm.prank(bob);
		registry.register(bob, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		bytes memory bobBytes = abi.encodePacked(bob);
		bytes memory stakingBytes = abi.encodePacked(address(staking));
		registry.acceptBeneficiaryAddress(bobBytes, stakingBytes);

		hevm.startPrank(bob);
		collateral.deposit{value: amount}();
		collateral.withdraw(amount + 10 ether); // try to withdraw 10 FIL more
		hevm.stopPrank();

		assertEq(collateral.getAvailableCollateral(bob), 0);
		assertEq(bob.balance, balanceBefore); // validate that amount withdrawn is the same as Bob's deposit

		require(wfil.balanceOf(address(collateral)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(bob) == 0, "INVALID_BALANCE");
	}
}
