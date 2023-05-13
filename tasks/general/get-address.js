const fa = require("@glif/filecoin-address");

import * as dotenv from "dotenv";
dotenv.config();

task("get-address", "Gets Filecoin f4 address and corresponding Ethereum address.").setAction(async (taskArgs) => {
	const DEPLOYER_PRIVATE_KEY = network.config.accounts[0];
	const deployer = new ethers.Wallet(DEPLOYER_PRIVATE_KEY);

	const f4Address = fa.newDelegatedEthAddress(deployer.address).toString();
	console.log("Ethereum address (this address should work for most tools):", deployer.address);
	console.log("f4address (informational only):", f4Address);
});

module.exports = {};
