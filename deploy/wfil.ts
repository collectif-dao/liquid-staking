import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunction: DeployFunction = async function ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) {
  const { deployer } = await getNamedAccounts();
  const { deploy } = deployments;

  const { address, newlyDeployed } = await deploy('WFIL', {
    from: deployer,
    deterministicDeployment: false,
    args: [deployer],
  })

  console.log("WFIL Address--->" + address)
};

export default deployFunction;

deployFunction.tags = ["WFIL"];

deployFunction.skip = ({ getChainId }) =>
  new Promise(async (resolve, reject) => {
    try {
      const chainId = await getChainId();
      resolve(chainId !== "31337");
    } catch (error) {
      reject(error);
    }
  });