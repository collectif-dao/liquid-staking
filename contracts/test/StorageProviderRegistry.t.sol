// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {WFIL} from "fevmate/token/WFIL.sol";
import {IWFIL} from "../libraries/tokens/IWFIL.sol";
import {BigIntsClient} from "../libraries/BigInts.sol";

import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";
import {Buffer} from "@ensdomains/buffer/contracts/Buffer.sol";
import {MinerTypes} from "filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import {BigInts} from "filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import {PrecompilesAPI} from "filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";

import {Resolver} from "../Resolver.sol";
import {BeneficiaryManagerMock} from "./mocks/BeneficiaryManagerMock.sol";
import {StorageProviderRegistryMock, StorageProviderRegistryCallerMock} from "./mocks/StorageProviderRegistryMock.sol";
import {StorageProviderCollateralMock} from "./mocks/StorageProviderCollateralMock.sol";
import {MinerMockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {LiquidStakingMock} from "./mocks/LiquidStakingMock.sol";
import {LiquidStakingController} from "../LiquidStakingController.sol";
import {RewardCollectorMock} from "./mocks/RewardCollectorMock.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {MinerActorMock} from "./mocks/MinerActorMock.sol";

import {ERC1967Proxy} from "@oz/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StorageProviderRegistryTest is DSTestPlus {
	StorageProviderRegistryMock public registry;
	StorageProviderRegistryCallerMock public callerMock;
	StorageProviderCollateralMock public collateral;
	MinerMockAPI private minerMockAPI;
	BigIntsClient private bigIntsLib;
	Resolver public resolver;
	LiquidStakingController public controller;
	BeneficiaryManagerMock public beneficiaryManager;
	RewardCollectorMock private rewardCollector;
	MinerActorMock public minerActor;

	LiquidStakingMock public staking;
	IWFIL public wfil;

	bytes public owner;
	uint64 public ownerId = 1508;
	uint64 private oldMinerId = 1648;

	address private proxyAdmin = address(0x777);
	address private aliceOwnerAddr = address(0x12341214212);
	uint256 private adminFee = 1000;
	uint256 private profitShare = 2000;
	uint64 public aliceOwnerId = 1508;
	uint256 maxRestaking = 10000;

	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant MIN_TIME_PERIOD = 90 days;
	uint256 private constant MAX_TIME_PERIOD = 360 days;
	uint256 private constant SAMPLE_DAILY_ALLOCATION = MAX_ALLOCATION / 30;

	function setUp() public {
		Buffer.buffer memory ownerBytes = Leb128.encodeUnsignedLeb128FromUInt64(ownerId);
		owner = ownerBytes.buf;

		wfil = IWFIL(address(new WFIL(msg.sender)));
		minerMockAPI = new MinerMockAPI(owner);
		minerActor = new MinerActorMock();

		bigIntsLib = new BigIntsClient();

		Resolver resolverImpl = new Resolver();
		ERC1967Proxy resolverProxy = new ERC1967Proxy(address(resolverImpl), "");
		resolver = Resolver(address(resolverProxy));
		resolver.initialize();

		BeneficiaryManagerMock bManagerImpl = new BeneficiaryManagerMock();
		ERC1967Proxy bManagerProxy = new ERC1967Proxy(address(bManagerImpl), "");
		beneficiaryManager = BeneficiaryManagerMock(address(bManagerProxy));
		beneficiaryManager.initialize(address(minerMockAPI), ownerId, address(resolver));

		RewardCollectorMock rCollectorImpl = new RewardCollectorMock();
		ERC1967Proxy rCollectorProxy = new ERC1967Proxy(address(rCollectorImpl), "");
		rewardCollector = RewardCollectorMock(payable(rCollectorProxy));
		rewardCollector.initialize(address(minerActor), aliceOwnerId, aliceOwnerAddr, address(wfil), address(resolver));

		LiquidStakingController controllerImpl = new LiquidStakingController();
		ERC1967Proxy controllerProxy = new ERC1967Proxy(address(controllerImpl), "");
		controller = LiquidStakingController(address(controllerProxy));
		controller.initialize(adminFee, profitShare, address(rewardCollector), address(resolver));

		// hevm.startPrank(proxyAdmin);
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
		registry.initialize(address(minerMockAPI), ownerId, MAX_ALLOCATION, address(resolver));

		StorageProviderCollateralMock collateralImpl = new StorageProviderCollateralMock();
		ERC1967Proxy collateralProxy = new ERC1967Proxy(address(collateralImpl), "");
		collateral = StorageProviderCollateralMock(payable(collateralProxy));
		collateral.initialize(wfil, address(resolver), 1500);

		resolver.setLiquidStakingControllerAddress(address(controller));
		resolver.setBeneficiaryManagerAddress(address(beneficiaryManager));
		resolver.setRegistryAddress(address(registry));
		resolver.setCollateralAddress(address(collateral));
		resolver.setLiquidStakingAddress(address(staking));
		resolver.setRewardCollectorAddress(address(rewardCollector));
		registry.registerPool(address(staking));

		callerMock = new StorageProviderRegistryCallerMock(address(registry));
		// hevm.stopPrank();
	}

	function testRegister(uint64 minerId, uint256 allocation, uint256 dailyAllocation) public {
		uint256 maxDailyAllocation = allocation / 30;
		hevm.assume(
			minerId > 1 &&
				minerId < 2115248121211227543 &&
				allocation > 0 &&
				allocation <= MAX_ALLOCATION &&
				dailyAllocation <= maxDailyAllocation &&
				dailyAllocation > 0
		);

		registry.register(minerId, address(staking), allocation, dailyAllocation);

		(bool isActive, address targetPool, uint64 minerActorId, int64 lastEpoch) = registry.getStorageProvider(
			ownerId
		);

		(
			uint256 allocationLimit,
			uint256 repayment,
			uint256 usedAllocation,
			uint256 dAllocation,
			uint256 accruedRewards,
			uint256 lockedRewards
		) = registry.allocations(ownerId);

		assertBoolEq(isActive, false);
		assertEq(targetPool, address(staking));
		assertEq(minerId, minerActorId);
		assertEq(allocationLimit, allocation);
		assertEq(repayment, 0);
		assertEq(usedAllocation, 0);
		assertEq(dAllocation, dailyAllocation);
		assertEq(accruedRewards, 0);
		assertEq(lockedRewards, 0);
		assertEq(lastEpoch, 0);
		// assertEq(restakingRatio, 0);
		assertEq(registry.sectorSizes(ownerId), 34359738368);
	}

	struct TestOnboardSPLocalVars {
		bool isActive;
		address targetPool;
		uint64 minerActorId;
		int64 lastEpoch;
		uint256 allocationLimit;
		uint256 repayment;
		uint256 usedAllocation;
		uint256 dailyAllocation;
		uint256 accruedRewards;
		uint256 lockedRewards;
	}

	function testOnboardStorageProvider(
		uint64 _minerId,
		uint256 _allocationLimit,
		uint256 _dailyAllocation,
		uint256 _repayment,
		int64 _lastEpoch
	) public {
		uint256 maxDailyAllocation = _allocationLimit / 30;
		hevm.assume(
			_minerId > 1 &&
				_minerId < 2115248121211227543 &&
				_repayment > _allocationLimit &&
				_allocationLimit < MAX_ALLOCATION &&
				_lastEpoch > 0 &&
				_dailyAllocation <= maxDailyAllocation &&
				_dailyAllocation > 0
		);

		registry.register(_minerId, address(staking), MAX_ALLOCATION, _dailyAllocation);
		registry.onboardStorageProvider(_minerId, _allocationLimit, _dailyAllocation, _repayment, _lastEpoch);

		TestOnboardSPLocalVars memory vars;

		(vars.isActive, vars.targetPool, vars.minerActorId, vars.lastEpoch) = registry.getStorageProvider(ownerId);

		(
			vars.allocationLimit,
			vars.repayment,
			vars.usedAllocation,
			vars.dailyAllocation,
			vars.accruedRewards,
			vars.lockedRewards
		) = registry.allocations(ownerId);

		assertBoolEq(vars.isActive, false);
		assertEq(vars.targetPool, address(staking));
		assertEq(vars.minerActorId, _minerId);
		assertEq(vars.allocationLimit, _allocationLimit);
		assertEq(vars.repayment, _repayment);
		assertEq(vars.usedAllocation, 0);
		assertEq(vars.dailyAllocation, _dailyAllocation);
		assertEq(vars.accruedRewards, 0);
		assertEq(vars.lockedRewards, 0);
		assertEq(vars.lastEpoch, _lastEpoch);
	}

	function testOnboardStorageProviderReverts(uint64 _minerId, uint256 _repayment, int64 _lastEpoch) public {
		hevm.assume(
			_minerId > 1 && _minerId < 2115248121211227543 && _repayment > (MAX_ALLOCATION * 2) && _lastEpoch > 0
		);

		registry.register(_minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		hevm.expectRevert(abi.encodeWithSignature("InvalidAllocation()"));
		registry.onboardStorageProvider(_minerId, MAX_ALLOCATION * 2, SAMPLE_DAILY_ALLOCATION, _repayment, _lastEpoch);
	}

	function testOnboardStorageProviderRevertsWithIncorrectRepayment(
		uint64 _minerId,
		uint256 _repayment,
		int64 _lastEpoch
	) public {
		hevm.assume(_minerId > 1 && _minerId < 2115248121211227543 && _repayment < MAX_ALLOCATION && _lastEpoch > 0);

		registry.register(_minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		hevm.expectRevert(abi.encodeWithSignature("InvalidRepayment()"));
		registry.onboardStorageProvider(_minerId, MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION, _repayment, _lastEpoch);
	}

	function testAcceptBeneficiaryAddress(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);
		uint256 repayment = MAX_ALLOCATION + 10;

		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION, repayment, lastEpoch);
		assertBoolEq(registry.isActiveProvider(ownerId), false);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		assertBoolEq(registry.isActiveProvider(ownerId), true);

		MinerTypes.GetBeneficiaryReturn memory beneficiary = minerMockAPI.getBeneficiary();
		(uint256 quota, bool err) = BigInts.toUint256(beneficiary.active.term.quota);
		require(!err, "INVALID_BIG_INT");
		require(quota == repayment, "INVALID_BENEFICIARY_QUOTA");
	}

	function testAcceptBeneficiaryAddressReverts(uint64 minerId, address provider, int64 lastEpoch) public {
		hevm.assume(
			provider != address(0) &&
				provider != address(this) &&
				lastEpoch > 0 &&
				minerId > 1 &&
				minerId < 2115248121211227543
		);

		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();

		hevm.prank(provider);
		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		registry.acceptBeneficiaryAddress(ownerId);

		assertBoolEq(registry.isActiveProvider(ownerId), false);
	}

	function testDeactivateStorageProvider(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);

		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);
		assertBoolEq(registry.isActiveProvider(ownerId), true);

		registry.deactivateStorageProvider(ownerId);
		assertBoolEq(registry.isActiveProvider(ownerId), false);
	}

	function testDeactivateStorageProviderReverts(uint64 minerId, address provider, int64 lastEpoch) public {
		hevm.assume(
			provider != address(0) &&
				provider != address(this) &&
				lastEpoch > 0 &&
				minerId > 1 &&
				minerId < 2115248121211227543
		);

		hevm.prank(provider);
		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);

		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		hevm.prank(provider);
		beneficiaryManager.changeBeneficiaryAddress();

		registry.acceptBeneficiaryAddress(ownerId);

		hevm.prank(provider);
		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		registry.deactivateStorageProvider(ownerId);
	}

	function testSetMinerAddress(uint64 newMinerId, int64 lastEpoch) public {
		hevm.assume(newMinerId > 1 && newMinerId < 2115248121211227543 && newMinerId != oldMinerId && lastEpoch > 0);

		registry.register(oldMinerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			newMinerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		registry.setMinerAddress(ownerId, newMinerId);
		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);
		assertEq(minerId, newMinerId);
	}

	function testSetMinerAddressReverts(uint64 newMinerId) public {
		hevm.assume(newMinerId > 1 && newMinerId < 2115248121211227543 && newMinerId != oldMinerId);

		registry.register(oldMinerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);

		hevm.expectRevert(abi.encodeWithSignature("InactiveSP()"));
		registry.setMinerAddress(ownerId, newMinerId);
	}

	function testSetMinerAddressRevertsWithSameMinerId(int64 lastEpoch) public {
		hevm.assume(lastEpoch > 0);
		uint64 newMinerId = oldMinerId;

		registry.register(oldMinerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			oldMinerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
		registry.setMinerAddress(ownerId, newMinerId);
	}

	function testRequestAllocationLimitUpdate(
		uint64 minerId,
		uint256 allocation,
		uint256 dailyAllocation,
		int64 lastEpoch
	) public {
		uint256 maxDailyAlloc = allocation / 30;
		hevm.assume(
			allocation < MAX_ALLOCATION &&
				allocation != MAX_ALLOCATION &&
				allocation > 0 &&
				minerId > 1 &&
				minerId < 2115248121211227543 &&
				lastEpoch > 0 &&
				dailyAllocation <= maxDailyAlloc &&
				dailyAllocation > 0
		);
		registry.register(minerId, address(staking), MAX_ALLOCATION, dailyAllocation);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, dailyAllocation, MAX_ALLOCATION + 10, lastEpoch);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		registry.requestAllocationLimitUpdate(allocation, dailyAllocation);
	}

	function testRequestAllocationLimitUpdateReverts(uint64 minerId, uint256 allocation, int64 lastEpoch) public {
		hevm.assume(
			allocation < MAX_ALLOCATION &&
				allocation != MAX_ALLOCATION &&
				allocation > SAMPLE_DAILY_ALLOCATION &&
				minerId > 1 &&
				minerId < 2115248121211227543 &&
				lastEpoch > 0
		);
		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();

		hevm.expectRevert(abi.encodeWithSignature("InactiveSP()"));
		registry.requestAllocationLimitUpdate(allocation, SAMPLE_DAILY_ALLOCATION);
	}

	function testRequestAllocationLimitUpdateRevertsWithSameAllocationLimit(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);
		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
		registry.requestAllocationLimitUpdate(MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
	}

	function testRequestAllocationLimitUpdateRevertsWithOverflow(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);
		uint256 newAllocation = MAX_ALLOCATION + 1;
		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		hevm.expectRevert(abi.encodeWithSignature("InvalidAllocation()"));
		registry.requestAllocationLimitUpdate(newAllocation, SAMPLE_DAILY_ALLOCATION);
	}

	function testUpdateAllocationLimit(uint64 minerId, uint256 allocation, int64 lastEpoch) public {
		hevm.assume(
			allocation < MAX_ALLOCATION &&
				allocation != MAX_ALLOCATION &&
				allocation > SAMPLE_DAILY_ALLOCATION &&
				minerId > 1 &&
				minerId < 2115248121211227543 &&
				lastEpoch > 0
		);
		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		registry.requestAllocationLimitUpdate(allocation, SAMPLE_DAILY_ALLOCATION); // TODO: add alice prank here
		registry.updateAllocationLimit(ownerId, allocation, SAMPLE_DAILY_ALLOCATION, allocation + 10);
	}

	function testUpdateAllocationLimitReverts(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);
		uint256 newAllocation = MAX_ALLOCATION - 10000;
		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		registry.requestAllocationLimitUpdate(newAllocation, SAMPLE_DAILY_ALLOCATION); // TODO: add alice prank here

		hevm.expectRevert(abi.encodeWithSignature("InvalidAllocation()"));
		registry.updateAllocationLimit(ownerId, MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION, MAX_ALLOCATION + 10);
	}

	function testSetRestaking(
		uint64 minerId,
		uint256 restakingRatio,
		address restakingAddress,
		int64 lastEpoch
	) public {
		hevm.assume(
			minerId > 1 &&
				minerId < 2115248121211227543 &&
				restakingRatio > 0 &&
				restakingRatio <= maxRestaking &&
				restakingAddress != address(0) &&
				lastEpoch > 0
		);
		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		registry.setRestaking(restakingRatio, restakingAddress);

		(uint256 ratio, address rAddr) = registry.restakings(ownerId);
		assertEq(ratio, restakingRatio);
		assertEq(rAddr, restakingAddress);
	}

	function testSetRestakingReverts(uint64 minerId, uint256 restakingRatio, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0 && restakingRatio > maxRestaking);
		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
		registry.setRestaking(restakingRatio, address(0x412412));

		hevm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
		registry.setRestaking(1500, address(0));

		(uint256 ratio, address rAddr) = registry.restakings(ownerId);
		assertEq(ratio, 0);
		assertEq(rAddr, address(0));
	}

	function testRegisterPool(address pool) public {
		hevm.assume(
			pool != address(0) && pool != address(staking) && pool != address(callerMock) && pool != address(registry)
		);

		registry.registerPool(pool);
		assertBoolEq(registry.isActivePool(pool), true);
	}

	function testRegisterPoolReverts(address pool) public {
		hevm.assume(pool != address(0) && pool != address(staking) && pool != address(registry));

		hevm.prank(aliceOwnerAddr);
		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		registry.registerPool(pool);
		assertBoolEq(registry.isActivePool(pool), false);

		hevm.expectRevert(abi.encodeWithSignature("ActivePool()"));
		registry.registerPool(address(staking));
		assertBoolEq(registry.isActivePool(address(staking)), true);
	}

	function testIncreaseRewards(uint64 minerId, uint256 _accruedRewards, int64 lastEpoch) public {
		hevm.assume(_accruedRewards > 0 && lastEpoch > 0 && minerId > 1 && minerId < 2115248121211227543);
		registry.registerPool(address(callerMock));

		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		resolver.setRewardCollectorAddress(address(callerMock)); // Test case only
		callerMock.increaseRewards(ownerId, _accruedRewards);

		(, , , , uint256 accruedRewards, ) = registry.allocations(ownerId);
		assertEq(accruedRewards, _accruedRewards);
	}

	function testIncreaseRewardsReverts(uint64 minerId, uint256 _accruedRewards, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && _accruedRewards > 0 && lastEpoch > 0);

		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		callerMock.increaseRewards(ownerId, _accruedRewards);

		(, , , , uint256 accruedRewards, ) = registry.allocations(ownerId);
		assertEq(accruedRewards, 0);
	}

	function testIncreaseUsedAllocation(uint64 minerId, uint256 allocated, int64 lastEpoch) public {
		hevm.assume(
			minerId > 1 &&
				minerId < 2115248121211227543 &&
				lastEpoch > 0 &&
				allocated > 0 &&
				allocated <= SAMPLE_DAILY_ALLOCATION
		);

		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		resolver.setCollateralAddress(address(callerMock)); // Test case only
		callerMock.increaseUsedAllocation(ownerId, allocated, block.timestamp);

		(, , uint256 usedAllocation, , , ) = registry.allocations(ownerId);
		assertEq(usedAllocation, allocated);
	}

	function testIncreaseUsedAllocationReverts(uint64 minerId, uint256 allocated, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0 && allocated > 0);

		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		callerMock.increaseUsedAllocation(ownerId, allocated, block.timestamp);

		(, , uint256 usedAllocation, , , ) = registry.allocations(ownerId);
		assertEq(usedAllocation, 0);
	}

	function testIncreasePledgeRepayment(uint64 minerId, uint256 _repaidPledge, int64 lastEpoch) public {
		hevm.assume(
			_repaidPledge > 0 &&
				_repaidPledge <= SAMPLE_DAILY_ALLOCATION &&
				lastEpoch > 0 &&
				minerId > 1 &&
				minerId < 2115248121211227543
		);
		registry.registerPool(address(callerMock));

		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		resolver.setCollateralAddress(address(callerMock)); // Test case only
		callerMock.increaseUsedAllocation(ownerId, _repaidPledge, block.timestamp);

		resolver.setRewardCollectorAddress(address(callerMock)); // Test case only
		callerMock.increasePledgeRepayment(ownerId, _repaidPledge);

		(, , , , , uint256 repaidPledge) = registry.allocations(ownerId);
		assertEq(repaidPledge, _repaidPledge);
	}

	function testIncreasePledgeRepaymentReverts(uint64 minerId, uint256 _repaidPledge, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && _repaidPledge > 0 && lastEpoch > 0);

		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		callerMock.increasePledgeRepayment(ownerId, _repaidPledge);

		(, , , , , uint256 repaidPledge) = registry.allocations(ownerId);
		assertEq(repaidPledge, 0);
	}

	function testIncreasePledgeRepaymentRevertsWithOverflow(
		uint64 minerId,
		uint256 _repaidPledge,
		int64 lastEpoch
	) public {
		hevm.assume(
			_repaidPledge > 0 &&
				_repaidPledge <= SAMPLE_DAILY_ALLOCATION &&
				lastEpoch > 0 &&
				minerId > 1 &&
				minerId < 2115248121211227543
		);
		registry.registerPool(address(callerMock));

		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(
			minerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10,
			lastEpoch
		);

		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(ownerId);

		resolver.setCollateralAddress(address(callerMock)); // Test case only

		uint256 _usedAllocation = _repaidPledge / 2;
		callerMock.increaseUsedAllocation(ownerId, _usedAllocation, block.timestamp);

		resolver.setRewardCollectorAddress(address(callerMock)); // Test case only

		hevm.expectRevert(abi.encodeWithSignature("AllocationOverflow()"));
		callerMock.increasePledgeRepayment(ownerId, _repaidPledge);

		(, , uint256 usedAllocation, , , uint256 repaidPledge) = registry.allocations(ownerId);
		assertEq(repaidPledge, 0);
		assertEq(usedAllocation, _usedAllocation);
	}

	function testUpdateMaxAllocation(uint256 maxAllocation) public {
		hevm.assume(maxAllocation > 0 && maxAllocation != MAX_ALLOCATION);
		registry.updateMaxAllocation(maxAllocation);
	}

	function testUpdateMaxAllocationReverts() public {
		hevm.expectRevert(abi.encodeWithSignature("InvalidAllocation()"));
		registry.updateMaxAllocation(MAX_ALLOCATION);

		hevm.prank(aliceOwnerAddr);
		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		registry.updateMaxAllocation(1);

		hevm.expectRevert(abi.encodeWithSignature("InvalidAllocation()"));
		registry.updateMaxAllocation(0);
	}
}
