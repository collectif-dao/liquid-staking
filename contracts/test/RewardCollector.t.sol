// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20, MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {WFIL} from "fevmate/token/WFIL.sol";
import {IWFIL} from "../libraries/tokens/IWFIL.sol";
import {Buffer} from "@ensdomains/buffer/contracts/Buffer.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";

import {StorageProviderCollateralMock} from "./mocks/StorageProviderCollateralMock.sol";
import {StorageProviderRegistryMock, StorageProviderRegistryCallerMock, MinerTypes} from "./mocks/StorageProviderRegistryMock.sol";
import {LiquidStakingMock} from "./mocks/LiquidStakingMock.sol";
import {MinerMockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {LiquidStaking} from "../LiquidStaking.sol";
import {LiquidStakingController} from "../LiquidStakingController.sol";
import {MinerActorMock} from "./mocks/MinerActorMock.sol";
import {Resolver} from "../Resolver.sol";
import {BeneficiaryManagerMock} from "./mocks/BeneficiaryManagerMock.sol";
import {RewardCollectorMock, BigInts} from "./mocks/RewardCollectorMock.sol";

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {ERC1967Proxy} from "@oz/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RewardCollectorTest is DSTestPlus {
	LiquidStakingMock public staking;
	IWFIL public wfil;
	StorageProviderCollateralMock public collateral;
	StorageProviderRegistryMock public registry;
	MinerActorMock public minerActor;
	MinerMockAPI private minerMockAPI;
	Resolver public resolver;
	LiquidStakingController public controller;
	BeneficiaryManagerMock public beneficiaryManager;
	RewardCollectorMock private rewardCollector;
	StorageProviderRegistryCallerMock private registryCaller;

	bytes public owner;
	uint64 public aliceOwnerId = 1508;
	uint64 public aliceMinerId = 16121;

	uint64 public SAMPLE_LSP_ACTOR_ID = 1021;

	uint256 private aliceKey = 0xBEEF;
	address private alice = address(0x122);
	address private aliceRestaking = address(0x123412);
	address private aliceOwnerAddr = address(0x12341214212);
	address private bob = address(0x123);

	uint256 private adminFee = 1000;
	uint256 private profitShare = 2000;

	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant MIN_TIME_PERIOD = 90 days;
	uint256 private constant MAX_TIME_PERIOD = 360 days;
	uint256 private constant SAMPLE_DAILY_ALLOCATION = MAX_ALLOCATION / 30;
	uint256 private constant repayment = MAX_ALLOCATION + 10;

	uint256 public baseCollateralRequirements = 1500;
	uint256 public constant BASIS_POINTS = 10000;
	uint256 private constant preCommitDeposit = 95700000000000000;
	uint256 private constant initialPledge = 151700000000000000;

	bytes32 public PERMIT_TYPEHASH =
		keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

	function setUp() public {
		alice = hevm.addr(aliceKey);
		Buffer.buffer memory ownerBytes = Leb128.encodeUnsignedLeb128FromUInt64(aliceOwnerId);
		owner = ownerBytes.buf;

		wfil = IWFIL(address(new WFIL(msg.sender)));
		minerActor = new MinerActorMock();
		minerMockAPI = new MinerMockAPI(owner);

		Resolver resolverImpl = new Resolver();
		ERC1967Proxy resolverProxy = new ERC1967Proxy(address(resolverImpl), "");
		resolver = Resolver(address(resolverProxy));
		resolver.initialize();

		BeneficiaryManagerMock bManagerImpl = new BeneficiaryManagerMock();
		ERC1967Proxy bManagerProxy = new ERC1967Proxy(address(bManagerImpl), "");
		beneficiaryManager = BeneficiaryManagerMock(address(bManagerProxy));
		beneficiaryManager.initialize(address(minerMockAPI), aliceOwnerId, address(resolver));

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
		controller.initialize(adminFee, profitShare, address(resolver));

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
			SAMPLE_LSP_ACTOR_ID,
			MAX_ALLOCATION,
			address(resolver)
		);

		registryCaller = new StorageProviderRegistryCallerMock(address(registry));

		StorageProviderCollateralMock collateralImpl = new StorageProviderCollateralMock();
		ERC1967Proxy collateralProxy = new ERC1967Proxy(address(collateralImpl), "");
		collateral = StorageProviderCollateralMock(payable(collateralProxy));
		collateral.initialize(wfil, address(resolver), baseCollateralRequirements);

		// router = new StakingRouter("Collective DAO Router", wfil);

		resolver.setLiquidStakingControllerAddress(address(controller));
		resolver.setRegistryAddress(address(registry));
		resolver.setBeneficiaryManagerAddress(address(beneficiaryManager));
		resolver.setCollateralAddress(address(collateral));
		resolver.setLiquidStakingAddress(address(staking));
		resolver.setRewardCollectorAddress(address(rewardCollector));
		registry.registerPool(address(staking));

		// prepare storage provider for getting FIL from liquid staking
		hevm.prank(alice);
		registry.register(aliceMinerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);

		registry.onboardStorageProvider(
			aliceMinerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10 ether,
			412678
		);

		hevm.prank(alice);
		beneficiaryManager.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(aliceOwnerId);
	}

	function testWithdrawRewards(uint256 amount) public {
		hevm.assume(amount != 0 && amount < MAX_ALLOCATION && amount > 1 ether);
		hevm.deal(address(this), amount);

		uint256 withdrawAmount = (amount * 500) / BASIS_POINTS;
		hevm.deal(address(minerActor), withdrawAmount);

		uint256 dailyAllocation = amount / 30;
		uint256 collateralAmount = (dailyAllocation * baseCollateralRequirements) / BASIS_POINTS;
		hevm.deal(alice, collateralAmount);

		hevm.prank(alice);
		registry.requestAllocationLimitUpdate(amount, dailyAllocation);
		registry.updateAllocationLimit(aliceOwnerId, amount, dailyAllocation, amount + 10); // TODO: FIX

		hevm.prank(alice);
		collateral.deposit{value: collateralAmount}(aliceOwnerId);

		staking.stake{value: amount}();

		hevm.prank(alice);
		staking.pledge(dailyAllocation);

		require(address(minerActor).balance == withdrawAmount + dailyAllocation, "INVALID_BALANCE");
		require(staking.totalAssets() == amount, "INVALID_BALANCE");

		rewardCollector.withdrawRewards(aliceOwnerId, withdrawAmount);

		uint256 protocolFees = (withdrawAmount * adminFee) / BASIS_POINTS;
		uint256 stakingShare = (withdrawAmount * profitShare) / BASIS_POINTS;
		uint256 spShare = withdrawAmount - (protocolFees + stakingShare);

		require(address(minerActor).balance == dailyAllocation, "INVALID_BALANCE");
		require(aliceOwnerAddr.balance == spShare, "INVALID_BALANCE");
		require(wfil.balanceOf(address(rewardCollector)) == protocolFees, "INVALID_BALANCE");
		require(staking.totalAssets() == amount + stakingShare, "INVALID_BALANCE");

		collateralAmount = (dailyAllocation * baseCollateralRequirements) / BASIS_POINTS;
		require(collateral.getLockedCollateral(aliceOwnerId) == collateralAmount, "INVALID_LOCKED_COLLATERAL");
	}

	function testWithdrawRewardsWithRestaking(uint256 amount) public {
		hevm.assume(amount != 0 && amount < MAX_ALLOCATION && amount > 1 ether);
		uint256 collateralAmount = (amount * baseCollateralRequirements) / BASIS_POINTS;
		hevm.deal(address(this), amount);
		hevm.deal(alice, collateralAmount);

		uint256 dailyAllocation = amount / 30;

		uint256 withdrawAmount = (amount * 500) / BASIS_POINTS;
		hevm.deal(address(minerActor), withdrawAmount);

		uint256 stakingProfit = (withdrawAmount * profitShare) / BASIS_POINTS;
		uint256 protocolFees = (withdrawAmount * adminFee) / BASIS_POINTS;
		uint256 protocolShare = stakingProfit + protocolFees;
		uint256 restakingAmt = ((withdrawAmount - protocolShare) * 2000) / BASIS_POINTS;
		uint256 spShare = withdrawAmount - (protocolShare + restakingAmt);

		hevm.prank(alice);
		registry.requestAllocationLimitUpdate(amount, dailyAllocation);
		registry.updateAllocationLimit(aliceOwnerId, amount, dailyAllocation, amount + 10); // TODO: FIX

		hevm.prank(alice);
		registry.setRestaking(2000, aliceRestaking);

		hevm.prank(alice);
		collateral.deposit{value: collateralAmount}(aliceOwnerId);

		staking.stake{value: amount}();

		hevm.prank(alice);
		staking.pledge(dailyAllocation);

		require(address(minerActor).balance == withdrawAmount + dailyAllocation, "INVALID_BALANCE");
		require(wfil.balanceOf(address(collateral)) == collateralAmount, "INVALID_BALANCE");
		require(staking.totalAssets() == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(address(staking)) == amount - dailyAllocation, "INVALID_BALANCE");

		rewardCollector.withdrawRewards(aliceOwnerId, withdrawAmount);

		require(aliceOwnerAddr.balance == spShare, "INVALID_BALANCE");
		require(
			wfil.balanceOf(address(staking)) == amount - dailyAllocation + stakingProfit + restakingAmt,
			"INVALID_BALANCE"
		);

		uint256 stakingAssets = amount + stakingProfit + restakingAmt;
		require(staking.totalAssets() == stakingAssets, "INVALID_BALANCE");
	}

	function testWithdrawPledge(uint256 amount) public {
		hevm.assume(amount < MAX_ALLOCATION && amount > 1 ether);
		hevm.deal(address(this), amount);

		uint256 dailyAllocation = amount / 30;
		uint256 collateralAmount = (dailyAllocation * baseCollateralRequirements) / BASIS_POINTS;
		hevm.deal(address(minerActor), collateralAmount);

		hevm.prank(alice);
		registry.requestAllocationLimitUpdate(amount, dailyAllocation);
		registry.updateAllocationLimit(aliceOwnerId, amount, dailyAllocation, amount + 10); // TODO: FIX

		hevm.prank(address(minerActor));
		collateral.deposit{value: collateralAmount}(aliceOwnerId);

		staking.stake{value: amount}();

		hevm.prank(address(minerActor));
		staking.pledge(dailyAllocation);

		require(address(minerActor).balance == dailyAllocation, "INVALID_BALANCE");
		require(staking.totalAssets() == amount, "INVALID_BALANCE");

		rewardCollector.withdrawPledge(aliceOwnerId, dailyAllocation);

		require(address(minerActor).balance == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(address(staking)) == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == amount, "INVALID_BALANCE");

		hevm.prank(address(minerActor));
		collateral.withdraw(aliceOwnerId, collateralAmount);
		// collateral.deposit{value: collateralAmount}(aliceOwnerId);
	}

	function testWithdrawPledgeReverts(uint256 amount) public {
		hevm.assume(amount < MAX_ALLOCATION && amount > 1 ether);
		uint256 collateralAmount = (amount * baseCollateralRequirements) / BASIS_POINTS;
		hevm.deal(address(this), amount);
		hevm.deal(address(minerActor), collateralAmount + 1);

		uint256 dailyAllocation = amount / 30;

		hevm.prank(alice);
		registry.requestAllocationLimitUpdate(amount, dailyAllocation);
		registry.updateAllocationLimit(aliceOwnerId, amount, dailyAllocation, amount + 10); // TODO: FIX

		hevm.prank(address(minerActor));
		collateral.deposit{value: collateralAmount}(aliceOwnerId);

		staking.stake{value: amount}();

		hevm.prank(address(minerActor));
		staking.pledge(dailyAllocation);

		hevm.expectRevert(abi.encodeWithSignature("AllocationOverflow()"));
		rewardCollector.withdrawPledge(aliceOwnerId, dailyAllocation + 1);
	}

	function testForwardChangeBeneficiary(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);

		(, address targetPool, , ) = registry.getStorageProvider(aliceOwnerId);
		assertEq(targetPool, address(staking));

		registryCaller.forwardChangeBeneficiary(minerId, SAMPLE_LSP_ACTOR_ID, repayment, lastEpoch);

		MinerTypes.GetBeneficiaryReturn memory beneficiary = minerMockAPI.getBeneficiary();
		(uint256 quota, bool err) = BigInts.toUint256(beneficiary.active.term.quota);
		require(!err, "INVALID_BIG_INT");
		require(quota == repayment, "INVALID_BENEFICIARY_QUOTA");
	}

	function testForwardChangeBeneficiaryReverts(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);

		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		rewardCollector.forwardChangeBeneficiary(minerId, SAMPLE_LSP_ACTOR_ID, repayment, lastEpoch);
	}
}
