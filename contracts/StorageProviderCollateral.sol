// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IStorageProviderCollateral.sol";
import "./interfaces/IStorageProviderRegistryClient.sol";
import "solmate/utils/SafeTransferLib.sol";
import {StorageProviderTypes} from "./types/StorageProviderTypes.sol";
import {IWETH9} from "fei-protocol/erc4626/external/PeripheryPayments.sol";
import {PrecompilesAPI} from "filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";

/**
 * @title Storage Provider Collateral stores collateral for covering potential
 * slashing risks by SPs (Storage Providers) in liquid staking protocol.
 *
 * The basis coverage is expected to be around 15% of the total FIL allocation
 * requested by SP. Over time as SPs earn FIL rewards, a locked portion of rewards
 * would be exchanged for the collateral provided upfront. Therefore locked SPs
 * collateral becomes accessible for withdrawals by stakers. This mechanism doesn't
 * create additional slashing risks as SPs are slashed by the locked rewards first,
 * making it a good option for collateralization in the system.
 *
 */
contract StorageProviderCollateral is IStorageProviderCollateral {
	using SafeTransferLib for address;

	// Mapping of storage provider collateral information to their owner ID
	mapping(uint64 => SPCollateral) public collaterals;

	// Storage Provider parameters
	struct SPCollateral {
		uint256 availableCollateral;
		uint256 lockedCollateral;
	}

	uint256 public collateralRequirements; // Number in basis points (10000 = 100%)
	uint256 public constant BASIS_POINTS = 10000;
	IStorageProviderRegistryClient public registry;

	IWETH9 public immutable WFIL; // WFIL implementation

	modifier activeStorageProvider(uint64 _ownerId) {
		require(registry.isActiveProvider(_ownerId), "INACTIVE_STORAGE_PROVIDER");
		_;
	}

	/**
	 * @dev Contract constructor function.
	 * @param _wFIL WFIL token implementation
	 *
	 */
	constructor(IWETH9 _wFIL, address _registry) {
		WFIL = _wFIL;
		registry = IStorageProviderRegistryClient(_registry);
		collateralRequirements = 1500;
	}

	receive() external payable virtual {}

	fallback() external payable virtual {}

	/**
	 * @dev Deposit `msg.value` FIL funds by the msg.sender into collateral
	 * @notice Wrapps of FIL into WFIL token internally
	 */
	function deposit() public payable {
		uint256 amount = msg.value;
		require(amount > 0, "INVALID_AMOUNT");

		uint64 ownerId = PrecompilesAPI.resolveEthAddress(msg.sender);
		require(registry.isActiveProvider(ownerId), "INACTIVE_STORAGE_PROVIDER");

		SPCollateral storage collateral = collaterals[ownerId];
		collateral.availableCollateral = collateral.availableCollateral + amount;

		_wrapFIL(address(this));

		emit StorageProviderCollateralDeposit(ownerId, amount);
	}

	/**
	 * @dev Withdraw `_amount` of FIL funds by the `msg.sender` from the collateral system
	 * @notice Unwraps of FIL into WFIL token internally and
	 * delivers maximum amount of FIL available for withdrawal if `_amount` is bigger.
	 */
	function withdraw(uint256 _amount) public {
		require(_amount > 0, "ZERO_AMOUNT");

		uint64 ownerId = PrecompilesAPI.resolveEthAddress(msg.sender);
		require(registry.isActiveProvider(ownerId), "INACTIVE_STORAGE_PROVIDER");

		uint256 maxWithdraw = calcMaximumWithdraw(ownerId);
		uint256 finalAmount = _amount > maxWithdraw ? maxWithdraw : _amount;

		collaterals[ownerId].availableCollateral = collaterals[ownerId].availableCollateral - finalAmount;

		_unwrapWFIL(msg.sender, finalAmount);

		emit StorageProviderCollateralWithdraw(ownerId, finalAmount);
	}

	/**
	 * @dev Locks required collateral amount based on `_allocated` FIL to pledge
	 * @notice Increases the total amount of locked collateral for storage provider
	 * @param _ownerId Storage provider owner ID
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function lock(uint64 _ownerId, uint256 _allocated) public activeStorageProvider(_ownerId) {
		require(registry.isActivePool(msg.sender), "INVALID_ACCESS");
		require(_allocated > 0, "ZERO_ALLOCATION");
		(, , , uint256 allocationLimit, , uint256 usedAllocation, uint256 accruedRewards, , , ) = registry
			.getStorageProvider(_ownerId);

		require(usedAllocation + _allocated <= allocationLimit, "ALLOCATION_OVERFLOW");

		uint256 totalRequirements = calcCollateralRequirements(usedAllocation, accruedRewards, _allocated);

		SPCollateral memory collateral = collaterals[_ownerId];
		require(
			totalRequirements <= collateral.lockedCollateral + collateral.availableCollateral,
			"INSUFFICIENT_COLLATERAL"
		);

		registry.increaseUsedAllocation(_ownerId, _allocated);

		uint256 lockAmount = calcLockAmount(_allocated);

		collateral.lockedCollateral = collateral.lockedCollateral + lockAmount;
		collateral.availableCollateral = collateral.availableCollateral - lockAmount;

		collaterals[_ownerId] = collateral;

		emit StorageProviderCollateralLock(_ownerId, _allocated, lockAmount);
	}

	/**
	 * @notice Return Storage Provider Collateral information with `_provider` address
	 */
	function getCollateral(uint64 _ownerId) public view returns (uint256, uint256) {
		SPCollateral memory collateral = collaterals[_ownerId];
		return (collateral.availableCollateral, collateral.lockedCollateral);
	}

	/**
	 * @notice Return Storage Provider Available Collateral information with `_provider` address
	 */
	function getAvailableCollateral(uint64 _ownerId) public view returns (uint256) {
		return collaterals[_ownerId].availableCollateral;
	}

	/**
	 * @notice Return Storage Provider Locked Collateral information with `_provider` address
	 */
	function getLockedCollateral(uint64 _ownerId) public view returns (uint256) {
		return collaterals[_ownerId].lockedCollateral;
	}

	/**
	 * @notice Calculates max collateral withdrawal amount for SP depending on the
	 * total used FIL allocation and locked rewards.
	 * @param _ownerId Storage Provider owner address
	 */
	function calcMaximumWithdraw(uint64 _ownerId) internal view returns (uint256 totalCollateral) {
		(, , , , , uint256 usedAllocation, uint256 accruedRewards, , , ) = registry.getStorageProvider(_ownerId);

		uint256 requirements = calcCollateralRequirements(usedAllocation, accruedRewards, 0);
		SPCollateral memory collateral = collaterals[_ownerId];

		totalCollateral = collateral.availableCollateral + collateral.lockedCollateral - requirements;
	}

	/**
	 * @notice Calculates total collateral requirements for SP depending on the
	 * total used FIL allocation and locked rewards.
	 * @param _usedAllocation Already used FIL allocation by Storage Provider
	 * @param _accruedRewards Accured rewards by SP
	 * @param _allocationToUse Allocation to be used by SP
	 */
	function calcCollateralRequirements(
		uint256 _usedAllocation,
		uint256 _accruedRewards,
		uint256 _allocationToUse
	) internal view returns (uint256 totalRequirements) {
		uint256 usedAllocation = _allocationToUse > 0 ? _usedAllocation + _allocationToUse : _usedAllocation;

		totalRequirements = ((usedAllocation - _accruedRewards) * collateralRequirements) / BASIS_POINTS;
	}

	/**
	 * @notice Calculates total lock amount for a given allocation
	 * @param _usedAllocation Used FIL allocation amount
	 */
	function calcLockAmount(uint256 _usedAllocation) internal view returns (uint256 lockAmount) {
		lockAmount = (_usedAllocation * collateralRequirements) / BASIS_POINTS;
	}

	/**
	 * @notice Wraps FIL into WFIL and transfers it to the `_recipient` address
	 * @param _recipient WFIL recipient address
	 */
	function _wrapFIL(address _recipient) internal {
		uint256 amount = msg.value;

		WFIL.deposit{value: amount}();
		WFIL.transfer(_recipient, amount);
	}

	/**
	 * @notice Unwraps `_amount` of WFIL into FIL and transfers it to the `_recipient` address
	 * @param _recipient WFIL recipient address
	 */
	function _unwrapWFIL(address _recipient, uint256 _amount) internal {
		uint256 balanceWETH9 = WFIL.balanceOf(address(this));
		require(balanceWETH9 >= _amount, "Insufficient WETH9");

		if (balanceWETH9 > 0) {
			WFIL.withdraw(_amount);
			_recipient.safeTransferETH(_amount);
		}
	}
}
