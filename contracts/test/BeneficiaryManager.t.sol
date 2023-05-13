// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Buffer} from "@ensdomains/buffer/contracts/Buffer.sol";
import {MinerMockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {Resolver} from "../Resolver.sol";
import {BeneficiaryManagerMock, BeneficiaryManagerCallerMock} from "./mocks/BeneficiaryManagerMock.sol";
import {LiquidStakingMock} from "./mocks/LiquidStakingMock.sol";
import {RewardCollectorMock} from "./mocks/RewardCollectorMock.sol";
import {StorageProviderRegistryMock} from "./mocks/StorageProviderRegistryMock.sol";
import {StorageProviderCollateralMock} from "./mocks/StorageProviderCollateralMock.sol";
import {LiquidStakingController} from "../LiquidStakingController.sol";
import {MinerActorMock} from "./mocks/MinerActorMock.sol";

import {WFIL} from "fevmate/token/WFIL.sol";
import {IWFIL} from "../libraries/tokens/IWFIL.sol";
import {MinerTypes} from "filecoin-solidity/contracts/v0.8/types/MinerTypes.sol";
import {BigInts} from "filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";
import {ERC1967Proxy} from "@oz/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

contract BeneficiaryManagerTest is DSTestPlus {
	BeneficiaryManagerMock public beneficiaryManager;
	BeneficiaryManagerCallerMock public bManagerCaller;
	Resolver public resolver;
	StorageProviderRegistryMock public registry;
	LiquidStakingMock public staking;
	IWFIL public wfil;
	StorageProviderCollateralMock public collateral;
	RewardCollectorMock private rewardCollector;
	LiquidStakingController public controller;
	MinerActorMock public minerActor;
	MinerMockAPI private minerMockAPI;

	uint64 public aliceOwnerId = 1508;
	address private aliceOwnerAddr = address(0x12341214212);
	bytes public owner;

	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant SAMPLE_DAILY_ALLOCATION = MAX_ALLOCATION / 30;
	uint256 private constant repayment = MAX_ALLOCATION + 10;

	uint256 private adminFee = 1000;
	uint256 private profitShare = 2000;

	function setUp() public {
		Buffer.buffer memory ownerBytes = Leb128.encodeUnsignedLeb128FromUInt64(aliceOwnerId);
		owner = ownerBytes.buf;

		wfil = IWFIL(address(new WFIL(msg.sender)));

		minerMockAPI = new MinerMockAPI(owner);
		minerActor = new MinerActorMock();

		Resolver resolverImpl = new Resolver();
		ERC1967Proxy resolverProxy = new ERC1967Proxy(address(resolverImpl), "");
		resolver = Resolver(address(resolverProxy));
		resolver.initialize();

		BeneficiaryManagerMock bManagerImpl = new BeneficiaryManagerMock();
		ERC1967Proxy bManagerProxy = new ERC1967Proxy(address(bManagerImpl), "");
		beneficiaryManager = BeneficiaryManagerMock(address(bManagerProxy));
		beneficiaryManager.initialize(address(minerMockAPI), aliceOwnerId, address(resolver));

		bManagerCaller = new BeneficiaryManagerCallerMock(address(beneficiaryManager));

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
		resolver.setRewardCollectorAddress(address(rewardCollector));
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

	function testUpdateBeneficiaryStatus(uint64 minerId) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543);

		resolver.setRegistryAddress(address(bManagerCaller));
		bManagerCaller.updateBeneficiaryStatus(minerId, true);

		resolver.setRewardCollectorAddress(address(bManagerCaller));
		bManagerCaller.updateBeneficiaryStatus(minerId, false);
	}

	function testUpdateBeneficiaryStatusReverts(uint64 minerId) public {
		hevm.assume(minerId > 1 && minerId < 2115248121211227543);

		hevm.expectRevert(abi.encodeWithSignature("InvalidAccess()"));
		bManagerCaller.updateBeneficiaryStatus(minerId, true);
	}
}
