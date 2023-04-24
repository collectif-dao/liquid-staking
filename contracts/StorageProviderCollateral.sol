// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IStorageProviderCollateral.sol";
import "./interfaces/IStorageProviderRegistryClient.sol";
import "solmate/utils/SafeTransferLib.sol";
import {StorageProviderTypes} from "./types/StorageProviderTypes.sol";
import {IWETH9} from "fei-protocol/erc4626/external/PeripheryPayments.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
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
contract StorageProviderCollateral is IStorageProviderCollateral, ReentrancyGuard, DSTestPlus {
	using SafeTransferLib for address;
	using FixedPointMathLib for uint256;

	// Mapping of storage provider collateral information to their owner ID
	mapping(uint64 => SPCollateral) public collaterals;

	// Mapping of storage provider total slashing amounts to their owner ID
	mapping(uint64 => uint256) public slashings;

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

		(uint256 lockedWithdraw, uint256 availableWithdraw, bool isUnlock) = calcMaximumWithdraw(ownerId);
		uint256 maxWithdraw = lockedWithdraw + availableWithdraw;
		uint256 finalAmount = _amount > maxWithdraw ? maxWithdraw : _amount;
		uint256 delta;

		if (isUnlock) {
			delta = finalAmount - lockedWithdraw;
			collaterals[ownerId].lockedCollateral = collaterals[ownerId].lockedCollateral - lockedWithdraw; // 10 - 2 == 8
			collaterals[ownerId].availableCollateral = collaterals[ownerId].availableCollateral - delta; // 5 + 1 == 6

			_unwrapWFIL(msg.sender, finalAmount);
		} else {
			collaterals[ownerId].availableCollateral = collaterals[ownerId].availableCollateral - finalAmount;
		}

		emit StorageProviderCollateralWithdraw(ownerId, finalAmount);
	}

	/**
	 * @dev Locks required collateral amount based on `_allocated` FIL to pledge
	 * @notice Increases the total amount of locked collateral for storage provider
	 * @param _ownerId Storage provider owner ID
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function lock(uint64 _ownerId, uint256 _allocated) external nonReentrant activeStorageProvider(_ownerId) {
		require(registry.isActivePool(msg.sender), "INVALID_ACCESS");
		require(_allocated > 0, "ZERO_ALLOCATION");

		_rebalance(_ownerId, _allocated);
		registry.increaseUsedAllocation(_ownerId, _allocated, block.timestamp);
	}

	/**
	 * @dev Fits collateral amounts based on SP pledge usage, distributed rewards and pledge paybacks
	 * @notice Rebalances the total locked and available collateral amounts
	 * @param _ownerId Storage provider owner ID
	 */
	function fit(uint64 _ownerId) external activeStorageProvider(_ownerId) {
		require(registry.isActivePool(msg.sender), "INVALID_ACCESS");

		_rebalance(_ownerId, 0);
	}

	/**
	 * @dev Slashes SP for a `_slashingAmt` and delivers WFIL amount to the `msg.sender` LSP
	 * @notice Doesn't perform a rebalancing checks
	 * @param _ownerId Storage provider owner ID
	 * @param _slashingAmt Slashing amount for SP
	 */
	function slash(uint64 _ownerId, uint256 _slashingAmt) external nonReentrant activeStorageProvider(_ownerId) {
		require(registry.isActivePool(msg.sender), "INVALID_ACCESS");

		SPCollateral memory collateral = collaterals[_ownerId];
		if (_slashingAmt <= collateral.lockedCollateral) {
			collateral.lockedCollateral = collateral.lockedCollateral - _slashingAmt;
		} else {
			uint256 totalCollateral = collateral.lockedCollateral + collateral.availableCollateral;
			require(_slashingAmt <= totalCollateral, "NOT_ENOUGH_COLLATERAL"); // TODO: introduce debt for SP to cover worst case scenario
			uint256 delta = _slashingAmt - collateral.lockedCollateral;

			collateral.lockedCollateral = 0;
			collateral.availableCollateral = collateral.availableCollateral - delta;
		}

		collaterals[_ownerId] = collateral;
		slashings[_ownerId] += _slashingAmt;

		WFIL.transfer(msg.sender, _slashingAmt);

		emit StorageProviderCollateralSlash(_ownerId, _slashingAmt, msg.sender);
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
	function calcMaximumWithdraw(uint64 _ownerId) internal returns (uint256, uint256, bool) {
		(, , uint256 usedAllocation, , uint256 accruedRewards, uint256 repaidPledge) = registry.allocations(_ownerId);

		uint256 requirements = calcCollateralRequirements(usedAllocation, accruedRewards, repaidPledge, 0);
		SPCollateral memory collateral = collaterals[_ownerId];

		emit log_named_uint("collateral.lockedCollateral:", collateral.lockedCollateral);
		emit log_named_uint("collateral.availableCollateral:", collateral.availableCollateral);
		emit log_named_uint("requirements:", requirements);

		(uint256 adjAmt, bool isUnlock) = calcCollateralAdjustment(collateral.lockedCollateral, requirements);

		emit log_named_uint("isUnlock:", isUnlock ? 1 : 0);
		emit log_named_uint("adjAmt before:", adjAmt);

		if (!isUnlock) {
			adjAmt = collateral.availableCollateral - adjAmt;
			emit log_named_uint("adjAmt:", collateral.availableCollateral - adjAmt);

			return (0, adjAmt, isUnlock);
		} else {
			return (adjAmt, collateral.availableCollateral, isUnlock);
		}
	}

	/**
	 * @notice Rebalances collateral for a specified `_ownerId` with `_allocated` in mind
	 * @param _ownerId Storage Provider owner address
	 * @param _allocated Hypothetical allocation for SP
	 */
	function _rebalance(uint64 _ownerId, uint256 _allocated) internal {
		(uint256 allocationLimit, , uint256 usedAllocation, , uint256 accruedRewards, uint256 repaidPledge) = registry
			.allocations(_ownerId);

		if (_allocated > 0) {
			require(usedAllocation + _allocated <= allocationLimit, "ALLOCATION_OVERFLOW");
		}

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

		(uint256 adjAmt, bool isUnlock) = calcCollateralAdjustment(collateral.lockedCollateral, totalRequirements);

		if (!isUnlock) {
			collateral.lockedCollateral = collateral.lockedCollateral + adjAmt;
			collateral.availableCollateral = collateral.availableCollateral - adjAmt;

			emit StorageProviderCollateralRebalance(_ownerId, adjAmt, 0, isUnlock);
		} else {
			collateral.lockedCollateral = collateral.lockedCollateral - adjAmt;
			collateral.availableCollateral = collateral.availableCollateral + adjAmt;

			emit StorageProviderCollateralRebalance(_ownerId, 0, adjAmt, isUnlock);
		}

		collaterals[_ownerId] = collateral;
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
	) internal pure returns (uint256, bool) {
		if (_lockedCollateral > 0 && _collateralRequirements > 0) {
			if (_lockedCollateral > _collateralRequirements) {
				return (_lockedCollateral - _collateralRequirements, true);
			} else {
				return (_collateralRequirements - _lockedCollateral, false);
			}
		} else if (_lockedCollateral > 0 && _collateralRequirements == 0) {
			return (_lockedCollateral, true);
		} else if (_lockedCollateral == 0 && _collateralRequirements > 0) {
			return (_collateralRequirements, false);
		} else if (_lockedCollateral == 0 && _collateralRequirements == 0) {
			return (0, true);
		}
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
