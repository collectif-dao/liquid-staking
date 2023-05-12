// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../StorageProviderCollateral.sol";
import {FilAddresses} from "filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {Leb128} from "filecoin-solidity/contracts/v0.8/utils/Leb128.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Storage Provider Registry Mock contract that works with mock Filecoin Miner API
 * @author Collective DAO
 */
contract StorageProviderCollateralMock is StorageProviderCollateral {
	bytes32 private constant COLLATERAL_ADMIN = keccak256("COLLATERAL_ADMIN");
	bytes32 private constant SLASHING_AGENT = keccak256("SLASHING_AGENT");

	/**
	 * @dev Contract initializer function.
	 * @param _wFIL WFIL token implementation
	 * @param _resolver Resolver contract implementation
	 * @param _baseRequirements Base collateral requirements for SPs
	 */
	function initialize(IWFIL _wFIL, address _resolver, uint256 _baseRequirements) public override initializer {
		__AccessControl_init();
		__ReentrancyGuard_init();
		__UUPSUpgradeable_init();

		WFIL = _wFIL;
		resolver = IResolverClient(_resolver);

		if (_baseRequirements == 0 || _baseRequirements > 10000) revert InvalidParams();
		baseRequirements = _baseRequirements;

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setRoleAdmin(COLLATERAL_ADMIN, DEFAULT_ADMIN_ROLE);
		grantRole(COLLATERAL_ADMIN, msg.sender);
		grantRole(SLASHING_AGENT, msg.sender);
		_setRoleAdmin(SLASHING_AGENT, DEFAULT_ADMIN_ROLE);
	}

	/**
	 * @dev Deposit `msg.value` FIL funds by the msg.sender into collateral
	 * @notice Wrapps of FIL into WFIL token internally
	 */
	function deposit(uint64 ownerId) public payable virtual {
		uint256 amount = msg.value;
		if (amount == 0) revert InvalidParams();

		if (!IRegistryClient(resolver.getRegistry()).isActiveProvider(ownerId)) revert InactiveSP();

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
		if (_amount == 0) revert InvalidParams();
		if (!IRegistryClient(resolver.getRegistry()).isActiveProvider(ownerId)) revert InactiveSP();

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

	function increaseUsedAllocation(uint64 ownerId, uint256 amount) public {
		IRegistryClient(resolver.getRegistry()).increaseUsedAllocation(ownerId, amount, block.timestamp);
	}

	/**
	 * @dev Slashes SP for a `_slashingAmt` and delivers WFIL amount to the `msg.sender` LSP
	 * @notice Doesn't perform a rebalancing checks
	 * @param _ownerId Storage provider owner ID
	 * @param _slashingAmt Slashing amount for SP
	 * @param _pool Liquid staking pool address
	 */
	function slash(
		uint64 _ownerId,
		uint256 _slashingAmt,
		address _pool
	) external nonReentrant activeStorageProvider(_ownerId) {
		_slash(_ownerId, _slashingAmt, _pool);
	}
}

interface IStorageProviderCollateralMock is IStorageProviderCollateral {
	/**
	 * @dev Slashes SP for a `_slashingAmt` and delivers WFIL amount to the `msg.sender` LSP
	 * @notice Doesn't perform a rebalancing checks
	 * @param _ownerId Storage provider owner ID
	 * @param _slashingAmt Slashing amount for SP
	 * @param _pool Liquid staking pool address
	 */
	function slash(uint64 _ownerId, uint256 _slashingAmt, address _pool) external;
}

/**
 * @title Storage Provider Collateral Caller Mock contract that routes calls to StorageProviderCollateral
 * @author Collective DAO
 */
contract StorageProviderCollateralCallerMock {
	IStorageProviderCollateralMock public collateral;

	/**
	 * @dev Contract constructor function.
	 * @param _collateral StorageProviderCollateral address to route calls
	 *
	 */
	constructor(address _collateral) {
		collateral = IStorageProviderCollateralMock(_collateral);
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

	/**
	 * @dev Fits collateral amounts based on SP pledge usage, distributed rewards and pledge paybacks
	 * @notice Rebalances the total locked and available collateral amounts
	 * @param _ownerId Storage provider owner ID
	 */
	function fit(uint64 _ownerId) public {
		collateral.fit(_ownerId);
	}

	/**
	 * @dev Slashes SP for a `_slashingAmt` and delivers WFIL amount to the `msg.sender` LSP
	 * @notice Doesn't perform a rebalancing checks
	 * @param _ownerId Storage provider owner ID
	 * @param _slashingAmt Slashing amount for SP
	 */
	function slash(uint64 _ownerId, uint256 _slashingAmt, address _pool) public {
		collateral.slash(_ownerId, _slashingAmt, _pool);
	}
}
