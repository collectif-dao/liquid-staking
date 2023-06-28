task("pledge", "Pledge from the pool")
	.addParam("amount", "Amount to pledge", "1")
	.addParam("minerId", "miner's minerId", "t01000")
	.setAction(async (taskArgs) => {
		let { amount, minerId } = taskArgs;
		amount = ethers.utils.parseEther(amount);
		minerId = ethers.BigNumber.from(minerId.slice(2));

		const LiquidStakingFactory = await ethers.getContractFactory("LiquidStaking");
		const LiquidStakingDeployment = await hre.deployments.get("LiquidStaking");
		const liquidStaking = LiquidStakingFactory.attach(LiquidStakingDeployment.address);
		const abiEncodedCall = liquidStaking.interface.encodeFunctionData("pledge(uint256,uint64)", [amount, minerId]);
		console.log("abiEncodedCall: ", abiEncodedCall);
		console.log("Liquid staking address: ", LiquidStakingDeployment.address);
	});

module.exports = {};
