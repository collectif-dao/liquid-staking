task("pledge", "Pledge from the pool")
	.addParam("amount", "Amount to pledge", "1")
	.setAction(async (taskArgs) => {
		let { amount } = taskArgs;
		amount = ethers.utils.parseEther(amount);

		const LiquidStakingFactory = await ethers.getContractFactory("LiquidStaking");
		const LiquidStakingDeployment = await hre.deployments.get("LiquidStaking");
		const liquidStaking = LiquidStakingFactory.attach(LiquidStakingDeployment.address);
		const abiEncodedCall = liquidStaking.interface.encodeFunctionData("pledge(uint256)", [amount]);
		console.log("abiEncodedCall: ", abiEncodedCall);
		console.log("Liquid staking address: ", LiquidStakingDeployment.address);
	});

module.exports = {};
