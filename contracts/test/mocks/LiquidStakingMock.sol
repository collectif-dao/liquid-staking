// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../../LiquidStaking.sol";
import {IMinerActorMock} from "./MinerActorMock.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/**
 * @title Liquid Staking Mock contract
 * @author Collective DAO
 */
contract LiquidStakingMock is LiquidStaking {
	using SafeTransferLib for *;

	IMinerActorMock private minerActorMock;

	constructor(address _wFIL, address minerActor) LiquidStaking(_wFIL) {
		minerActorMock = IMinerActorMock(minerActor);
	}

	function pledge(uint256 assets, uint64 sectorNumber, bytes memory proof) external virtual override nonReentrant {
		require(assets <= totalAssets(), "PLEDGE_WITHDRAWAL_OVERFLOW");

		bytes memory provider = abi.encodePacked(msg.sender);
		collateral.lock(provider, assets);

		(, , bytes memory miner, , , , , ) = registry.getStorageProvider(provider);

		emit Pledge(miner, assets, sectorNumber);

		WFIL.withdraw(assets);

		totalFilPledged += assets;

		msg.sender.safeTransferETH(assets);
	}

	function withdrawRewards(bytes memory miner, uint256 amount) external virtual override nonReentrant {
		MinerTypes.WithdrawBalanceParams memory params;
		params.amount_requested = toBytes(amount);

		MinerTypes.WithdrawBalanceReturn memory response = minerActorMock.withdrawBalance(miner, params);

		uint256 withdrawn = toUint256(response.amount_withdrawn, 0);
		require(withdrawn == amount, "INCORRECT_WITHDRAWAL_AMOUNT");

		WFIL.deposit{value: withdrawn}();

		// TODO: Increase rewards, recalculate locked rewards
		registry.increaseRewards(miner, withdrawn, 0);
	}
}
