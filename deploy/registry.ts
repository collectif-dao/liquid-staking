import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import '@nomiclabs/hardhat-ethers';

const deployFunction: DeployFunction = async function ({ deployments, getNamedAccounts, ethers, network }: HardhatRuntimeEnvironment) {
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;
    const feeData = await ethers.provider.getFeeData();

    const maxAllocation = ethers.BigNumber.from("1000000000000000000000000");

    // StorageProviderRegistry deployment
    const registry = await deploy('StorageProviderRegistry', {
        from: deployer,
        deterministicDeployment: false,
        skipIfAlreadyDeployed: true,
        args: [maxAllocation],
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
        maxFeePerGas: feeData.maxFeePerGas,
    })

    console.log("StorageProviderRegistry Address--->" + registry.address)
};

export default deployFunction;

// deployFunction.dependencies = ['LiquidStaking'];
deployFunction.tags = ['Registry'];