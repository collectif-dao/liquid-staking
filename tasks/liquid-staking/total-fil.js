import {callRpc} from "../utils";

task("total-fil", "Total FIL available in the pool")
  .setAction(async (taskArgs) => {

  

  
  const LiquidStakingFactory = await ethers.getContractFactory("LiquidStaking");
  const LiquidStakingDeployment = await hre.deployments.get("LiquidStaking");
  const liquidStaking = LiquidStakingFactory.attach(LiquidStakingDeployment.address);

  const totalFIL = await liquidStaking.totalFilAvailable();
  console.log("Total FIL available in the pool:", ethers.utils.formatEther(totalFIL));

})


module.exports = {}