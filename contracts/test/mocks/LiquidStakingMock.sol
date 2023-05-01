// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../LiquidStaking.sol";
import {IMinerActorMock} from "./MinerActorMock.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {BigInts} from "filecoin-solidity/contracts/v0.8/utils/BigInts.sol";
import {MinerMockAPI as MockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";

/**
 * @title Liquid Staking Mock contract
 * @author Collective DAO
 */
contract LiquidStakingMock is LiquidStaking {
	using SafeTransferLib for *;

	IMinerActorMock private minerActorMock;
	MockAPI private mockAPI;

	uint64 public ownerId;
	address private ownerAddr;

	uint256 private constant BASIS_POINTS = 10000;

	constructor(
		address _wFIL,
		address minerActor,
		uint64 _ownerId,
		uint256 _adminFee,
		uint256 _profitShare,
		address _rewardCollector,
		address _ownerAddr,
		address _minerApiMock
	) LiquidStaking(_wFIL, _adminFee, _profitShare, _rewardCollector) {
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
		require(amount <= totalAssets(), "PLEDGE_WITHDRAWAL_OVERFLOW");
		require(!activeSlashings[ownerId], "ACTIVE_SLASHING");

		collateral.lock(ownerId, amount);

		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);

		emit Pledge(ownerId, minerId, amount);

		WFIL.withdraw(amount);

		totalFilPledged += amount;

		msg.sender.safeTransferETH(amount); // TODO: misleading transfer
	}

	/**
	 * @notice Withdraw initial pledge from Storage Provider's Miner Actor by `ownerId`
	 * This function is triggered when sector is not extended by miner actor and initial pledge unlocked
	 * @param ownerId Storage provider owner ID
	 * @param amount Initial pledge amount
	 */
	function withdrawPledge(uint64 ownerId, uint256 amount) external virtual override nonReentrant {
		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);
		CommonTypes.FilActorId minerActorId = CommonTypes.FilActorId.wrap(minerId);

		CommonTypes.BigInt memory withdrawnBInt = minerActorMock.withdrawBalance(
			minerActorId,
			BigInts.fromUint256(amount)
		);

		(uint256 withdrawn, bool abort) = BigInts.toUint256(withdrawnBInt);
		require(!abort, "INCORRECT_BIG_NUM");
		require(withdrawn == amount, "INCORRECT_WITHDRAWAL_AMOUNT");

		WFIL.deposit{value: withdrawn}();

		registry.increasePledgeRepayment(ownerId, amount);

		totalFilPledged -= amount;

		collateral.fit(ownerId);

		emit PledgeRepayment(ownerId, minerId, amount);
	}

	/**
	 * @notice Withdraw FIL assets from Storage Provider by `ownerId` and it's Miner actor
	 * and restake `restakeAmount` into the Storage Provider specified f4 address
	 * @param ownerId Storage provider owner ID
	 * @param amount Withdrawal amount
	 */
	function withdrawRewards(uint64 ownerId, uint256 amount) external virtual override nonReentrant {
		WithdrawRewardsLocalVars memory vars;

		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);
		vars.minerActorId = CommonTypes.FilActorId.wrap(minerId);

		vars.withdrawnBInt = minerActorMock.withdrawBalance(vars.minerActorId, BigInts.fromUint256(amount));

		(vars.withdrawn, vars.abort) = BigInts.toUint256(vars.withdrawnBInt);
		require(!vars.abort, "INCORRECT_BIG_NUM");
		require(vars.withdrawn == amount, "INCORRECT_WITHDRAWAL_AMOUNT");

		uint256 profitShare = profitShares[ownerId];
		vars.stakingProfit = (vars.withdrawn * profitShare) / BASIS_POINTS;
		vars.protocolFees = (vars.withdrawn * adminFee) / BASIS_POINTS;

		(vars.restakingRatio, vars.restakingAddress) = registry.restakings(ownerId);

		vars.isRestaking = vars.restakingRatio > 0 && vars.restakingAddress != address(0);

		if (vars.isRestaking) {
			vars.restakingAmt = (vars.withdrawn * vars.restakingRatio) / BASIS_POINTS;
		}

		vars.spShare = vars.withdrawn - (vars.stakingProfit + vars.protocolFees + vars.restakingAmt);

		WFIL.deposit{value: vars.withdrawn}();
		WFIL.safeTransfer(rewardCollector, vars.protocolFees);

		WFIL.withdraw(vars.spShare);
		ownerAddr.safeTransferETH(vars.spShare);

		registry.increaseRewards(ownerId, vars.stakingProfit);
		collateral.fit(ownerId);

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
		require(msg.sender == address(registry), "INVALID_ACCESS");
		require(targetPool == address(this), "INCORRECT_ADDRESS");

		CommonTypes.FilActorId filMinerId = CommonTypes.FilActorId.wrap(minerId);

		MinerTypes.ChangeBeneficiaryParams memory params;

		params.new_beneficiary = FilAddresses.fromEthAddress(targetPool);
		params.new_quota = BigInts.fromUint256(quota);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(expiration);

		mockAPI.changeBeneficiary(params);
	}
}
