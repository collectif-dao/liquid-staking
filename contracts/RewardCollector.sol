// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ILiquidStakingControllerClient as IStakingControllerClient} from "./interfaces/ILiquidStakingControllerClient.sol";
import {IStorageProviderCollateralClient as ICollateralClient} from "./interfaces/IStorageProviderCollateralClient.sol";
import {IStorageProviderRegistryClient as IRegistryClient} from "./interfaces/IStorageProviderRegistryClient.sol";
import {IResolverClient} from "./interfaces/IResolverClient.sol";
import {IRewardCollector} from "./interfaces/IRewardCollector.sol";
import {ILiquidStakingClient} from "./interfaces/ILiquidStakingClient.sol";
import {IWFIL} from "./libraries/tokens/IWFIL.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {MinerAPI, CommonTypes, MinerTypes} from "filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import {BigInts} from "filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import {FilAddresses} from "filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {FilAddress} from "fevmate/utils/FilAddress.sol";
import {SendAPI} from "filecoin-solidity/contracts/v0.8/SendAPI.sol";

/**
 * @title RewardCollector contract acts as beneficiary address for storage providers.
 * It allows the protocol to collect fees and distribute them to the Liquid Staking pool
 */
contract RewardCollector is
	IRewardCollector,
	Initializable,
	ReentrancyGuardUpgradeable,
	AccessControlUpgradeable,
	UUPSUpgradeable
{
	error InvalidAccess();
	error InvalidParams();
	error InactivePool();
	error IncorrectWithdrawal();
	error BigNumConversion();

	uint256 private constant BASIS_POINTS = 10000;

	IResolverClient internal resolver;
	IWFIL public WFIL;

	bytes32 private constant FEE_DISTRIBUTOR = keccak256("FEE_DISTRIBUTOR");

	modifier onlyAdmin() {
		if (!hasRole(FEE_DISTRIBUTOR, msg.sender)) revert InvalidAccess();
		_;
	}

	/**
	 * @dev Contract initializer function.
	 * @param _resolver Resolver contract address
	 */
	function initialize(address _wFIL, address _resolver) public initializer {
		__AccessControl_init();
		__ReentrancyGuard_init();
		__UUPSUpgradeable_init();

		WFIL = IWFIL(_wFIL);
		resolver = IResolverClient(_resolver);

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		grantRole(FEE_DISTRIBUTOR, msg.sender);
		_setRoleAdmin(FEE_DISTRIBUTOR, DEFAULT_ADMIN_ROLE);
	}

	receive() external payable virtual {}

	fallback() external payable virtual {}

	/**
	 * @notice Withdraw initial pledge from Storage Provider's Miner Actor by `ownerId`
	 * This function is triggered when sector is not extended by miner actor and initial pledge unlocked
	 * @param ownerId Storage provider owner ID
	 * @param amount Initial pledge amount
	 * @dev Please note that pledge amount withdrawn couldn't exceed used allocation by SP
	 */
	function withdrawPledge(uint64 ownerId, uint256 amount) external virtual nonReentrant {
		if (!hasRole(FEE_DISTRIBUTOR, msg.sender)) revert InvalidAccess();
		if (amount == 0) revert InvalidParams();

		IRegistryClient registry = IRegistryClient(resolver.getRegistry());

		(, address stakingPool, uint64 minerId, ) = registry.getStorageProvider(ownerId);

		CommonTypes.BigInt memory withdrawnBInt = MinerAPI.withdrawBalance(
			CommonTypes.FilActorId.wrap(minerId),
			BigInts.fromUint256(amount)
		);

		(uint256 withdrawn, bool abort) = BigInts.toUint256(withdrawnBInt);
		if (abort) revert BigNumConversion();
		if (withdrawn != amount) revert IncorrectWithdrawal();

		WFIL.deposit{value: withdrawn}();
		WFIL.transfer(stakingPool, withdrawn);

		registry.increasePledgeRepayment(ownerId, amount);

		ILiquidStakingClient(stakingPool).repayPledge(amount);
		ICollateralClient(resolver.getCollateral()).fit(ownerId);

		emit WithdrawPledge(ownerId, minerId, amount);
	}

	struct WithdrawRewardsLocalVars {
		uint256 restakingRatio;
		address restakingAddress;
		uint256 withdrawn;
		bool abort;
		bool isRestaking;
		uint256 protocolFees;
		uint256 stakingProfit;
		uint256 restakingAmt;
		uint256 protocolShare;
		uint256 spShare;
	}

	/**
	 * @notice Withdraw FIL assets from Storage Provider by `ownerId` and it's Miner actor
	 * and restake `restakeAmount` into the Storage Provider specified f4 address
	 * @param ownerId Storage provider owner ID
	 * @param amount Withdrawal amount
	 */
	function withdrawRewards(uint64 ownerId, uint256 amount) external virtual nonReentrant {
		if (!hasRole(FEE_DISTRIBUTOR, msg.sender)) revert InvalidAccess();

		WithdrawRewardsLocalVars memory vars;
		IRegistryClient registry = IRegistryClient(resolver.getRegistry());

		(, address stakingPool, uint64 minerId, ) = registry.getStorageProvider(ownerId);

		CommonTypes.BigInt memory withdrawnBInt = MinerAPI.withdrawBalance(
			CommonTypes.FilActorId.wrap(minerId),
			BigInts.fromUint256(amount)
		);

		(vars.withdrawn, vars.abort) = BigInts.toUint256(withdrawnBInt);
		if (vars.abort) revert BigNumConversion();
		if (vars.withdrawn != amount) revert IncorrectWithdrawal();

		IStakingControllerClient controller = IStakingControllerClient(resolver.getLiquidStakingController());

		vars.stakingProfit = (vars.withdrawn * controller.getProfitShares(ownerId, stakingPool)) / BASIS_POINTS;
		vars.protocolFees = (vars.withdrawn * controller.adminFee()) / BASIS_POINTS;

		(vars.restakingRatio, vars.restakingAddress) = registry.restakings(ownerId);

		vars.isRestaking = vars.restakingRatio > 0 && vars.restakingAddress != address(0);

		if (vars.isRestaking) {
			vars.restakingAmt =
				((vars.withdrawn - vars.stakingProfit - vars.protocolFees) * vars.restakingRatio) /
				BASIS_POINTS;
		}

		vars.protocolShare = vars.stakingProfit + vars.protocolFees + vars.restakingAmt;
		vars.spShare = vars.withdrawn - vars.protocolShare;

		WFIL.deposit{value: vars.protocolShare}();
		WFIL.transfer(stakingPool, vars.protocolShare - vars.protocolFees);

		SendAPI.send(CommonTypes.FilActorId.wrap(ownerId), vars.spShare);

		registry.increaseRewards(ownerId, vars.stakingProfit);
		ICollateralClient(resolver.getCollateral()).fit(ownerId);

		emit WithdrawRewards(ownerId, minerId, vars.spShare, vars.stakingProfit, vars.protocolShare);

		if (vars.isRestaking) {
			ILiquidStakingClient(stakingPool).restake(vars.restakingAmt, vars.restakingAddress);
		}
	}

	/**
	 * @notice Forwards the changeBeneficiary Miner actor call as Liquid Staking
	 * @param minerId Miner actor ID
	 * @param beneficiaryActorId Beneficiary address to be setup (Actor ID)
	 * @param quota Total beneficiary quota
	 * @param expiration Expiration epoch
	 */
	function forwardChangeBeneficiary(
		uint64 minerId,
		uint64 beneficiaryActorId,
		uint256 quota,
		int64 expiration
	) external virtual {
		if (msg.sender != resolver.getRegistry()) revert InvalidAccess();

		MinerTypes.ChangeBeneficiaryParams memory params;
		params.new_beneficiary = FilAddresses.fromActorID(beneficiaryActorId);
		params.new_quota = BigInts.fromUint256(quota);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(expiration);

		MinerAPI.changeBeneficiary(CommonTypes.FilActorId.wrap(minerId), params);

		emit BeneficiaryAddressUpdated(address(this), beneficiaryActorId, minerId, quota, expiration);
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
}
