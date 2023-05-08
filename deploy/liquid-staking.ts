import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import '@nomiclabs/hardhat-ethers';

const deployFunction: DeployFunction = async function ({ deployments, getNamedAccounts, ethers, upgrades }: HardhatRuntimeEnvironment) {
    const { deployer } = await getNamedAccounts();
    const { deploy, save } = deployments;
    const feeData = await ethers.provider.getFeeData();
    const chainId = await ethers.provider.getNetwork();
    let wFIL;

    const adminFee = 0;
    const baseProfitShare = 3000;
    const rewardCollector = deployer;

    // BigInts library deployment
    const bigInts = await deploy('BigIntsClient', {
        from: deployer,
        deterministicDeployment: false,
        skipIfAlreadyDeployed: true,
        args: [],
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
        maxFeePerGas: feeData.maxFeePerGas,
    })

    console.log("Library Address--->" + bigInts.address)

    if (chainId.chainId == 31337) {
        wFIL = (await deployments.get('WFIL')).address;
    } else if (chainId.chainId == 3141) {
        wFIL = "0x6C297AeD654816dc5d211c956DE816Ba923475D2";
    } // TODO: add calibration and mainnet versions of WFIL

    const LiquidStakingFactory = await ethers.getContractFactory("LiquidStaking");
        const provider = new ethers.providers.FallbackProvider([ethers.provider], 1);
    provider.getFeeData = async () => feeData;
    const signer = new ethers.Wallet(process.env.PRIVATE_KEY).connect(provider);

    // LiquidStaking contract deployment
    // const staking = await upgrades.deployProxy(LiquidStakingFactory, [wFIL, adminFee, baseProfitShare, rewardCollector, bigInts.address], {
    //     initializer: 'initialize',
    //     unsafeAllow: ['delegatecall'],
    //     kind: 'uups',
    // });
    // await staking.deployed();

    // const staking = await deploy('LiquidStaking', {
    //     from: deployer,
    //     deterministicDeployment: false,
    //     skipIfAlreadyDeployed: true,
    //     args: [wFIL, adminFee, baseProfitShare, rewardCollector, bigInts.address],
    //     maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
    //     maxFeePerGas: feeData.maxFeePerGas,
    // })

    // console.log(
    //     `LiquidStaking deployed to ${staking.address}`
    // );

    // const artifact = await deployments.getExtendedArtifact('LiquidStaking');
    // let proxyDeployments = {
    //     address: staking.address,
    //     ...artifact
    // }

    // await save('LiquidStaking', proxyDeployments);

};

export default deployFunction;

deployFunction.dependencies = ['WFIL'];
deployFunction.tags = ['LiquidStaking'];