import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import '@nomiclabs/hardhat-ethers';

const deployFunction: DeployFunction = async function ({ deployments, getNamedAccounts, ethers }: HardhatRuntimeEnvironment) {
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;
    const feeData = await ethers.provider.getFeeData();
    const chainId = await ethers.provider.getNetwork();
    let wFIL;

    const baseRequirements = 2725;
    
    if (chainId.chainId == 31337 || chainId.chainId === 31415926) {
        wFIL = (await deployments.get('WFIL')).address;
    } else if (chainId.chainId == 3141) {
        wFIL = "0x6C297AeD654816dc5d211c956DE816Ba923475D2";
    } // TODO: add calibration and mainnet versions of WFIL

    const registry = await deployments.get('StorageProviderRegistry');

    // StorageProviderCollateral deployment
    const collateral = await deploy('StorageProviderCollateral', {
        from: deployer,
        deterministicDeployment: false,
        skipIfAlreadyDeployed: true,
        args: [wFIL, registry.address, baseRequirements],
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
        maxFeePerGas: feeData.maxFeePerGas,
    })

    console.log("StorageProviderCollateral Address--->" + collateral.address)
};

export default deployFunction;

deployFunction.dependencies = ['Registry', 'WFIL'];
deployFunction.tags = ['Collateral'];