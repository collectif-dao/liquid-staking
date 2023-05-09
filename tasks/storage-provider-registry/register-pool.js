import {callRpc} from "../utils";

task("register-pool", "Register a miner in the pool.")
  .addParam("poolAddress", "pool address", "0xdE263cC43Eb828949Ac90708d2b49138e7E77c91")
  .setAction(async (taskArgs) => {

   const accounts = await ethers.getSigners();
   const signer = accounts[0];


  let { poolAddress } = taskArgs;
  
  const StorageProviderRegistryFactory = await ethers.getContractFactory("StorageProviderRegistry");
  const storageProviderRegistryDeployment = await hre.deployments.get("StorageProviderRegistry");
  const storageProviderRegistry = StorageProviderRegistryFactory.attach(storageProviderRegistryDeployment.address);

//   const priorityFee = await callRpc("eth_maxPriorityFeePerGas");
//   let tx = await storageProviderRegistry.connect(signer).registerPool(poolAddress, {
//       maxPriorityFeePerGas: priorityFee
//   });

//   let receipt = await tx.wait();
//   console.log(receipt);
})


module.exports = {}