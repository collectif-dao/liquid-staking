import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunction: DeployFunction = async function ({ deployments, getNamedAccounts, ethers }: HardhatRuntimeEnvironment) {
	console.log('deploy function running');
	const { deployer } = await getNamedAccounts();
	const { deploy } = deployments;
	const feeData = await ethers.provider.getFeeData();

	const { address, newlyDeployed } = await deploy("Storage", {
		from: deployer,
		args: [deployer],
		maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
		maxFeePerGas: feeData.maxFeePerGas,
	});

	console.log("Storage Address---> " + address);
};

export default deployFunction;

deployFunction.tags = ["Storage"];

deployFunction.skip = ({ getChainId }) =>
	new Promise(async (resolve, reject) => {
		try {
			const chainId = await getChainId();
			resolve(chainId !== "31337" && chainId !== "31415926");
		} catch (error) {
			reject(error);
		}
	});
