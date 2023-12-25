task("get-sp-info", "Get info by owner id")
	.addParam("minerid", "Owner id", "t01000")
	.setAction(async (taskArgs) => {
		let { minerid } = taskArgs;
		minerid = ethers.BigNumber.from(minerid.slice(2));

		const StorageProviderRegistryFactory = await ethers.getContractFactory("StorageProviderRegistry");
		const storageProviderRegistryDeployment = await hre.deployments.get("StorageProviderRegistry");
		const storageProviderRegistry = StorageProviderRegistryFactory.attach(storageProviderRegistryDeployment.address);

		try {
			const sp = await storageProviderRegistry.storageProviders(minerid);
			const allocations = await storageProviderRegistry.allocations(minerid);
			const restakings = await storageProviderRegistry.restakings(minerid);
			const status = await storageProviderRegistry.syncedBeneficiary(minerid);

			console.log("Is active SP: ", sp.active);
			console.log("Is onboarded SP: ", sp.onboarded);
			console.log("Target pool: ", sp.targetPool);
			console.log("Owner ID: ", sp.ownerId);
			console.log("Last epoch for beneficiary: ", sp.lastEpoch);

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
