import { callRpc } from "../utils";

task("onboard", "Onboard a miner")
	.addParam("minerId", "Miner id", "t01000")
	.addParam("allocationLimit", "Overall FIL allocation for a storage provider", "10000")
	.addParam("dailyAllocation", "Daily FIL allocation for a storage provider", "1000")
	.addParam("repayment", "Repayment amount for a storage provider", "12000")
	.addParam("lastEpoch", "Last epoch", "897999909")
	.setAction(async (taskArgs) => {
		const accounts = await ethers.getSigners();
		const signer = accounts[0];

		let { minerId, allocationLimit, dailyAllocation, repayment, lastEpoch } = taskArgs;

		minerId = ethers.BigNumber.from(minerId.slice(2));
		lastEpoch = ethers.BigNumber.from(lastEpoch);
		allocationLimit = ethers.utils.parseEther(allocationLimit);
		dailyAllocation = ethers.utils.parseEther(dailyAllocation);
		repayment = ethers.utils.parseEther(repayment);

		const StorageProviderRegistryFactory = await ethers.getContractFactory("StorageProviderRegistry");
		const storageProviderRegistryDeployment = await hre.deployments.get("StorageProviderRegistry");
		const storageProviderRegistry = StorageProviderRegistryFactory.attach(storageProviderRegistryDeployment.address);

		const priorityFee = await callRpc("eth_maxPriorityFeePerGas");
		let tx = await storageProviderRegistry
			.connect(signer)
			.onboardStorageProvider(minerId, allocationLimit, dailyAllocation, repayment, lastEpoch, {
				maxPriorityFeePerGas: priorityFee,
			});

		let receipt = await tx.wait();
		console.log(receipt);
	});

module.exports = {};
