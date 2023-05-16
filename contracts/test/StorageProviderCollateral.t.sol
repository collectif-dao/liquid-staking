// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {WFIL} from "fevmate/token/WFIL.sol";
import {IWFIL} from "../libraries/tokens/IWFIL.sol";
import {Buffer} from "@ensdomains/buffer/contracts/Buffer.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {stdError} from "forge-std/StdError.sol";

import {Resolver} from "../Resolver.sol";
import {StorageProviderCollateralMock, IStorageProviderCollateral, StorageProviderCollateralCallerMock} from "./mocks/StorageProviderCollateralMock.sol";
import {StorageProviderRegistryMock, StorageProviderRegistryCallerMock} from "./mocks/StorageProviderRegistryMock.sol";
import {LiquidStakingMock} from "./mocks/LiquidStakingMock.sol";
import {LiquidStakingController} from "../LiquidStakingController.sol";
import {MinerMockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {MinerActorMock} from "./mocks/MinerActorMock.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {ERC1967Proxy} from "@oz/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RewardCollectorMock} from "./mocks/RewardCollectorMock.sol";

contract StorageProviderCollateralTest is DSTestPlus {
	StorageProviderCollateralMock public collateral;
	StorageProviderCollateralCallerMock public callerMock;
	StorageProviderRegistryCallerMock public registryCallerMock;

	StorageProviderRegistryMock public registry;
	LiquidStakingMock public staking;
	IWFIL public wfil;
	MinerMockAPI private minerMockAPI;
	MinerActorMock public minerActor;
	Resolver public resolver;
	LiquidStakingController public controller;
	RewardCollectorMock private rewardCollector;

	bytes public owner;
	uint64 public aliceOwnerId = 1508;
	uint64 public aliceMinerId = 1648;
	uint64 public bobOwnerId = 1521;
	uint64 private oldMinerId = 1648;

	uint64 public SAMPLE_REWARD_COLLECTOR_ID = 1021;

	address private alice = address(0x122);
	bytes private aliceBytesAddress = abi.encodePacked(alice);
	address private bob = address(0x123);
	address private aliceOwnerAddr = address(0x12341214212);
	int64 private lastEpoch = 897999909;

	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant MIN_TIME_PERIOD = 90 days;
	uint256 private constant MAX_TIME_PERIOD = 360 days;
	uint256 private constant SAMPLE_DAILY_ALLOCATION = MAX_ALLOCATION / 30;

	uint256 public baseCollateralRequirements = 1500;
	uint256 public constant BASIS_POINTS = 10000;

	receive() external payable virtual {}

	fallback() external payable virtual {}

	function setUp() public {
		Buffer.buffer memory ownerBytes = Leb128.encodeUnsignedLeb128FromUInt64(aliceOwnerId);
		owner = ownerBytes.buf;

		wfil = IWFIL(address(new WFIL(msg.sender)));
		minerMockAPI = new MinerMockAPI(owner);
		minerActor = new MinerActorMock();

		Resolver resolverImpl = new Resolver();
		ERC1967Proxy resolverProxy = new ERC1967Proxy(address(resolverImpl), "");
		resolver = Resolver(address(resolverProxy));
		resolver.initialize();

		RewardCollectorMock rCollectorImpl = new RewardCollectorMock();
		ERC1967Proxy rCollectorProxy = new ERC1967Proxy(address(rCollectorImpl), "");
		rewardCollector = RewardCollectorMock(payable(rCollectorProxy));
		rewardCollector.initialize(
			address(minerMockAPI),
			address(minerActor),
			aliceOwnerId,
			aliceOwnerAddr,
			address(wfil),
			address(resolver)
		);

		LiquidStakingController controllerImpl = new LiquidStakingController();
		ERC1967Proxy controllerProxy = new ERC1967Proxy(address(controllerImpl), "");
		controller = LiquidStakingController(address(controllerProxy));
		controller.initialize(1000, 3000, address(resolver));

		LiquidStakingMock stakingImpl = new LiquidStakingMock();
		ERC1967Proxy stakingProxy = new ERC1967Proxy(address(stakingImpl), "");
		staking = LiquidStakingMock(payable(stakingProxy));
		staking.initialize(
			address(wfil),
			address(minerActor),
			aliceOwnerId,
			aliceOwnerAddr,
			address(minerMockAPI),
			address(resolver)
		);

		StorageProviderRegistryMock registryImpl = new StorageProviderRegistryMock();
		ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), "");
		registry = StorageProviderRegistryMock(address(registryProxy));
		registry.initialize(
			address(minerMockAPI),
			aliceOwnerId,
			SAMPLE_REWARD_COLLECTOR_ID,
			MAX_ALLOCATION,
			address(resolver)
		);

		StorageProviderCollateralMock collateralImpl = new StorageProviderCollateralMock();
		ERC1967Proxy collateralProxy = new ERC1967Proxy(address(collateralImpl), "");
		collateral = StorageProviderCollateralMock(payable(collateralProxy));
		collateral.initialize(wfil, address(resolver), baseCollateralRequirements);

		callerMock = new StorageProviderCollateralCallerMock(address(collateral));
		registryCallerMock = new StorageProviderRegistryCallerMock(address(registry));

		resolver.setLiquidStakingControllerAddress(address(controller));
		resolver.setRegistryAddress(address(registry));
		resolver.setCollateralAddress(address(collateral));
		resolver.setLiquidStakingAddress(address(staking));
		resolver.setRewardCollectorAddress(address(rewardCollector));
		registry.registerPool(address(staking));

		hevm.prank(alice);
		registry.register(aliceMinerId, MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION); // TODO: add missing steps for SP onboarding

		registry.onboardStorageProvider(
			aliceMinerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		registry.acceptBeneficiaryAddress(aliceOwnerId);
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
		hevm.expectRevert(abi.encodeWithSignature("InactiveSP()"));
		collateral.deposit{value: amount}(bobOwnerId);

		require(wfil.balanceOf(address(collateral)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testWithdraw(uint128 amount) public {
		hevm.assume(amount != 0 && amount < 2000000000 ether);
		hevm.deal(alice, amount);

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
		collateral.deposit{value: amount}(aliceOwnerId);
		collateral.withdraw(aliceOwnerId, amount + 10 ether); // try to withdraw 10 FIL more
		hevm.stopPrank();

		assertEq(collateral.getAvailableCollateral(aliceOwnerId), 0);
		assertEq(alice.balance, balanceBefore); // validate that amount withdrawn is the same as Bob's deposit

		require(wfil.balanceOf(address(collateral)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testWithdrawAfterIncreasingCollateralRequirements(uint128 amount) public {
		hevm.assume(amount >= 1 ether && amount < SAMPLE_DAILY_ALLOCATION);
		hevm.deal(alice, amount);

		uint256 additionalAllocation = (amount * 1000) / BASIS_POINTS;

		hevm.prank(alice);
		collateral.deposit{value: amount}(aliceOwnerId);

		collateral.increaseUsedAllocation(aliceOwnerId, additionalAllocation);

		assertEq(collateral.getAvailableCollateral(aliceOwnerId), amount);
		assertEq(collateral.getLockedCollateral(aliceOwnerId), 0);

		uint256 collateralRequirements = collateral.getCollateralRequirements(aliceOwnerId);
		uint256 lockedAmount = ((additionalAllocation * collateralRequirements) / BASIS_POINTS);
		uint256 balanceAfter = amount - lockedAmount;

		hevm.prank(alice);
		collateral.withdraw(aliceOwnerId, amount);

		assertEq(alice.balance, balanceAfter);
		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);

		emit log_named_uint("wfil.balanceOf(address(collateral): ", wfil.balanceOf(address(collateral)));
		emit log_named_uint("lockedAmount: ", lockedAmount);

		require(wfil.balanceOf(address(collateral)) == lockedAmount, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testWithdrawUnderwaterCase(uint128 amount) public {
		hevm.assume(amount >= 1 ether && amount < SAMPLE_DAILY_ALLOCATION);
		hevm.deal(alice, amount);

		uint256 collateralRequirements = collateral.getCollateralRequirements(aliceOwnerId);
		uint256 depositAmount = (amount * (collateralRequirements / 2)) / BASIS_POINTS;

		hevm.prank(alice);
		collateral.deposit{value: depositAmount}(aliceOwnerId);

		collateral.increaseUsedAllocation(aliceOwnerId, SAMPLE_DAILY_ALLOCATION);

		assertEq(collateral.getAvailableCollateral(aliceOwnerId), depositAmount);
		assertEq(collateral.getLockedCollateral(aliceOwnerId), 0);

		hevm.prank(alice);
		hevm.expectRevert(stdError.arithmeticError);
		collateral.withdraw(aliceOwnerId, amount);
	}

	function testLock(uint256 amount) public {
		hevm.assume(amount != 0 && amount <= SAMPLE_DAILY_ALLOCATION);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		collateral.deposit{value: amount}(aliceOwnerId);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), amount);
		hevm.stopPrank();

		// call via mock contract
		callerMock.lock(aliceOwnerId, amount);

		uint256 lockedAmount = (amount * baseCollateralRequirements) / BASIS_POINTS;
		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);

		require(wfil.balanceOf(address(collateral)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testFitDown(uint256 percentage) public {
		hevm.assume(percentage > 0 && percentage <= BASIS_POINTS);
		hevm.deal(alice, SAMPLE_DAILY_ALLOCATION);

		hevm.startPrank(alice);
		collateral.deposit{value: SAMPLE_DAILY_ALLOCATION}(aliceOwnerId);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), SAMPLE_DAILY_ALLOCATION);
		hevm.stopPrank();

		// call via mock contract
		callerMock.lock(aliceOwnerId, SAMPLE_DAILY_ALLOCATION);

		uint256 lockedAmount = FixedPointMathLib.mulDivDown(
			SAMPLE_DAILY_ALLOCATION,
			baseCollateralRequirements,
			BASIS_POINTS
		);
		uint256 availableAmount = SAMPLE_DAILY_ALLOCATION - lockedAmount;
		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), availableAmount);

		require(wfil.balanceOf(address(collateral)) == SAMPLE_DAILY_ALLOCATION, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");

		resolver.setRewardCollectorAddress(address(registryCallerMock)); // bypassing registry checks on reward collector address

		uint256 pledgeRepayment = FixedPointMathLib.mulDivDown(SAMPLE_DAILY_ALLOCATION, percentage, BASIS_POINTS);
		// reduce collateral requirements by initial pledge repayment
		registryCallerMock.increasePledgeRepayment(aliceOwnerId, pledgeRepayment);

		resolver.setRewardCollectorAddress(address(callerMock)); // bypassing collateral fit checks on reward collector address
		callerMock.fit(aliceOwnerId);

		uint256 adjAmt = FixedPointMathLib.mulDivDown(lockedAmount, percentage, BASIS_POINTS);

		lockedAmount = lockedAmount - adjAmt;
		availableAmount = availableAmount + adjAmt;

		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), availableAmount);
	}

	function testFitUp(uint256 additionalAllocation) public {
		hevm.assume(additionalAllocation >= 0 && additionalAllocation <= SAMPLE_DAILY_ALLOCATION);
		hevm.deal(alice, SAMPLE_DAILY_ALLOCATION);

		hevm.prank(alice);
		registry.requestAllocationLimitUpdate(MAX_ALLOCATION, MAX_ALLOCATION);
		registry.updateAllocationLimit(aliceOwnerId, MAX_ALLOCATION, MAX_ALLOCATION, MAX_ALLOCATION + 10);

		hevm.prank(alice);
		collateral.deposit{value: SAMPLE_DAILY_ALLOCATION}(aliceOwnerId);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), SAMPLE_DAILY_ALLOCATION);

		// call via mock contract
		callerMock.lock(aliceOwnerId, SAMPLE_DAILY_ALLOCATION);

		uint256 lockedAmount = FixedPointMathLib.mulDivDown(
			SAMPLE_DAILY_ALLOCATION,
			baseCollateralRequirements,
			BASIS_POINTS
		);
		uint256 availableAmount = SAMPLE_DAILY_ALLOCATION - lockedAmount;
		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), availableAmount);

		require(wfil.balanceOf(address(collateral)) == SAMPLE_DAILY_ALLOCATION, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");

		collateral.increaseUsedAllocation(aliceOwnerId, additionalAllocation);

		resolver.setRewardCollectorAddress(address(callerMock)); // bypassing collateral fit checks on reward collector address
		callerMock.fit(aliceOwnerId);

		uint256 usedAllocation = additionalAllocation + SAMPLE_DAILY_ALLOCATION;
		uint256 newCollRequirements = FixedPointMathLib.mulDivDown(
			usedAllocation,
			baseCollateralRequirements,
			BASIS_POINTS
		);
		uint256 adjAmt = newCollRequirements - lockedAmount;
		emit log_named_uint("adjAmt:", adjAmt);

		lockedAmount = lockedAmount + adjAmt;
		availableAmount = availableAmount - adjAmt;

		emit log_named_uint("aliceOwnerId locked collateral:", collateral.getLockedCollateral(aliceOwnerId));
		emit log_named_uint("lockedAmount:", lockedAmount);

		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), availableAmount);
	}

	function testLockReverts(uint256 amount) public {
		hevm.assume(amount > MAX_ALLOCATION);
		hevm.deal(alice, amount);

		hevm.prank(alice);
		collateral.deposit{value: amount}(aliceOwnerId);

		hevm.expectRevert(abi.encodeWithSignature("AllocationOverflow()"));
		callerMock.lock(aliceOwnerId, amount);

		assertEq(collateral.getAvailableCollateral(aliceOwnerId), amount);
		assertEq(collateral.getLockedCollateral(aliceOwnerId), 0);
	}

	function testLockRevertsWithInvalidAccess(uint256 amount) public {
		hevm.assume(amount != 0 && amount <= MAX_ALLOCATION);
		hevm.deal(alice, amount);

		hevm.prank(alice);
		collateral.deposit{value: amount}(aliceOwnerId);

		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		collateral.lock(aliceOwnerId, amount); // direct calls are prohibited
	}

	function testSlash(uint256 amount) public {
		hevm.assume(amount > 1 ether && amount <= SAMPLE_DAILY_ALLOCATION);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		collateral.deposit{value: amount}(aliceOwnerId);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), amount);
		hevm.stopPrank();

		// call via mock contract
		callerMock.lock(aliceOwnerId, amount);

		uint256 lockedAmount = (amount * baseCollateralRequirements) / BASIS_POINTS;
		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);

		require(wfil.balanceOf(address(collateral)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");

		uint256 slashingAmt = (lockedAmount * 5000) / BASIS_POINTS;
		uint256 totalSlashing = slashingAmt;

		callerMock.slash(aliceOwnerId, slashingAmt, address(callerMock));

		lockedAmount = lockedAmount - slashingAmt;
		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);
		assertEq(collateral.slashings(aliceOwnerId), slashingAmt);

		uint256 collateralBalance = amount - slashingAmt;
		require(wfil.balanceOf(address(collateral)) == collateralBalance, "INVALID_BALANCE");
		require(wfil.balanceOf(address(callerMock)) == slashingAmt, "INVALID_BALANCE");

		slashingAmt = (lockedAmount * 15000) / BASIS_POINTS;
		totalSlashing = totalSlashing + slashingAmt;

		callerMock.slash(aliceOwnerId, slashingAmt, address(callerMock));

		assertEq(collateral.getLockedCollateral(aliceOwnerId), 0);
		assertEq(collateral.slashings(aliceOwnerId), totalSlashing);

		collateralBalance = collateralBalance - slashingAmt;
		require(wfil.balanceOf(address(collateral)) == collateralBalance, "INVALID_BALANCE");
		require(wfil.balanceOf(address(callerMock)) == totalSlashing, "INVALID_BALANCE");
	}

	function testSlashReverts(uint256 amount) public {
		hevm.assume(amount > 1 ether && amount <= SAMPLE_DAILY_ALLOCATION);
		hevm.deal(alice, amount);

		uint256 lockedAmount = (amount * baseCollateralRequirements) / BASIS_POINTS;

		hevm.startPrank(alice);
		collateral.deposit{value: lockedAmount}(aliceOwnerId);
		assertEq(collateral.getAvailableCollateral(aliceOwnerId), lockedAmount);
		hevm.stopPrank();

		// call via mock contract
		callerMock.lock(aliceOwnerId, amount);

		assertEq(collateral.getLockedCollateral(aliceOwnerId), lockedAmount);

		require(wfil.balanceOf(address(collateral)) == lockedAmount, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");

		hevm.expectRevert(abi.encodeWithSignature("InsufficientCollateral()"));
		callerMock.slash(aliceOwnerId, amount + 1, address(callerMock));
	}

	function testUpdateCollateralRequirements(uint256 requirements) public {
		hevm.assume(requirements <= 10000 && requirements > 0 && requirements != 1500);

		collateral.updateCollateralRequirements(aliceOwnerId, requirements);

		require(collateral.collateralRequirements(aliceOwnerId) == requirements, "INVALID_REQUIREMENTS");
	}

	function testUpdateCollateralRequirementsReverts(uint256 requirements) public {
		hevm.assume(requirements > 10000);

		hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
		collateral.updateCollateralRequirements(aliceOwnerId, requirements);
	}

	function testUpdateCollateralRequirementsRevertsWithSameRequirements() public {
		collateral.updateCollateralRequirements(aliceOwnerId, 0);

		hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
		collateral.updateCollateralRequirements(aliceOwnerId, 1500);
	}

	function testUpdateBaseCollateralRequirements(uint256 requirements) public {
		hevm.assume(requirements > 0 && requirements != baseCollateralRequirements);
		collateral.updateBaseCollateralRequirements(requirements);
	}

	function testUpdateBaseCollateralRequirementsReverts() public {
		hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
		collateral.updateBaseCollateralRequirements(baseCollateralRequirements);

		hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
		collateral.updateBaseCollateralRequirements(0);

		hevm.prank(aliceOwnerAddr);
		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		collateral.updateBaseCollateralRequirements(1);

		hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
		collateral.updateBaseCollateralRequirements(0);
	}

	function testReportSlashing(uint128 amount) public {
		hevm.assume(amount <= SAMPLE_DAILY_ALLOCATION && amount > 1 ether);
		uint256 collateralAmount = (amount * baseCollateralRequirements) / BASIS_POINTS;

		hevm.deal(address(this), amount);
		hevm.deal(alice, collateralAmount);

		hevm.prank(alice);
		collateral.deposit{value: collateralAmount}(aliceOwnerId);

		staking.stake{value: amount}();

		hevm.prank(alice);
		staking.pledge(amount);

		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(address(staking)) == 0, "INVALID_BALANCE");
		require(address(minerActor).balance == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == amount, "INVALID_BALANCE");

		uint256 slashingAmt = (collateralAmount * 5000) / BASIS_POINTS;
		collateral.reportSlashing(aliceOwnerId, slashingAmt);

		require(staking.totalAssets() == amount + slashingAmt, "INVALID_BALANCE");
		require(wfil.balanceOf(address(staking)) == slashingAmt, "INVALID_BALANCE");
		require(address(minerActor).balance == amount, "INVALID_BALANCE");

		assertEq(collateral.getLockedCollateral(aliceOwnerId), collateralAmount - slashingAmt);
		assertEq(collateral.slashings(aliceOwnerId), slashingAmt);
	}

	function testReportSlashingReverts(uint128 amount) public {
		hevm.assume(amount <= SAMPLE_DAILY_ALLOCATION && amount > 1 ether);
		uint256 collateralAmount = (amount * baseCollateralRequirements) / BASIS_POINTS;

		hevm.deal(address(this), amount);
		hevm.deal(alice, collateralAmount);

		hevm.prank(alice);
		collateral.deposit{value: collateralAmount}(aliceOwnerId);

		staking.stake{value: amount}();

		hevm.prank(alice);
		staking.pledge(amount);

		hevm.expectRevert(abi.encodeWithSignature("InsufficientCollateral()"));
		collateral.reportSlashing(aliceOwnerId, collateralAmount + 1);
	}

	function testReportSlashingRevertsInvalidAccess(uint128 amount) public {
		hevm.assume(amount <= SAMPLE_DAILY_ALLOCATION && amount > 1 ether);
		uint256 collateralAmount = (amount * baseCollateralRequirements) / BASIS_POINTS;

		hevm.deal(address(this), amount);
		hevm.deal(alice, collateralAmount);

		hevm.prank(alice);
		collateral.deposit{value: collateralAmount}(aliceOwnerId);

		staking.stake{value: amount}();

		hevm.prank(alice);
		staking.pledge(amount);

		hevm.prank(alice);
		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		collateral.reportSlashing(aliceOwnerId, collateralAmount + 1);
	}

	function testReportRecovery(uint128 amount) public {
		hevm.assume(amount <= SAMPLE_DAILY_ALLOCATION && amount > 1 ether);
		uint256 collateralAmount = (amount * baseCollateralRequirements) / BASIS_POINTS;

		hevm.deal(address(this), amount);
		hevm.deal(alice, collateralAmount);

		hevm.prank(alice);
		collateral.deposit{value: collateralAmount}(aliceOwnerId);

		staking.stake{value: amount}();

		hevm.prank(alice);
		staking.pledge(amount);

		uint256 slashingAmt = (collateralAmount * 5000) / BASIS_POINTS;
		collateral.reportSlashing(aliceOwnerId, slashingAmt);

		assertEq(collateral.getLockedCollateral(aliceOwnerId), collateralAmount - slashingAmt);
		assertEq(collateral.slashings(aliceOwnerId), slashingAmt);
		assertBoolEq(collateral.activeSlashings(aliceOwnerId), true);

		collateral.reportRecovery(aliceOwnerId);
		assertBoolEq(collateral.activeSlashings(aliceOwnerId), false);
	}

	function testReportRecoveryReverts(uint128 amount) public {
		hevm.assume(amount <= SAMPLE_DAILY_ALLOCATION && amount > 1 ether);

		hevm.expectRevert(abi.encodeWithSignature("InactiveSlashing()"));
		collateral.reportRecovery(aliceOwnerId);
	}

	function testReportRecoveryRevertsWithInvalidAccess(uint128 amount) public {
		hevm.assume(amount <= SAMPLE_DAILY_ALLOCATION && amount > 1 ether);

		hevm.prank(alice);
		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		collateral.reportRecovery(aliceOwnerId);
	}
}
