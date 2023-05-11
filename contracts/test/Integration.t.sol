// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20, MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {WFIL} from "fevmate/token/WFIL.sol";
import {IWFIL} from "../libraries/tokens/IWFIL.sol";
import {BigIntsClient} from "../libraries/BigInts.sol";
import {Buffer} from "@ensdomains/buffer/contracts/Buffer.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IStorageProviderCollateral, StorageProviderCollateralMock} from "./mocks/StorageProviderCollateralMock.sol";
import {StorageProviderRegistryMock} from "./mocks/StorageProviderRegistryMock.sol";
import {LiquidStakingMock} from "./mocks/LiquidStakingMock.sol";
import {MinerActorMock} from "./mocks/MinerActorMock.sol";
import {MinerMockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {Resolver} from "../Resolver.sol";
import {LiquidStakingController} from "../LiquidStakingController.sol";
import {BeneficiaryManagerMock} from "./mocks/BeneficiaryManagerMock.sol";

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {ERC1967Proxy} from "@oz/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract IntegrationTest is DSTestPlus {
	using FixedPointMathLib for uint256;

	LiquidStakingMock public staking;
	IWFIL public wfil;
	StorageProviderCollateralMock public collateral;
	StorageProviderRegistryMock public registry;
	MinerActorMock public minerActor;
	MinerMockAPI private minerMockAPI;
	BigIntsClient private bigIntsLib;
	Resolver public resolver;
	LiquidStakingController public controller;
	BeneficiaryManagerMock public beneficiaryManager;

	bytes public owner;
	uint64 public aliceOwnerId = 1508;
	uint64 public aliceMinerId = 16121;

	uint256 private aliceKey = 0xBEEF;
	address private alice = address(0x122);
	address private aliceRestaking = address(0x123412);
	address private aliceOwnerAddr = address(0x12341214212);

	address private staker = address(0x12321124);

	uint256 private ALICE_TOTAL_ALLOCATION = 100000 ether;
	uint256 private ALICE_DAILY_ALLOCATION = 1000 ether;
	uint256 private ALICE_ALLOCATION_PERIOD = 100;
	uint256 private ALICE_RESTAKING_RATIO = 2000;

	uint256 private adminFee = 200;
	uint256 private profitShare = 3000;
	address private rewardCollector = address(0x12523);

	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
	uint256 private constant MAX_ALLOCATION = 1000000 ether;
	uint256 private constant MIN_TIME_PERIOD = 365 days;
	uint256 private constant MAX_TIME_PERIOD = 1825 days;

	uint256 public baseCollateralRequirements = 2800;
	uint256 public constant BASIS_POINTS = 10000;
	uint256 private constant genesisTimestamp = 1683985020;
	uint256 private constant initialPledge = 216900000000000000;
	uint256 private constant rewardsPerTiB = 10300000000000000;

	uint256 private constant ONE_DAY = 24 * 1 hours;

	function setUp() public {
		alice = hevm.addr(aliceKey);
		Buffer.buffer memory ownerBytes = Leb128.encodeUnsignedLeb128FromUInt64(aliceOwnerId);
		owner = ownerBytes.buf;

		wfil = IWFIL(address(new WFIL(msg.sender)));
		minerActor = new MinerActorMock();
		minerMockAPI = new MinerMockAPI(owner);
		bigIntsLib = new BigIntsClient();

		Resolver resolverImpl = new Resolver();
		ERC1967Proxy resolverProxy = new ERC1967Proxy(address(resolverImpl), "");
		resolver = Resolver(address(resolverProxy));
		resolver.initialize();

		BeneficiaryManagerMock bManagerImpl = new BeneficiaryManagerMock();
		ERC1967Proxy bManagerProxy = new ERC1967Proxy(address(bManagerImpl), "");
		beneficiaryManager = BeneficiaryManagerMock(address(bManagerProxy));
		beneficiaryManager.initialize(address(minerMockAPI), aliceOwnerId, address(resolver));

		LiquidStakingController controllerImpl = new LiquidStakingController();
		ERC1967Proxy controllerProxy = new ERC1967Proxy(address(controllerImpl), "");
		controller = LiquidStakingController(address(controllerProxy));
		controller.initialize(adminFee, profitShare, rewardCollector, address(resolver));

		LiquidStakingMock stakingImpl = new LiquidStakingMock();
		ERC1967Proxy stakingProxy = new ERC1967Proxy(address(stakingImpl), "");
		staking = LiquidStakingMock(payable(stakingProxy));
		staking.initialize(
			address(wfil),
			address(minerActor),
			aliceOwnerId,
			aliceOwnerAddr,
			address(minerMockAPI),
			address(bigIntsLib),
			address(resolver)
		);

		StorageProviderRegistryMock registryImpl = new StorageProviderRegistryMock();
		ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), "");
		registry = StorageProviderRegistryMock(address(registryProxy));
		registry.initialize(address(minerMockAPI), aliceOwnerId, MAX_ALLOCATION, address(resolver));

		StorageProviderCollateralMock collateralImpl = new StorageProviderCollateralMock();
		ERC1967Proxy collateralProxy = new ERC1967Proxy(address(collateralImpl), "");
		collateral = StorageProviderCollateralMock(payable(collateralProxy));
		collateral.initialize(wfil, address(resolver), baseCollateralRequirements);

		registry.registerPool(address(staking));
		resolver.setLiquidStakingControllerAddress(address(controller));
		resolver.setRegistryAddress(address(registry));
		resolver.setCollateralAddress(address(collateral));
		resolver.setLiquidStakingAddress(address(staking));
		resolver.setBeneficiaryManagerAddress(address(beneficiaryManager));

		hevm.prank(alice);
		registry.register(aliceMinerId, address(staking), ALICE_TOTAL_ALLOCATION, ALICE_DAILY_ALLOCATION);

		registry.onboardStorageProvider(
			aliceMinerId,
			ALICE_TOTAL_ALLOCATION,
			ALICE_DAILY_ALLOCATION,
			ALICE_TOTAL_ALLOCATION + 55000 ether, // TODO: CALCULATE ALICE REPAYMENT AMOUNT
			10000000
		);

		hevm.prank(alice);
		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(aliceOwnerId);

		hevm.warp(genesisTimestamp);
	}

	struct TestExecutionLocalVars {
		uint256 dailyAllocation;
		uint256 hypotheticalRepayment;
		uint256 targetCollateral;
		uint256 totalAllocated;
		// sectors section
		uint256 newSectors;
		uint256 totalSectors;
		// rewards section
		uint256 totalRewardsPerDay;
		uint256 availableRewardsPerDay;
		uint256 revenuePerDay;
		uint256 totalAvailableRewards;
		uint256 totalRewards;
		uint256 rewardsDelta;
	}

	function testSuccessfulInteractions(uint256 totalAllocation) public {
		hevm.assume(totalAllocation > ALICE_TOTAL_ALLOCATION && totalAllocation <= MAX_ALLOCATION);
		hevm.deal(staker, totalAllocation);

		TestExecutionLocalVars memory vars;

		vars.dailyAllocation = totalAllocation / ALICE_ALLOCATION_PERIOD;
		vars.hypotheticalRepayment = (totalAllocation * 15000) / BASIS_POINTS;

		hevm.prank(alice);
		registry.requestAllocationLimitUpdate(totalAllocation, vars.dailyAllocation);
		registry.updateAllocationLimit(aliceOwnerId, totalAllocation, vars.dailyAllocation, vars.hypotheticalRepayment);

		hevm.prank(staker);
		staking.stake{value: totalAllocation}();

		require(staking.balanceOf(address(staker)) == totalAllocation, "INVALID_STAKER_CLFIL_BALANCE");
		require(wfil.balanceOf(address(staker)) == 0, "INVALID_STAKER_WFIL_BALANCE");
		require(staker.balance == 0, "INVALID_STAKER_FIL_BALANCE");
		require(wfil.balanceOf(address(staking)) == totalAllocation, "INVALID_LSP_WFIL_BALANCE");
		require(staking.totalAssets() == totalAllocation, "INVALID_LSP_ASSETS");

		vars.targetCollateral = (totalAllocation * collateral.collateralRequirements(aliceOwnerId)) / BASIS_POINTS;
		hevm.deal(alice, vars.targetCollateral);

		hevm.prank(alice);
		collateral.deposit{value: vars.targetCollateral}(aliceOwnerId);

		require(alice.balance == 0, "INVALID_ALICE_BALANCE_AFTER_cDEPOSIT");

		vars.newSectors = calculateNumSectors(vars.dailyAllocation);

		vars.totalRewardsPerDay = calculateRewardsForSectors(vars.newSectors);
		vars.availableRewardsPerDay = (vars.totalRewardsPerDay * 2500) / BASIS_POINTS;
		vars.revenuePerDay = (vars.availableRewardsPerDay * profitShare) / BASIS_POINTS;
		vars.totalSectors = vars.newSectors * ALICE_ALLOCATION_PERIOD;
		vars.totalAvailableRewards = vars.availableRewardsPerDay * ALICE_ALLOCATION_PERIOD;

		hevm.deal(address(minerActor), vars.totalAvailableRewards);

		for (uint256 i = 0; i < ALICE_ALLOCATION_PERIOD; i++) {
			uint256 timeDelta = ONE_DAY * i;
			hevm.warp(genesisTimestamp + timeDelta);

			hevm.prank(alice);
			staking.pledge(vars.dailyAllocation);
			vars.totalAllocated = vars.totalAllocated + vars.dailyAllocation;

			uint256 collateralRequirements = (vars.totalAllocated * collateral.collateralRequirements(aliceOwnerId)) /
				BASIS_POINTS;

			if (i == 0) {
				vars.rewardsDelta = vars.totalAvailableRewards + vars.totalAllocated;
			} else {
				vars.rewardsDelta =
					vars.totalAvailableRewards +
					vars.totalAllocated -
					(vars.availableRewardsPerDay * (i - 1));
			}

			require(address(minerActor).balance == vars.rewardsDelta, "INVALID_MINER_ACTOR_BALANCE_AFTER_PLEDGE");
			require(
				collateral.getLockedCollateral(aliceOwnerId) == collateralRequirements,
				"INVALID_LOCKED_COLLATERAL"
			);

			if (i > 0) {
				staking.withdrawRewards(aliceOwnerId, vars.availableRewardsPerDay);
				vars.rewardsDelta =
					vars.totalAvailableRewards +
					vars.totalAllocated -
					(vars.availableRewardsPerDay * (i));

				require(
					address(minerActor).balance == vars.rewardsDelta,
					"INVALID_MINER_ACTOR_BALANCE_AFTER_WITHDRAWAL"
				);
				require(staking.totalAssets() == totalAllocation + (vars.revenuePerDay * (i)), "INVALID_LSP_ASSETS");
				require(staking.totalFilPledged() == vars.totalAllocated, "INVALID_LSP_PLEDGED_ASSETS");
				require(
					collateral.getLockedCollateral(aliceOwnerId) == collateralRequirements,
					"INVALID_LOCKED_COLLATERAL"
				);
				require(
					wfil.balanceOf(address(staking)) ==
						totalAllocation - vars.totalAllocated + (vars.revenuePerDay * (i)),
					"INVALID_LSP_WFIL_BALANCE"
				);
			} else {
				require(staking.totalAssets() == totalAllocation, "INVALID_LSP_ASSETS");
				require(staking.totalFilPledged() == vars.totalAllocated, "INVALID_LSP_PLEDGED_ASSETS");
			}
		}
	}

	function testDailyAndTotalAllocationOverflows(uint256 totalAllocation) public {
		hevm.assume(totalAllocation > ALICE_TOTAL_ALLOCATION && totalAllocation <= MAX_ALLOCATION);
		hevm.deal(staker, totalAllocation);

		TestExecutionLocalVars memory vars;

		vars.dailyAllocation = totalAllocation / ALICE_ALLOCATION_PERIOD;
		vars.hypotheticalRepayment = (totalAllocation * 15000) / BASIS_POINTS;

		hevm.prank(alice);
		registry.requestAllocationLimitUpdate(totalAllocation, vars.dailyAllocation);
		registry.updateAllocationLimit(aliceOwnerId, totalAllocation, vars.dailyAllocation, vars.hypotheticalRepayment);

		hevm.prank(staker);
		staking.stake{value: totalAllocation}();

		require(staking.balanceOf(address(staker)) == totalAllocation, "INVALID_STAKER_CLFIL_BALANCE");
		require(wfil.balanceOf(address(staker)) == 0, "INVALID_STAKER_WFIL_BALANCE");
		require(staker.balance == 0, "INVALID_STAKER_FIL_BALANCE");
		require(wfil.balanceOf(address(staking)) == totalAllocation, "INVALID_LSP_WFIL_BALANCE");
		require(staking.totalAssets() == totalAllocation, "INVALID_LSP_ASSETS");

		vars.targetCollateral = (totalAllocation * collateral.collateralRequirements(aliceOwnerId)) / BASIS_POINTS;
		hevm.deal(alice, vars.targetCollateral);

		hevm.prank(alice);
		collateral.deposit{value: vars.targetCollateral}(aliceOwnerId);

		require(alice.balance == 0, "INVALID_ALICE_BALANCE_AFTER_cDEPOSIT");

		vars.newSectors = calculateNumSectors(vars.dailyAllocation);

		vars.totalRewardsPerDay = calculateRewardsForSectors(vars.newSectors);
		vars.availableRewardsPerDay = (vars.totalRewardsPerDay * 2500) / BASIS_POINTS;
		vars.revenuePerDay = (vars.availableRewardsPerDay * profitShare) / BASIS_POINTS;
		// vars.lockedRewardsPerDay = vars.totalRewardsPerDay - vars.availableRewardsPerDay;

		vars.totalSectors = vars.newSectors * ALICE_ALLOCATION_PERIOD;

		// vars.totalRewards = vars.totalRewardsPerDay * ALICE_ALLOCATION_PERIOD;
		vars.totalAvailableRewards = vars.availableRewardsPerDay * ALICE_ALLOCATION_PERIOD;

		hevm.deal(address(minerActor), vars.totalAvailableRewards);

		for (uint256 i = 0; i <= ALICE_ALLOCATION_PERIOD; i++) {
			uint256 timeDelta = ONE_DAY * i;
			hevm.warp(genesisTimestamp + timeDelta);
			uint256 collateralRequirements;

			if (i == ALICE_ALLOCATION_PERIOD) {
				hevm.prank(alice);
				hevm.expectRevert(abi.encodeWithSignature("AllocationOverflow()"));
				staking.pledge(vars.dailyAllocation);
			} else {
				hevm.prank(alice);
				staking.pledge(vars.dailyAllocation);
				vars.totalAllocated = vars.totalAllocated + vars.dailyAllocation;

				collateralRequirements =
					(vars.totalAllocated * collateral.collateralRequirements(aliceOwnerId)) /
					BASIS_POINTS;

				if (i == 0) {
					vars.rewardsDelta = vars.totalAvailableRewards + vars.totalAllocated;
				} else {
					vars.rewardsDelta =
						vars.totalAvailableRewards +
						vars.totalAllocated -
						(vars.availableRewardsPerDay * (i - 1));
				}

				require(address(minerActor).balance == vars.rewardsDelta, "INVALID_MINER_ACTOR_BALANCE_AFTER_PLEDGE");
				require(
					collateral.getLockedCollateral(aliceOwnerId) == collateralRequirements,
					"INVALID_LOCKED_COLLATERAL"
				);
			}

			if (i == 50) {
				hevm.prank(alice);
				hevm.expectRevert(abi.encodeWithSignature("AllocationOverflow()"));
				staking.pledge(1); // trying to pledge 1 wei after pledging daily allocation
			}

			if (i > 0 && i < ALICE_ALLOCATION_PERIOD) {
				staking.withdrawRewards(aliceOwnerId, vars.availableRewardsPerDay);
				vars.rewardsDelta =
					vars.totalAvailableRewards +
					vars.totalAllocated -
					(vars.availableRewardsPerDay * (i));

				require(
					address(minerActor).balance == vars.rewardsDelta,
					"INVALID_MINER_ACTOR_BALANCE_AFTER_WITHDRAWAL"
				);
				require(staking.totalAssets() == totalAllocation + (vars.revenuePerDay * (i)), "INVALID_LSP_ASSETS");
				require(staking.totalFilPledged() == vars.totalAllocated, "INVALID_LSP_PLEDGED_ASSETS");
				require(
					collateral.getLockedCollateral(aliceOwnerId) == collateralRequirements,
					"INVALID_LOCKED_COLLATERAL"
				);
				require(
					wfil.balanceOf(address(staking)) ==
						totalAllocation - vars.totalAllocated + (vars.revenuePerDay * (i)),
					"INVALID_LSP_WFIL_BALANCE"
				);
			} else if (i == 0) {
				require(staking.totalAssets() == totalAllocation, "INVALID_LSP_ASSETS");
				require(staking.totalFilPledged() == vars.totalAllocated, "INVALID_LSP_PLEDGED_ASSETS");
			}
		}
	}

	function testSlashingEffectOnPledge(uint256 totalAllocation) public {
		hevm.assume(totalAllocation > ALICE_TOTAL_ALLOCATION && totalAllocation <= MAX_ALLOCATION);
		hevm.deal(staker, totalAllocation);

		TestExecutionLocalVars memory vars;

		vars.dailyAllocation = totalAllocation / ALICE_ALLOCATION_PERIOD;
		vars.hypotheticalRepayment = (totalAllocation * 15000) / BASIS_POINTS;

		hevm.prank(alice);
		registry.requestAllocationLimitUpdate(totalAllocation, vars.dailyAllocation);
		registry.updateAllocationLimit(aliceOwnerId, totalAllocation, vars.dailyAllocation, vars.hypotheticalRepayment);

		hevm.prank(staker);
		staking.stake{value: totalAllocation}();

		require(staking.balanceOf(address(staker)) == totalAllocation, "INVALID_STAKER_CLFIL_BALANCE");
		require(wfil.balanceOf(address(staker)) == 0, "INVALID_STAKER_WFIL_BALANCE");
		require(staker.balance == 0, "INVALID_STAKER_FIL_BALANCE");
		require(wfil.balanceOf(address(staking)) == totalAllocation, "INVALID_LSP_WFIL_BALANCE");
		require(staking.totalAssets() == totalAllocation, "INVALID_LSP_ASSETS");

		vars.targetCollateral = (totalAllocation * collateral.collateralRequirements(aliceOwnerId)) / BASIS_POINTS;
		hevm.deal(alice, vars.targetCollateral);

		hevm.prank(alice);
		collateral.deposit{value: vars.targetCollateral}(aliceOwnerId);

		require(alice.balance == 0, "INVALID_ALICE_BALANCE_AFTER_cDEPOSIT");

		vars.newSectors = calculateNumSectors(vars.dailyAllocation);

		vars.totalRewardsPerDay = calculateRewardsForSectors(vars.newSectors);
		vars.availableRewardsPerDay = (vars.totalRewardsPerDay * 2500) / BASIS_POINTS;
		vars.revenuePerDay = (vars.availableRewardsPerDay * profitShare) / BASIS_POINTS;
		vars.totalSectors = vars.newSectors * ALICE_ALLOCATION_PERIOD;
		vars.totalAvailableRewards = vars.availableRewardsPerDay * ALICE_ALLOCATION_PERIOD;

		hevm.deal(address(minerActor), vars.totalAvailableRewards);

		uint256 slashingDay = 50;
		uint256 slashingAllocation = (vars.dailyAllocation * slashingDay);
		uint256 slashingColReq = (slashingAllocation * collateral.collateralRequirements(aliceOwnerId)) / BASIS_POINTS;
		uint256 slashingAmt = (slashingColReq * 5000) / BASIS_POINTS;

		hevm.deal(alice, slashingAmt);

		for (uint256 i = 0; i < ALICE_ALLOCATION_PERIOD; i++) {
			uint256 timeDelta = ONE_DAY * i;
			hevm.warp(genesisTimestamp + timeDelta);

			hevm.prank(alice);
			staking.pledge(vars.dailyAllocation);
			vars.totalAllocated = vars.totalAllocated + vars.dailyAllocation;

			uint256 collateralRequirements = (vars.totalAllocated * collateral.collateralRequirements(aliceOwnerId)) /
				BASIS_POINTS;

			if (i == 0) {
				vars.rewardsDelta = vars.totalAvailableRewards + vars.totalAllocated;
			} else {
				vars.rewardsDelta =
					vars.totalAvailableRewards +
					vars.totalAllocated -
					(vars.availableRewardsPerDay * (i - 1));
			}

			require(address(minerActor).balance == vars.rewardsDelta, "INVALID_MINER_ACTOR_BALANCE_AFTER_PLEDGE");
			require(
				collateral.getLockedCollateral(aliceOwnerId) == collateralRequirements,
				"INVALID_LOCKED_COLLATERAL"
			);

			if (i == slashingDay) {
				collateral.reportSlashing(aliceOwnerId, slashingAmt);

				uint256 lockedCol = collateralRequirements > slashingAmt
					? collateralRequirements - slashingAmt
					: slashingAmt - collateralRequirements;

				require(collateral.getLockedCollateral(aliceOwnerId) == lockedCol, "INVALID_LOCKED_COLLATERAL");
				assertEq(collateral.slashings(aliceOwnerId), slashingAmt);
				assertBoolEq(collateral.activeSlashings(aliceOwnerId), true);

				// Try to pledge daily allocation after slashing
				hevm.prank(alice);
				hevm.expectRevert(abi.encodeWithSignature("ActiveSlashing()"));
				staking.pledge(vars.dailyAllocation);

				// Recover SP after recovering sectors
				collateral.reportRecovery(aliceOwnerId);
				assertBoolEq(collateral.activeSlashings(aliceOwnerId), false);

				hevm.prank(alice);
				collateral.deposit{value: slashingAmt}(aliceOwnerId);
			}

			if (i > 0) {
				staking.withdrawRewards(aliceOwnerId, vars.availableRewardsPerDay);
				vars.rewardsDelta =
					vars.totalAvailableRewards +
					vars.totalAllocated -
					(vars.availableRewardsPerDay * (i));

				if (i >= slashingDay) {
					uint256 slashingEffect = (vars.revenuePerDay * (i)) + slashingAmt;
					require(staking.totalAssets() == totalAllocation + slashingEffect, "INVALID_LSP_ASSETS");
					require(
						wfil.balanceOf(address(staking)) == totalAllocation - vars.totalAllocated + slashingEffect,
						"INVALID_LSP_WFIL_BALANCE"
					);
				} else {
					require(
						staking.totalAssets() == totalAllocation + (vars.revenuePerDay * (i)),
						"INVALID_LSP_ASSETS"
					);
					require(
						wfil.balanceOf(address(staking)) ==
							totalAllocation - vars.totalAllocated + (vars.revenuePerDay * (i)),
						"INVALID_LSP_WFIL_BALANCE"
					);
				}

				require(
					address(minerActor).balance == vars.rewardsDelta,
					"INVALID_MINER_ACTOR_BALANCE_AFTER_WITHDRAWAL"
				);
				require(staking.totalFilPledged() == vars.totalAllocated, "INVALID_LSP_PLEDGED_ASSETS");
				require(
					collateral.getLockedCollateral(aliceOwnerId) == collateralRequirements,
					"INVALID_LOCKED_COLLATERAL"
				);
			} else if (i == 0) {
				require(staking.totalAssets() == totalAllocation, "INVALID_LSP_ASSETS");
				require(staking.totalFilPledged() == vars.totalAllocated, "INVALID_LSP_PLEDGED_ASSETS");
			}
		}
	}

	function testIncreaseProfitShareAndCollateralRequirements(uint256 totalAllocation) public {
		hevm.assume(totalAllocation > ALICE_TOTAL_ALLOCATION && totalAllocation <= MAX_ALLOCATION);
		hevm.deal(staker, totalAllocation);

		TestExecutionLocalVars memory vars;

		vars.dailyAllocation = totalAllocation / ALICE_ALLOCATION_PERIOD;
		vars.hypotheticalRepayment = (totalAllocation * 15000) / BASIS_POINTS;

		hevm.prank(alice);
		registry.requestAllocationLimitUpdate(totalAllocation, vars.dailyAllocation);
		registry.updateAllocationLimit(aliceOwnerId, totalAllocation, vars.dailyAllocation, vars.hypotheticalRepayment);

		hevm.prank(staker);
		staking.stake{value: totalAllocation}();

		require(staking.balanceOf(address(staker)) == totalAllocation, "INVALID_STAKER_CLFIL_BALANCE");
		require(wfil.balanceOf(address(staker)) == 0, "INVALID_STAKER_WFIL_BALANCE");
		require(staker.balance == 0, "INVALID_STAKER_FIL_BALANCE");
		require(wfil.balanceOf(address(staking)) == totalAllocation, "INVALID_LSP_WFIL_BALANCE");
		require(staking.totalAssets() == totalAllocation, "INVALID_LSP_ASSETS");

		vars.targetCollateral = (totalAllocation * collateral.collateralRequirements(aliceOwnerId)) / BASIS_POINTS;
		hevm.deal(alice, vars.targetCollateral);

		hevm.prank(alice);
		collateral.deposit{value: vars.targetCollateral}(aliceOwnerId);

		require(alice.balance == 0, "INVALID_ALICE_BALANCE_AFTER_cDEPOSIT");

		vars.newSectors = calculateNumSectors(vars.dailyAllocation);

		vars.totalRewardsPerDay = calculateRewardsForSectors(vars.newSectors);
		vars.availableRewardsPerDay = (vars.totalRewardsPerDay * 2500) / BASIS_POINTS;
		vars.revenuePerDay = (vars.availableRewardsPerDay * profitShare) / BASIS_POINTS;
		vars.totalSectors = vars.newSectors * ALICE_ALLOCATION_PERIOD;
		vars.totalAvailableRewards = vars.availableRewardsPerDay * ALICE_ALLOCATION_PERIOD;

		hevm.deal(address(minerActor), vars.totalAvailableRewards);

		uint256 profitShareUpdate = 4000;
		uint256 collateralRequirementsUpdate = 2500;
		uint256 updatedRevenue = (vars.availableRewardsPerDay * profitShareUpdate) / BASIS_POINTS;

		for (uint256 i = 0; i < ALICE_ALLOCATION_PERIOD; i++) {
			uint256 timeDelta = ONE_DAY * i;

			hevm.warp(genesisTimestamp + timeDelta);

			hevm.prank(alice);
			staking.pledge(vars.dailyAllocation);
			vars.totalAllocated = vars.totalAllocated + vars.dailyAllocation;

			uint256 collateralRequirements = (vars.totalAllocated * collateral.collateralRequirements(aliceOwnerId)) /
				BASIS_POINTS;

			if (i == 0) {
				vars.rewardsDelta = vars.totalAvailableRewards + vars.totalAllocated;
			} else {
				vars.rewardsDelta =
					vars.totalAvailableRewards +
					vars.totalAllocated -
					(vars.availableRewardsPerDay * (i - 1));
			}

			require(address(minerActor).balance == vars.rewardsDelta, "INVALID_MINER_ACTOR_BALANCE_AFTER_PLEDGE");
			require(
				collateral.getLockedCollateral(aliceOwnerId) == collateralRequirements,
				"INVALID_LOCKED_COLLATERAL"
			);

			if (i == 70) {
				controller.updateProfitShare(aliceOwnerId, profitShareUpdate, address(staking));
				collateral.updateCollateralRequirements(aliceOwnerId, collateralRequirementsUpdate);
			}

			if (i > 0) {
				staking.withdrawRewards(aliceOwnerId, vars.availableRewardsPerDay);
				vars.rewardsDelta =
					vars.totalAvailableRewards +
					vars.totalAllocated -
					(vars.availableRewardsPerDay * (i));

				if (i >= 70) {
					uint256 accuredRevenue = vars.revenuePerDay * 69;
					collateralRequirements = (vars.totalAllocated * collateralRequirementsUpdate) / BASIS_POINTS;

					require(
						staking.totalAssets() == totalAllocation + accuredRevenue + (updatedRevenue * (i - 69)),
						"INVALID_LSP_ASSETS"
					);
					require(
						collateral.getLockedCollateral(aliceOwnerId) == collateralRequirements,
						"INVALID_LOCKED_COLLATERAL"
					);
					require(
						wfil.balanceOf(address(staking)) ==
							totalAllocation - vars.totalAllocated + accuredRevenue + (updatedRevenue * (i - 69)),
						"INVALID_LSP_WFIL_BALANCE"
					);
				} else {
					require(
						staking.totalAssets() == totalAllocation + (vars.revenuePerDay * (i)),
						"INVALID_LSP_ASSETS"
					);
					require(
						collateral.getLockedCollateral(aliceOwnerId) == collateralRequirements,
						"INVALID_LOCKED_COLLATERAL"
					);
					require(
						wfil.balanceOf(address(staking)) ==
							totalAllocation - vars.totalAllocated + (vars.revenuePerDay * (i)),
						"INVALID_LSP_WFIL_BALANCE"
					);
				}

				require(
					address(minerActor).balance == vars.rewardsDelta,
					"INVALID_MINER_ACTOR_BALANCE_AFTER_WITHDRAWAL"
				);
				require(staking.totalFilPledged() == vars.totalAllocated, "INVALID_LSP_PLEDGED_ASSETS");
			} else {
				require(staking.totalAssets() == totalAllocation, "INVALID_LSP_ASSETS");
				require(staking.totalFilPledged() == vars.totalAllocated, "INVALID_LSP_PLEDGED_ASSETS");
			}
		}
	}

	struct RestakingLocalVars {
		uint256 adminShare;
		uint256 protocolShare;
		address restakingAddr;
		uint256 restakingRatio;
		uint256 restakingAmt;
		uint256 clFILShares;
		uint256 totalclFILShares;
		uint256 clFILTotalSupply;
		uint256 totalStakingAssets;
	}

	function testRestakingEffect(uint256 totalAllocation) public {
		hevm.assume(totalAllocation > ALICE_TOTAL_ALLOCATION && totalAllocation <= MAX_ALLOCATION);
		hevm.deal(staker, totalAllocation);

		TestExecutionLocalVars memory vars;
		RestakingLocalVars memory rVars;

		vars.dailyAllocation = totalAllocation / ALICE_ALLOCATION_PERIOD;
		vars.hypotheticalRepayment = (totalAllocation * 15000) / BASIS_POINTS;

		hevm.prank(alice);
		registry.requestAllocationLimitUpdate(totalAllocation, vars.dailyAllocation);
		registry.updateAllocationLimit(aliceOwnerId, totalAllocation, vars.dailyAllocation, vars.hypotheticalRepayment);

		hevm.prank(staker);
		staking.stake{value: totalAllocation}();

		require(staking.balanceOf(address(staker)) == totalAllocation, "INVALID_STAKER_CLFIL_BALANCE");
		require(wfil.balanceOf(address(staker)) == 0, "INVALID_STAKER_WFIL_BALANCE");
		require(staker.balance == 0, "INVALID_STAKER_FIL_BALANCE");
		require(wfil.balanceOf(address(staking)) == totalAllocation, "INVALID_LSP_WFIL_BALANCE");
		require(staking.totalAssets() == totalAllocation, "INVALID_LSP_ASSETS");

		vars.targetCollateral = (totalAllocation * collateral.collateralRequirements(aliceOwnerId)) / BASIS_POINTS;
		hevm.deal(alice, vars.targetCollateral);

		hevm.prank(alice);
		collateral.deposit{value: vars.targetCollateral}(aliceOwnerId);

		require(alice.balance == 0, "INVALID_ALICE_BALANCE_AFTER_cDEPOSIT");

		vars.newSectors = calculateNumSectors(vars.dailyAllocation);

		vars.totalRewardsPerDay = calculateRewardsForSectors(vars.newSectors);
		vars.availableRewardsPerDay = (vars.totalRewardsPerDay * 2500) / BASIS_POINTS;
		vars.revenuePerDay = (vars.availableRewardsPerDay * profitShare) / BASIS_POINTS;
		vars.totalSectors = vars.newSectors * ALICE_ALLOCATION_PERIOD;
		vars.totalAvailableRewards = vars.availableRewardsPerDay * ALICE_ALLOCATION_PERIOD;

		hevm.deal(address(minerActor), vars.totalAvailableRewards);

		rVars.adminShare = (vars.availableRewardsPerDay * adminFee) / BASIS_POINTS;
		rVars.protocolShare = vars.revenuePerDay + rVars.adminShare;
		rVars.restakingAddr = address(0x123777);
		rVars.restakingRatio = 2500;
		rVars.restakingAmt =
			((vars.availableRewardsPerDay - rVars.protocolShare) * rVars.restakingRatio) /
			BASIS_POINTS;
		rVars.clFILShares;
		rVars.totalclFILShares;

		hevm.prank(alice);
		registry.setRestaking(rVars.restakingRatio, rVars.restakingAddr);

		for (uint256 i = 0; i < ALICE_ALLOCATION_PERIOD; i++) {
			uint256 timeDelta = ONE_DAY * i;
			hevm.warp(genesisTimestamp + timeDelta);

			hevm.prank(alice);
			staking.pledge(vars.dailyAllocation);
			vars.totalAllocated = vars.totalAllocated + vars.dailyAllocation;

			uint256 collateralRequirements = (vars.totalAllocated * collateral.collateralRequirements(aliceOwnerId)) /
				BASIS_POINTS;

			if (i == 0) {
				vars.rewardsDelta = vars.totalAvailableRewards + vars.totalAllocated;
			} else {
				vars.rewardsDelta =
					vars.totalAvailableRewards +
					vars.totalAllocated -
					(vars.availableRewardsPerDay * (i - 1));
			}

			require(address(minerActor).balance == vars.rewardsDelta, "INVALID_MINER_ACTOR_BALANCE_AFTER_PLEDGE");
			require(
				collateral.getLockedCollateral(aliceOwnerId) == collateralRequirements,
				"INVALID_LOCKED_COLLATERAL"
			);

			if (i > 0) {
				rVars.clFILTotalSupply = staking.totalSupply();
				rVars.totalStakingAssets = totalAllocation + (rVars.restakingAmt * i) + (vars.revenuePerDay * i);

				rVars.clFILShares = rVars.restakingAmt.mulDivDown(rVars.clFILTotalSupply, rVars.totalStakingAssets);
				rVars.totalclFILShares += rVars.clFILShares;

				staking.withdrawRewards(aliceOwnerId, vars.availableRewardsPerDay);
				vars.rewardsDelta =
					vars.totalAvailableRewards +
					vars.totalAllocated -
					(vars.availableRewardsPerDay * (i));

				require(staking.balanceOf(rVars.restakingAddr) == rVars.totalclFILShares, "INVALID_clFIL_SHARES");

				require(
					address(minerActor).balance == vars.rewardsDelta,
					"INVALID_MINER_ACTOR_BALANCE_AFTER_WITHDRAWAL"
				);
				require(staking.totalAssets() == rVars.totalStakingAssets, "INVALID_LSP_ASSETS");
				require(staking.totalFilPledged() == vars.totalAllocated, "INVALID_LSP_PLEDGED_ASSETS");
				require(
					collateral.getLockedCollateral(aliceOwnerId) == collateralRequirements,
					"INVALID_LOCKED_COLLATERAL"
				);
				require(
					wfil.balanceOf(address(staking)) ==
						totalAllocation - vars.totalAllocated + (vars.revenuePerDay * i) + (rVars.restakingAmt * i),
					"INVALID_LSP_WFIL_BALANCE"
				);
			} else {
				require(staking.totalAssets() == totalAllocation, "INVALID_LSP_ASSETS");
				require(staking.totalFilPledged() == vars.totalAllocated, "INVALID_LSP_PLEDGED_ASSETS");
			}
		}
	}

	function testUnUsedPledge(uint256 totalAllocation) public {
		hevm.assume(totalAllocation > ALICE_TOTAL_ALLOCATION && totalAllocation <= MAX_ALLOCATION);
		hevm.deal(staker, totalAllocation);

		TestExecutionLocalVars memory vars;

		vars.dailyAllocation = totalAllocation / ALICE_ALLOCATION_PERIOD;
		vars.hypotheticalRepayment = (totalAllocation * 15000) / BASIS_POINTS;

		hevm.prank(alice);
		registry.requestAllocationLimitUpdate(totalAllocation, vars.dailyAllocation);
		registry.updateAllocationLimit(aliceOwnerId, totalAllocation, vars.dailyAllocation, vars.hypotheticalRepayment);

		hevm.prank(staker);
		staking.stake{value: totalAllocation}();

		require(staking.balanceOf(address(staker)) == totalAllocation, "INVALID_STAKER_CLFIL_BALANCE");
		require(wfil.balanceOf(address(staker)) == 0, "INVALID_STAKER_WFIL_BALANCE");
		require(staker.balance == 0, "INVALID_STAKER_FIL_BALANCE");
		require(wfil.balanceOf(address(staking)) == totalAllocation, "INVALID_LSP_WFIL_BALANCE");
		require(staking.totalAssets() == totalAllocation, "INVALID_LSP_ASSETS");

		vars.targetCollateral = (totalAllocation * collateral.collateralRequirements(aliceOwnerId)) / BASIS_POINTS;
		hevm.deal(alice, vars.targetCollateral);

		hevm.prank(alice);
		collateral.deposit{value: vars.targetCollateral}(aliceOwnerId);

		require(alice.balance == 0, "INVALID_ALICE_BALANCE_AFTER_cDEPOSIT");

		vars.newSectors = calculateNumSectors(vars.dailyAllocation) / 2;

		vars.totalRewardsPerDay = calculateRewardsForSectors(vars.newSectors);
		vars.availableRewardsPerDay = (vars.totalRewardsPerDay * 2500) / BASIS_POINTS;
		vars.revenuePerDay = (vars.availableRewardsPerDay * profitShare) / BASIS_POINTS;
		vars.totalSectors = vars.newSectors * ALICE_ALLOCATION_PERIOD;
		vars.totalAvailableRewards = vars.availableRewardsPerDay * ALICE_ALLOCATION_PERIOD;

		uint256 minerActorInitialBalance = totalAllocation / 2 + vars.totalAvailableRewards;
		hevm.deal(address(minerActor), minerActorInitialBalance);

		uint256 unPledged = vars.dailyAllocation / 2;
		uint256 pledgeDelta;

		for (uint256 i = 0; i < ALICE_ALLOCATION_PERIOD; i++) {
			uint256 timeDelta = ONE_DAY * i;
			hevm.warp(genesisTimestamp + timeDelta);

			hevm.prank(alice);
			staking.pledge(vars.dailyAllocation);
			vars.totalAllocated = vars.totalAllocated + vars.dailyAllocation;

			uint256 collateralRequirements;

			if (i == 0) {
				collateralRequirements =
					((vars.totalAllocated) * collateral.collateralRequirements(aliceOwnerId)) /
					BASIS_POINTS;
				vars.rewardsDelta = vars.totalAllocated + (totalAllocation / 2) + vars.totalAvailableRewards;
			} else {
				collateralRequirements =
					((vars.totalAllocated - (unPledged * (i - 1))) * collateral.collateralRequirements(aliceOwnerId)) /
					BASIS_POINTS;
				pledgeDelta = (totalAllocation / 2) - (unPledged * (i - 1));
				vars.rewardsDelta =
					vars.totalAllocated +
					pledgeDelta +
					vars.totalAvailableRewards -
					(vars.availableRewardsPerDay * (i - 1));
			}

			require(address(minerActor).balance == vars.rewardsDelta, "INVALID_MINER_ACTOR_BALANCE_AFTER_PLEDGE");
			require(
				collateral.getLockedCollateral(aliceOwnerId) == collateralRequirements,
				"INVALID_LOCKED_COLLATERAL"
			);

			if (i > 0) {
				staking.withdrawRewards(aliceOwnerId, vars.availableRewardsPerDay);
				pledgeDelta = (totalAllocation / 2) - (unPledged * (i));
				vars.rewardsDelta =
					vars.totalAllocated +
					pledgeDelta +
					vars.totalAvailableRewards -
					(vars.availableRewardsPerDay * (i));

				staking.withdrawPledge(aliceOwnerId, unPledged);

				collateralRequirements =
					((vars.totalAllocated - (unPledged * (i))) * collateral.collateralRequirements(aliceOwnerId)) /
					BASIS_POINTS;

				require(
					address(minerActor).balance == vars.rewardsDelta,
					"INVALID_MINER_ACTOR_BALANCE_AFTER_WITHDRAWAL"
				);
				require(staking.totalAssets() == totalAllocation + (vars.revenuePerDay * (i)), "INVALID_LSP_ASSETS_2");
				require(
					staking.totalFilPledged() == vars.totalAllocated - unPledged * (i),
					"INVALID_LSP_PLEDGED_ASSETS"
				);
				require(
					collateral.getLockedCollateral(aliceOwnerId) == collateralRequirements,
					"INVALID_LOCKED_COLLATERAL"
				);
				require(
					wfil.balanceOf(address(staking)) ==
						totalAllocation - vars.totalAllocated + (vars.revenuePerDay * (i)) + (unPledged * (i)),
					"INVALID_LSP_WFIL_BALANCE"
				);
			} else {
				require(staking.totalAssets() == totalAllocation, "INVALID_LSP_ASSETS");
				require(staking.totalFilPledged() == vars.totalAllocated, "INVALID_LSP_PLEDGED_ASSETS");
			}
		}
	}

	function calculateNumSectors(uint256 allocation) internal pure returns (uint256) {
		return allocation / initialPledge;
	}

	function calculateRewardsForSectors(uint256 numSectors) internal pure returns (uint256) {
		uint256 rewardsPerSector = rewardsPerTiB / 32;

		return numSectors * rewardsPerSector;
	}
}
