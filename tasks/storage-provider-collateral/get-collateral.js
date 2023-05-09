task("get-collateral", "Get collateral by miner id")
  .addParam("minerOwnerId", "Miner owner id", "t0100")
  .setAction(async (taskArgs) => {

	let {minerOwnerId} = taskArgs;
  	minerOwnerId = ethers.BigNumber.from(minerOwnerId.slice(2));

	const StorageProviderCollateralFactory = await ethers.getContractFactory("StorageProviderCollateral");
	const storageProviderCollateralDeployment = await hre.deployments.get("StorageProviderCollateral");
	const storageProviderCollateral = StorageProviderCollateralFactory.attach(storageProviderCollateralDeployment.address);
	
	try {
		const collateralInfo = await storageProviderCollateral.getCollateral(minerOwnerId)
		const [available, locked] = collateralInfo;
		console.log("Available collateral: ", ethers.utils.formatEther(available), " FIL");
		console.log("Locked collateral: ", ethers.utils.formatEther(available), " FIL");
	} catch (e) {
		console.log(e)
	}
})


module.exports = {}