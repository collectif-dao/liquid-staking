task("encode", "encode transaction")
	.setAction(async (taskArgs) => {

		const LiquidStakingFactory = await ethers.getContractFactory("LiquidStaking");
		const LiquidStakingDeployment = await hre.deployments.get("LiquidStaking");
		const stakingContract = LiquidStakingFactory.attach(LiquidStakingDeployment.address);

		console.log('stakingContract.interface: ', stakingContract.interface.encodeFunctionData("stake"));
		console.log('stake function encoded: ', ethers.utils.id("stake()").slice(0,10));

		const base64encoded = ethers.utils.base64.encode(ethers.utils.id("stake()").slice(0,10));

		console.log('base64encoded: ', base64encoded);
		
		const base64decoded = '0x' + Buffer.from(ethers.utils.base64.decode("RDpLZvE=")).toString("hex");

		console.log('base64decoded: ', base64decoded);

		// const functionDataDecoded = stakingContract.interface.decodeFunctionData("stake", base64decoded);

		// console.log( "functionDataDecoded: ", functionDataDecoded);

		const params = "WESDgeGCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADeC2s6dkAAAAAAAAAAAAAAAAAACeDw2D3YgCQONQanrEzoJQCyvZKw==";
		const paramsDecoded = '0x' + Buffer.from(ethers.utils.base64.decode(params)).toString("hex");

		console.log("paramsDecoded: ", paramsDecoded);


		const hexEncodedUnstake = stakingContract.interface.encodeFunctionData("unstake", ["1000000000000000000","0x9e0f0d83dD880240e3506A7Ac4CE82500b2bD92B"])
		console.log("hexEncodedUnstake: ", hexEncodedUnstake);

		const base64encodedUnstake = ethers.utils.base64.encode(hexEncodedUnstake);

		console.log("base64encodedUnstake: ", base64encodedUnstake);

		const base64DecodedUnstake = '0x' + Buffer.from(ethers.utils.base64.decode(base64encodedUnstake)).toString("hex");

		console.log("base64DecodedUnstake: ", base64DecodedUnstake);

	});

module.exports = {};
