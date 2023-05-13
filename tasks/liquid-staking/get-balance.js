task("get-balance", "Get clFIL balance of an address")
	.addParam("address", "User address", "0xe975146D08609310Ed4DB354233533Ad07dDc2F5")
	.setAction(async (taskArgs) => {
		let { address } = taskArgs;

		const LiquidStakingFactory = await ethers.getContractFactory("LiquidStaking");
		const LiquidStakingDeployment = await hre.deployments.get("LiquidStaking");
		const staking = LiquidStakingFactory.attach(LiquidStakingDeployment.address);

		try {
			const clFILBalance = await staking.balanceOf(address);

			console.log("clFIL balance is: ", ethers.utils.formatEther(clFILBalance), " clFIL");
		} catch (e) {
			console.log(e);
		}
	});

module.exports = {};
