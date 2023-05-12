import {callRpc} from "../utils";

task("stake", "Stake to the pool")
  .addParam("amount", "stake amount in FIL", "1000")
  .setAction(async (taskArgs) => {

   const accounts = await ethers.getSigners();
   const signer = accounts[0];


  let { amount } = taskArgs;
  amount = ethers.utils.parseEther(amount);

  console.log('amount: ', amount.toString());
  
  const LiquidStakingFactory = await ethers.getContractFactory("LiquidStaking");
  const LiquidStakingDeployment = await hre.deployments.get("LiquidStaking");
  const liquidStaking = LiquidStakingFactory.attach(LiquidStakingDeployment.address);

  const priorityFee = await callRpc("eth_maxPriorityFeePerGas");
  let tx = await liquidStaking.connect(signer).stake({
      maxPriorityFeePerGas: priorityFee,
	  value: amount
  });

  let receipt = await tx.wait();
  console.log(receipt);

})


module.exports = {}