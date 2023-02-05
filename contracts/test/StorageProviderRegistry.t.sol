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

	bytes public owner = abi.encodePacked(address(this));
	bytes private oldMiner = bytes("f2rhhfmqyc4jqirwwangsi752ea2pllz425w4yupq");

	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant MIN_TIME_PERIOD = 90 days;
	uint256 private constant MAX_TIME_PERIOD = 360 days;

	function setUp() public {
		wfil = IWETH9(address(new WFIL()));
		staking = IERC4626(address(new MockERC4626(wfil, "Collective FIL Liquid Staking", "clFIL")));

		registry = new StorageProviderRegistryMock(
			owner,
			MAX_STORAGE_PROVIDERS,
			MAX_ALLOCATION,
			MIN_TIME_PERIOD,
			MAX_TIME_PERIOD
		);
	}

	function testRegister(bytes memory miner, uint256 allocation, uint256 period) public {
		hevm.assume(
			miner.length > 1 &&
				allocation != 0 &&
				allocation <= MAX_ALLOCATION &&
				period >= MIN_TIME_PERIOD &&
				period <= MAX_TIME_PERIOD
		);

		registry.register(miner, address(staking), allocation, period);

		(
			bool isActive,
			address targetPool,
			bytes memory minerActor,
			uint256 allocationLimit,
			uint256 usedAllocation,
			uint256 accruedRewards,
			uint256 lockedRewards,
			uint256 maxPeriod
		) = registry.getStorageProvider(owner);

		assertBoolEq(isActive, false);
		assertEq(targetPool, address(staking));
		assertEq0(miner, minerActor);
		assertEq(allocationLimit, allocation);
		assertEq(usedAllocation, 0);
		assertEq(accruedRewards, 0);
		assertEq(lockedRewards, 0);
		assertEq(maxPeriod, period + block.timestamp);
		assertEq(registry.getTotalActiveStorageProviders(), 0);
	}

	function testChangeBeneficiaryAddress(address miner) public {
		registry.register(abi.encodePacked(miner), address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);
		registry.changeBeneficiaryAddress(address(staking));

		(, address targetPool, , , , , , ) = registry.getStorageProvider(owner);

		assertEq(targetPool, address(staking));
	}

	function testChangeBeneficiaryAddressReverts(address miner, address beneficiary) public {
		hevm.assume(beneficiary != address(0) && beneficiary != address(staking) && miner != address(0));
		hevm.etch(beneficiary, bytes("0x102"));

		registry.register(abi.encodePacked(miner), address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		hevm.expectRevert("INVALID_ADDRESS");

		registry.changeBeneficiaryAddress(beneficiary);
	}

	function testAcceptBeneficiaryAddress(address miner) public {
		hevm.assume(miner != address(0));
		bytes memory minerAddress = abi.encodePacked(miner);

		registry.register(minerAddress, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);
		assertBoolEq(registry.isActiveProvider(owner), false);

		registry.acceptBeneficiaryAddress(owner, address(staking));

		assertBoolEq(registry.isActiveProvider(owner), true);
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

	function testDeactivateStorageProvider(address miner) public {
		hevm.assume(miner != address(0));
		bytes memory minerAddress = abi.encodePacked(miner);

		registry.register(minerAddress, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);
		registry.acceptBeneficiaryAddress(owner, address(staking));
		assertBoolEq(registry.isActiveProvider(owner), true);

		registry.deactivateStorageProvider(owner);
		assertBoolEq(registry.isActiveProvider(owner), false);
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

	function testSetMinerAddress(bytes memory newMiner) public {
		hevm.assume(newMiner.length > 1 && keccak256(newMiner) != keccak256(oldMiner));

		registry.register(oldMiner, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);
		registry.acceptBeneficiaryAddress(owner, address(staking));

		registry.setMinerAddress(owner, newMiner);
		(, , bytes memory minerAddress, , , , , ) = registry.getStorageProvider(owner);
		assertEq0(minerAddress, newMiner);
	}

	function testSetMinerAddressReverts(bytes memory newMiner) public {
		hevm.assume(newMiner.length > 1 && keccak256(newMiner) != keccak256(oldMiner));

		registry.register(oldMiner, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		hevm.expectRevert("INACTIVE_STORAGE_PROVIDER");
		registry.setMinerAddress(owner, newMiner);
	}

	function testSetAllocationLimit(uint256 allocation) public {
		hevm.assume(allocation < MAX_ALLOCATION);
		registry.register(oldMiner, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		registry.acceptBeneficiaryAddress(owner, address(staking));

		registry.setAllocationLimit(owner, allocation);
		(, , , uint256 allocationLimit, , , , ) = registry.getStorageProvider(owner);
		assertEq(allocationLimit, allocation);
	}

	function testSetAllocationLimitReverts(uint256 allocation) public {
		hevm.assume(allocation < MAX_ALLOCATION);
		registry.register(oldMiner, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);

		hevm.expectRevert("INACTIVE_STORAGE_PROVIDER");
		registry.setAllocationLimit(owner, allocation);
	}

	function testSetMaxRedeemablePeriod(uint256 period) public {
		hevm.assume(period > MIN_TIME_PERIOD && period < MAX_TIME_PERIOD);

		registry.register(oldMiner, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);
		registry.acceptBeneficiaryAddress(owner, address(staking));

		registry.setMaxRedeemablePeriod(owner, period);
		(, , , , , , , uint256 maxRedeemablePeriod) = registry.getStorageProvider(owner);
		assertEq(maxRedeemablePeriod, period + block.timestamp);
	}

	function testSetMaxRedeemablePeriodReverts(uint256 period) public {
		hevm.assume(period < MIN_TIME_PERIOD);

		registry.register(oldMiner, address(staking), MAX_ALLOCATION, MIN_TIME_PERIOD);
		registry.acceptBeneficiaryAddress(owner, address(staking));

		hevm.expectRevert("INVALID_PERIOD");
		registry.setMaxRedeemablePeriod(owner, period);
	}
}
