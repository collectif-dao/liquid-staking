import { callRpc } from "../utils";

task("withdraw-pledge", "Withdraw miner's pledge")
	.addParam("ownerId", "miner's ownerId", "t0100")
	.addParam("amount", "withdraw amount in FIL", "1")
	.setAction(async (taskArgs) => {
		const accounts = await ethers.getSigners();
		const signer = accounts[0];

		let { ownerId, amount } = taskArgs;
		ownerId = ethers.BigNumber.from(ownerId.slice(2));
		amount = ethers.utils.parseEther(amount);

		const RewardCollectorFactory = await ethers.getContractFactory("RewardCollector");
		const RewardCollectorDeployment = await hre.deployments.get("RewardCollector");
		const rewardCollector = RewardCollectorFactory.attach(RewardCollectorDeployment.address);

		const priorityFee = await callRpc("eth_maxPriorityFeePerGas");
		let tx = await rewardCollector.connect(signer).withdrawPledge(ownerId, amount, {
			maxPriorityFeePerGas: priorityFee,
		});

		let receipt = await tx.wait();
		console.log(receipt);
	});

module.exports = {};
