// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IResolverClient} from "./interfaces/IResolverClient.sol";
import {ILiquidStakingController} from "./interfaces/ILiquidStakingController.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title LiquidStaking Controller allows to manage the parameters of Liquid Staking contract
 */
contract LiquidStakingController is ILiquidStakingController, Initializable, AccessControlUpgradeable, UUPSUpgradeable {
	error InvalidParams();
	error InvalidAccess();

	uint256 public adminFee;
	uint256 public baseProfitShare;
	uint256 public liquidityCap;
	bool public withdrawalsActivated;

	IResolverClient internal resolver;

	mapping(bytes32 => uint256) private profitShares;

	bytes32 private constant STAKING_CONTROLLER_ADMIN = keccak256("STAKING_CONTROLLER_ADMIN");

	modifier onlyAdmin() {
		if (!hasRole(STAKING_CONTROLLER_ADMIN, msg.sender)) revert InvalidAccess();
		_;
	}

	/**
	 * @dev Contract initializer function.
	 * @param _adminFee Admin fee percentage
	 * @param _baseProfitShare Base profit sharing percentage
	 */
	function initialize(
		uint256 _adminFee,
		uint256 _baseProfitShare,
		address _resolver,
		uint256 _liquidityCap,
		bool _withdrawalsActivated
	) public initializer {
		__AccessControl_init();
		__UUPSUpgradeable_init();

		if (_adminFee > 2000 || _baseProfitShare > 8000) revert InvalidParams();
		adminFee = _adminFee;
		baseProfitShare = _baseProfitShare;
		liquidityCap = _liquidityCap;
		withdrawalsActivated = _withdrawalsActivated;

		resolver = IResolverClient(_resolver);

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		grantRole(STAKING_CONTROLLER_ADMIN, msg.sender);
		_setRoleAdmin(STAKING_CONTROLLER_ADMIN, DEFAULT_ADMIN_ROLE);
	}

	/**
	 * @dev Updates profit sharing requirements for SP with `_ownerId` by `_profitShare` percentage
	 * @notice Only triggered by Liquid Staking admin or registry contract while registering SP
	 * @param _ownerId Storage provider owner ID
	 * @param _profitShare Percentage of profit sharing
	 * @param _pool Address of liquid staking pool
	 */
	function updateProfitShare(uint64 _ownerId, uint256 _profitShare, address _pool) external {
		if (!hasRole(STAKING_CONTROLLER_ADMIN, msg.sender) && msg.sender != resolver.getRegistry())
			revert InvalidAccess();

		bytes32 shareHash = keccak256(abi.encodePacked(_ownerId, _pool));

		if (_profitShare == 0) {
			profitShares[shareHash] = baseProfitShare;

			emit ProfitShareUpdate(_ownerId, 0, baseProfitShare);
		} else {
			uint256 prevShare = profitShares[shareHash];
			if (_profitShare > 8000 || _profitShare == prevShare) revert InvalidParams();

			profitShares[shareHash] = _profitShare;

			emit ProfitShareUpdate(_ownerId, prevShare, _profitShare);
		}
	}

	/**
	 * @notice Updates admin fee for the protocol revenue
	 * @param fee New admin fee
	 * @dev Make sure that admin fee is not greater than 20%
	 */
	function updateAdminFee(uint256 fee) external onlyAdmin {
		if (fee > 2000 || fee == adminFee) revert InvalidParams();

		adminFee = fee;

		emit UpdateAdminFee(fee);
	}

	/**
	 * @notice Updates base profit sharing ratio
	 * @param share New base profit sharing ratio
	 * @dev Make sure that profit sharing is not greater than 80%
	 */
	function updateBaseProfitShare(uint256 share) external onlyAdmin {
		if (share > 8000 || share == 0 || share == baseProfitShare) revert InvalidParams();

		baseProfitShare = share;

		emit UpdateBaseProfitShare(share);
	}

	/**
	 * @notice Updates liquidity cap for liquid staking protocol
	 * @param cap New admin liquidity cap
	 * @dev Make sure that new liquidity cap is not equal and higher than the prevous cap
	 */
	function updateLiquidityCap(uint256 cap) external onlyAdmin {
		if (cap > 0 && cap <= liquidityCap) revert InvalidParams();

		liquidityCap = cap;

		emit UpdateLiquidityCap(cap);
	}

	/**
	 * @notice Activates withdrawals for liquid staking protocol
	 * @dev This is a one way transaction that needs to take place after the initial activation period
	 */
	function activateWithdrawals() external onlyAdmin {
		if (withdrawalsActivated) revert InvalidParams();

		withdrawalsActivated = true;

		emit WithdrawalsActivated();
	}

	/**
	 * @notice Returns total amount of fees held by LSP for a specific SP with `_ownerId`
	 * @param _ownerId Storage Provider owner ID
	 * @param _pool Liquid Staking contract address
	 */
	function totalFees(uint64 _ownerId, address _pool) external view virtual override returns (uint256) {
		return profitShares[_computeShareHash(_ownerId, _pool)] + adminFee;
	}

	/**
	 * @notice UUPS Upgradeable function to update the liquid staking pool implementation
	 * @dev Only triggered by contract admin
	 */
	function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}

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

	/**
	 * @notice Returns the profit share for SP at the specific `_pool` by `_ownerId`
	 */
	function getProfitShares(uint64 _ownerId, address _pool) external view returns (uint256) {
		return profitShares[_computeShareHash(_ownerId, _pool)];
	}

	function _computeShareHash(uint64 _ownerId, address _pool) internal pure returns (bytes32) {
		return keccak256(abi.encodePacked(_ownerId, _pool));
	}
}
