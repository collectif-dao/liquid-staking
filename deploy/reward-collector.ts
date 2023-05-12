import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import '@nomiclabs/hardhat-ethers';
import { deployAndSaveContract, getWFIL } from '../utils';

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, ethers } = hre;

    const chainId = await ethers.provider.getNetwork();
    const wFIL = await getWFIL(chainId.chainId, deployments);

    const resolver = await deployments.get('Resolver');

    await deployAndSaveContract('RewardCollector', [wFIL, resolver.address], hre);
};

export default deployFunction;

deployFunction.tags = ['RewardCollector'];
deployFunction.dependencies = ['Resolver', 'WFIL'];
