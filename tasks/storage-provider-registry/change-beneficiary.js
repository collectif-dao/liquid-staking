task("change-beneficiary", "Delegate beneficiary address to the pool.").setAction(async (taskArgs) => {
	const StorageProviderRegistry = await ethers.getContractFactory("StorageProviderRegistry");

	const abiEncodedCall = StorageProviderRegistry.interface.encodeFunctionData("changeBeneficiaryAddress");
	const storageProviderRegistryDeployment = await hre.deployments.get("StorageProviderRegistry");

	console.log("abiEncodedCall: ", abiEncodedCall);
	console.log("Storage Provider Registry address: ", storageProviderRegistryDeployment.address);
});

module.exports = {};
