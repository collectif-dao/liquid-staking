import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import { deployAndSaveContract, getWFIL } from "../utils";
import { getContractAddress } from "ethers/lib/utils";
import { WFIL } from "../typechain-types";

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
	const { deployments, ethers } = hre;
	const [signer] = await ethers.getSigners();
	const initialDeposit = 1000;

	const chainId = await ethers.provider.getNetwork();
	const wFIL = await getWFIL(chainId.chainId, deployments);
	const wFILContract = await ethers.getContractAt<WFIL>("WFIL", wFIL);

	const resolver = await deployments.get("Resolver");

	let tx = await (await wFILContract.deposit({ value: initialDeposit })).wait();

	const transactionCount = await signer.getTransactionCount();
	const proxyAddr = getContractAddress({
		from: signer.address,
		nonce: transactionCount + 2,
	});

	tx = await (await wFILContract.approve(proxyAddr, initialDeposit)).wait();
	let balance = await wFILContract.balanceOf(signer.address);
	console.log(balance);
	console.log(proxyAddr);

	await deployAndSaveContract("LiquidStaking", [wFIL, resolver.address, initialDeposit], hre);
};

export default deployFunction;

deployFunction.dependencies = ["WFIL", "Resolver", "LiquidStakingController"];
deployFunction.tags = ["LiquidStaking"];
