import { callRpc } from "../utils";

task("update-allocation-limit", "Update allocation limit for SP")
	.addParam("ownerId", "Owner ID of SP", "t0100")
	.addParam("allocationLimit", "Allocation limit", "12000")
	.addParam("dailyAllocation", "Daily allocation limit", "1200")
	.addParam("repayment", "Repayment amount for a storage provider", "14500")
	.setAction(async (taskArgs) => {
		let { ownerId, allocationLimit, dailyAllocation, repayment } = taskArgs;

		const accounts = await ethers.getSigners();
		const signer = accounts[0];

		ownerId = ethers.BigNumber.from(ownerId.slice(2));
		allocationLimit = ethers.utils.parseEther(allocationLimit);
		dailyAllocation = ethers.utils.parseEther(dailyAllocation);
		repayment = ethers.utils.parseEther(repayment);

		const StorageProviderRegistryFactory = await ethers.getContractFactory("StorageProviderRegistry");
		const storageProviderRegistryDeployment = await hre.deployments.get("StorageProviderRegistry");
		const storageProviderRegistry = StorageProviderRegistryFactory.attach(storageProviderRegistryDeployment.address);

		const priorityFee = await callRpc("eth_maxPriorityFeePerGas");
		let tx = await storageProviderRegistry.connect(signer).updateAllocationLimit(ownerId, allocationLimit, dailyAllocation, repayment, {
			maxPriorityFeePerGas: priorityFee,
		});

		let receipt = await tx.wait();
		console.log(receipt);
	});

module.exports = {};
