// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {WFIL} from "./mocks/WFIL.sol";
import {IWETH9, IERC4626} from "fei-protocol/erc4626/ERC4626RouterBase.sol";

import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";
import {Buffer} from "@ensdomains/buffer/contracts/Buffer.sol";
import {PrecompilesAPI} from "filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";

import {StorageProviderRegistryMock, StorageProviderRegistryCallerMock} from "./mocks/StorageProviderRegistryMock.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

contract StorageProviderRegistryTest is DSTestPlus {
	StorageProviderRegistryMock public registry;
	StorageProviderRegistryCallerMock public callerMock;

	IERC4626 public staking;
	IWETH9 public wfil;

	bytes public owner;
	uint64 public ownerId = 1508;
	uint64 private oldMinerId = 1648;

	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant MIN_TIME_PERIOD = 90 days;
	uint256 private constant MAX_TIME_PERIOD = 360 days;

	function setUp() public {
		Buffer.buffer memory ownerBytes = Leb128.encodeUnsignedLeb128FromUInt64(ownerId);
		owner = ownerBytes.buf;

		wfil = IWETH9(address(new WFIL()));
		staking = IERC4626(address(new MockERC4626(wfil, "Collective FIL Liquid Staking", "clFIL")));

		registry = new StorageProviderRegistryMock(
			owner,
			ownerId,
			MAX_STORAGE_PROVIDERS,
			MAX_ALLOCATION,
			MIN_TIME_PERIOD,
			MAX_TIME_PERIOD
		);
		callerMock = new StorageProviderRegistryCallerMock(address(registry));
	}

	function testRegister(uint64 minerId, uint256 allocation) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && allocation > 0 && allocation <= MAX_ALLOCATION);

		registry.register(minerId, address(staking), allocation);

		(
			bool isActive,
			address targetPool,
			uint64 minerActorId,
			uint256 allocationLimit,
			uint256 repayment,
			uint256 usedAllocation,
			uint256 accruedRewards,
			uint256 lockedRewards,
			int64 lastEpoch,
			uint256 restakingRatio
		) = registry.getStorageProvider(ownerId);

		assertBoolEq(isActive, false);
		assertEq(targetPool, address(staking));
		assertEq(minerId, minerActorId);
		assertEq(allocationLimit, allocation);
		assertEq(repayment, 0);
		assertEq(usedAllocation, 0);
		assertEq(accruedRewards, 0);
		assertEq(lockedRewards, 0);
		assertEq(lastEpoch, 0);
		assertEq(restakingRatio, 0);
		assertEq(registry.getTotalActiveStorageProviders(), 0);
		assertEq(registry.sectorSizes(ownerId), 34359738368);
	}

	function testOnboardStorageProvider(
		uint64 _minerId,
		uint256 _allocationLimit,
		uint256 _repayment,
		int64 _lastEpoch
	) public {
		hevm.assume(
			_minerId > 1 &&
				_minerId < 2115248121211227543 &&
				_repayment > _allocationLimit &&
				_allocationLimit < MAX_ALLOCATION &&
				_lastEpoch > 0
		);

		registry.register(_minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(_minerId, _allocationLimit, _repayment, _lastEpoch);

		(
			bool isActive,
			address targetPool,
			uint64 minerActorId,
			uint256 allocationLimit,
			uint256 repayment,
			uint256 usedAllocation,
			uint256 accruedRewards,
			uint256 lockedRewards,
			int64 lastEpoch,
			uint256 restakingRatio
		) = registry.getStorageProvider(ownerId);

		assertBoolEq(isActive, false);
		assertEq(targetPool, address(staking));
		assertEq(minerActorId, _minerId);
		assertEq(allocationLimit, _allocationLimit);
		assertEq(repayment, _repayment);
		assertEq(usedAllocation, 0);
		assertEq(accruedRewards, 0);
		assertEq(lockedRewards, 0);
		assertEq(lastEpoch, _lastEpoch);
		assertEq(restakingRatio, 0);
		assertEq(registry.getTotalActiveStorageProviders(), 0);
	}

	function testOnboardStorageProviderReverts(uint64 _minerId, uint256 _repayment, int64 _lastEpoch) public {
		hevm.assume(
			_minerId > 1 && _minerId < 2115248121211227543 && _repayment > (MAX_ALLOCATION * 2) && _lastEpoch > 0
		);

		registry.register(_minerId, address(staking), MAX_ALLOCATION);
		hevm.expectRevert("INCORRECT_ALLOCATION");
		registry.onboardStorageProvider(_minerId, MAX_ALLOCATION * 2, _repayment, _lastEpoch);
	}

	function testOnboardStorageProviderRevertsWithIncorrectRepayment(
		uint64 _minerId,
		uint256 _repayment,
		int64 _lastEpoch
	) public {
		hevm.assume(_minerId > 1 && _minerId < 2115248121211227543 && _repayment < MAX_ALLOCATION && _lastEpoch > 0);

		registry.register(_minerId, address(staking), MAX_ALLOCATION);
		hevm.expectRevert("INCORRECT_REPAYMENT");
		registry.onboardStorageProvider(_minerId, MAX_ALLOCATION, _repayment, _lastEpoch);
	}

	function testChangeBeneficiaryAddress(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);

		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);
		registry.changeBeneficiaryAddress(address(staking));

		(, address targetPool, , , , , , , , ) = registry.getStorageProvider(ownerId);

		assertEq(targetPool, address(staking));
	}

	function testChangeBeneficiaryAddressReverts(uint64 minerId, address beneficiary, int64 lastEpoch) public {
		hevm.assume(
			beneficiary != address(0) &&
				beneficiary != address(staking) &&
				minerId > 1 &&
				minerId < 2115248121211227543 &&
				lastEpoch > 0
		);
		hevm.etch(beneficiary, bytes("0x102"));

		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		hevm.expectRevert("INVALID_ADDRESS");
		registry.changeBeneficiaryAddress(beneficiary);
	}

	function testAcceptBeneficiaryAddress(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);

		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);
		assertBoolEq(registry.isActiveProvider(ownerId), false);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		assertBoolEq(registry.isActiveProvider(ownerId), true);
		assertEq(registry.getTotalActiveStorageProviders(), 1);
	}

	function testAcceptBeneficiaryAddressReverts(uint64 minerId, address provider, int64 lastEpoch) public {
		hevm.assume(
			provider != address(0) &&
				provider != address(this) &&
				lastEpoch > 0 &&
				minerId > 1 &&
				minerId < 2115248121211227543
		);

		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));

		hevm.prank(provider);
		hevm.expectRevert("INVALID_ACCESS");
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		assertBoolEq(registry.isActiveProvider(ownerId), false);
		assertEq(registry.getTotalActiveStorageProviders(), 0);
	}

	function testDeactivateStorageProvider(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);

		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));
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
		registry.register(minerId, address(staking), MAX_ALLOCATION);

		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		hevm.prank(provider);
		registry.changeBeneficiaryAddress(address(staking));

		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		hevm.prank(provider);
		hevm.expectRevert("INVALID_ACCESS");
		registry.deactivateStorageProvider(ownerId);
	}

	function testSetMinerAddress(uint64 newMinerId, int64 lastEpoch) public {
		hevm.assume(newMinerId > 1 && newMinerId < 2115248121211227543 && newMinerId != oldMinerId && lastEpoch > 0);

		registry.register(oldMinerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(newMinerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		registry.setMinerAddress(ownerId, newMinerId);
		(, , uint64 minerId, , , , , , , ) = registry.getStorageProvider(ownerId);
		assertEq(minerId, newMinerId);
	}

	function testSetMinerAddressReverts(uint64 newMinerId) public {
		hevm.assume(newMinerId > 1 && newMinerId < 2115248121211227543 && newMinerId != oldMinerId);

		registry.register(oldMinerId, address(staking), MAX_ALLOCATION);

		hevm.expectRevert("INACTIVE_STORAGE_PROVIDER");
		registry.setMinerAddress(ownerId, newMinerId);
	}

	function testSetMinerAddressRevertsWithSameMinerId(int64 lastEpoch) public {
		hevm.assume(lastEpoch > 0);
		uint64 newMinerId = oldMinerId;

		registry.register(oldMinerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(oldMinerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		hevm.expectRevert("SAME_MINER");
		registry.setMinerAddress(ownerId, newMinerId);
	}

	function testRequestAllocationLimitUpdate(uint64 minerId, uint256 allocation, int64 lastEpoch) public {
		hevm.assume(
			allocation < MAX_ALLOCATION &&
				allocation != MAX_ALLOCATION &&
				allocation > 0 &&
				minerId > 1 &&
				minerId < 2115248121211227543 &&
				lastEpoch > 0
		);
		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		registry.requestAllocationLimitUpdate(allocation);
	}

	function testRequestAllocationLimitUpdateReverts(uint64 minerId, uint256 allocation, int64 lastEpoch) public {
		hevm.assume(
			allocation < MAX_ALLOCATION &&
				allocation != MAX_ALLOCATION &&
				allocation > 0 &&
				minerId > 1 &&
				minerId < 2115248121211227543 &&
				lastEpoch > 0
		);
		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));

		hevm.expectRevert("INACTIVE_STORAGE_PROVIDER");
		registry.requestAllocationLimitUpdate(allocation);
	}

	function testRequestAllocationLimitUpdateRevertsWithSameAllocationLimit(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);
		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		hevm.expectRevert("SAME_ALLOCATION_LIMIT");
		registry.requestAllocationLimitUpdate(MAX_ALLOCATION);
	}

	function testRequestAllocationLimitUpdateRevertsWithOverflow(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);
		uint256 newAllocation = MAX_ALLOCATION + 1;
		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		hevm.expectRevert("ALLOCATION_OVERFLOW");
		registry.requestAllocationLimitUpdate(newAllocation);
	}

	function testUpdateAllocationLimit(uint64 minerId, uint256 allocation, int64 lastEpoch) public {
		hevm.assume(
			allocation < MAX_ALLOCATION &&
				allocation != MAX_ALLOCATION &&
				allocation > 0 &&
				minerId > 1 &&
				minerId < 2115248121211227543 &&
				lastEpoch > 0
		);
		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		registry.requestAllocationLimitUpdate(allocation);
		registry.updateAllocationLimit(ownerId, allocation);
	}

	function testUpdateAllocationLimitReverts(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);
		uint256 newAllocation = MAX_ALLOCATION - 10000;
		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		registry.requestAllocationLimitUpdate(newAllocation);

		hevm.expectRevert("INVALID_ALLOCATION");
		registry.updateAllocationLimit(ownerId, MAX_ALLOCATION);
	}

	function testSetRestakingRatio(uint64 minerId, uint256 restakingRatio, int64 lastEpoch) public {
		hevm.assume(
			minerId > 1 &&
				minerId < 2115248121211227543 &&
				restakingRatio > 0 &&
				restakingRatio < 10000 &&
				lastEpoch > 0
		);
		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		registry.setRestakingRatio(restakingRatio);

		(, , , , , , , , , uint256 ratio) = registry.getStorageProvider(ownerId);
		assertEq(ratio, restakingRatio);
	}

	function testSetRestakingRatioReverts(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);
		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		hevm.expectRevert("INVALID_RESTAKING_RATIO");
		registry.setRestakingRatio(15000);

		(, , , , , , , , , uint256 ratio) = registry.getStorageProvider(ownerId);
		assertEq(ratio, 0);
	}

	function testSetRestakingRatioRevertsWithSameRatio(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);
		uint256 restakingRatio = 1000;

		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		registry.setRestakingRatio(restakingRatio);

		hevm.expectRevert("SAME_RATIO");
		registry.setRestakingRatio(restakingRatio);

		(, , , , , , , , , uint256 ratio) = registry.getStorageProvider(ownerId);
		assertEq(ratio, restakingRatio);
	}

	function testCollateralAddress(address collateral) public {
		hevm.assume(collateral != address(0));
		hevm.etch(collateral, bytes("0x10378"));

		registry.setCollateralAddress(collateral);
	}

	function testCollateralAddressReverts(address collateral, address provider) public {
		hevm.assume(collateral != address(0) && provider != address(0) && provider != address(this));
		hevm.etch(collateral, bytes("0x103789851206015297"));

		hevm.prank(provider);
		hevm.expectRevert("INVALID_ACCESS");
		registry.setCollateralAddress(collateral);
	}

	function testRegisterPool(address pool) public {
		hevm.assume(pool != address(0));
		hevm.etch(pool, bytes("0x10148"));

		registry.registerPool(pool);
		assertBoolEq(registry.isActivePool(pool), true);
	}

	function testRegisterPoolReverts(address pool, address provider) public {
		hevm.assume(pool != address(0) && provider != address(0) && provider != address(this));
		hevm.etch(pool, bytes("0x10148851206015297"));

		hevm.prank(provider);
		hevm.expectRevert("INVALID_ACCESS");
		registry.registerPool(pool);
		assertBoolEq(registry.isActivePool(pool), false);
	}

	function testIncreaseRewards(uint64 minerId, uint256 _accruedRewards, int64 lastEpoch) public {
		hevm.assume(_accruedRewards > 0 && lastEpoch > 0 && minerId > 1 && minerId < 2115248121211227543);
		registry.registerPool(address(callerMock));

		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		callerMock.increaseRewards(ownerId, _accruedRewards, 0);

		(, , , , , , uint256 accruedRewards, , , ) = registry.getStorageProvider(ownerId);
		assertEq(accruedRewards, _accruedRewards);
	}

	function testIncreaseRewardsReverts(uint64 minerId, uint256 _accruedRewards, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && _accruedRewards > 0 && lastEpoch > 0);

		hevm.expectRevert("INVALID_ACCESS");
		callerMock.increaseRewards(ownerId, _accruedRewards, 0);

		(, , , , , , uint256 accruedRewards, , , ) = registry.getStorageProvider(ownerId);
		assertEq(accruedRewards, 0);
	}

	function testIncreaseUsedAllocation(uint64 minerId, uint256 allocated, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0 && allocated > 0);
		registry.setCollateralAddress(address(callerMock));

		registry.register(minerId, address(staking), MAX_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, MAX_ALLOCATION + 10, lastEpoch);

		registry.changeBeneficiaryAddress(address(staking));
		registry.acceptBeneficiaryAddress(ownerId, address(staking));

		callerMock.increaseUsedAllocation(ownerId, allocated);

		(, , , , , uint256 usedAllocation, , , , ) = registry.getStorageProvider(ownerId);
		assertEq(usedAllocation, allocated);
	}

	function testIncreaseUsedAllocationReverts(uint64 minerId, uint256 allocated, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0 && allocated > 0);

		hevm.expectRevert("INVALID_ACCESS");
		callerMock.increaseUsedAllocation(ownerId, allocated);

		(, , , , , uint256 usedAllocation, , , , ) = registry.getStorageProvider(ownerId);
		assertEq(usedAllocation, 0);
	}
}
