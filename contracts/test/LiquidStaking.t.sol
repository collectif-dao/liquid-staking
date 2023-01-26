// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ERC20, MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {WFIL} from "./mocks/WFIL.sol";

import {IStorageProviderCollateral, StorageProviderCollateral} from "../StorageProviderCollateral.sol";
import {StorageProviderRegistryMock} from "./mocks/StorageProviderRegistryMock.sol";
import {IStakingRouter, StakingRouter} from "../StakingRouter.sol";
import {IERC4626RouterBase, ERC4626RouterBase, IWETH9, IERC4626, SelfPermit, PeripheryPayments} from "fei-protocol/erc4626/ERC4626RouterBase.sol";
import {LiquidStaking} from "../LiquidStaking.sol";

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

contract LiquidStakingTest is DSTestPlus {
	LiquidStaking public staking;
	StakingRouter public router;
	IWETH9 public wfil;
	StorageProviderCollateral public collateral;
	StorageProviderRegistryMock public registry;

	uint256 private aliceKey = 0xBEEF;
	address private alice = address(0x122);
	address private bob = address(0x123);

	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant MIN_TIME_PERIOD = 90 days;
	uint256 private constant MAX_TIME_PERIOD = 360 days;

	uint256 public collateralRequirements = 1500;
	uint256 public constant BASIS_POINTS = 10000;

	bytes32 public PERMIT_TYPEHASH =
		keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

	function setUp() public {
		alice = hevm.addr(aliceKey);

		wfil = IWETH9(address(new WFIL()));
		staking = new LiquidStaking(address(wfil));

		registry = new StorageProviderRegistryMock(
			abi.encodePacked(alice),
			MAX_STORAGE_PROVIDERS,
			MAX_ALLOCATION,
			MIN_TIME_PERIOD,
			MAX_TIME_PERIOD
		);

		collateral = new StorageProviderCollateral(wfil, address(registry));

		router = new StakingRouter("Collective DAO Router", wfil);

		registry.setCollateralAddress(address(collateral));
		staking.setCollateralAddress(address(collateral));
		staking.setRegistryAddress(address(registry));
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

	function testStakeViaMulticall(uint256 amount) public {
		hevm.assume(amount != 0 && amount > 100);
		hevm.deal(alice, amount);
		hevm.startPrank(alice);

		bytes[] memory data = new bytes[](1);
		data[0] = abi.encodeWithSelector(LiquidStaking.stake.selector, amount);

		staking.multicall{value: amount}(data);
		hevm.stopPrank();

		require(staking.balanceOf(alice) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
		require(staking.totalAssets() == amount, "INVALID_BALANCE");
	}

	function testStakeWithPermitViaRouterMulticall(uint256 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(alice, amount);
		hevm.startPrank(alice);

		wfil.deposit{value: amount}();

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			aliceKey,
			keccak256(
				abi.encodePacked(
					"\x19\x01",
					wfil.DOMAIN_SEPARATOR(),
					keccak256(abi.encode(PERMIT_TYPEHASH, alice, address(router), amount, 0, block.timestamp))
				)
			)
		);

		bytes[] memory data = new bytes[](3);
		data[0] = abi.encodeWithSelector(SelfPermit.selfPermit.selector, wfil, amount, block.timestamp, v, r, s);
		data[1] = abi.encodeWithSelector(PeripheryPayments.approve.selector, wfil, address(staking), amount);
		data[2] = abi.encodeWithSelector(StakingRouter.depositToVault.selector, staking, alice, amount, amount);

		router.multicall(data);
		hevm.stopPrank();

		require(staking.balanceOf(alice) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
		require(staking.totalAssets() == amount, "INVALID_BALANCE");
	}

	function testStakeZeroFIL(uint256 amount) public {
		hevm.assume(amount == 0);
		hevm.deal(address(this), 1 ether);

		hevm.expectRevert("ZERO_SHARES");
		staking.stake{value: amount}();
	}

	function testDepositZeroFIL(uint256 amount) public {
		hevm.assume(amount == 0);
		hevm.deal(address(this), 1 ether);

		wfil.deposit{value: amount}();
		wfil.approve(address(staking), amount);

		hevm.expectRevert("ZERO_SHARES");
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
		hevm.assume(amount != 0 && amount <= MAX_ALLOCATION && amount > 1 ether);
		uint256 collateralAmount = (amount * collateralRequirements) / BASIS_POINTS;
		hevm.deal(address(this), amount);
		hevm.deal(alice, collateralAmount);

		// prepare storage provider for getting FIL from liquid staking
		hevm.startPrank(alice);
		registry.register(alice, address(staking), amount, MIN_TIME_PERIOD);

		bytes memory aliceBytes = abi.encodePacked(alice);
		bytes memory stakingBytes = abi.encodePacked(address(staking));

		registry.acceptBeneficiaryAddress(aliceBytes, stakingBytes);

		collateral.deposit{value: collateralAmount}();
		hevm.stopPrank();

		staking.stake{value: amount}();

		// try to pledge FIL from the pool
		hevm.prank(alice);
		staking.pledge(amount);

		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(alice.balance == amount, "INVALID_BALANCE");
		require(staking.totalAssets() == amount, "INVALID_BALANCE");
	}
}
