// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ERC20, MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {WFIL} from "./mocks/WFIL.sol";

import {IStakingRouter, StakingRouter} from "../StakingRouter.sol";
import {IERC4626RouterBase, ERC4626RouterBase, IWETH9, IERC4626, SelfPermit, PeripheryPayments} from "fei-protocol/erc4626/ERC4626RouterBase.sol";

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

contract StakingRouterTest is DSTestPlus {
	IERC4626 public staking;
	StakingRouter public router;
	IWETH9 public wfil;

	uint256 private aliceKey = 0xBEEF;
	address private alice;

	bytes32 public PERMIT_TYPEHASH =
		keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

	receive() external payable {}

	function setUp() public {
		wfil = IWETH9(address(new WFIL()));
		staking = IERC4626(address(new MockERC4626(wfil, "Collective FIL Liquid Staking", "clFIL")));

		router = new StakingRouter("", wfil);

		alice = hevm.addr(aliceKey);
	}

	function testMint(uint256 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(address(this), amount);
		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);
		router.pullToken(wfil, amount, address(router));
		router.mint(IERC4626(address(staking)), address(this), amount, amount);

		require(staking.balanceOf(address(this)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
	}

	function testDeposit(uint256 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(address(this), amount);

		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);
		router.pullToken(wfil, amount, address(router));
		router.deposit(IERC4626(address(staking)), address(this), amount, amount);

		require(staking.balanceOf(address(this)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
	}

	function testDepositToVault(uint256 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(address(this), amount);

		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);
		router.depositToVault(IERC4626(address(staking)), address(this), amount, amount);

		require(staking.balanceOf(address(this)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
	}

	function testDepositWithPermit(uint256 amount) public {
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

		wfil.permit(alice, address(router), amount, block.timestamp, v, r, s);

		router.approve(wfil, address(staking), amount);
		router.depositToVault(staking, alice, amount, amount);
		hevm.stopPrank();

		require(staking.balanceOf(alice) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == 0, "INVALID_BALANCE");
	}

	function testDepositWithPermitViaMulticall(uint256 amount) public {
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
	}

	function testDepositTo(uint256 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(address(this), amount);

		address mockVault = address(0x1);

		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);

		router.depositToVault(IERC4626(address(staking)), mockVault, amount, amount);

		require(staking.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(staking.balanceOf(mockVault) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(address(this)) == 0, "INVALID_BALANCE");
	}

	function testDepositBelowMinOutReverts(uint256 amount) public {
		hevm.assume(amount != 0 && amount != type(uint256).max);
		hevm.deal(address(this), amount);

		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);

		hevm.expectRevert(abi.encodeWithSignature("MinSharesError()"));
		router.depositToVault(IERC4626(address(staking)), address(this), amount, amount + 1);
	}

	function testWithdraw(uint128 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(address(this), amount);

		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);

		router.depositToVault(IERC4626(address(staking)), address(this), amount, amount);

		staking.approve(address(router), amount);
		router.withdraw(staking, address(this), amount, amount);

		require(staking.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(address(this)) == amount, "INVALID_BALANCE");
	}

	function testWithdrawWithPermit(uint128 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(alice, amount);
		hevm.startPrank(alice);

		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);
		router.depositToVault(IERC4626(address(staking)), alice, amount, amount);

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			aliceKey,
			keccak256(
				abi.encodePacked(
					"\x19\x01",
					staking.DOMAIN_SEPARATOR(),
					keccak256(abi.encode(PERMIT_TYPEHASH, alice, address(router), amount, 0, block.timestamp))
				)
			)
		);

		staking.permit(alice, address(router), amount, block.timestamp, v, r, s);
		router.withdraw(staking, alice, amount, amount);
		hevm.stopPrank();

		require(staking.balanceOf(alice) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == amount, "INVALID_BALANCE");
	}

	function testWithdrawWithPermitViaMulticall(uint128 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(alice, amount);
		hevm.startPrank(alice);

		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);

		router.depositToVault(IERC4626(address(staking)), alice, amount, amount);

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			aliceKey,
			keccak256(
				abi.encodePacked(
					"\x19\x01",
					staking.DOMAIN_SEPARATOR(),
					keccak256(abi.encode(PERMIT_TYPEHASH, alice, address(router), amount, 0, block.timestamp))
				)
			)
		);

		bytes[] memory data = new bytes[](2);
		data[0] = abi.encodeWithSelector(SelfPermit.selfPermit.selector, staking, amount, block.timestamp, v, r, s);
		data[1] = abi.encodeWithSelector(IERC4626RouterBase.withdraw.selector, staking, alice, amount, amount);

		router.multicall(data);
		hevm.stopPrank();

		require(staking.balanceOf(alice) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == amount, "INVALID_BALANCE");
	}

	function testFailWithdrawAboveMaxOut(uint128 amount) public {
		hevm.assume(amount != 0 && amount != type(uint256).max);
		hevm.deal(address(this), amount);

		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);
		router.depositToVault(IERC4626(address(staking)), address(this), amount, amount);

		staking.approve(address(router), amount);
		router.withdraw(IERC4626(address(staking)), address(this), amount, amount - 1);
	}

	function testRedeem(uint128 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(address(this), amount);

		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);
		router.depositToVault(IERC4626(address(staking)), address(this), amount, amount);

		staking.approve(address(router), amount);

		router.redeem(staking, address(this), amount, amount);

		require(staking.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(address(this)) == amount, "INVALID_BALANCE");
	}

	function testRedeemMax(uint128 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(address(this), amount);

		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);

		router.depositToVault(IERC4626(address(staking)), address(this), amount, amount);

		staking.approve(address(router), amount);
		router.redeemMax(staking, address(this), amount);

		require(staking.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(address(this)) == amount, "INVALID_BALANCE");
	}

	function testRedeemWithPermit(uint128 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(alice, amount);
		hevm.startPrank(alice);

		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);

		router.depositToVault(IERC4626(address(staking)), alice, amount, amount);

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			aliceKey,
			keccak256(
				abi.encodePacked(
					"\x19\x01",
					staking.DOMAIN_SEPARATOR(),
					keccak256(abi.encode(PERMIT_TYPEHASH, alice, address(router), amount, 0, block.timestamp))
				)
			)
		);

		staking.permit(alice, address(router), amount, block.timestamp, v, r, s);

		router.redeem(staking, alice, amount, amount);
		hevm.stopPrank();

		require(staking.balanceOf(alice) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == amount, "INVALID_BALANCE");
	}

	function testRedeemWithPermitViaMulticall(uint128 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(alice, amount);
		hevm.startPrank(alice);

		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);

		router.depositToVault(IERC4626(address(staking)), alice, amount, amount);

		(uint8 v, bytes32 r, bytes32 s) = hevm.sign(
			aliceKey,
			keccak256(
				abi.encodePacked(
					"\x19\x01",
					staking.DOMAIN_SEPARATOR(),
					keccak256(abi.encode(PERMIT_TYPEHASH, alice, address(router), amount, 0, block.timestamp))
				)
			)
		);

		bytes[] memory data = new bytes[](2);
		data[0] = abi.encodeWithSelector(SelfPermit.selfPermit.selector, staking, amount, block.timestamp, v, r, s);
		data[1] = abi.encodeWithSelector(IERC4626RouterBase.redeem.selector, staking, alice, amount, amount);

		router.multicall(data);
		hevm.stopPrank();

		require(staking.balanceOf(alice) == 0, "INVALID_BALANCE");
		require(wfil.balanceOf(alice) == amount, "INVALID_BALANCE");
	}

	function testRedeemBelowMinOutReverts(uint128 amount) public {
		hevm.assume(amount != 0 && amount != type(uint128).max);
		hevm.deal(address(this), amount);

		wfil.deposit{value: amount}();
		wfil.approve(address(router), amount);

		router.approve(wfil, address(staking), amount);

		router.depositToVault(IERC4626(address(staking)), address(this), amount, amount);

		staking.approve(address(router), amount);

		hevm.expectRevert(abi.encodeWithSignature("MinAmountError()"));
		router.redeem(IERC4626(address(staking)), address(this), amount, amount + 1);
	}

	function testDepositFILToWFILVaultWithPermitViaMulticall(uint256 amount) public {
		hevm.assume(amount != 0);
		hevm.deal(alice, amount);
		hevm.startPrank(alice);

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

		bytes[] memory data = new bytes[](4);
		data[0] = abi.encodeWithSelector(PeripheryPayments.wrapWETH9.selector);
		data[1] = abi.encodeWithSelector(SelfPermit.selfPermit.selector, wfil, amount, block.timestamp, v, r, s);
		data[2] = abi.encodeWithSelector(PeripheryPayments.approve.selector, wfil, address(staking), amount);
		data[3] = abi.encodeWithSelector(ERC4626RouterBase.deposit.selector, staking, address(this), amount, amount);

		router.multicall{value: amount}(data);
		hevm.stopPrank();

		require(staking.balanceOf(address(this)) == amount, "INVALID_BALANCE");
		require(wfil.balanceOf(address(router)) == 0, "INVALID_BALANCE");
	}

	function testWithdrawFILFromWFILVaultAndUnwrapViaMulticall(uint256 amount) public {
		hevm.assume(amount != 0 && amount < 100 ether);
		hevm.deal(address(this), amount);

		uint256 balanceBefore = address(this).balance;

		router.approve(wfil, address(staking), amount);

		bytes[] memory data = new bytes[](2);
		data[0] = abi.encodeWithSelector(PeripheryPayments.wrapWETH9.selector);
		data[1] = abi.encodeWithSelector(ERC4626RouterBase.deposit.selector, staking, address(this), amount, amount);

		router.multicall{value: amount}(data);

		staking.approve(address(router), amount);

		bytes[] memory withdrawData = new bytes[](2);
		withdrawData[0] = abi.encodeWithSelector(
			ERC4626RouterBase.withdraw.selector,
			staking,
			address(router),
			amount,
			amount
		);
		withdrawData[1] = abi.encodeWithSelector(PeripheryPayments.unwrapWETH9.selector, amount, address(this));

		router.multicall(withdrawData);

		require(staking.balanceOf(address(this)) == 0, "INVALID_BALANCE");
		require(address(this).balance == balanceBefore, "INVALID_BALANCE");
	}
}
