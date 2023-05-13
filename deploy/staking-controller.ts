import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import { deployAndSaveContract } from "../utils";

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
	const { deployments, ethers } = hre;

	const resolver = await deployments.get("Resolver");
	const rewardCollector = await deployments.get("RewardCollector");

	const adminFee = 0;
	const baseProfitShare = 3000;

	await deployAndSaveContract("LiquidStakingController", [adminFee, baseProfitShare, rewardCollector.address, resolver.address], hre);
};

export default deployFunction;

deployFunction.tags = ["LiquidStakingController"];
deployFunction.dependencies = ["Resolver", "BeneficiaryManager", "WFIL", "RewardCollector"];
