import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import { deployAndSaveContract } from "../utils";
import type { Resolver } from "../typechain-types";

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
	const { deployments, ethers } = hre;

	const resolver = await deployments.get("Resolver");

	const adminFee = 0;
	const baseProfitShare = 4000;
	const liquidityCap = ethers.utils.parseEther("1000000");

	await deployAndSaveContract("LiquidStakingController", [adminFee, baseProfitShare, resolver.address, liquidityCap, false], hre);

	const stakingController = await deployments.get("LiquidStakingController");

	const feeData = await ethers.provider.getFeeData();
	const overrides = {
		maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
		maxFeePerGas: feeData.maxFeePerGas,
	};

	const resolverContract = await ethers.getContractAt<Resolver>("Resolver", resolver.address);
	await (await resolverContract.setLiquidStakingControllerAddress(stakingController.address, overrides)).wait();
};

export default deployFunction;

deployFunction.tags = ["LiquidStakingController"];
deployFunction.dependencies = ["Resolver", "WFIL"];
