import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import '@nomiclabs/hardhat-ethers';

const deployFunction: DeployFunction = async function ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) {
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;

    const adminFee = 0;
    const baseProfitShare = 3000;
    const rewardCollector = deployer;

    // BigInts library deployment
    const bigInts = await deploy('BigIntsClient', {
        from: deployer,
        deterministicDeployment: false,
        args: [],
    })

    console.log("Library Address--->" + bigInts.address)

    const wFIL = await deployments.get('WFIL');

    // LiquidStaking contract deployment
    const staking = await deploy('LiquidStaking', {
        from: deployer,
        deterministicDeployment: false,
        args: [wFIL.address, adminFee, baseProfitShare, rewardCollector, bigInts.address],
    })

    console.log(
        `LiquidStaking deployed to ${staking.address}`
    );
};

export default deployFunction;

deployFunction.dependencies = ['WFIL'];
deployFunction.tags = ['LiquidStaking'];