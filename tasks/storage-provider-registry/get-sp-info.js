task("get-sp-info", "Get info by owner id")
	.addParam("ownerId", "Owner id", "t0100")
	.setAction(async (taskArgs) => {
		let { ownerId } = taskArgs;
		ownerId = ethers.BigNumber.from(ownerId.slice(2));

		const StorageProviderRegistryFactory = await ethers.getContractFactory("StorageProviderRegistry");
		const storageProviderRegistryDeployment = await hre.deployments.get("StorageProviderRegistry");
		const storageProviderRegistry = StorageProviderRegistryFactory.attach(storageProviderRegistryDeployment.address);

		try {
			const sp = await storageProviderRegistry.storageProviders(ownerId);
			const allocations = await storageProviderRegistry.allocations(ownerId);
			const restakings = await storageProviderRegistry.restakings(ownerId);
			const status = await storageProviderRegistry.beneficiaryStatus(ownerId);

			console.log("SP info: ", sp);
			console.log();
			console.log("Allocation Limit: ", allocations.allocationLimit.toString() + " FIL");
			console.log("Daily allocation: ", allocations.dailyAllocation.toString() + " FIL");
			console.log("Used allocation: ", allocations.usedAllocation.toString() + " FIL");
			console.log("Accrued rewards: ", allocations.accruedRewards.toString() + " FIL");
			console.log("Repaid pledge: ", allocations.repaidPledge.toString() + " FIL");
			console.log();
			console.log("Repayment: ", allocations.repayment.toString() + " FIL");
			console.log("Expiration: ", sp.lastEpoch.toString());
			console.log();
			console.log("Restaking ratio: ", restakings.restakingRatio.toString());
			console.log("Restaking address: ", restakings.restakingAddress);
			console.log();
			console.log("Beneficiary status: ", status);
		} catch (e) {
			console.log(e);
		}
	});

module.exports = {};
