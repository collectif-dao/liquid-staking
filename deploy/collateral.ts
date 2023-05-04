import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import '@nomiclabs/hardhat-ethers';

const deployFunction: DeployFunction = async function ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) {
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;

    const baseRequirements = 2725;

    const wFIL = await deployments.get('WFIL');
    const registry = await deployments.get('StorageProviderRegistry');

    // StorageProviderCollateral deployment
    const collateral = await deploy('StorageProviderCollateral', {
        from: deployer,
        deterministicDeployment: false,
        args: [wFIL.address, registry.address, baseRequirements],
    })

    console.log("StorageProviderCollateral Address--->" + collateral.address)
};

export default deployFunction;

deployFunction.dependencies = ['Registry', 'WFIL'];
deployFunction.tags = ['Collateral'];