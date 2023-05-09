task("register", "Register a miner in the pool.")
  .addParam("minerId", "Miner id", "t01000")
  .addParam("allocationLimit", "Overall FIL allocation for a storage provider", "10000")
  .addParam("dailyAllocation", "Daily FIL allocation for a storage provider", "1000")
  .setAction(async (taskArgs) => {

  console.log(taskArgs);
  let {minerId, allocationLimit, dailyAllocation} = taskArgs;
  minerId = ethers.BigNumber.from(minerId.slice(2));
  allocationLimit = ethers.utils.parseEther(allocationLimit);
  dailyAllocation = ethers.utils.parseEther(dailyAllocation);
  const liquidStaking = await hre.deployments.get("LiquidStaking");
	const storageProviderRegistryDeployment = await hre.deployments.get("StorageProviderRegistry");
  const StorageProviderRegistry = await ethers.getContractFactory("StorageProviderRegistry");
  const abiEncodedCall = StorageProviderRegistry.interface.encodeFunctionData('register(uint64,address,uint256,uint256)', [minerId, liquidStaking.address, allocationLimit, dailyAllocation]);
  console.log("abiEncodedCall: ", abiEncodedCall)
	console.log("storageProviderRegistryDeployment: ", storageProviderRegistryDeployment.address);
})


module.exports = {}