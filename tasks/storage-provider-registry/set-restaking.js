task("set-restaking", "Set restaking ratio for SP")
	.addParam("ratio", "Restaking ratio", "7000")
	.addParam("address", "ETH address of SP", "0xe975146D08609310Ed4DB354233533Ad07dDc2F5")
	.setAction(async (taskArgs) => {
		let { ratio, address } = taskArgs;
		ratio = ethers.BigNumber.from(ratio);

		const StorageProviderRegistryFactory = await ethers.getContractFactory("StorageProviderRegistry");
		const storageProviderRegistryDeployment = await hre.deployments.get("StorageProviderRegistry");
		const storageProviderRegistry = StorageProviderRegistryFactory.attach(storageProviderRegistryDeployment.address);

		const abiEncodedCall = storageProviderRegistry.interface.encodeFunctionData("setRestaking(uint256,address)", [ratio, address]);
		console.log("abiEncodedCall: ", abiEncodedCall);
		console.log("storageProviderRegistryDeployment: ", storageProviderRegistryDeployment.address);
	});

module.exports = {};
