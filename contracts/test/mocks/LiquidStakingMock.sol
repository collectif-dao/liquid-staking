// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../LiquidStaking.sol";
import {IMinerActorMock} from "./MinerActorMock.sol";
import {MinerMockAPI as MockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Liquid Staking Mock contract
 * @author Collective DAO
 */
contract LiquidStakingMock is LiquidStaking {
	using SafeTransferLib for *;

	bytes32 private constant LIQUID_STAKING_ADMIN = keccak256("LIQUID_STAKING_ADMIN");
	bytes32 private constant FEE_DISTRIBUTOR = keccak256("FEE_DISTRIBUTOR");

	IMinerActorMock private minerActorMock;
	MockAPI private mockAPI;

	uint64 public ownerId;
	address private ownerAddr;

	uint256 private constant BASIS_POINTS = 10000;

	function initialize(
		address _wFIL,
		address minerActor,
		uint64 _ownerId,
		uint256 _adminFee,
		uint256 _profitShare,
		address _rewardCollector,
		address _ownerAddr,
		address _minerApiMock,
		address _bigIntsLib,
		address _resolver
	) public initializer {
		__AccessControl_init();
		__ReentrancyGuard_init();
		ClFILToken.initialize(_wFIL);
		__UUPSUpgradeable_init();

		if (_adminFee > 2000 || _rewardCollector == address(0)) revert InvalidParams();
		if (_wFIL == address(0)) revert InvalidParams();

		adminFee = _adminFee;
		baseProfitShare = _profitShare;
		rewardCollector = _rewardCollector;

		BigInts = IBigInts(_bigIntsLib);
		resolver = IResolverClient(_resolver);

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		grantRole(LIQUID_STAKING_ADMIN, msg.sender);
		_setRoleAdmin(LIQUID_STAKING_ADMIN, DEFAULT_ADMIN_ROLE);
		grantRole(FEE_DISTRIBUTOR, msg.sender);
		_setRoleAdmin(FEE_DISTRIBUTOR, DEFAULT_ADMIN_ROLE);

		minerActorMock = IMinerActorMock(minerActor);
		ownerId = _ownerId;
		ownerAddr = _ownerAddr;

		mockAPI = MockAPI(_minerApiMock);
	}

	/**
	 * @notice Pledge FIL assets from liquid staking pool to miner pledge for one or multiple sectors
	 * @param amount Amount of FIL to be pledged from Liquid Staking Pool
	 */
	function pledge(uint256 amount) external virtual override nonReentrant {
		if (amount > totalAssets()) revert InvalidParams();

		ICollateralClient collateral = ICollateralClient(resolver.getCollateral());
		if (collateral.activeSlashings(ownerId)) revert ActiveSlashing();

		collateral.lock(ownerId, amount);

		(, , uint64 minerId, ) = IRegistryClient(resolver.getRegistry()).getStorageProvider(ownerId);

		emit Pledge(ownerId, minerId, amount);

		WFIL.withdraw(amount);

		totalFilPledged += amount;

		address(minerActorMock).safeTransferETH(amount);
	}

	/**
	 * @notice Withdraw initial pledge from Storage Provider's Miner Actor by `ownerId`
	 * This function is triggered when sector is not extended by miner actor and initial pledge unlocked
	 * @param ownerId Storage provider owner ID
	 * @param amount Initial pledge amount
	 */
	function withdrawPledge(uint64 ownerId, uint256 amount) external virtual override nonReentrant {
		if (!hasRole(FEE_DISTRIBUTOR, msg.sender)) revert InvalidAccess();
		IRegistryClient registry = IRegistryClient(resolver.getRegistry());

		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);
		CommonTypes.FilActorId minerActorId = CommonTypes.FilActorId.wrap(minerId);

		CommonTypes.BigInt memory withdrawnBInt = minerActorMock.withdrawBalance(
			minerActorId,
			BigInts.fromUint256(amount)
		);

		(uint256 withdrawn, bool abort) = BigInts.toUint256(withdrawnBInt);
		if (abort) revert BigNumConversion();
		if (withdrawn != amount) revert IncorrectWithdrawal();

		WFIL.deposit{value: withdrawn}();

		registry.increasePledgeRepayment(ownerId, amount);

		totalFilPledged -= amount;

		ICollateralClient(resolver.getCollateral()).fit(ownerId);

		emit PledgeRepayment(ownerId, minerId, amount);
	}

	/**
	 * @notice Withdraw FIL assets from Storage Provider by `ownerId` and it's Miner actor
	 * and restake `restakeAmount` into the Storage Provider specified f4 address
	 * @param ownerId Storage provider owner ID
	 * @param amount Withdrawal amount
	 */
	function withdrawRewards(uint64 ownerId, uint256 amount) external virtual override nonReentrant {
		if (!hasRole(FEE_DISTRIBUTOR, msg.sender)) revert InvalidAccess();
		WithdrawRewardsLocalVars memory vars;
		IRegistryClient registry = IRegistryClient(resolver.getRegistry());

		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);
		CommonTypes.BigInt memory withdrawnBInt = minerActorMock.withdrawBalance(
			CommonTypes.FilActorId.wrap(minerId),
			BigInts.fromUint256(amount)
		);

		(vars.withdrawn, vars.abort) = BigInts.toUint256(withdrawnBInt);
		if (vars.abort) revert BigNumConversion();
		if (vars.withdrawn != amount) revert IncorrectWithdrawal();

		uint256 profitShare = profitShares[ownerId];
		vars.stakingProfit = (vars.withdrawn * profitShare) / BASIS_POINTS;
		vars.protocolFees = (vars.withdrawn * adminFee) / BASIS_POINTS;
		vars.protocolShare = vars.stakingProfit + vars.protocolFees;

		(vars.restakingRatio, vars.restakingAddress) = registry.restakings(ownerId);

		vars.isRestaking = vars.restakingRatio > 0 && vars.restakingAddress != address(0);

		if (vars.isRestaking) {
			vars.restakingAmt = ((vars.withdrawn - vars.protocolShare) * vars.restakingRatio) / BASIS_POINTS;
		}

		vars.spShare = vars.withdrawn - (vars.protocolShare + vars.restakingAmt);

		WFIL.deposit{value: vars.withdrawn}();
		WFIL.transfer(rewardCollector, vars.protocolFees);

		WFIL.withdraw(vars.spShare);
		ownerAddr.safeTransferETH(vars.spShare);

		registry.increaseRewards(ownerId, vars.stakingProfit);
		ICollateralClient(resolver.getCollateral()).fit(ownerId);

		if (vars.isRestaking) {
			_restake(vars.restakingAmt, vars.restakingAddress);
		}
	}

	/**
	 * @notice Triggers changeBeneficiary Miner actor call
	 * @param minerId Miner actor ID
	 * @param targetPool LSP smart contract address
	 * @param quota Total beneficiary quota
	 * @param expiration Expiration epoch
	 */
	function forwardChangeBeneficiary(
		uint64 minerId,
		address targetPool,
		uint256 quota,
		int64 expiration
	) external override {
		if (msg.sender != resolver.getRegistry()) revert InvalidAccess();
		if (targetPool != address(this)) revert InvalidAddress();

		CommonTypes.FilActorId filMinerId = CommonTypes.FilActorId.wrap(minerId);

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = FilAddresses.fromEthAddress(targetPool);
		params.new_quota = BigInts.fromUint256(quota);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(expiration);

		mockAPI.changeBeneficiary(params);
	}
}
