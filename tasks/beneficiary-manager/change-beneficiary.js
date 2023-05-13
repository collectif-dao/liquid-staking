import { task } from "hardhat/config";

task("change-beneficiary", "Delegate beneficiary address to the pool.").setAction(async (taskArgs) => {
	const StorageProviderRegistry = await ethers.getContractFactory("StorageProviderRegistry");
	const abiEncodedCall = StorageProviderRegistry.interface.encodeFunctionData("changeBeneficiaryAddress");
	const storageProviderRegistryDeployment = await deployments.get("StorageProviderRegistry");

	console.log("abiEncodedCall: ", abiEncodedCall);
	console.log("Storage Provider Registry address: ", storageProviderRegistryDeployment.address);
});

module.exports = {};
