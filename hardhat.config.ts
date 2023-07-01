import { HardhatUserConfig } from "hardhat/config";
import "@openzeppelin/hardhat-upgrades";
import * as fs from "fs";
import { subtask } from "hardhat/config";
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from "hardhat/builtin-tasks/task-names";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-preprocessor";
import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";
import "@nomicfoundation/hardhat-ledger";
// import "@nomicfoundation/hardhat-foundry";
import * as path from "path";
import "./tasks";

import * as dotenv from "dotenv";
dotenv.config();

subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS, async (_, { config }, runSuper) => {
	const paths = await runSuper();

	const res = paths.filter((solidityFilePath) => {
		const relativePath = path.relative(config.paths.sources, solidityFilePath);
		return !relativePath.includes("test/") && !relativePath.includes("router/") && !relativePath.includes("oracle/");
	});
	return res;
});

function getRemappings() {
	return fs
		.readFileSync("remappings.txt", "utf8")
		.split("\n")
		.filter(Boolean) // remove empty lines
		.map((line) => line.trim().split("="));
}

const config: HardhatUserConfig = {
	namedAccounts: {
		deployer: {
			default: 0,
		},
		dev: {
			default: 1,
		},
	},
	solidity: {
		compilers: [
			{
				version: "0.8.17",
				settings: {
					optimizer: {
						enabled: true,
						runs: 0,
						details: {
							yul: false,
							constantOptimizer: true,
						},
					},
				},
			},
		],
	},
	defaultNetwork: "localnet",
	networks: {
		hardhat: {},
		development: {
			url: "http://0.0.0.0:8545",
			chainId: 1337,
		},
		localnet: {
			url: "http://127.0.0.1:1234/rpc/v1",
			chainId: 31415926,
			accounts: [process.env.PRIVATE_KEY],
			saveDeployments: true,
			// gasPrice: 100000000,
			// gasMultiplier: 8000,
			live: true,
		},
		filecoin: {
			url: `${process.env.FILECOIN_MAINNET_RPC_URL}`,
			chainId: 314,
			ledgerAccounts: [`${process.env.DEPLOYER_ADDRESS}`],
			live: true,
			saveDeployments: true,
			timeout: 1000000,
		},
		calibration: {
			url: `${process.env.CALIBRATION_RPC_URL}`,
			chainId: 314159,
			ledgerAccounts: [`${process.env.DEPLOYER_ADDRESS}`],
			live: true,
			saveDeployments: true,
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
		sources: "./contracts/",
		cache: "./cache",
	},
};

export default config;
