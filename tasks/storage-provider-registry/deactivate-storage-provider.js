import { callRpc } from "../utils";

task("deactivate-storage-provider", "Deactivate storage provider and renounce beneficiary address")
	.addParam("ownerId", "Miner's owner id", "t0100")
	.setAction(async (taskArgs) => {
		const accounts = await ethers.getSigners();
		const signer = accounts[0];

		let { ownerId } = taskArgs;
		ownerId = ethers.BigNumber.from(ownerId.slice(2));

		const StorageProviderRegistryFactory = await ethers.getContractFactory("StorageProviderRegistry");
		const storageProviderRegistryDeployment = await hre.deployments.get("StorageProviderRegistry");
		const storageProviderRegistry = StorageProviderRegistryFactory.attach(storageProviderRegistryDeployment.address);

		const priorityFee = await callRpc("eth_maxPriorityFeePerGas");
		let tx = await storageProviderRegistry.connect(signer).deactivateStorageProvider(ownerId, {
			maxPriorityFeePerGas: priorityFee,
		});

		let receipt = await tx.wait();
		console.log(receipt);
	});

module.exports = {};
