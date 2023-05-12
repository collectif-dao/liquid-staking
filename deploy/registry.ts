import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import '@nomiclabs/hardhat-ethers';
import { deployAndSaveContract } from "../utils";

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {  
    const { deployments, ethers } = hre;

    const resolver = await deployments.get('Resolver');
    const maxAllocation = ethers.utils.parseEther('1000000');

    await deployAndSaveContract('StorageProviderRegistry', [maxAllocation, resolver.address], hre);
};

export default deployFunction;

deployFunction.dependencies = ['Resolver'];
deployFunction.tags = ['StorageProviderRegistry'];