import { callRpc } from "../utils";

task("withdraw-rewards", "Withdraw miner's rewards")
	.addParam("minerId", "miner's minerId", "t01000")
	.addParam("amount", "withdraw amount in FIL", "1")
	.setAction(async (taskArgs) => {
		const accounts = await ethers.getSigners();
		const signer = accounts[0];

		let { minerId, amount } = taskArgs;
		minerId = ethers.BigNumber.from(minerId.slice(2));
		amount = ethers.utils.parseEther(amount);

		const feeData = await ethers.provider.getFeeData();
		const overrides = {
			maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
			maxFeePerGas: feeData.maxFeePerGas,
		};

		const RewardCollectorFactory = await ethers.getContractFactory("RewardCollector");
		const RewardCollectorDeployment = await hre.deployments.get("RewardCollector");
		const rewardCollector = RewardCollectorFactory.attach(RewardCollectorDeployment.address);

		let tx = await rewardCollector.connect(signer).withdrawRewards(minerId, amount, overrides);
		let receipt = await tx.wait();
		console.log(receipt);
	});

module.exports = {};
