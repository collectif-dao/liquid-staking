task("get-sp-info", "Get info by miner id")
  .addParam("minerId", "Miner id", "t0100")
  .setAction(async (taskArgs) => {

	let {minerId} = taskArgs;
  	minerId = ethers.BigNumber.from(minerId.slice(2));

	const StorageProviderRegistryFactory = await ethers.getContractFactory("StorageProviderRegistry");
	const storageProviderRegistryDeployment = await hre.deployments.get("StorageProviderRegistry");
	const storageProviderRegistry = StorageProviderRegistryFactory.attach(storageProviderRegistryDeployment.address);
	
	try {
		const sp = await storageProviderRegistry.storageProviders(minerId)
		const allocations = await storageProviderRegistry.allocations(minerId);
		console.log("SP info: ", sp);
		console.log("Allocations: ", allocations.repayment.toString(), sp.lastEpoch.toString());
	} catch (e) {
		console.log(e)
	}
})


module.exports = {}