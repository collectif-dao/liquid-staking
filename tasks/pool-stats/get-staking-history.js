const fs = require('fs');

task("get-staking-history", "Fetch all staking events by stakers")
	.setAction(async (taskArgs) => {

		const LiquidStakingFactory = await ethers.getContractFactory("LiquidStaking");
		const LiquidStakingDeployment = await hre.deployments.get("LiquidStaking");
		const liquidStaking = LiquidStakingFactory.attach(LiquidStakingDeployment.address);

		const STEP_SIZE = 1000;
		const CONTRACTS_DEPLOYMENT_BLOCK = 2995888
		const TIMEOUT_ERROR_BLOCK = 3111888

		let eventsChunks = [];

		try {

			let currentBlock = TIMEOUT_ERROR_BLOCK;

			// let currentBlock = await liquidStaking.provider.getBlockNumber(); // get Current block height
			let startBlock = 2995888; // liquid staking deployment block number;
			let endBlock = startBlock + STEP_SIZE;

			currentBlock = startBlock + 50000;

			// currentBlock = Math.trunc((currentBlock - startBlock)/3) + startBlock;

			async function* BlockRangeGenerator() {
				
			  while (endBlock <= currentBlock) {
			    const eventsChunk = await liquidStaking.queryFilter(liquidStaking.filters.Deposit(), startBlock, endBlock);
			    startBlock = endBlock;
					endBlock = endBlock + STEP_SIZE;
					console.log('startBlock: ', endBlock);
					console.log('endBlock: ', endBlock);
					yield eventsChunk
			  }
			}

			

			for await (const eventsChunk of BlockRangeGenerator()) {
				eventsChunks.push(eventsChunk)
			}

			const lastChunk = await liquidStaking.queryFilter(liquidStaking.filters.Deposit(), startBlock, currentBlock);
			eventsChunks.push(lastChunk);	

			const events = eventsChunks.reduce((acc, chunk) => acc.concat(chunk), [])
			console.log('events:', events);

			await fs.writeFile('./deposit_events.json', JSON.stringify(events), 'utf8', function (err) {
			    if (err) {
			        console.log("An error occurred while writing events to the file.");
			        return console.log(err);
			    }

			    console.log("events file has been saved.");
			});

		} catch (e) {
			console.log(e);
		}
	});

module.exports = {};
