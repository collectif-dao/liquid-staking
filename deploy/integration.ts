import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import type { Resolver, StorageProviderRegistry } from "../typechain-types";

const deployFunction: DeployFunction = async function ({ deployments, ethers }: HardhatRuntimeEnvironment) {
	const feeData = await ethers.provider.getFeeData();
	const overrides = {
		maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
		maxFeePerGas: feeData.maxFeePerGas,
	};

	const registry = await deployments.get("StorageProviderRegistry");
	const staking = await deployments.get("LiquidStaking");
	const stakingController = await deployments.get("LiquidStakingController");
	const collateral = await deployments.get("StorageProviderCollateral");
	const beneficiaryManager = await deployments.get("BeneficiaryManager");
	const rewardCollector = await deployments.get("RewardCollector");

	const resolver = await deployments.get("Resolver");
	const resolverContract = await ethers.getContractAt<Resolver>("Resolver", resolver.address);

	var receipt = await (await resolverContract.setCollateralAddress(collateral.address, overrides)).wait();
	receipt = await (await resolverContract.setLiquidStakingControllerAddress(stakingController.address, overrides)).wait();
	receipt = await (await resolverContract.setRegistryAddress(registry.address, overrides)).wait();
	receipt = await (await resolverContract.setLiquidStakingAddress(staking.address, overrides)).wait();
	receipt = await (await resolverContract.setBeneficiaryManagerAddress(beneficiaryManager.address, overrides)).wait();
	receipt = await (await resolverContract.setRewardCollectorAddress(rewardCollector.address, overrides)).wait();

	const registryContract = await ethers.getContractAt<StorageProviderRegistry>("StorageProviderRegistry", registry.address);
	receipt = await (await registryContract.registerPool(staking.address, overrides)).wait();
};

export default deployFunction;

deployFunction.dependencies = [
	"StorageProviderCollateral",
	"LiquidStaking",
	"StorageProviderRegistry",
	"BeneficiaryManager",
	"RewardCollector",
	"LiquidStakingController",
];
deployFunction.tags = ["Integration"];
