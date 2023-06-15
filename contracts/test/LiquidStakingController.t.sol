// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Resolver} from "../Resolver.sol";
import {LiquidStakingController} from "../LiquidStakingController.sol";
import {ERC1967Proxy} from "@oz/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

contract LiquidStakingControllerTest is DSTestPlus {
	LiquidStakingController public controller;
	Resolver public resolver;

	uint256 private aliceKey = 0xBEEF;
	address private alice = address(0x122);
	uint64 public aliceOwnerId = 1508;

	uint256 private adminFee = 1000;
	uint256 private profitShare = 2000;
	address private rewardCollector = address(0x12523);

	uint256 private liquidityCap = 1_000_000e18;
	bool private withdrawalsActivated = false;

	function setUp() public {
		alice = hevm.addr(aliceKey);

		Resolver resolverImpl = new Resolver();
		ERC1967Proxy resolverProxy = new ERC1967Proxy(address(resolverImpl), "");
		resolver = Resolver(address(resolverProxy));
		resolver.initialize();

		LiquidStakingController controllerImpl = new LiquidStakingController();
		ERC1967Proxy controllerProxy = new ERC1967Proxy(address(controllerImpl), "");
		controller = LiquidStakingController(address(controllerProxy));
		controller.initialize(adminFee, profitShare, address(resolver), liquidityCap, withdrawalsActivated);
	}

	function testUpdateProfitShare(uint256 share) public {
		hevm.assume(share <= 8000 && share > 0 && share != profitShare);

		controller.updateProfitShare(aliceOwnerId, share, address(this));

		require(controller.getProfitShares(aliceOwnerId, address(this)) == share, "INVALID_PROFIT_SHARE");
	}

	function testUpdateProfitShareReverts(uint256 share) public {
		hevm.assume(share > 10000);

		hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
		controller.updateProfitShare(aliceOwnerId, share, address(this));
	}

	function testUpdateProfitShareRevertsWithSameRequirements() public {
		controller.updateProfitShare(aliceOwnerId, 0, address(this));

		hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
		controller.updateProfitShare(aliceOwnerId, profitShare, address(this));
	}

	function testUpdateAdminFee(uint256 fee) public {
		hevm.assume(fee <= 2000 && fee != adminFee);

		controller.updateAdminFee(fee);
	}

	function testUpdateAdminFeeReverts(uint256 fee) public {
		hevm.assume(fee > 2000 || fee == adminFee);

		if (fee == adminFee) {
			hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
			controller.updateAdminFee(fee);
		} else {
			hevm.prank(alice);
			hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
			controller.updateAdminFee(fee);

			hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
			controller.updateAdminFee(fee);
		}
	}

	function testBaseProfitShare(uint256 share) public {
		hevm.assume(share <= 8000 && share != profitShare && share > 0);

		controller.updateBaseProfitShare(share);
	}

	function testBaseProfitShareReverts(uint256 share) public {
		hevm.assume(share > 8000 || share == profitShare);

		if (share == profitShare) {
			hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
			controller.updateBaseProfitShare(profitShare);
		} else {
			hevm.prank(alice);
			hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
			controller.updateBaseProfitShare(share);

			hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
			controller.updateBaseProfitShare(share);

			hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
			controller.updateBaseProfitShare(0);
		}
	}

	function testUpdateLiquidityCap(uint256 cap) public {
		hevm.assume(cap > liquidityCap);

		uint256 previousCap = controller.liquidityCap();
		require(previousCap == liquidityCap, "INVALID_LIQUIDITY_CAP");

		controller.updateLiquidityCap(cap);
		require(cap == controller.liquidityCap(), "INVALID_LIQUIDITY_CAP");
	}

	function testUpdateLiquidityCapReverts(uint256 cap) public {
		hevm.assume(cap <= liquidityCap && cap != 0);

		hevm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
		controller.updateLiquidityCap(cap);
	}

	function testActivateWithdrawals() public {
		bool status = controller.withdrawalsActivated();
		require(status == withdrawalsActivated, "INVALID_WITHDRAWALS");

		controller.activateWithdrawals();
		require(controller.withdrawalsActivated(), "INVALID_WITHDRAWALS");
	}
}
