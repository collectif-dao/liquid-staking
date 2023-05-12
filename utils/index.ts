import { DeploymentsExtension } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export const getWFIL = async (chainId: number, deployments: DeploymentsExtension):Promise<string> => {
    let wFIL;

    if (chainId == 31337 || chainId === 31415926) {
        wFIL = (await deployments.get('WFIL')).address;
    } else if (chainId == 3141) {
        return "0x6C297AeD654816dc5d211c956DE816Ba923475D2";
    }

    return wFIL;
}

export const deployAndSaveContract = async (name: string, args: unknown[], hre: HardhatRuntimeEnvironment):Promise<void> => {
    const { ethers, deployments, upgrades } = hre;
    const { save } = deployments;
    const chainId = await ethers.provider.getNetwork();
    const feeData = await ethers.provider.getFeeData();

    let Factory;

    if (chainId.chainId == 31337) {
        Factory = await ethers.getContractFactory(name);
    } else {
        const provider = new ethers.providers.FallbackProvider([ethers.provider], 1);
        provider.getFeeData = async () => feeData;
        const signer = new ethers.Wallet(process.env.PRIVATE_KEY).connect(provider);
    
        Factory = await ethers.getContractFactory(name, signer);
    }

    const contract = await upgrades.deployProxy(Factory, args, {
        initializer: 'initialize',
        unsafeAllow: ['delegatecall'],
        kind: 'uups',
    });
    await contract.deployed();

    console.log(name + " Address---> " + contract.address);

    const implAddr = await contract.getImplementation();
    console.log("Implementation address for " + name + " is " + implAddr);

    const artifact = await deployments.getExtendedArtifact(name);
    let proxyDeployments = {
        address: contract.address,
        ...artifact
    }

    await save(name, proxyDeployments);
}