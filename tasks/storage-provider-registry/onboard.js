import { callRpc } from "../utils";

task("onboard", "Onboard a miner")
	.addParam("minerId", "Miner id", "f02239446")
	.addParam("allocationLimit", "Overall FIL allocation for a storage provider", "100000")
	.addParam("dailyAllocation", "Daily FIL allocation for a storage provider", "5000")
	.addParam("repayment", "Repayment amount for a storage provider", "136139")
	.addParam("lastEpoch", "Last epoch", "5205618")
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

		const feeData = await ethers.provider.getFeeData();
		const overrides = {
			maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
			maxFeePerGas: feeData.maxFeePerGas,
		};

		let tx = await storageProviderRegistry
			.connect(signer)
			.onboardStorageProvider(minerId, allocationLimit, dailyAllocation, repayment, lastEpoch, overrides);

		let receipt = await tx.wait();
		console.log(receipt);
	});

module.exports = {};
