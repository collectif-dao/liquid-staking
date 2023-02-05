// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../contracts/interfaces/IStorageProviderRegistry.sol";
import "../contracts/interfaces/ILiquidStaking.sol";

contract AfterDeploymentScript is Script {
	address private router = 0x23452f45D78940eDf620fa3929ab98E26356d1A5;
	address private stakingAddr = 0xDBc572c2E175442867CA95a9502de3A39d4D4C8a;
	address private collateralAddr = 0x1d2e9B77cfbD33F0c64E5Dc08d78776E68a3867A;
	address private registryAddr = 0x3FFaF5f2F102d651A49EBc91576b2305058c42Ab;
	address private wfil = 0x100318977B758AcBF9B78Aad3623D04468eca070;

	function run() external {
		uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
		vm.startBroadcast(deployerPrivateKey);

		ILiquidStaking staking = ILiquidStaking(stakingAddr);
		IStorageProviderRegistry registry = IStorageProviderRegistry(registryAddr);

		registry.setCollateralAddress(collateralAddr);
		staking.setCollateralAddress(collateralAddr);
		staking.setRegistryAddress(registryAddr);

		vm.stopBroadcast();
	}
}
