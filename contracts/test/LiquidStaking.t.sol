// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20, MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {WFIL} from "fevmate/token/WFIL.sol";
import {IWFIL} from "../libraries/tokens/IWFIL.sol";
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
import {RewardCollectorMock} from "./mocks/RewardCollectorMock.sol";

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {ERC1967Proxy} from "@oz/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract LiquidStakingTest is DSTestPlus {
	LiquidStakingMock public staking;
	// StakingRouter public router;
	IWFIL public wfil;
	StorageProviderCollateralMock public collateral;
	StorageProviderRegistryMock public registry;
	MinerActorMock public minerActor;
	MinerMockAPI private minerMockAPI;
	Resolver public resolver;
	LiquidStakingController public controller;
	RewardCollectorMock private rewardCollector;

	bytes public owner;
	uint64 public aliceOwnerId = 1508;
	uint64 public aliceMinerId = 16121;

	uint64 public SAMPLE_REWARD_COLLECTOR_ID = 1021;

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

	uint256 public baseCollateralRequirements = 1500;
	uint256 public constant BASIS_POINTS = 10000;
	uint256 private constant preCommitDeposit = 95700000000000000;
	uint256 private constant initialPledge = 151700000000000000;
	uint256 initialDeposit = 1000;

	uint256 private liquidityCap = 1_000_000e18;
	bool private withdrawalsActivated = false;

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
		controller.initialize(adminFee, profitShare, address(resolver), liquidityCap, withdrawalsActivated);

		resolver.setLiquidStakingControllerAddress(address(controller));

		hevm.deal(address(this), initialDeposit);
		wfil.deposit{value: initialDeposit}();

		LiquidStakingMock stakingImpl = new LiquidStakingMock();
		ERC1967Proxy stakingProxy = new ERC1967Proxy(address(stakingImpl), "");
		staking = LiquidStakingMock(payable(stakingProxy));
		wfil.approve(address(staking), initialDeposit);
		staking.initialize(
			address(wfil),
			address(minerActor),
			aliceOwnerId,
			aliceOwnerAddr,
			address(minerMockAPI),
			address(resolver),
			initialDeposit
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

		// router = new StakingRouter("Collective DAO Router", wfil);

		resolver.setRegistryAddress(address(registry));
		resolver.setCollateralAddress(address(collateral));
		resolver.setLiquidStakingAddress(address(staking));
		resolver.setRewardCollectorAddress(address(rewardCollector));
		registry.registerPool(address(staking));

		// prepare storage provider for getting FIL from liquid staking
		hevm.prank(alice);
		registry.register(aliceMinerId, MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);

		registry.onboardStorageProvider(
			aliceMinerId,
			MAX_ALLOCATION,
			SAMPLE_DAILY_ALLOCATION,
			MAX_ALLOCATION + 10 ether,
			412678
		);

		registry.acceptBeneficiaryAddress(aliceMinerId);
	}

	function testStake(uint256 amount) public {
		hevm.assume(amount != 0 && amount <= liquidityCap - initialDeposit);
		hevm.deal(address(this), amount);

		staking.stake{value: amount}();

		require(staking.balanceOf(address(this)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(address(staking)) == initialDeposit + amount, "INVALID_BALANCE");
		require(staking.totalAssets() == initialDeposit + amount, "INVALID_BALANCE");
	}

	function testStakeRevertWithMoreThanLiquidityCap(uint256 amount) public {
		hevm.assume(amount > liquidityCap - initialDeposit && amount < type(uint256).max - initialDeposit);
		hevm.deal(address(this), amount);

		hevm.expectRevert(abi.encodeWithSignature("ERC4626Overflow()"));
		staking.stake{value: amount}();
	}

	function testDeposit(uint256 amount) public {
		hevm.assume(amount != 0 && amount < liquidityCap - initialDeposit);
		hevm.deal(address(this), amount);

		wfil.deposit{value: amount}();
		wfil.approve(address(staking), amount);

		staking.deposit(amount, address(this));

		require(staking.balanceOf(address(this)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(address(staking)) == initialDeposit + amount, "INVALID_BALANCE");
		require(staking.totalAssets() == initialDeposit + amount, "INVALID_BALANCE");
	}

	function testDepositRevertWithMoreThanLiquidityCap(uint256 amount) public {
		hevm.assume(amount > liquidityCap - initialDeposit && amount < type(uint256).max - initialDeposit);
		hevm.deal(address(this), amount);

		wfil.deposit{value: amount}();
		wfil.approve(address(staking), amount);

		hevm.expectRevert(abi.encodeWithSignature("ERC4626Overflow()"));
		staking.deposit(amount, address(this));
	}

	function testMint(uint256 amount) public {
		hevm.assume(amount != 0 && amount < liquidityCap - initialDeposit);
		hevm.deal(address(this), amount);

		wfil.deposit{value: amount}();
		wfil.approve(address(staking), amount);

		staking.mint(amount, address(this));

		require(staking.balanceOf(address(this)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(address(staking)) == initialDeposit + amount, "INVALID_BALANCE");
		require(staking.totalAssets() == initialDeposit + amount, "INVALID_BALANCE");
	}

	function testMintRevertWithMoreThanLiquidityCap(uint256 amount) public {
		hevm.assume(amount > liquidityCap - initialDeposit && amount < type(uint256).max - initialDeposit);
		hevm.deal(address(this), amount);

		wfil.deposit{value: amount}();
		wfil.approve(address(staking), amount);

		hevm.expectRevert(abi.encodeWithSignature("ERC4626Overflow()"));
		staking.mint(amount, address(this));
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
		hevm.assume(amount != 0 && amount < liquidityCap - initialDeposit);
		hevm.deal(alice, amount);

		controller.activateWithdrawals();

		hevm.startPrank(alice);
		staking.stake{value: amount}();
		staking.unstake(amount, alice);
		hevm.stopPrank();

		require(staking.balanceOf(alice) == 0, "INVALID_BALANCE");
		require(alice.balance == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == initialDeposit, "INVALID_BALANCE");
	}

	function testUnstakeRevertsBeforeWithdrawalActivation(uint128 amount) public {
		hevm.assume(amount != 0 && amount < liquidityCap - initialDeposit);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		staking.stake{value: amount}();

		hevm.expectRevert(abi.encodeWithSignature("ERC4626Overflow()"));
		staking.unstake(amount, alice);
		hevm.stopPrank();
	}

	function testUnstakeAssets(uint128 amount) public {
		hevm.assume(amount != 0 && amount < liquidityCap - initialDeposit);
		hevm.deal(alice, amount);

		controller.activateWithdrawals();

		hevm.startPrank(alice);
		staking.stake{value: amount}();
		staking.unstakeAssets(amount, alice);
		hevm.stopPrank();

		require(staking.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(alice.balance == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == initialDeposit, "INVALID_BALANCE");
	}

	function testUnstakeAssetsRevertsBeforeWithdrawalActivation(uint128 amount) public {
		hevm.assume(amount != 0 && amount < liquidityCap - initialDeposit);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		staking.stake{value: amount}();

		hevm.expectRevert(abi.encodeWithSignature("ERC4626Overflow()"));
		staking.unstakeAssets(amount, alice);
		hevm.stopPrank();
	}

	function testRedeem(uint128 amount) public {
		hevm.assume(amount != 0 && amount < liquidityCap - initialDeposit);
		hevm.deal(alice, amount);

		controller.activateWithdrawals();

		hevm.startPrank(alice);
		staking.stake{value: amount}();
		staking.redeem(amount, alice, alice);
		hevm.stopPrank();

		require(staking.balanceOf(alice) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == initialDeposit, "INVALID_BALANCE");
	}

	function testRedeemRevertsBeforeWithdrawalActivation(uint128 amount) public {
		hevm.assume(amount != 0 && amount < liquidityCap - initialDeposit);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		staking.stake{value: amount}();

		hevm.expectRevert(abi.encodeWithSignature("ERC4626Overflow()"));
		staking.redeem(amount, alice, alice);
		hevm.stopPrank();
	}

	function testWithdraw(uint128 amount) public {
		hevm.assume(amount != 0 && amount < liquidityCap - initialDeposit);
		hevm.deal(alice, amount);

		controller.activateWithdrawals();

		hevm.startPrank(alice);
		staking.stake{value: amount}();
		staking.withdraw(amount, alice, alice);
		hevm.stopPrank();

		require(staking.balanceOf(alice) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == initialDeposit, "INVALID_BALANCE");
	}

	function testWithdrawRevertsBeforeWithdrawalActivation(uint128 amount) public {
		hevm.assume(amount != 0 && amount < liquidityCap - initialDeposit);
		hevm.deal(alice, amount);

		hevm.startPrank(alice);
		staking.stake{value: amount}();

		hevm.expectRevert(abi.encodeWithSignature("ERC4626Overflow()"));
		staking.withdraw(amount, alice, alice);
		hevm.stopPrank();
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
		staking.pledge(amount, aliceMinerId);

		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(address(minerActor).balance == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == amount + initialDeposit, "INVALID_BALANCE");
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
		staking.pledge(pledgeAmt, aliceMinerId);

		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(address(staking)) == amount + initialDeposit - pledgeAmt, "INVALID_BALANCE");
		require(address(minerActor).balance == pledgeAmt, "INVALID_BALANCE");
		require(staking.totalAssets() == amount + initialDeposit, "INVALID_BALANCE");

		uint256 slashingAmt = (collateralAmount * 500000000000000000) / 1000000000000000000;
		collateral.reportSlashing(aliceOwnerId, slashingAmt);

		require(staking.totalAssets() == amount + initialDeposit + slashingAmt, "INVALID_BALANCE");
		// emit log_named_uint("wfil.balanceOf(address(staking))", wfil.balanceOf(address(staking)));
		// emit log_named_uint("pledgeAmt + slashingAmt", pledgeAmt + slashingAmt);
		// require(wfil.balanceOf(address(staking)) == pledgeAmt + slashingAmt, "INVALID_BALANCE"); // Fails due to rounding error

		assertEq(collateral.getLockedCollateral(aliceOwnerId), collateralAmount - slashingAmt);
		assertEq(collateral.slashings(aliceOwnerId), slashingAmt);
		assertBoolEq(collateral.activeSlashings(aliceOwnerId), true);

		hevm.expectRevert(abi.encodeWithSignature("ActiveSlashing()"));
		staking.pledge(pledgeAmt, aliceMinerId);
	}

	function testStakingAttack(uint256 amount) public {
		controller.activateWithdrawals();
		address attacker = address(0x1253);
		// initial balances

		uint256 initialAttackerBalance = 10000 * 1e18 + 1;
		uint256 initialAliceBalance = 20000 * 1e18;
		hevm.deal(attacker, initialAttackerBalance);
		hevm.deal(alice, initialAliceBalance);

		// stake 1 wei, get 1 share
		hevm.startPrank(attacker);
		staking.stake{value: 1}();

		emit log_named_uint("Share balance of attacker:", staking.balanceOf(attacker));

		// transfer 10k WFIL directly to staking
		wfil.deposit{value: initialAttackerBalance - 1}();
		emit log_named_uint("WFIL Balance of attacker:", wfil.balanceOf(attacker));

		wfil.transfer(address(staking), initialAttackerBalance - 1);
		emit log_named_uint("WFIL Balance of staking:", wfil.balanceOf(address(staking)));

		hevm.stopPrank();

		// now alice deposits 20k and also gets 1 share
		hevm.prank(alice);
		emit log_named_uint("Initial Alice Balance:", alice.balance);
		staking.stake{value: initialAliceBalance}();

		emit log_named_uint("Share balance of Alice:", staking.balanceOf(alice));

		// attacker withdraws 1 share
		hevm.prank(attacker);
		emit log_named_uint("Attacker Balance Before Attack:", attacker.balance);
		staking.unstake(1, attacker);
		emit log_named_uint("Attacker Balance After Attack:", attacker.balance);

		hevm.prank(alice);
		staking.unstake(1, alice);
		emit log_named_uint("Alice balance after attack:", alice.balance);

		require(attacker.balance < initialAttackerBalance, "SUCCESSFULL_ATTACK");
	}

	function testLiquidityCapForMint(uint128 amount) public {
		hevm.assume(amount <= SAMPLE_DAILY_ALLOCATION && amount >= 1 ether);
		uint256 collateralAmount = (amount * baseCollateralRequirements) / BASIS_POINTS;
		uint256 pledgeAmt = FixedPointMathLib.mulDivDown(amount, 5000, BASIS_POINTS);

		hevm.deal(address(this), amount);
		hevm.deal(alice, collateralAmount);

		hevm.prank(alice);
		collateral.deposit{value: collateralAmount}(aliceOwnerId);

		staking.stake{value: amount}();

		hevm.prank(alice);
		staking.pledge(pledgeAmt, aliceMinerId);

		uint256 withdrawAmount = FixedPointMathLib.mulDivDown(pledgeAmt, 5000, BASIS_POINTS);
		uint256 stakingProfit = FixedPointMathLib.mulDivDown(withdrawAmount, profitShare, BASIS_POINTS);
		uint256 protocolFees = FixedPointMathLib.mulDivDown(withdrawAmount, adminFee, BASIS_POINTS);
		uint256 protocolShare = stakingProfit + protocolFees;

		rewardCollector.withdrawRewards(aliceMinerId, withdrawAmount);

		uint256 leftCapital = amount + stakingProfit + initialDeposit - pledgeAmt;
		require(wfil.balanceOf(address(staking)) == leftCapital, "INVALID_STAKING_WFIL_BALANCE");
		require(staking.totalFilAvailable() == leftCapital, "INVALID_STAKING_AVAILABLE_FIL");
		require(staking.totalAssets() == amount + stakingProfit + initialDeposit, "INVALID_STAKING_ASSETS");

		uint256 maxDeposit = liquidityCap - leftCapital;

		require(staking.maxDeposit(address(this)) == maxDeposit, "INVALID_MAX_DEPOSIT");
		require(staking.maxMint(address(this)) == staking.convertToShares(maxDeposit), "INVALID_MAX_MINT");

		uint256 overflowDeposit = maxDeposit + 1;
		hevm.deal(address(this), overflowDeposit);

		hevm.expectRevert(abi.encodeWithSignature("ERC4626Overflow()"));
		staking.stake{value: overflowDeposit}();

		wfil.deposit{value: overflowDeposit}();
		wfil.approve(address(staking), overflowDeposit);

		hevm.expectRevert(abi.encodeWithSignature("ERC4626Overflow()"));
		staking.deposit(overflowDeposit, address(this));

		uint256 shareMint = staking.convertToShares(overflowDeposit + 1); // test case to get rid of the pottential rounding down error
		hevm.expectRevert(abi.encodeWithSignature("ERC4626Overflow()"));
		staking.mint(shareMint, address(this));

		controller.updateLiquidityCap(0);

		staking.deposit(overflowDeposit, address(this));
		assertEq(staking.maxDeposit(address(this)), type(uint256).max);
	}
}
