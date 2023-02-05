// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../contracts/interfaces/IStorageProviderRegistry.sol";
import "../contracts/interfaces/ILiquidStaking.sol";

contract AfterDeploymentScript is Script {
	address private router = 0xdD983F73765022a96bf8970Da6A0CdEf7830Abc1;
	address private stakingAddr = 0x0C5e71f8cC828D12C19AB807d793ebB4c832C837;
	address private collateralAddr = 0xD43D81D79455526222B006a34300990b228b5457;
	address private registryAddr = 0xD2e3c87b83D77Ba725adC7ac8c40289558d06585;
	address private wfil = 0x652DC2a67dE2C24c2B29f5016DBcF500f75eCfCe;
	address private oracle = 0x363290A6993d85e55e61e92B7A0c25a1ab9f6c53;

	function run() external {
		uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
		vm.startBroadcast(deployerPrivateKey);

		ILiquidStaking staking = ILiquidStaking(stakingAddr);
		IStorageProviderRegistry registry = IStorageProviderRegistry(registryAddr);

		registry.setCollateralAddress(collateralAddr);
		staking.setCollateralAddress(collateralAddr);
		staking.setRegistryAddress(registryAddr);
		registry.registerPool(address(staking));

		vm.stopBroadcast();
	}
}
