import { callRpc } from "../utils";

task("accept-beneficiary", "Accept beneficiary change.")
	.addParam("minerId", "Miner id", "t01000")
	.setAction(async (taskArgs) => {
		const accounts = await ethers.getSigners();
		const signer = accounts[0];

		let { minerId } = taskArgs;
		minerId = ethers.BigNumber.from(minerId.slice(2));

		const feeData = await ethers.provider.getFeeData();
		const overrides = {
			maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
			maxFeePerGas: feeData.maxFeePerGas,
		};

		const StorageProviderRegistryFactory = await ethers.getContractFactory("StorageProviderRegistry");
		const storageProviderRegistryDeployment = await hre.deployments.get("StorageProviderRegistry");
		const storageProviderRegistry = StorageProviderRegistryFactory.attach(storageProviderRegistryDeployment.address);

		let tx = await storageProviderRegistry.connect(signer).acceptBeneficiaryAddress(minerId, overrides);

		let receipt = await tx.wait();
		console.log(receipt);
	});

module.exports = {};
