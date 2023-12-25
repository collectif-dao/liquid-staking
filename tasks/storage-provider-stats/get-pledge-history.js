task("get-pledge-history", "Get pledge data by owner id")
	.addParam("minerid", "Owner id", "t01000")
	.setAction(async (taskArgs) => {
		let { minerid } = taskArgs;
		minerid = ethers.BigNumber.from(minerid.slice(2));

		const LiquidStakingFactory = await ethers.getContractFactory("LiquidStaking");
		const LiquidStakingDeployment = await hre.deployments.get("LiquidStaking");
		const liquidStaking = LiquidStakingFactory.attach(LiquidStakingDeployment.address);

		console.log(liquidStaking.filters.Pledge());

		// try {
		// 	const startBlock = 2995888;
		// 	const endBlock = -1;
		// 	const pledgeEvents = await liquidStaking.queryFilter(liquidStaking.filters.Pledge(), startBlock, endBlock);

		// 	const totalPledge = pledgeEvents.reduce((acc, event) => {
		// 		return acc.add(event.args.amount);
		// 	}, ethers.BigNumber.from(0));

		// 	console.log('totalPledge in attoFIL: ', totalPledge.toString(), ' attoFIL');
		// 	console.log('totalPledge in FIL: ', ethers.utils.formatEther(totalPledge), ' FIL');

		// } catch (e) {
		// 	console.log(e);
		// }
	});

module.exports = {};
