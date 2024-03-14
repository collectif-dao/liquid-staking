task("encode", "encode transaction")
	.setAction(async (taskArgs) => {

		const LiquidStakingFactory = await ethers.getContractFactory("LiquidStaking");
		const LiquidStakingDeployment = await hre.deployments.get("LiquidStaking");
		const stakingContract = LiquidStakingFactory.attach(LiquidStakingDeployment.address);

		console.log('stakingContract.interface: ', stakingContract.interface.encodeFunctionData("stake"));

		const base64encoded = ethers.utils.base64.encode(stakingContract.interface.encodeFunctionData("stake"));

		console.log('base64encoded: ', base64encoded);
		
		const base64decoded = '0x' + Buffer.from(ethers.utils.base64.decode("RDpLZvE=")).toString("hex");

		console.log('base64decoded: ', base64decoded);

		const functionDataDecoded = stakingContract.interface.decodeFunctionData("stake", base64decoded);

		console.log( "functionDataDecoded: ", functionDataDecoded);
	});

module.exports = {};
