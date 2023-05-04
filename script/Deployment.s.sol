// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../contracts/LiquidStaking.sol";
// import "../contracts/StakingRouter.sol";
import "../contracts/StorageProviderRegistry.sol";
import "../contracts/StorageProviderCollateral.sol";

contract DeploymentScript is Script {
	// StakingRouter public router;
	LiquidStaking public staking;
	StorageProviderCollateral private collateral;
	StorageProviderRegistry private registry;
	IWFIL public wfil;

	uint256 private constant MAX_STORAGE_PROVIDERS = 200;
	uint256 private constant MAX_ALLOCATION = 10000 ether;
	uint256 private constant MIN_TIME_PERIOD = 90 days;
	uint256 private constant MAX_TIME_PERIOD = 360 days;

	function run() external {
		uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
		vm.startBroadcast(deployerPrivateKey);

		// wfil = IWETH9(address(new WFIL()));

		// router = new StakingRouter("Collective DAO Router", wfil);
		// staking = new LiquidStaking(address(wfil));
		// registry = new StorageProviderRegistry(MAX_STORAGE_PROVIDERS, MAX_ALLOCATION, MIN_TIME_PERIOD, MAX_TIME_PERIOD);
		// collateral = new StorageProviderCollateral(wfil, address(registry));

		vm.stopBroadcast();
	}
}
