// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../StorageProviderCollateral.sol";
import {FilAddresses} from "filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Storage Provider Registry Mock contract that works with mock Filecoin Miner API
 * @author Collective DAO
 */
contract StorageProviderCollateralMock is StorageProviderCollateral {
	using Counters for Counters.Counter;
	using Address for address;

	/**
	 * @dev Contract constructor function.
	 * @param _wFIL WFIL token implementation
	 *
	 */
	constructor(IWETH9 _wFIL, address _registry) StorageProviderCollateral(_wFIL, _registry) {}

	/**
	 * @dev Deposit `msg.value` FIL funds by the msg.sender into collateral
	 * @notice Wrapps of FIL into WFIL token internally
	 */
	function deposit(uint64 ownerId) public payable virtual {
		uint256 amount = msg.value;
		require(amount > 0, "INVALID_AMOUNT");

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
	function withdraw(uint64 ownerId, uint256 _amount) public virtual {
		require(_amount > 0, "ZERO_AMOUNT");

		require(registry.isActiveProvider(ownerId), "INACTIVE_STORAGE_PROVIDER");

		uint256 maxWithdraw = calcMaximumWithdraw(ownerId);
		uint256 finalAmount = _amount > maxWithdraw ? maxWithdraw : _amount;

		collaterals[ownerId].availableCollateral = collaterals[ownerId].availableCollateral - finalAmount;

		_unwrapWFIL(msg.sender, finalAmount);

		emit StorageProviderCollateralWithdraw(ownerId, finalAmount);
	}
}

/**
 * @title Storage Provider Collateral Caller Mock contract that routes calls to StorageProviderCollateral
 * @author Collective DAO
 */
contract StorageProviderCollateralCallerMock {
	IStorageProviderCollateral public collateral;

	/**
	 * @dev Contract constructor function.
	 * @param _collateral StorageProviderCollateral address to route calls
	 *
	 */
	constructor(address _collateral) {
		collateral = IStorageProviderCollateral(_collateral);
	}

	/**
	 * @dev Locks required collateral amount based on `_allocated` FIL to pledge
	 * @notice Increases the total amount of locked collateral for storage provider
	 * @param _ownerId Storage provider owner ID
	 * @param _allocated FIL amount that is going to be pledged for Storage Provider
	 */
	function lock(uint64 _ownerId, uint256 _allocated) public {
		collateral.lock(_ownerId, _allocated);
	}
}
