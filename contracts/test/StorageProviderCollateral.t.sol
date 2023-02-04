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
	bytes private aliceBytesAddress = abi.encodePacked(alice);
	address private bob = address(0x123);

	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant MIN_TIME_PERIOD = 90 days;
	uint256 private constant MAX_TIME_PERIOD = 360 days;

	uint256 public collateralRequirements = 1500;
	uint256 public constant BASIS_POINTS = 10000;

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
		registry.register(aliceBytesAddress, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);
		registry.acceptBeneficiaryAddress(aliceBytesAddress, address(staking));
	}

	function testDeposit(uint256 amount) public {
		hevm.assume(amount != 0 && amount != type(uint256).max);
		hevm.deal(alice, amount);

		hevm.prank(alice);
		collateral.deposit{value: amount}();

		uint256 availableCollateral = collateral.getAvailableCollateral(aliceBytesAddress);

		assertEq(availableCollateral, amount);
		assertEq(collateral.getLockedCollateral(aliceBytesAddress), 0);

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

		collateral.withdraw(amount);
		hevm.stopPrank();

		assertEq(collateral.getAvailableCollateral(aliceBytesAddress), 0);
		assertEq(alice.balance, balanceBefore);

		require(wfil.balanceOf(address(collateral)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testWithdrawMaxAmount(uint128 amount) public {
		hevm.assume(amount != 0 && amount < 2000000000 ether);
		hevm.deal(alice, amount);
		uint256 balanceBefore = amount;

		hevm.prank(alice);
		registry.register(aliceBytesAddress, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		registry.acceptBeneficiaryAddress(aliceBytesAddress, address(staking));

		hevm.startPrank(alice);
		collateral.deposit{value: amount}();
		collateral.withdraw(amount + 10 ether); // try to withdraw 10 FIL more
		hevm.stopPrank();

		assertEq(collateral.getAvailableCollateral(aliceBytesAddress), 0);
		assertEq(alice.balance, balanceBefore); // validate that amount withdrawn is the same as Bob's deposit

		require(wfil.balanceOf(address(collateral)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testLock(uint256 amount) public {
		hevm.assume(amount != 0 && amount <= MAX_ALLOCATION);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);

		registry.register(aliceBytesAddress, address(staking), amount, MIN_TIME_PERIOD);
		registry.acceptBeneficiaryAddress(aliceBytesAddress, address(staking));

		collateral.deposit{value: amount}();
		assertEq(collateral.getAvailableCollateral(aliceBytesAddress), amount);
		hevm.stopPrank();

		collateral.lock(aliceBytesAddress, amount);

		uint256 lockedAmount = (amount * collateralRequirements) / BASIS_POINTS;
		assertEq(collateral.getLockedCollateral(aliceBytesAddress), lockedAmount);

		require(wfil.balanceOf(address(collateral)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testLockReverts(uint256 amount) public {
		hevm.assume(amount != 0 && amount <= MAX_ALLOCATION);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);

		registry.register(aliceBytesAddress, address(staking), amount, MIN_TIME_PERIOD);
		registry.acceptBeneficiaryAddress(aliceBytesAddress, address(staking));

		collateral.deposit{value: amount}();
		hevm.stopPrank();

		hevm.expectRevert("ALLOCATION_OVERFLOW");
		collateral.lock(aliceBytesAddress, amount * 2);

		assertEq(collateral.getAvailableCollateral(aliceBytesAddress), amount);
		assertEq(collateral.getLockedCollateral(aliceBytesAddress), 0);
	}
}
