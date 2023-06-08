// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IResolver} from "./interfaces/IResolver.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title Resolver contract used to resolve registered addresses in the protocol
 * by their identifiers
 */
contract Resolver is IResolver, Initializable, OwnableUpgradeable, UUPSUpgradeable {
	// Map of registered addresses (identifier => registeredAddress)
	mapping(bytes32 => address) private _addresses;

	bytes32 private constant LIQUID_STAKING = "LIQUID_STAKING";
	bytes32 private constant REGISTRY = "REGISTRY";
	bytes32 private constant COLLATERAL = "COLLATERAL";
	bytes32 private constant LIQUID_STAKING_CONTROLLER = "LIQUID_STAKING_CONTROLLER";
	bytes32 private constant REWARD_COLLECTOR = "REWARD_COLLECTOR";
	bytes32 private constant PROTOCOL_REWARDS = "PROTOCOL_REWARDS";

	/**
	 * @dev Contract initializer function.
	 */
	function initialize() public initializer {
		__Ownable_init();
		__UUPSUpgradeable_init();
	}

	/**
	 * @notice Sets a `newAddress` for a contract by `id`
	 * @param id Address Identifier
	 * @param newAddress Contract implementation address
	 * @dev Only triggered by resolver owner
	 */
	function setAddress(bytes32 id, address newAddress) external override onlyOwner {
		address oldAddress = _addresses[id];

		if (oldAddress == newAddress || newAddress == address(0)) revert InvalidAddress();

		_addresses[id] = newAddress;
		emit AddressSet(id, oldAddress, newAddress);
	}

	/**
	 * @notice Returns an address of a contract by its identifier
	 * @param id Address identifier
	 */
	function getAddress(bytes32 id) public view override returns (address) {
		return _addresses[id];
	}

	/**
	 * @notice Update StorageProviderRegistry smart contract address
	 * @param newAddress StorageProviderRegistry smart contract address
	 * @dev Only triggered by resolver owner
	 */
	function setRegistryAddress(address newAddress) external override onlyOwner {
		_setAddress(REGISTRY, newAddress);

		emit RegistryAddressUpdated(newAddress);
	}

	/**
	 * @notice Returns an address of a Storage Provider Registry contract
	 */
	function getRegistry() external view override returns (address) {
		return getAddress(REGISTRY);
	}

	/**
	 * @notice Update StorageProviderCollateral smart contract address
	 * @param newAddress StorageProviderCollateral smart contract address
	 * @dev Only triggered by resolver owner
	 */
	function setCollateralAddress(address newAddress) external override onlyOwner {
		_setAddress(COLLATERAL, newAddress);

		emit CollateralAddressUpdated(newAddress);
	}

	/**
	 * @notice Returns an address of a Storage Provider Collateral contract
	 */
	function getCollateral() external view override returns (address) {
		return getAddress(COLLATERAL);
	}

	/**
	 * @notice Update LiquidStaking smart contract address
	 * @param newAddress LiquidStaking smart contract address
	 * @dev Only triggered by resolver owner
	 */
	function setLiquidStakingAddress(address newAddress) external override onlyOwner {
		_setAddress(LIQUID_STAKING, newAddress);

		emit LiquidStakingAddressUpdated(newAddress);
	}

	/**
	 * @notice Returns an address of a Liquid Staking contract
	 */
	function getLiquidStaking() external view override returns (address) {
		return getAddress(LIQUID_STAKING);
	}

	/**
	 * @notice Update LiquidStakingController address
	 * @param newAddress LiquidStakingController smart contract address
	 * @dev Only triggered by resolver owner
	 */
	function setLiquidStakingControllerAddress(address newAddress) external override onlyOwner {
		_setAddress(LIQUID_STAKING_CONTROLLER, newAddress);

		emit LiquidStakingControllerAddressUpdated(newAddress);
	}

	/**
	 * @notice Returns an address of a Liquid Staking Controller contract
	 */
	function getLiquidStakingController() external view override returns (address) {
		return getAddress(LIQUID_STAKING_CONTROLLER);
	}

	/**
	 * @notice Update Reward Collector contract address
	 * @param newAddress RewardCollector address
	 * @dev Only triggered by resolver owner
	 */
	function setRewardCollectorAddress(address newAddress) external override onlyOwner {
		_setAddress(REWARD_COLLECTOR, newAddress);

		emit RewardCollectorAddressUpdated(newAddress);
	}

	/**
	 * @notice Returns an address of a Reward Collector contract
	 */
	function getRewardCollector() external view override returns (address) {
		return getAddress(REWARD_COLLECTOR);
	}

	/**
	 * @notice Update Protocol Rewards address
	 * @param newAddress Protocol Rewards address
	 * @dev Only triggered by resolver owner
	 */
	function setProtocolRewardsAddress(address newAddress) external override onlyOwner {
		_setAddress(PROTOCOL_REWARDS, newAddress);

		emit ProtocolRewardsAddressUpdated(newAddress);
	}

	/**
	 * @notice Returns a ProtocolRewards address
	 */
	function getProtocolRewards() external view override returns (address) {
		return getAddress(PROTOCOL_REWARDS);
	}

	function _setAddress(bytes32 id, address newAddr) internal {
		if (newAddr == _addresses[id] || newAddr == address(0)) revert InvalidAddress();

		_addresses[id] = newAddr;
	}

	/**
	 * @notice UUPS Upgradeable function to update the liquid staking pool implementation
	 * @dev Only triggered by contract admin
	 */
	function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

	/**
	 * @notice Returns the version of clFIL token contract
	 */
	function version() external pure virtual returns (string memory) {
		return "v1";
	}

	/**
	 * @notice Returns the implementation contract
	 */
	function getImplementation() external view returns (address) {
		return _getImplementation();
	}
}
