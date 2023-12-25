task("total-fil", "Total FIL available in the pool").setAction(async (taskArgs) => {
	const LiquidStakingFactory = await ethers.getContractFactory("LiquidStaking");
	const LiquidStakingDeployment = await hre.deployments.get("LiquidStaking");
	const liquidStaking = LiquidStakingFactory.attach(LiquidStakingDeployment.address);

	const totalFIL = await liquidStaking.totalFilAvailable();
	const maxDeposit = await liquidStaking.maxDeposit("0xe975146D08609310Ed4DB354233533Ad07dDc2F5");
	console.log("Total FIL available in the pool:", ethers.utils.formatEther(totalFIL));
	console.log("Max deposit:", ethers.utils.formatEther(maxDeposit));

	const LiquidStakingControllerFactory = await ethers.getContractFactory("LiquidStakingController");
	const LiquidStakingControllerDeployment = await hre.deployments.get("LiquidStakingController");
	const LiquidStakingController = LiquidStakingControllerFactory.attach(LiquidStakingControllerDeployment.address);
	const liquidityCap = await LiquidStakingController.liquidityCap();
	console.log("liquidityCap in the pool:", ethers.utils.formatEther(liquidityCap));
});

module.exports = {};
