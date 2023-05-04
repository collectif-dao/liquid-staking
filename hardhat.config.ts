import { HardhatUserConfig } from "hardhat/config";
import {subtask} from "hardhat/config";
import {TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS} from "hardhat/builtin-tasks/task-names";
import * as fs from "fs";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "hardhat-preprocessor";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import "@nomiclabs/hardhat-ethers";
import * as dotenv from 'dotenv';
import * as path from 'path';
dotenv.config();

const PRIVATE_KEY = process.env.PRIVATE_KEY;
const url = process.env.HYPERSPACE_RPC_URL;

subtask(
  TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS,
  async (_, { config }, runSuper) => {
    const paths = await runSuper();

    return paths
      .filter(solidityFilePath => {
        const relativePath = path.relative(config.paths.sources, solidityFilePath)
        // console.log(relativePath);
        return !relativePath.includes('test/');
      })
  }
);

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
  defaultNetwork: "hyperspace",
  networks: {
    hardhat: {},
    development: {
      url: 'http://0.0.0.0:8545',
      chainId: 1337,
    },
    hyperspace: {
      chainId: 3141,
      url: "https://api.hyperspace.node.glif.io/rpc/v1",
      accounts: [PRIVATE_KEY],
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
