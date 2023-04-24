// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../LiquidStaking.sol";
import {IMinerActorMock} from "./MinerActorMock.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {BigInts} from "filecoin-solidity/contracts/v0.8/utils/BigInts.sol";

/**
 * @title Liquid Staking Mock contract
 * @author Collective DAO
 */
contract LiquidStakingMock is LiquidStaking {
	using SafeTransferLib for *;

	IMinerActorMock private minerActorMock;

	uint64 public ownerId;
	address private ownerAddr;

	uint256 private constant BASIS_POINTS = 10000;

	constructor(
		address _wFIL,
		address minerActor,
		uint64 _ownerId,
		uint256 _adminFee,
		uint256 _profitShare,
		address _rewardCollector
	) LiquidStaking(_wFIL, _adminFee, _profitShare, _rewardCollector) {
		minerActorMock = IMinerActorMock(minerActor);
		ownerId = _ownerId;
		ownerAddr = msg.sender;
	}

	/**
	 * @notice Pledge FIL assets from liquid staking pool to miner pledge for one or multiple sectors
	 * @param amount Amount of FIL to be pledged from Liquid Staking Pool
	 */
	function pledge(uint256 amount) external virtual override nonReentrant {
		require(amount <= totalAssets(), "PLEDGE_WITHDRAWAL_OVERFLOW");

		collateral.lock(ownerId, amount);

		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);

		emit Pledge(ownerId, minerId, amount);

		WFIL.withdraw(amount);

		totalFilPledged += amount;

		msg.sender.safeTransferETH(amount);
	}

	/**
	 * @notice Withdraw FIL assets from Storage Provider by `ownerId` and it's Miner actor
	 * @param ownerId Storage provider owner ID
	 * @param amount Withdrawal amount
	 */
	function withdrawRewards(uint64 ownerId, uint256 amount) external virtual override nonReentrant {
		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);
		CommonTypes.FilActorId minerActorId = CommonTypes.FilActorId.wrap(minerId);
		CommonTypes.BigInt memory amountBInt = BigInts.fromUint256(amount);

		CommonTypes.BigInt memory withdrawnBInt = minerActorMock.withdrawBalance(minerActorId, amountBInt);

		(uint256 withdrawn, bool abort) = BigInts.toUint256(withdrawnBInt);
		require(!abort, "INCORRECT_BIG_NUM");
		require(withdrawn == amount, "INCORRECT_WITHDRAWAL_AMOUNT");

		uint256 stakingProfit = (withdrawn * profitShare) / BASIS_POINTS;
		uint256 protocolFees = (withdrawn * adminFee) / BASIS_POINTS;
		uint256 spShare = withdrawn - (stakingProfit + protocolFees);

		WFIL.deposit{value: withdrawn}();
		WFIL.safeTransfer(ownerAddr, spShare);
		WFIL.safeTransfer(rewardCollector, protocolFees);

		// _unwrapWFIL(ownerAddr, spShare);
		// WFIL.withdraw(spShare);
		// payable(ownerAddr).transfer(spShare);

		registry.increaseRewards(minerId, stakingProfit);
		collateral.fit(ownerId);
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
	 * @param _ownerId Storage provider owner ID
	 * @param amount Withdrawal amount
	 * @param totalRewards Total amount of rewards accured by SP - profit sharing
	 */
	function withdrawAndRestakeRewards(
		uint64 _ownerId,
		uint256 amount,
		uint256 totalRewards
	) external virtual override nonReentrant {
		WithdrawAndRestakeLocalVars memory vars;

		(, , uint64 minerId, ) = registry.getStorageProvider(_ownerId);
		vars.minerActorId = CommonTypes.FilActorId.wrap(minerId);

		(vars.restakingRatio, vars.restakingAddress) = registry.restakings(_ownerId);
		require(vars.restakingAddress != address(0), "RESTAKING_NOT_SET");
		vars.restakingAmt = (totalRewards * vars.restakingRatio) / BASIS_POINTS;

		uint256 shares;
		require((shares = previewDeposit(vars.restakingAmt)) != 0, "ZERO_SHARES");

		vars.targetWithdraw = amount + vars.restakingAmt;
		vars.amountBInt = BigInts.fromUint256(vars.targetWithdraw);
		vars.withdrawnBInt = minerActorMock.withdrawBalance(vars.minerActorId, vars.amountBInt);

		(vars.withdrawn, vars.abort) = BigInts.toUint256(vars.withdrawnBInt);
		require(!vars.abort, "INCORRECT_BIG_NUM");
		require(vars.withdrawn == vars.targetWithdraw, "INCORRECT_WITHDRAWAL_AMOUNT");

		WFIL.deposit{value: vars.withdrawn}();

		vars.protocolFees = (amount * adminFee) / BASIS_POINTS;
		WFIL.safeTransfer(rewardCollector, vars.protocolFees);

		registry.increaseRewards(minerId, amount);
		collateral.fit(_ownerId);

		_restake(vars.restakingAmt, vars.restakingAddress);
	}
}
