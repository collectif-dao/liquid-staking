import { Contract, ContractFactory } from "ethers";
import { DeploymentsExtension } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export const getWFIL = async (chainId: number, deployments: DeploymentsExtension): Promise<string> => {
	let wFIL;

	if (chainId == 31337 || chainId === 31415926) {
		wFIL = (await deployments.get("WFIL")).address;
	} else if (chainId == 314159) {
		return "0xaC26a4Ab9cF2A8c5DBaB6fb4351ec0F4b07356c4";
	} else if (chainId == 314) {
		return "0x60E1773636CF5E4A227d9AC24F20fEca034ee25A";
	}

	return wFIL;
};

export const deployAndSaveContract = async (name: string, args: unknown[], hre: HardhatRuntimeEnvironment): Promise<void> => {
	const { ethers, deployments, upgrades } = hre;
	const { save } = deployments;
	const chainId = await ethers.provider.getNetwork();
	const feeData = await ethers.provider.getFeeData();

	let Factory: ContractFactory;

	Factory = await ethers.getContractFactory(name);

	let contract: Contract;

	contract = await upgrades.deployProxy(Factory, args, {
		initializer: "initialize",
		unsafeAllow: ["delegatecall"],
		kind: "uups",
		timeout: 1000000,
	});
	await contract.deployed();

	console.log(name + " Address---> " + contract.address);

	const implAddr = await contract.getImplementation();
	console.log("Implementation address for " + name + " is " + implAddr);

	const artifact = await deployments.getExtendedArtifact(name);
	let proxyDeployments = {
		address: contract.address,
		...artifact,
	};

	await save(name, proxyDeployments);
};
