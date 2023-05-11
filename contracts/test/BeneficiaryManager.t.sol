// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Buffer} from "@ensdomains/buffer/contracts/Buffer.sol";
import {MinerMockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {Resolver} from "../Resolver.sol";
import {BeneficiaryManagerMock} from "./mocks/BeneficiaryManagerMock.sol";
import {LiquidStakingMock, LiquidStakingCallerMock} from "./mocks/LiquidStakingMock.sol";
import {StorageProviderRegistryMock} from "./mocks/StorageProviderRegistryMock.sol";
import {StorageProviderCollateralMock} from "./mocks/StorageProviderCollateralMock.sol";
import {LiquidStakingController} from "../LiquidStakingController.sol";

import {WFIL} from "fevmate/token/WFIL.sol";
import {IWFIL} from "../libraries/tokens/IWFIL.sol";
import {MinerTypes} from "filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import {BigInts} from "filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";
import {ERC1967Proxy} from "@oz/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {BigIntsClient} from "../libraries/BigInts.sol";

contract BeneficiaryManagerTest is DSTestPlus {
	BeneficiaryManagerMock public beneficiaryManager;
	Resolver public resolver;
	StorageProviderRegistryMock public registry;
	LiquidStakingMock public staking;
	IWFIL public wfil;
	BigIntsClient private bigIntsLib;
	LiquidStakingCallerMock private stakingCaller;
	StorageProviderCollateralMock public collateral;
	LiquidStakingController public controller;

	uint64 public aliceOwnerId = 1508;
	address private aliceOwnerAddr = address(0x12341214212);
	bytes public owner;

	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant SAMPLE_DAILY_ALLOCATION = MAX_ALLOCATION / 30;
	uint256 private constant repayment = MAX_ALLOCATION + 10;

	uint256 private adminFee = 1000;
	uint256 private profitShare = 2000;
	address private rewardCollector = address(0x12523);

	MinerMockAPI private minerMockAPI;

	function setUp() public {
		Buffer.buffer memory ownerBytes = Leb128.encodeUnsignedLeb128FromUInt64(aliceOwnerId);
		owner = ownerBytes.buf;

		wfil = IWFIL(address(new WFIL(msg.sender)));

		minerMockAPI = new MinerMockAPI(owner);
		bigIntsLib = new BigIntsClient();

		Resolver resolverImpl = new Resolver();
		ERC1967Proxy resolverProxy = new ERC1967Proxy(address(resolverImpl), "");
		resolver = Resolver(address(resolverProxy));
		resolver.initialize();

		BeneficiaryManagerMock bManagerImpl = new BeneficiaryManagerMock();
		ERC1967Proxy bManagerProxy = new ERC1967Proxy(address(bManagerImpl), "");
		beneficiaryManager = BeneficiaryManagerMock(address(bManagerProxy));
		beneficiaryManager.initialize(address(minerMockAPI), aliceOwnerId, address(resolver));

		LiquidStakingController controllerImpl = new LiquidStakingController();
		ERC1967Proxy controllerProxy = new ERC1967Proxy(address(controllerImpl), "");
		controller = LiquidStakingController(address(controllerProxy));
		controller.initialize(adminFee, profitShare, rewardCollector, address(resolver));

		LiquidStakingMock stakingImpl = new LiquidStakingMock();
		ERC1967Proxy stakingProxy = new ERC1967Proxy(address(stakingImpl), "");
		staking = LiquidStakingMock(payable(stakingProxy));
		staking.initialize(
			address(wfil),
			address(0x21421),
			aliceOwnerId,
			aliceOwnerAddr,
			address(minerMockAPI),
			address(bigIntsLib),
			address(resolver)
		);

		stakingCaller = new LiquidStakingCallerMock(address(staking));

		StorageProviderRegistryMock registryImpl = new StorageProviderRegistryMock();
		ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), "");
		registry = StorageProviderRegistryMock(address(registryProxy));
		registry.initialize(address(minerMockAPI), aliceOwnerId, MAX_ALLOCATION, address(resolver));

		StorageProviderCollateralMock collateralImpl = new StorageProviderCollateralMock();
		ERC1967Proxy collateralProxy = new ERC1967Proxy(address(collateralImpl), "");
		collateral = StorageProviderCollateralMock(payable(collateralProxy));
		collateral.initialize(wfil, address(resolver), 1500);

		resolver.setBeneficiaryManagerAddress(address(beneficiaryManager));
		resolver.setRegistryAddress(address(registry));
		resolver.setLiquidStakingAddress(address(staking));
		registry.registerPool(address(staking));
		resolver.setLiquidStakingControllerAddress(address(controller));
		resolver.setCollateralAddress(address(collateral));
	}

	function testChangeBeneficiaryAddress(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);

		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION, repayment, lastEpoch);
		beneficiaryManager.changeBeneficiaryAddress();

		(, address targetPool, , ) = registry.getStorageProvider(aliceOwnerId);
		assertEq(targetPool, address(staking));

		MinerTypes.GetBeneficiaryReturn memory beneficiary = minerMockAPI.getBeneficiary();
		(uint256 quota, bool err) = BigInts.toUint256(beneficiary.active.term.quota);
		require(!err, "INVALID_BIG_INT");
		require(quota == repayment, "INVALID_BENEFICIARY_QUOTA");
	}

	function testChangeBeneficiaryAddressReverts(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);
		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);

		hevm.expectRevert(abi.encodeWithSignature("InactiveSP()"));
		beneficiaryManager.changeBeneficiaryAddress();
	}

	function testForwardChangeBeneficiary(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);

		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION, repayment, lastEpoch);
		beneficiaryManager.changeBeneficiaryAddress();

		(, address targetPool, , ) = registry.getStorageProvider(aliceOwnerId);
		assertEq(targetPool, address(staking));

		resolver.setRegistryAddress(address(stakingCaller)); // bypassing the registry address checks
		stakingCaller.forwardChangeBeneficiary(minerId, targetPool, repayment, lastEpoch);

		MinerTypes.GetBeneficiaryReturn memory beneficiary = minerMockAPI.getBeneficiary();
		(uint256 quota, bool err) = BigInts.toUint256(beneficiary.active.term.quota);
		require(!err, "INVALID_BIG_INT");
		require(quota == repayment, "INVALID_BENEFICIARY_QUOTA");
	}

	function testForwardChangeBeneficiaryReverts(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);

		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION, repayment, lastEpoch);
		beneficiaryManager.changeBeneficiaryAddress();

		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		stakingCaller.forwardChangeBeneficiary(minerId, address(staking), repayment, lastEpoch);
	}

	function testForwardChangeBeneficiaryRevertsWithDirectCall(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);

		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION, repayment, lastEpoch);
		beneficiaryManager.changeBeneficiaryAddress();

		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		beneficiaryManager.forwardChangeBeneficiary(minerId, address(staking), repayment, lastEpoch);
	}

	function testForwardChangeBeneficiaryRevertsWithInvalidStakingAddress(uint64 minerId, int64 lastEpoch) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543 && lastEpoch > 0);

		registry.register(minerId, address(staking), MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION);
		registry.onboardStorageProvider(minerId, MAX_ALLOCATION, SAMPLE_DAILY_ALLOCATION, repayment, lastEpoch);
		beneficiaryManager.changeBeneficiaryAddress();

		resolver.setRegistryAddress(address(stakingCaller)); // bypassing the registry address checks

		hevm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
		stakingCaller.forwardChangeBeneficiary(minerId, address(this), repayment, lastEpoch);
	}
}
