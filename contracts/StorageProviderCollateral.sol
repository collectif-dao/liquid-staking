// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IStorageProviderCollateral.sol";
import "./interfaces/IStorageProviderRegistryClient.sol";
import "solmate/utils/SafeTransferLib.sol";
import {StorageProviderTypes} from "./types/StorageProviderTypes.sol";
import {IWETH9} from "fei-protocol/erc4626/external/PeripheryPayments.sol";
import {PrecompilesAPI} from "filecoin-solidity/contracts/v0.8/PrecompilesAPI.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

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
contract StorageProviderCollateral is IStorageProviderCollateral, DSTestPlus {
	using SafeTransferLib for address;
	using FixedPointMathLib for uint256;

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

		(uint256 maxWithdraw, bool isUnlock) = calcMaximumWithdraw(ownerId);
		uint256 finalAmount = _amount > maxWithdraw ? maxWithdraw : _amount;

		if (isUnlock) {
			collaterals[ownerId].lockedCollateral = collaterals[ownerId].lockedCollateral - finalAmount;
		} else {
			collaterals[ownerId].availableCollateral = collaterals[ownerId].availableCollateral - finalAmount;
		}

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
		(uint256 allocationLimit, , uint256 usedAllocation, , uint256 accruedRewards, uint256 repaidPledge) = registry
			.allocations(_ownerId);

		require(usedAllocation + _allocated <= allocationLimit, "ALLOCATION_OVERFLOW");

		uint256 totalRequirements = calcCollateralRequirements(
			usedAllocation,
			accruedRewards,
			repaidPledge,
			_allocated
		);

		SPCollateral memory collateral = collaterals[_ownerId];
		require(
			totalRequirements <= collateral.lockedCollateral + collateral.availableCollateral,
			"INSUFFICIENT_COLLATERAL"
		);

		registry.increaseUsedAllocation(_ownerId, _allocated, block.timestamp);

		(uint256 adjAmt, bool isUnlock) = calcCollateralAdjustment(collateral.lockedCollateral, totalRequirements);

		emit log_named_uint("adjAmt:", adjAmt);
		emit log_named_uint("isUnlock:", isUnlock ? 1 : 0);

		if (!isUnlock) {
			collateral.lockedCollateral = collateral.lockedCollateral + adjAmt;
			collateral.availableCollateral = collateral.availableCollateral - adjAmt;
		} else {
			collateral.lockedCollateral = collateral.lockedCollateral - adjAmt;
			collateral.availableCollateral = collateral.availableCollateral + adjAmt;
		}

		collaterals[_ownerId] = collateral;

		emit StorageProviderCollateralLock(_ownerId, _allocated, adjAmt);
	}

	/**
	 * @dev Fits collateral amounts based on SP pledge usage, distributed rewards and pledge paybacks
	 * @notice Rebalances the total locked and available collateral amounts
	 * @param _ownerId Storage provider owner ID
	 */
	function fit(uint64 _ownerId) public activeStorageProvider(_ownerId) {
		require(registry.isActivePool(msg.sender), "INVALID_ACCESS");
		(, , uint256 usedAllocation, , uint256 accruedRewards, uint256 repaidPledge) = registry.allocations(_ownerId);

		uint256 totalRequirements = calcCollateralRequirements(usedAllocation, accruedRewards, repaidPledge, 0);

		emit log_named_uint("totalRequirements:", totalRequirements);

		SPCollateral memory collateral = collaterals[_ownerId];
		require(
			totalRequirements <= collateral.lockedCollateral + collateral.availableCollateral,
			"INSUFFICIENT_COLLATERAL"
		);
		emit log_named_uint("collateral.lockedCollateral:", collateral.lockedCollateral);
		emit log_named_uint("collateral.availableCollateral:", collateral.availableCollateral);

		(uint256 adjAmt, bool isUnlock) = calcCollateralAdjustment(collateral.lockedCollateral, totalRequirements);

		emit log_named_uint("adjAmt:", adjAmt);
		emit log_named_uint("isUnlock:", isUnlock ? 1 : 0);

		if (!isUnlock) {
			collateral.lockedCollateral = collateral.lockedCollateral + adjAmt;
			collateral.availableCollateral = collateral.availableCollateral - adjAmt;
		} else {
			collateral.lockedCollateral = collateral.lockedCollateral - adjAmt;
			collateral.availableCollateral = collateral.availableCollateral + adjAmt;
		}

		collaterals[_ownerId] = collateral;

		emit StorageProviderCollateralFit(_ownerId, adjAmt, isUnlock);
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
	function calcMaximumWithdraw(uint64 _ownerId) internal returns (uint256, bool) {
		(, , uint256 usedAllocation, , uint256 accruedRewards, uint256 repaidPledge) = registry.allocations(_ownerId);

		uint256 requirements = calcCollateralRequirements(usedAllocation, accruedRewards, repaidPledge, 0);
		SPCollateral memory collateral = collaterals[_ownerId];

		emit log_named_uint("collateral.lockedCollateral:", collateral.lockedCollateral);
		emit log_named_uint("collateral.availableCollateral:", collateral.availableCollateral);
		emit log_named_uint("requirements:", requirements);

		(uint256 adjAmt, bool isUnlock) = calcCollateralAdjustment(collateral.lockedCollateral, requirements);

		emit log_named_uint("adjAmt:", adjAmt);
		emit log_named_uint("isUnlock:", isUnlock ? 1 : 0);

		if (!isUnlock) {
			adjAmt = collateral.availableCollateral - adjAmt;
		}

		return (adjAmt, isUnlock);
	}

	/**
	 * @notice Calculates total collateral requirements for SP depending on the
	 * total used FIL allocation and locked rewards.
	 * @param _usedAllocation Already used FIL allocation by Storage Provider
	 * @param _accruedRewards Accured rewards by SP
	 * @param _repaidPledge Repaid pledge by SP
	 * @param _allocationToUse Allocation to be used by SP
	 */
	function calcCollateralRequirements(
		uint256 _usedAllocation,
		uint256 _accruedRewards,
		uint256 _repaidPledge,
		uint256 _allocationToUse
	) internal view returns (uint256) {
		uint256 usedAllocation = _allocationToUse > 0 ? _usedAllocation + _allocationToUse : _usedAllocation;
		uint256 req = (usedAllocation - _accruedRewards) - _repaidPledge;

		if (req > 0) {
			return req.mulDivDown(collateralRequirements, BASIS_POINTS);
		} else {
			return 0;
		}
	}

	/**
	 * @notice Calculates collateral adjustment for SP depending on the
	 * total locked collateral and overall collateral requirements.
	 * @param _lockedCollateral Locked collateral amount for Storage Provider
	 * @param _collateralRequirements Collateral requirements for SP
	 */
	function calcCollateralAdjustment(
		uint256 _lockedCollateral,
		uint256 _collateralRequirements
	) internal pure returns (uint256 adjAmt, bool isUnlock) {
		if (_lockedCollateral > 0 && _collateralRequirements > 0) {
			if (_lockedCollateral > _collateralRequirements) {
				adjAmt = _lockedCollateral - _collateralRequirements;
				isUnlock = true;
			} else {
				adjAmt = _collateralRequirements - _lockedCollateral;
				isUnlock = false;
			}
		} else if (_lockedCollateral > 0 && _collateralRequirements == 0) {
			adjAmt = _lockedCollateral;
			isUnlock = true;
		} else if (_lockedCollateral == 0 && _collateralRequirements > 0) {
			adjAmt = _collateralRequirements;
			isUnlock = false;
		}

		return (adjAmt, isUnlock);
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
