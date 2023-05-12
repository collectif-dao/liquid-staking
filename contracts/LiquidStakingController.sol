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
	error InvalidAddress();

	uint256 public adminFee;
	uint256 public baseProfitShare;
	address public rewardCollector;

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
	 * @param _rewardCollector Rewards collector address
	 */
	function initialize(
		uint256 _adminFee,
		uint256 _baseProfitShare,
		address _rewardCollector,
		address _resolver
	) public initializer {
		__AccessControl_init();
		__UUPSUpgradeable_init();

		if (_adminFee > 2000 || _rewardCollector == address(0)) revert InvalidParams();
		adminFee = _adminFee;
		baseProfitShare = _baseProfitShare;
		rewardCollector = _rewardCollector;

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
		uint256 prevFee = adminFee;
		if (fee > 2000 || fee == prevFee) revert InvalidParams();

		adminFee = fee;

		emit UpdateAdminFee(fee);
	}

	/**
	 * @notice Updates base profit sharing ratio
	 * @param share New base profit sharing ratio
	 * @dev Make sure that profit sharing is not greater than 80%
	 */
	function updateBaseProfitShare(uint256 share) external onlyAdmin {
		uint256 prevShare = baseProfitShare;
		if (share > 8000 || share == 0 || share == prevShare) revert InvalidParams();

		baseProfitShare = share;

		emit UpdateBaseProfitShare(share);
	}

	/**
	 * @notice Updates reward collector address of the protocol revenue
	 * @param collector New rewards collector address
	 */
	function updateRewardsCollector(address collector) external onlyAdmin {
		address prevAddr = rewardCollector;
		if (collector == address(0) || prevAddr == collector) revert InvalidAddress();

		rewardCollector = collector;

		emit UpdateRewardCollector(collector);
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
