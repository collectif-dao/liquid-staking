import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import '@nomiclabs/hardhat-ethers';
import type { StorageProviderRegistry, LiquidStaking } from '../typechain-types';

const deployFunction: DeployFunction = async function ({ deployments, ethers }: HardhatRuntimeEnvironment) {
    const feeData = await ethers.provider.getFeeData();
    const overrides = {
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
        maxFeePerGas: feeData.maxFeePerGas,
    }

    const registry = await deployments.get('StorageProviderRegistry');
    const staking = await deployments.get('LiquidStaking');
    const collateral = await deployments.get('StorageProviderCollateral');

    const registryContract = await ethers.getContractAt<StorageProviderRegistry>("StorageProviderRegistry", registry.address);
    var receipt = await ((await registryContract.setCollateralAddress(collateral.address, overrides)).wait());
    receipt = await ((await registryContract.registerPool(staking.address, overrides)).wait());

    const stakingContract = await ethers.getContractAt<LiquidStaking>("LiquidStaking", staking.address);
    receipt = await ((await stakingContract.setCollateralAddress(collateral.address, overrides)).wait());
    receipt = await ((await stakingContract.setRegistryAddress(registry.address, overrides)).wait());
};

export default deployFunction;

deployFunction.dependencies = ['Collateral', 'LiquidStaking'];
deployFunction.tags = ['Integration'];