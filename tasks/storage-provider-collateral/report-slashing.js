import { callRpc } from "../utils";

task("report-slashing", "Report slashing by miner")
	.addParam("ownerId", "miner's ownerId", "t0100")
	.addParam("amount", "slashing amount in FIL", "0.2725")
	.setAction(async (taskArgs) => {
		const accounts = await ethers.getSigners();
		const signer = accounts[0];

		let { ownerId, amount } = taskArgs;
		ownerId = ethers.BigNumber.from(ownerId.slice(2));
		amount = ethers.utils.parseEther(amount);

		console.log("amount: ", amount.toString());

		const StorageProviderCollateralFactory = await ethers.getContractFactory("StorageProviderCollateral");
		const StorageProviderCollateralDeployment = await hre.deployments.get("StorageProviderCollateral");
		const collateral = StorageProviderCollateralFactory.attach(StorageProviderCollateralDeployment.address);

		const priorityFee = await callRpc("eth_maxPriorityFeePerGas");
		let tx = await collateral.connect(signer).reportSlashing(ownerId, amount, {
			maxPriorityFeePerGas: priorityFee,
		});

		let receipt = await tx.wait();
		console.log(receipt);
	});

module.exports = {};
