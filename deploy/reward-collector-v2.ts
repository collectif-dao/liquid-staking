import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import { Contract, ContractFactory } from "ethers";
import { RewardCollector } from "../typechain-types";

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
	console.log("Reward collector upgrade");
	const { deployments, ethers, upgrades } = hre;

	let Factory: ContractFactory;
	Factory = await ethers.getContractFactory("RewardCollectorV2");

	let contract: Contract;

	const rewardCollector = await deployments.get("RewardCollector");
	const rcContract = await ethers.getContractAt<RewardCollector>("RewardCollector", rewardCollector.address);

	let version = await rcContract.version();
	console.log(version);

	contract = await upgrades.upgradeProxy(rewardCollector.address, Factory, {
		unsafeAllow: ["delegatecall"],
	});
	await contract.deployed();

	console.log("RewardCollector Address---> " + contract.address);

	const implAddr = await contract.getImplementation();

	console.log("Implementation address for RewardCollectorV2 is " + implAddr);

	version = await rcContract.version();
	console.log(version);
};

export default deployFunction;

deployFunction.tags = ["RewardCollectorV2"];
deployFunction.dependencies = [
	"Resolver",
	"WFIL",
	"RewardCollector",
	"Integration",
	"StorageProviderCollateral",
	"LiquidStaking",
	"StorageProviderRegistry",
	"LiquidStakingController",
];
