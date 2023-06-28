task("request-allocation-update", "Request allocation update for SP")
	.addParam("minerId", "Miner id", "t01000")
	.addParam("limit", "Allocation limit", "12000")
	.addParam("dailyAllocation", "Daily allocation limit", "1200")
	.setAction(async (taskArgs) => {
		let { minerId, limit, dailyAllocation } = taskArgs;
		minerId = ethers.BigNumber.from(minerId.slice(2));
		allocationLimit = ethers.utils.parseEther(limit);
		dailyAllocation = ethers.utils.parseEther(dailyAllocation);

		const StorageProviderRegistryFactory = await ethers.getContractFactory("StorageProviderRegistry");
		const storageProviderRegistryDeployment = await hre.deployments.get("StorageProviderRegistry");
		const storageProviderRegistry = StorageProviderRegistryFactory.attach(storageProviderRegistryDeployment.address);

		const abiEncodedCall = storageProviderRegistry.interface.encodeFunctionData(
			"requestAllocationLimitUpdate(uint64,uint256,uint256)",
			[minerId, allocationLimit, dailyAllocation]
		);

		console.log("abiEncodedCall: ", abiEncodedCall);
		console.log("storageProviderRegistryDeployment: ", storageProviderRegistryDeployment.address);
	});

module.exports = {};
