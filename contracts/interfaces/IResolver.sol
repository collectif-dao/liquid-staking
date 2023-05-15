// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IResolver {
	error InvalidAddress();

	/**
	 * @notice Emitted when new address set
	 * @param id Address Identifier
	 * @param oldAddress Old contract implementation address
	 * @param newAddress New contract implementation address
	 */
	event AddressSet(bytes32 id, address oldAddress, address newAddress);

	/**
	 * @notice Emitted when StorageProviderRegistry address updated
	 * @param newAddress New contract implementation address
	 */
	event RegistryAddressUpdated(address newAddress);

	/**
	 * @notice Emitted when StorageProviderCollateral address updated
	 * @param newAddress New contract implementation address
	 */
	event CollateralAddressUpdated(address newAddress);

	/**
	 * @notice Emitted when LiquidStaking address updated
	 * @param newAddress New contract implementation address
	 */
	event LiquidStakingAddressUpdated(address newAddress);

	/**
	 * @notice Emitted when LiquidStaking address updated
	 * @param newAddress New contract implementation address
	 */
	event LiquidStakingControllerAddressUpdated(address newAddress);

	/**
	 * @notice Emitted when RewardCollector address updated
	 * @param newAddress New contract implementation address
	 */
	event RewardCollectorAddressUpdated(address newAddress);

	/**
	 * @notice Sets a `newAddress` for a contract by `id`
	 * @param id Address Identifier
	 * @param newAddress Contract implementation address
	 * @dev Only triggered by resolver owner
	 */
	function setAddress(bytes32 id, address newAddress) external;

	/**
	 * @notice Returns an address of a contract by its identifier
	 * @param id Address identifier
	 */
	function getAddress(bytes32 id) external view returns (address);

	/**
	 * @notice Update StorageProviderRegistry smart contract address
	 * @param newAddress StorageProviderRegistry smart contract address
	 * @dev Only triggered by resolver owner
	 */
	function setRegistryAddress(address newAddress) external;

	/**
	 * @notice Returns an address of a Storage Provider Registry contract
	 */
	function getRegistry() external view returns (address);

	/**
	 * @notice Update StorageProviderCollateral smart contract address
	 * @param newAddress StorageProviderCollateral smart contract address
	 * @dev Only triggered by resolver owner
	 */
	function setCollateralAddress(address newAddress) external;

	/**
	 * @notice Returns an address of a Storage Provider Collateral contract
	 */
	function getCollateral() external view returns (address);

	/**
	 * @notice Update LiquidStaking smart contract address
	 * @param newAddress LiquidStaking smart contract address
	 * @dev Only triggered by resolver owner
	 */
	function setLiquidStakingAddress(address newAddress) external;

	/**
	 * @notice Returns an address of a Liquid Staking contract
	 */
	function getLiquidStaking() external view returns (address);

	/**
	 * @notice Returns the implementation contract
	 */
	function getImplementation() external view returns (address);

	/**
	 * @notice Update LiquidStakingController address
	 * @param newAddress LiquidStakingController smart contract address
	 * @dev Only triggered by resolver owner
	 */
	function setLiquidStakingControllerAddress(address newAddress) external;

	/**
	 * @notice Returns an address of a Liquid Staking Controller contract
	 */
	function getLiquidStakingController() external view returns (address);

	/**
	 * @notice Update Reward Collector smart contract address
	 * @param newAddress Reward Collector smart contract address
	 * @dev Only triggered by resolver owner
	 */
	function setRewardCollectorAddress(address newAddress) external;

	/**
	 * @notice Returns an address of a Reward Collector contract
	 */
	function getRewardCollector() external view returns (address);
}
