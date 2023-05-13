import { callRpc } from "../utils";

task("report-recovery", "Report recovery after slashing by miner")
	.addParam("ownerId", "miner's ownerId", "t0100")
	.setAction(async (taskArgs) => {
		const accounts = await ethers.getSigners();
		const signer = accounts[0];

		let { ownerId } = taskArgs;
		ownerId = ethers.BigNumber.from(ownerId.slice(2));

		const StorageProviderCollateralFactory = await ethers.getContractFactory("StorageProviderCollateral");
		const StorageProviderCollateralDeployment = await hre.deployments.get("StorageProviderCollateral");
		const collateral = StorageProviderCollateralFactory.attach(StorageProviderCollateralDeployment.address);

		const priorityFee = await callRpc("eth_maxPriorityFeePerGas");
		let tx = await collateral.connect(signer).reportRecovery(ownerId, {
			maxPriorityFeePerGas: priorityFee,
		});

		let receipt = await tx.wait();
		console.log(receipt);
	});

module.exports = {};
