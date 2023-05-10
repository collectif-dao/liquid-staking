// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20, MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {WFIL} from "fevmate/token/WFIL.sol";
import {IWFIL} from "../libraries/tokens/IWFIL.sol";
import {BigIntsClient} from "../libraries/BigInts.sol";
import {Buffer} from "@ensdomains/buffer/contracts/Buffer.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";

import {IStorageProviderCollateral, StorageProviderCollateralMock} from "./mocks/StorageProviderCollateralMock.sol";
import {StorageProviderRegistryMock} from "./mocks/StorageProviderRegistryMock.sol";
// import {IStakingRouter, StakingRouter} from "../StakingRouter.sol";
import {IERC4626RouterBase, ERC4626RouterBase, IERC4626, SelfPermit, PeripheryPayments} from "fei-protocol/erc4626/ERC4626RouterBase.sol";
import {LiquidStakingMock} from "./mocks/LiquidStakingMock.sol";
import {MinerMockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {LiquidStaking} from "../LiquidStaking.sol";
import {LiquidStakingController} from "../LiquidStakingController.sol";
import {MinerActorMock} from "./mocks/MinerActorMock.sol";
import {Resolver} from "../Resolver.sol";

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {ERC1967Proxy} from "@oz/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LiquidStakingTest is DSTestPlus {
	LiquidStakingMock public staking;
	// StakingRouter public router;
	IWFIL public wfil;
	StorageProviderCollateralMock public collateral;
	StorageProviderRegistryMock public registry;
	MinerActorMock public minerActor;
	MinerMockAPI private minerMockAPI;
	BigIntsClient private bigIntsLib;
	Resolver public resolver;
	LiquidStakingController public controller;

	bytes public owner;
	uint64 public aliceOwnerId = 1508;
	uint64 public aliceMinerId = 16121;

	uint256 private aliceKey = 0xBEEF;
	address private alice = address(0x122);
	address private aliceRestaking = address(0x123412);
	address private aliceOwnerAddr = address(0x12341214212);
	address private bob = address(0x123);

	uint256 private adminFee = 1000;
	uint256 private profitShare = 2000;
	address private rewardCollector = address(0x12523);

	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant MIN_TIME_PERIOD = 90 days;
	uint256 private constant MAX_TIME_PERIOD = 360 days;
	uint256 private constant SAMPLE_DAILY_ALLOCATION = MAX_ALLOCATION / 30;

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

		bigIntsLib = new BigIntsClient();

		Resolver resolverImpl = new Resolver();
		ERC1967Proxy resolverProxy = new ERC1967Proxy(address(resolverImpl), "");
		resolver = Resolver(address(resolverProxy));
		resolver.initialize();

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

		// router = new StakingRouter("Collective DAO Router", wfil);

		resolver.setLiquidStakingControllerAddress(address(controller));
		resolver.setRegistryAddress(address(registry));
		resolver.setCollateralAddress(address(collateral));
		resolver.setLiquidStakingAddress(address(staking));
		resolver.setBigIntsAddress(address(bigIntsLib));
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
		registry.changeBeneficiaryAddress();
		registry.acceptBeneficiaryAddress(aliceOwnerId);
	}

	function testStake(uint256 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(address(this), amount);

		staking.stake{value: amount}();

		require(staking.balanceOf(address(this)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(address(staking)) == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == amount, "INVALID_BALANCE");
	}

	function testDeposit(uint256 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(address(this), amount);

		wfil.deposit{value: amount}();
		wfil.approve(address(staking), amount);

		staking.deposit(amount, address(this));

		require(staking.balanceOf(address(this)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(address(staking)) == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == amount, "INVALID_BALANCE");
	}

	// function testStakeViaRouterMulticall(uint256 amount) public {
	// 	hevm.assume(amount != 0);
	// 	hevm.deal(alice, amount);

	// 	hevm.startPrank(alice);
	// 	wfil.deposit{value: amount}();
	// 	wfil.approve(address(router), amount);

	// 	router.approve(wfil, address(staking), amount);
	// 	router.depositToVault(IERC4626(address(staking)), alice, amount, amount);
	// 	hevm.stopPrank();

	// 	require(staking.balanceOf(alice) == amount, "INVALID_BALANCE");
	// 	require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	// 	require(staking.totalAssets() == amount, "INVALID_BALANCE");
	// }

	// function testStakeWithPermitViaRouterMulticall(uint256 amount) public {
	// 	hevm.assume(amount != 0);
	// 	hevm.deal(alice, amount);
	// 	hevm.startPrank(alice);

	// 	wfil.deposit{value: amount}();

	// 	(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
	// 		aliceKey,
	// 		keccak256(
	// 			abi.encodePacked(
	// 				"\x19\x01",
	// 				wfil.DOMAIN_SEPARATOR(),
	// 				keccak256(abi.encode(PERMIT_TYPEHASH, alice, address(router), amount, 0, block.timestamp))
	// 			)
	// 		)
	// 	);

	// 	bytes[] memory data = new bytes[](3);
	// 	data[0] = abi.encodeWithSelector(SelfPermit.selfPermit.selector, wfil, amount, block.timestamp, v, r, s);
	// 	data[1] = abi.encodeWithSelector(PeripheryPayments.approve.selector, wfil, address(staking), amount);
	// 	data[2] = abi.encodeWithSelector(StakingRouter.depositToVault.selector, staking, alice, amount, amount);

	// 	router.multicall(data);
	// 	hevm.stopPrank();

	// 	require(staking.balanceOf(alice) == amount, "INVALID_BALANCE");
	// 	require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	// 	require(staking.totalAssets() == amount, "INVALID_BALANCE");
	// }

	function testStakeZeroFIL(uint256 amount) public {
		hevm.assume(amount == 0);
		hevm.deal(address(this), 1 ether);

		hevm.expectRevert(abi.encodeWithSignature("ERC4626ZeroShares()"));
		staking.stake{value: amount}();
	}

	function testDepositZeroFIL(uint256 amount) public {
		hevm.assume(amount == 0);
		hevm.deal(address(this), 1 ether);

		wfil.deposit{value: amount}();
		wfil.approve(address(staking), amount);

		hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
		staking.deposit(amount, address(this));
	}

	function testUnstake(uint128 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		staking.stake{value: amount}();
		staking.unstake(amount, alice);
		hevm.stopPrank();

		require(staking.balanceOf(alice) == 0, "INVALID_BALANCE");
		require(alice.balance == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == 0, "INVALID_BALANCE");
	}

	function testUnstakeAssets(uint128 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		staking.stake{value: amount}();
		staking.unstakeAssets(amount, alice);
		hevm.stopPrank();

		require(staking.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(alice.balance == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == 0, "INVALID_BALANCE");
	}

	function testRedeem(uint128 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		staking.stake{value: amount}();
		staking.redeem(amount, alice, alice);
		hevm.stopPrank();

		require(staking.balanceOf(alice) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == 0, "INVALID_BALANCE");
	}

	function testWithdraw(uint128 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		staking.stake{value: amount}();
		staking.withdraw(amount, alice, alice);
		hevm.stopPrank();

		require(staking.balanceOf(alice) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == 0, "INVALID_BALANCE");
	}

	function testPledge(uint128 amount) public {
		hevm.assume(amount <= SAMPLE_DAILY_ALLOCATION && amount > 1 ether);
		uint256 collateralAmount = (amount * baseCollateralRequirements) / BASIS_POINTS;

		hevm.deal(address(this), amount);
		hevm.deal(alice, collateralAmount);

		hevm.prank(alice);
		collateral.deposit{value: collateralAmount}(aliceOwnerId);

		staking.stake{value: amount}();

		// try to pledge FIL from the pool
		hevm.prank(alice);
		staking.pledge(amount);

		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(address(minerActor).balance == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == amount, "INVALID_BALANCE");
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

		staking.withdrawRewards(aliceOwnerId, withdrawAmount);

		uint256 protocolFees = (withdrawAmount * adminFee) / BASIS_POINTS;
		uint256 stakingShare = (withdrawAmount * profitShare) / BASIS_POINTS;
		uint256 spShare = withdrawAmount - (protocolFees + stakingShare);

		require(address(minerActor).balance == dailyAllocation, "INVALID_BALANCE");
		require(aliceOwnerAddr.balance == spShare, "INVALID_BALANCE");
		require(wfil.balanceOf(rewardCollector) == protocolFees, "INVALID_BALANCE");
		require(staking.totalAssets() == amount + stakingShare, "INVALID_BALANCE");

		collateralAmount = (dailyAllocation * baseCollateralRequirements) / BASIS_POINTS;
		require(collateral.getLockedCollateral(aliceOwnerId) == collateralAmount, "INVALID_LOCKED_COLLATERAL");
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

		staking.withdrawPledge(aliceOwnerId, dailyAllocation);

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
		staking.withdrawPledge(aliceOwnerId, dailyAllocation + 1);
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

		staking.withdrawRewards(aliceOwnerId, withdrawAmount);

		require(aliceOwnerAddr.balance == spShare, "INVALID_BALANCE");
		require(
			wfil.balanceOf(address(staking)) == amount - dailyAllocation + stakingProfit + restakingAmt,
			"INVALID_BALANCE"
		);

		uint256 stakingAssets = amount + stakingProfit + restakingAmt;
		require(staking.totalAssets() == stakingAssets, "INVALID_BALANCE");
	}

	function testPledgeRevertsAfterReportSlashing(uint128 amount) public {
		hevm.assume(amount <= SAMPLE_DAILY_ALLOCATION && amount > 1 ether);

		uint256 pledgeAmt = (amount * 500000000000000000) / 1000000000000000000;
		uint256 collateralAmount = (pledgeAmt * 150000000000000000) / 1000000000000000000;

		hevm.deal(address(this), amount);
		hevm.deal(alice, collateralAmount);

		hevm.prank(alice);
		collateral.deposit{value: collateralAmount}(aliceOwnerId);

		staking.stake{value: amount}();

		hevm.prank(alice);
		staking.pledge(pledgeAmt);

		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(address(staking)) == amount - pledgeAmt, "INVALID_BALANCE");
		require(address(minerActor).balance == pledgeAmt, "INVALID_BALANCE");
		require(staking.totalAssets() == amount, "INVALID_BALANCE");

		uint256 slashingAmt = (collateralAmount * 500000000000000000) / 1000000000000000000;
		collateral.reportSlashing(aliceOwnerId, slashingAmt);

		require(staking.totalAssets() == amount + slashingAmt, "INVALID_BALANCE");
		// emit log_named_uint("wfil.balanceOf(address(staking))", wfil.balanceOf(address(staking)));
		// emit log_named_uint("pledgeAmt + slashingAmt", pledgeAmt + slashingAmt);
		// require(wfil.balanceOf(address(staking)) == pledgeAmt + slashingAmt, "INVALID_BALANCE"); // Fails due to rounding error

		assertEq(collateral.getLockedCollateral(aliceOwnerId), collateralAmount - slashingAmt);
		assertEq(collateral.slashings(aliceOwnerId), slashingAmt);
		assertBoolEq(collateral.activeSlashings(aliceOwnerId), true);

		hevm.expectRevert(abi.encodeWithSignature("ActiveSlashing()"));
		staking.pledge(pledgeAmt);
	}
}
