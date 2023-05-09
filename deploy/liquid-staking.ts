import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import '@nomiclabs/hardhat-ethers';

const deployFunction: DeployFunction = async function ({ deployments, getNamedAccounts, ethers }: HardhatRuntimeEnvironment) {
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;
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

    if (chainId.chainId == 31337 || chainId.chainId === 31415926) {
        wFIL = (await deployments.get('WFIL')).address;
    } else if (chainId.chainId == 3141) {
        wFIL = "0x6C297AeD654816dc5d211c956DE816Ba923475D2";
    } // TODO: add calibration and mainnet versions of WFIL

    // LiquidStaking contract deployment
    const staking = await deploy('LiquidStaking', {
        from: deployer,
        deterministicDeployment: false,
        skipIfAlreadyDeployed: true,
        args: [wFIL, adminFee, baseProfitShare, rewardCollector, bigInts.address],
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
        maxFeePerGas: feeData.maxFeePerGas,
    })

    console.log(
        `LiquidStaking deployed to ${staking.address}`
    );
};

export default deployFunction;

deployFunction.dependencies = ['WFIL'];
deployFunction.tags = ['LiquidStaking'];