// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {WFIL} from "fevmate/token/WFIL.sol";
import {IERC4626} from "fei-protocol/erc4626/interfaces/IERC4626.sol";
import {IWETH9} from "fei-protocol/erc4626/external/PeripheryPayments.sol";
import {Buffer} from "@ensdomains/buffer/contracts/Buffer.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {StorageProviderCollateralMock, IStorageProviderCollateral, StorageProviderCollateralCallerMock} from "./mocks/StorageProviderCollateralMock.sol";
import {StorageProviderRegistryMock, StorageProviderRegistryCallerMock} from "./mocks/StorageProviderRegistryMock.sol";
import {LiquidStakingMock} from "./mocks/LiquidStakingMock.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

contract StorageProviderCollateralTest is DSTestPlus {
	StorageProviderCollateralMock public collateral;
	StorageProviderCollateralCallerMock public callerMock;
	StorageProviderRegistryCallerMock public registryCallerMock;

	StorageProviderRegistryMock public registry;
	LiquidStakingMock public staking;
	IWETH9 public wfil;

	bytes public owner;
	uint64 public aliceOwnerId = 1508;
	uint64 public aliceMinerId = 1648;
	uint64 public bobOwnerId = 1521;
	uint64 private oldMinerId = 1648;

	address private alice = address(0x122);
	bytes private aliceBytesAddress = abi.encodePacked(alice);
	address private bob = address(0x123);
	address private rewardCollector = address(0x12523);
	address private aliceOwnerAddr = address(0x12341214212);

	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant MIN_TIME_PERIOD = 90 days;
	uint256 private constant MAX_TIME_PERIOD = 360 days;
	uint256 private constant SAMPLE_DAILY_ALLOCATION = MAX_ALLOCATION / 30;

	uint256 public collateralRequirements = 1500;
	uint256 public constant BASIS_POINTS = 10000;

	function setUp() public {
		Buffer.buffer memory ownerBytes = Leb128.encodeUnsignedLeb128FromUInt64(aliceOwnerId);
		owner = ownerBytes.buf;

		wfil = IWETH9(address(new WFIL(msg.sender)));
		staking = new LiquidStakingMock(
			address(wfil),
			address(0x21421),
			aliceOwnerId,
			1000,
			3000,
			rewardCollector,
			aliceOwnerAddr
		);

		registry = new StorageProviderRegistryMock(
			owner,
			aliceOwnerId,
			MAX_STORAGE_PROVIDERS,
			MAX_ALLOCATION,
			MIN_TIME_PERIOD,
			MAX_TIME_PERIOD
		);

		collateral = new StorageProviderCollateralMock(wfil, address(registry));
		callerMock = new StorageProviderCollateralCallerMock(address(collateral));
		registryCallerMock = new StorageProviderRegistryCallerMock(address(registry));

		registry.setCollateralAddress(address(collateral));
		staking.setRegistryAddress(address(registry));

		hevm.startPrank(alice);
		registry.register(aliceMinerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION); // TODO: add missing steps for SP onboarding
		registry.changeBeneficiaryAddress(address(staking));
		hevm.stopPrank();

		registry.acceptBeneficiaryAddress(aliceOwnerId, address(staking));
		registry.registerPool(address(callerMock));
	}

	function testDeposit(uint256 amount) public {
		hevm.assume(amount != 0 && amount != type(uint256).max);
		hevm.deal(alice, amount);

		hevm.prank(alice);
		collateral.deposit{value: amount}(aliceOwnerId);

		uint256 availableCollateral = collateral.getAvailableCollateral(aliceOwnerId);

		assertEq(availableCollateral, amount);
		assertEq(collateral.getLockedCollateral(aliceOwnerId), 0);

		require(wfil.balanceOf(address(collateral)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testDepositReverts(uint256 amount) public {
		hevm.assume(amount != 0 && amount != type(uint256).max);
		hevm.deal(bob, amount);

		hevm.prank(bob);
		hevm.expectRevert("INACTIVE_STORAGE_PROVIDER");
		collateral.deposit{value: amount}(bobOwnerId);

		require(wfil.balanceOf(address(collateral)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testWithdraw(uint128 amount) public {
		hevm.assume(amount != 0 && amount < 2000000000 ether);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		registry.register(aliceMinerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.changeBeneficiaryAddress(address(staking));
		hevm.stopPrank();

		registry.acceptBeneficiaryAddress(aliceOwnerId, address(staking));

		uint256 balanceBefore = amount;

		hevm.startPrank(alice);
		collateral.deposit{value: amount}(aliceOwnerId);
		collateral.withdraw(aliceOwnerId, amount);
		hevm.stopPrank();

		assertEq(collateral.getAvailableCollateral(aliceOwnerId), 0);
		assertEq(alice.balance, balanceBefore);

		require(wfil.balanceOf(address(collateral)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testWithdrawMaxAmount(uint128 amount) public {
		hevm.assume(amount != 0 && amount < 2000000000 ether);
		hevm.deal(alice, amount);
		uint256 balanceBefore = amount;

		hevm.startPrank(alice);
		registry.register(aliceMinerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.changeBeneficiaryAddress(address(staking));
		hevm.stopPrank();

		registry.acceptBeneficiaryAddress(aliceOwnerId, address(staking));

		hevm.startPrank(alice);
		collateral.deposit{value: amount}(aliceOwnerId);
		collateral.withdraw(aliceOwnerId, amount + 10 ether); // try to withdraw 10 FIL more
		hevm.stopPrank();

		assertEq(collateral.getAvailableCollateral(aliceOwnerId), 0);
		assertEq(alice.balance, balanceBefore); // validate that amount withdrawn is the same as Bob's deposit

		require(wfil.balanceOf(address(collateral)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testLock(uint256 amount) public {
		hevm.assume(amount != 0 && amount <= SAMPLE_DAILY_ALLOCATION);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		registry.register(aliceMinerId, address(staking), amount, SAMPLE_DAILY_ALLOCATION);
		registry.changeBeneficiaryAddress(address(staking));
		hevm.stopPrank();

		registry.acceptBeneficiaryAddress(aliceOwnerId, address(staking));

		hevm.startPrank(alice);
		collateral.deposit{value: amount}(aliceOwnerId);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), amount);
		hevm.stopPrank();

		// call via mock contract
		callerMock.lock(aliceOwnerId, amount);

		uint256 lockedAmount = (amount * collateralRequirements) / BASIS_POINTS;
		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);

		require(wfil.balanceOf(address(collateral)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	// TODO: fix rounding errors on precision calculations

	function testFitDown(uint256 percentage) public {
		hevm.assume(percentage > 0 && percentage <= BASIS_POINTS);
		hevm.deal(alice, SAMPLE_DAILY_ALLOCATION);

		hevm.startPrank(alice);
		registry.register(aliceMinerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.changeBeneficiaryAddress(address(staking));
		hevm.stopPrank();

		registry.acceptBeneficiaryAddress(aliceOwnerId, address(staking));

		hevm.startPrank(alice);
		collateral.deposit{value: SAMPLE_DAILY_ALLOCATION}(aliceOwnerId);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), SAMPLE_DAILY_ALLOCATION);
		hevm.stopPrank();

		// call via mock contract
		callerMock.lock(aliceOwnerId, SAMPLE_DAILY_ALLOCATION);

		uint256 lockedAmount = Math.mulDiv(SAMPLE_DAILY_ALLOCATION, collateralRequirements, BASIS_POINTS);
		uint256 availableAmount = SAMPLE_DAILY_ALLOCATION - lockedAmount;
		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), availableAmount);

		require(wfil.balanceOf(address(collateral)) == SAMPLE_DAILY_ALLOCATION, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");

		registry.registerPool(address(registryCallerMock));

		uint256 pledgeRepayment = Math.mulDiv(SAMPLE_DAILY_ALLOCATION, percentage, BASIS_POINTS);
		// reduce collateral requirements by initial pledge repayment
		registryCallerMock.increasePledgeRepayment(aliceOwnerId, pledgeRepayment);

		callerMock.fit(aliceOwnerId);

		uint256 adjAmt = Math.mulDiv(lockedAmount, percentage, BASIS_POINTS);

		lockedAmount = lockedAmount - adjAmt;
		availableAmount = availableAmount + adjAmt;

		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), availableAmount);
	}

	function testFitUp(uint256 additionalAllocation) public {
		hevm.assume(additionalAllocation >= 0 && additionalAllocation <= SAMPLE_DAILY_ALLOCATION);
		hevm.deal(alice, SAMPLE_DAILY_ALLOCATION);

		hevm.startPrank(alice);
		registry.register(aliceMinerId, address(staking), MAX_ALLOCATION, MAX_ALLOCATION);
		registry.changeBeneficiaryAddress(address(staking));
		hevm.stopPrank();

		registry.acceptBeneficiaryAddress(aliceOwnerId, address(staking));

		hevm.startPrank(alice);
		collateral.deposit{value: SAMPLE_DAILY_ALLOCATION}(aliceOwnerId);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), SAMPLE_DAILY_ALLOCATION);
		hevm.stopPrank();

		// call via mock contract
		callerMock.lock(aliceOwnerId, SAMPLE_DAILY_ALLOCATION);

		uint256 lockedAmount = Math.mulDiv(SAMPLE_DAILY_ALLOCATION, collateralRequirements, BASIS_POINTS);
		uint256 availableAmount = SAMPLE_DAILY_ALLOCATION - lockedAmount;
		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), availableAmount);

		require(wfil.balanceOf(address(collateral)) == SAMPLE_DAILY_ALLOCATION, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");

		collateral.increaseUserAllocation(aliceOwnerId, additionalAllocation);

		callerMock.fit(aliceOwnerId);

		uint256 adjAmt = Math.mulDiv(additionalAllocation, collateralRequirements, BASIS_POINTS);
		emit log_named_uint("adjAmt:", adjAmt);

		lockedAmount = lockedAmount + adjAmt;
		availableAmount = availableAmount - adjAmt;

		emit log_named_uint("aliceOwnerId locked collateral:", collateral.getLockedCollateral(aliceOwnerId));
		emit log_named_uint("lockedAmount:", lockedAmount);

		// assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);
		// assertEq(collateral.getAvailableCollateral(aliceOwnerId), availableAmount);
	}

	function testLockReverts(uint256 amount) public {
		hevm.assume(amount != 0 && amount <= MAX_ALLOCATION);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		registry.register(aliceMinerId, address(staking), amount, SAMPLE_DAILY_ALLOCATION);
		registry.changeBeneficiaryAddress(address(staking));
		hevm.stopPrank();

		registry.acceptBeneficiaryAddress(aliceOwnerId, address(staking));

		hevm.prank(alice);
		collateral.deposit{value: amount}(aliceOwnerId);

		hevm.expectRevert("ALLOCATION_OVERFLOW");
		callerMock.lock(aliceOwnerId, amount * 2);

		assertEq(collateral.getAvailableCollateral(aliceOwnerId), amount);
		assertEq(collateral.getLockedCollateral(aliceOwnerId), 0);
	}

	function testLockRevertsWithInvalidAccess(uint256 amount) public {
		hevm.assume(amount != 0 && amount <= MAX_ALLOCATION);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		registry.register(aliceMinerId, address(staking), amount, SAMPLE_DAILY_ALLOCATION);
		registry.changeBeneficiaryAddress(address(staking));
		hevm.stopPrank();

		registry.acceptBeneficiaryAddress(aliceOwnerId, address(staking));

		hevm.prank(alice);
		collateral.deposit{value: amount}(aliceOwnerId);

		hevm.expectRevert("INVALID_ACCESS");
		collateral.lock(aliceOwnerId, amount); // direct calls are prohibited
	}

	function testSlash(uint256 amount) public {
		hevm.assume(amount > 1 ether && amount <= SAMPLE_DAILY_ALLOCATION);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		registry.register(aliceMinerId, address(staking), amount, SAMPLE_DAILY_ALLOCATION);
		registry.changeBeneficiaryAddress(address(staking));
		hevm.stopPrank();

		registry.acceptBeneficiaryAddress(aliceOwnerId, address(staking));

		hevm.startPrank(alice);
		collateral.deposit{value: amount}(aliceOwnerId);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), amount);
		hevm.stopPrank();

		// call via mock contract
		callerMock.lock(aliceOwnerId, amount);

		uint256 lockedAmount = (amount * collateralRequirements) / BASIS_POINTS;
		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);

		require(wfil.balanceOf(address(collateral)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");

		uint256 slashingAmt = (lockedAmount * 5000) / BASIS_POINTS;
		uint256 totalSlashing = slashingAmt;

		callerMock.slash(aliceOwnerId, slashingAmt);

		lockedAmount = lockedAmount - slashingAmt;
		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);
		assertEq(collateral.slashings(aliceOwnerId), slashingAmt);

		uint256 collateralBalance = amount - slashingAmt;
		require(wfil.balanceOf(address(collateral)) == collateralBalance, "INVALID_BALANCE");
		require(wfil.balanceOf(address(callerMock)) == slashingAmt, "INVALID_BALANCE");

		slashingAmt = (lockedAmount * 15000) / BASIS_POINTS;
		totalSlashing = totalSlashing + slashingAmt;

		callerMock.slash(aliceOwnerId, slashingAmt);

		assertEq(collateral.getLockedCollateral(aliceOwnerId), 0);
		assertEq(collateral.slashings(aliceOwnerId), totalSlashing);

		collateralBalance = collateralBalance - slashingAmt;
		require(wfil.balanceOf(address(collateral)) == collateralBalance, "INVALID_BALANCE");
		require(wfil.balanceOf(address(callerMock)) == totalSlashing, "INVALID_BALANCE");
	}

	function testSlashReverts(uint256 amount) public {
		hevm.assume(amount > 1 ether && amount <= SAMPLE_DAILY_ALLOCATION);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		registry.register(aliceMinerId, address(staking), amount, SAMPLE_DAILY_ALLOCATION);
		registry.changeBeneficiaryAddress(address(staking));
		hevm.stopPrank();

		registry.acceptBeneficiaryAddress(aliceOwnerId, address(staking));
		uint256 lockedAmount = (amount * collateralRequirements) / BASIS_POINTS;

		hevm.startPrank(alice);
		collateral.deposit{value: lockedAmount}(aliceOwnerId);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), lockedAmount);
		hevm.stopPrank();

		// call via mock contract
		callerMock.lock(aliceOwnerId, amount);

		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);

		require(wfil.balanceOf(address(collateral)) == lockedAmount, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");

		hevm.expectRevert("NOT_ENOUGH_COLLATERAL");
		callerMock.slash(aliceOwnerId, amount + 1);
	}

	function testUpdateCollateralRequirements(uint256 requirements) public {
		hevm.assume(requirements <= 10000 && requirements > 0 && requirements != 1500);

		collateral.updateCollateralRequirements(aliceOwnerId, requirements);

		require(collateral.collateralRequirements(aliceOwnerId) == requirements, "INVALID_REQUIREMENTS");
	}

	function testUpdateCollateralRequirementsReverts(uint256 requirements) public {
		hevm.assume(requirements > 10000);

		hevm.expectRevert("COLLATERAL_REQUIREMENTS_OVERFLOW");
		collateral.updateCollateralRequirements(aliceOwnerId, requirements);
	}

	function testUpdateCollateralRequirementsRevertsWithSameRequirements() public {
		collateral.updateCollateralRequirements(aliceOwnerId, 0);

		hevm.expectRevert("SAME_COLLATERAL_REQUIREMENTS");
		collateral.updateCollateralRequirements(aliceOwnerId, 1500);
	}
}
