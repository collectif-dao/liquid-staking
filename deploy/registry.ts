import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import '@nomiclabs/hardhat-ethers';
import * as dotenv from 'dotenv';

const deployFunction: DeployFunction = async function ({ deployments, getNamedAccounts, ethers, upgrades }: HardhatRuntimeEnvironment) {
    const { deployer } = await getNamedAccounts();
    const { save } = deployments;
    const feeData = await ethers.provider.getFeeData();
    const maxAllocation = ethers.BigNumber.from("1000000000000000000000000");

    const provider = new ethers.providers.FallbackProvider([ethers.provider], 1);
    provider.getFeeData = async () => feeData;
    const signer = new ethers.Wallet(process.env.PRIVATE_KEY).connect(provider);

    const RegistryFactory = await ethers.getContractFactory('StorageProviderRegistry', signer);

    // StorageProviderRegistry deployment
    const registry = await upgrades.deployProxy(RegistryFactory, [maxAllocation], {
        initializer: 'initialize',
        unsafeAllow: ['delegatecall'],
        kind: 'uups',
    });
    await registry.deployed();

    console.log("StorageProviderRegistry Address--->" + registry.address)
    console.log('version: ' + await registry.functions.version());

    const artifact = await deployments.getExtendedArtifact('StorageProviderRegistry');
    let proxyDeployments = {
        address: registry.address,
        ...artifact
    }

    await save('StorageProviderRegistry', proxyDeployments);
};

export default deployFunction;

// deployFunction.dependencies = ['LiquidStaking'];
deployFunction.tags = ['Registry'];