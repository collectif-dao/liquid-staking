import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import '@nomiclabs/hardhat-ethers';
import { deployAndSaveContract } from "../utils";

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    await deployAndSaveContract('Resolver', [], hre);
};

export default deployFunction;

deployFunction.tags = ['Resolver'];