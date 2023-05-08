import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import '@nomiclabs/hardhat-ethers';

const deployFunction: DeployFunction = async function ({ deployments, getNamedAccounts, ethers, upgrades }: HardhatRuntimeEnvironment) {
    const { deployer } = await getNamedAccounts();
    const { save } = deployments;
    const feeData = await ethers.provider.getFeeData();
    const chainId = await ethers.provider.getNetwork();
    let wFIL;

    const baseRequirements = 2725;
    
    if (chainId.chainId == 31337) {
        wFIL = (await deployments.get('WFIL')).address;
    } else if (chainId.chainId == 3141) {
        wFIL = "0x6C297AeD654816dc5d211c956DE816Ba923475D2";
    } // TODO: add calibration and mainnet versions of WFIL

    const registry = await deployments.get('StorageProviderRegistry');

    const provider = new ethers.providers.FallbackProvider([ethers.provider], 1);
    provider.getFeeData = async () => feeData;
    const signer = new ethers.Wallet(process.env.PRIVATE_KEY).connect(provider);

    const StorageProviderCollateralFactory = await ethers.getContractFactory("StorageProviderCollateral", signer);
    
    // StorageProviderCollateral deployment
    const collateral = await upgrades.deployProxy(StorageProviderCollateralFactory, [wFIL, registry.address, baseRequirements], {
        initializer: 'initialize',
        unsafeAllow: ['delegatecall'],
        kind: 'uups',
    });
    await collateral.deployed();

    console.log("StorageProviderCollateral Address--->" + collateral.address)
    console.log('version: ' + await collateral.functions.version());

    const artifact = await deployments.getExtendedArtifact('StorageProviderCollateral');
    let proxyDeployments = {
        address: collateral.address,
        ...artifact
    }

    await save('StorageProviderCollateral', proxyDeployments);

    // const collateral = await deploy('StorageProviderCollateral', {
    //     from: deployer,
    //     deterministicDeployment: false,
    //     skipIfAlreadyDeployed: true,
    //     args: [wFIL, registry.address, baseRequirements],
    //     maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
    //     maxFeePerGas: feeData.maxFeePerGas,
    // })
};

export default deployFunction;

deployFunction.dependencies = ['Registry', 'WFIL'];
deployFunction.tags = ['Collateral'];