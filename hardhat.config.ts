import { HardhatUserConfig } from "hardhat/config";
import * as fs from "fs";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-preprocessor";
import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";

function getRemappings() {
  return fs
    .readFileSync("remappings.txt", "utf8")
    .split("\n")
    .filter(Boolean) // remove empty lines
    .map((line) => line.trim().split("="));
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.12",
      },
      {
        version: "0.8.17",
      },
    ],
  },
  networks: {
    hardhat: {},
    development: {
      url: 'http://0.0.0.0:8545',
      chainId: 1337,
    },
    hyperspace: {
      url: `${process.env.HYPERSPACE_RPC_URL}`,
      chainId: 3141,
      accounts: [process.env.PRIVATE_KEY],
      live: true,
      saveDeployments: true,
      gasPrice: 100000000,
      gasMultiplier: 8000,
    },
  },
  preprocess: {
    eachLine: (hre) => ({
      transform: (line: string) => {
        if (line.match(/^\s*import /i)) {
          for (const [from, to] of getRemappings()) {
            if (line.includes(from)) {
              line = line.replace(from, to);
              break;
            }
          }
        }
        return line;
      },
    }),
  },
  paths: {
    sources: "./contracts",
    cache: "./cache",
  },
};

export default config;
