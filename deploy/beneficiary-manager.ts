import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import '@nomiclabs/hardhat-ethers';
import { deployAndSaveContract } from "../utils";

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const resolver = await hre.deployments.get('Resolver');
    await deployAndSaveContract('BeneficiaryManager', [resolver.address], hre);
};

export default deployFunction;

deployFunction.tags = ['BeneficiaryManager'];
deployFunction.dependencies = ['Resolver'];
