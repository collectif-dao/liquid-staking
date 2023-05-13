task("request-allocation-update", "Request allocation update for SP")
	.addParam("limit", "Allocation limit", "12000")
	.addParam("dailyAllocation", "Daily allocation limit", "1200")
	.setAction(async (taskArgs) => {
		let { limit, dailyAllocation } = taskArgs;
		allocationLimit = ethers.utils.parseEther(limit);
		dailyAllocation = ethers.utils.parseEther(dailyAllocation);

		const StorageProviderRegistryFactory = await ethers.getContractFactory("StorageProviderRegistry");
		const storageProviderRegistryDeployment = await hre.deployments.get("StorageProviderRegistry");
		const storageProviderRegistry = StorageProviderRegistryFactory.attach(storageProviderRegistryDeployment.address);

		const abiEncodedCall = storageProviderRegistry.interface.encodeFunctionData("requestAllocationLimitUpdate(uint256,uint256)", [
			allocationLimit,
			dailyAllocation,
		]);

		console.log("abiEncodedCall: ", abiEncodedCall);
		console.log("storageProviderRegistryDeployment: ", storageProviderRegistryDeployment.address);
	});

module.exports = {};
