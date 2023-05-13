task("deposit", "Deposit collateral to the pool")
	.addParam("amount", "deposit amount in FIL", "200")
	.setAction(async (taskArgs) => {
		let { amount } = taskArgs;
		amount = ethers.utils.parseEther(amount);

		const StorageProviderCollateralFactory = await ethers.getContractFactory("StorageProviderCollateral");
		const StorageProviderCollateralDeployment = await hre.deployments.get("StorageProviderCollateral");
		const storageProviderCollateral = StorageProviderCollateralFactory.attach(StorageProviderCollateralDeployment.address);

		const abiEncodedCall = storageProviderCollateral.interface.encodeFunctionData("deposit");
		console.log("abiEncodedCall: ", abiEncodedCall);
		console.log("storageProviderCollateral address: ", StorageProviderCollateralDeployment.address);
		console.log("amount: ", amount.toString());
	});

module.exports = {};
