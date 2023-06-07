task("contracts", "List deployment addresses for smart contracts").setAction(async (taskArgs) => {
	const StorageProviderRegistry = await hre.deployments.get("StorageProviderRegistry");
	console.log("StorageProviderRegistry: ", StorageProviderRegistry.address);

	const StorageProviderCollateral = await hre.deployments.get("StorageProviderCollateral");
	console.log("StorageProviderCollateral: ", StorageProviderCollateral.address);

	const LiquidStaking = await hre.deployments.get("LiquidStaking");
	console.log("LiquidStaking: ", LiquidStaking.address);

	const Resolver = await hre.deployments.get("Resolver");
	console.log("Resolver: ", Resolver.address);

	const RewardCollector = await hre.deployments.get("RewardCollector");
	console.log("RewardCollector: ", RewardCollector.address);

	const LiquidStakingController = await hre.deployments.get("LiquidStakingController");
	console.log("LiquidStakingController: ", LiquidStakingController.address);
});

module.exports = {};
