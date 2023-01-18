// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {WFIL} from "./mocks/WFIL.sol";
import {IWETH9, IERC4626} from "fei-protocol/erc4626/ERC4626RouterBase.sol";

import {StorageProviderRegistryMock} from "./mocks/StorageProviderRegistryMock.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

contract StorageProviderRegistryTest is DSTestPlus {
	StorageProviderRegistryMock public registry;
	IERC4626 public staking;
	IWETH9 public wfil;

	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant MIN_TIME_PERIOD = 90 days;
	uint256 private constant MAX_TIME_PERIOD = 360 days;

	function setUp() public {
		wfil = IWETH9(address(new WFIL()));
		staking = IERC4626(address(new MockERC4626(wfil, "Collective FIL Liquid Staking", "clFIL")));

		registry = new StorageProviderRegistryMock(
			abi.encodePacked(msg.sender),
			MAX_STORAGE_PROVIDERS,
			MAX_ALLOCATION,
			MIN_TIME_PERIOD,
			MAX_TIME_PERIOD
		);
	}

	function testRegister(address workerAddress, uint256 allocation, uint256 period) public {
		hevm.assume(
			workerAddress != address(0) &&
				allocation != 0 &&
				allocation <= MAX_ALLOCATION &&
				period >= MIN_TIME_PERIOD &&
				period <= MAX_TIME_PERIOD
		);

		registry.register(workerAddress, address(staking), allocation, period);

		(
			bool isActive,
			address targetPool,
			address worker,
			uint256 allocationLimit,
			uint256 usedAllocation,
			uint256 accruedRewards,
			uint256 lockedRewards,
			uint256 maxPeriod
		) = registry.getStorageProvider(address(this));

		assertBoolEq(isActive, false);
		assertEq(targetPool, address(staking));
		assertEq(worker, workerAddress);
		assertEq(allocationLimit, allocation);
		assertEq(usedAllocation, 0);
		assertEq(accruedRewards, 0);
		assertEq(lockedRewards, 0);
		assertEq(maxPeriod, period + block.timestamp);
		assertEq(registry.getTotalActiveStorageProviders(), 0);
	}

	function testChangeBeneficiaryAddress() public {
		registry.register(address(0x11), address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		bytes memory target = abi.encodePacked(address(staking));
		registry.changeBeneficiaryAddress(target);

		(, address targetPool, , , , , , ) = registry.getStorageProvider(address(this));

		assertEq(targetPool, address(staking));
	}

	function testChangeBeneficiaryAddressReverts(address beneficiary) public {
		hevm.assume(beneficiary != address(0) && beneficiary != address(staking));
		hevm.etch(beneficiary, bytes("0x102"));

		registry.register(address(0x11), address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		hevm.expectRevert("INVALID_ADDRESS");

		bytes memory target = abi.encodePacked(beneficiary);
		registry.changeBeneficiaryAddress(target);
	}

	function testAcceptBeneficiaryAddress(address provider) public {
		hevm.assume(provider != address(0));
		hevm.prank(provider);

		registry.register(provider, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);
		assertBoolEq(registry.isActiveProvider(provider), false);

		bytes memory target = abi.encodePacked(provider);
		bytes memory benefiticiaryTarget = abi.encodePacked(address(staking));
		registry.acceptBeneficiaryAddress(target, benefiticiaryTarget);

		assertBoolEq(registry.isActiveProvider(provider), true);

		assertEq(registry.getTotalActiveStorageProviders(), 1);
	}

	// function testAcceptBeneficiaryAddressReverts(address provider) public {
	// 	hevm.assume(provider != address(0) && provider != address(this));

	// 	registry.register(provider, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

	// 	hevm.prank(provider);
	// 	hevm.expectRevert("Ownable: caller is not the owner");

	// 	bytes memory target = abi.encodePacked(provider);
	// 	bytes memory benefiticiaryTarget = abi.encodePacked(address(staking));
	// 	registry.acceptBeneficiaryAddress(target, benefiticiaryTarget);

	// 	assertBoolEq(registry.isActiveProvider(provider), false);
	// 	assertEq(registry.getTotalActiveStorageProviders(), 0);
	// }

	function testDeactivateStorageProvider(address provider) public {
		hevm.assume(provider != address(0));
		hevm.prank(provider);

		registry.register(provider, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		bytes memory target = abi.encodePacked(provider);
		bytes memory benefiticiaryTarget = abi.encodePacked(address(staking));
		registry.acceptBeneficiaryAddress(target, benefiticiaryTarget);

		registry.deactivateStorageProvider(provider);
		assertBoolEq(registry.isActiveProvider(provider), false);
	}

	// function testDeactivateStorageProviderReverts(address provider) public {
	// 	hevm.assume(provider != address(0) && provider != address(this));
	// 	hevm.prank(provider);

	// 	registry.register(provider, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

	// 	bytes memory target = abi.encodePacked(provider);
	// 	bytes memory benefiticiaryTarget = abi.encodePacked(address(staking));
	// 	registry.acceptBeneficiaryAddress(target, benefiticiaryTarget);

	// 	hevm.prank(provider);
	// 	hevm.expectRevert("Ownable: caller is not the owner");
	// 	registry.deactivateStorageProvider(provider);
	// }

	function testSetWorketAddress(address provider, address worker) public {
		hevm.assume(provider != address(0) && worker != address(0) && worker != provider);
		hevm.prank(provider);

		registry.register(provider, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		bytes memory target = abi.encodePacked(provider);
		bytes memory benefiticiaryTarget = abi.encodePacked(address(staking));
		registry.acceptBeneficiaryAddress(target, benefiticiaryTarget);

		registry.setWorkerAddress(provider, worker);
		(, , address workerAddress, , , , , ) = registry.getStorageProvider(provider);
		assertEq(workerAddress, worker);
	}

	function testSetWorketAddressReverts(address provider, address worker) public {
		hevm.assume(provider != address(0) && worker != address(0) && worker != provider);
		hevm.prank(provider);

		registry.register(provider, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		hevm.expectRevert("INACTIVE_STORAGE_PROVIDER");
		registry.setWorkerAddress(provider, worker);
	}

	function testSetAllocationLimit(address provider, uint256 allocation) public {
		hevm.assume(provider != address(0) && allocation < MAX_ALLOCATION);
		hevm.prank(provider);

		registry.register(provider, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		bytes memory target = abi.encodePacked(provider);
		bytes memory benefiticiaryTarget = abi.encodePacked(address(staking));
		registry.acceptBeneficiaryAddress(target, benefiticiaryTarget);

		registry.setAllocationLimit(provider, allocation);
		(, , , uint256 allocationLimit, , , , ) = registry.getStorageProvider(provider);
		assertEq(allocationLimit, allocation);
	}

	function testSetAllocationLimitReverts(address provider, uint256 allocation) public {
		hevm.assume(provider != address(0) && allocation < MAX_ALLOCATION);
		hevm.prank(provider);

		registry.register(provider, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		hevm.expectRevert("INACTIVE_STORAGE_PROVIDER");
		registry.setAllocationLimit(provider, allocation);
	}

	function testSetMaxRedeemablePeriod(address provider, uint256 period) public {
		hevm.assume(provider != address(0) && period > MIN_TIME_PERIOD && period < MAX_TIME_PERIOD);
		hevm.prank(provider);

		registry.register(provider, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		bytes memory target = abi.encodePacked(provider);
		bytes memory benefiticiaryTarget = abi.encodePacked(address(staking));
		registry.acceptBeneficiaryAddress(target, benefiticiaryTarget);

		registry.setMaxRedeemablePeriod(provider, period);
		(, , , , , , , uint256 maxRedeemablePeriod) = registry.getStorageProvider(provider);
		assertEq(maxRedeemablePeriod, period + block.timestamp);
	}

	function testSetMaxRedeemablePeriodReverts(address provider, uint256 period) public {
		hevm.assume(provider != address(0) && period < MIN_TIME_PERIOD);
		hevm.prank(provider);

		registry.register(provider, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		bytes memory target = abi.encodePacked(provider);
		bytes memory benefiticiaryTarget = abi.encodePacked(address(staking));
		registry.acceptBeneficiaryAddress(target, benefiticiaryTarget);

		hevm.expectRevert("INVALID_PERIOD");
		registry.setMaxRedeemablePeriod(provider, period);
	}
}
