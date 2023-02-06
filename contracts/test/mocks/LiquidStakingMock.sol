// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

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

	constructor(address _wFIL, address minerActor, address _oracle) LiquidStaking(_wFIL, _oracle) {
		minerActorMock = IMinerActorMock(minerActor);
	}

	function pledge(uint64 sectorNumber, bytes memory proof) external virtual override nonReentrant {
		uint256 assets = oracle.getPledgeFees();
		require(assets <= totalAssets(), "PLEDGE_WITHDRAWAL_OVERFLOW");

		bytes memory provider = abi.encodePacked(msg.sender);
		collateral.lock(provider, assets);

		(, , bytes memory miner, , , , , ) = registry.getStorageProvider(provider);

		emit Pledge(miner, assets, sectorNumber);

		WFIL.withdraw(assets);

		totalFilPledged += assets;

		msg.sender.safeTransferETH(assets);
	}

	/**
	 * @notice Pledge FIL assets from liquid staking pool to miner pledge for multiple sectors
	 * @param sectorNumbers Sector number to be sealed
	 * @param proofs Sector proof for sealing
	 */
	function pledgeAggregate(
		uint64[] memory sectorNumbers,
		bytes[] memory proofs
	) external virtual override nonReentrant {
		require(sectorNumbers.length == proofs.length, "INVALID_PARAMS");
		uint256 pledgePerSector = oracle.getPledgeFees();
		uint256 totalPledge = pledgePerSector * sectorNumbers.length;

		require(totalPledge <= totalAssets(), "PLEDGE_WITHDRAWAL_OVERFLOW");

		bytes memory provider = abi.encodePacked(msg.sender);
		collateral.lock(provider, totalPledge);

		(, , bytes memory miner, , , , , ) = registry.getStorageProvider(provider);

		for (uint256 i = 0; i < sectorNumbers.length; i++) {
			emit Pledge(miner, pledgePerSector, sectorNumbers[i]);
		}

		WFIL.withdraw(totalPledge);

		totalFilPledged += totalPledge;

		msg.sender.safeTransferETH(totalPledge);
	}

	function withdrawRewards(bytes memory miner, uint256 amount) external virtual override nonReentrant {
		MinerTypes.WithdrawBalanceParams memory params;
		params.amount_requested = Bytes.toBytes(amount);

		MinerTypes.WithdrawBalanceReturn memory response = minerActorMock.withdrawBalance(miner, params);

		uint256 withdrawn = Bytes.toUint256(response.amount_withdrawn, 0);
		require(withdrawn == amount, "INCORRECT_WITHDRAWAL_AMOUNT");

		WFIL.deposit{value: withdrawn}();

		// TODO: Increase rewards, recalculate locked rewards
		registry.increaseRewards(miner, withdrawn, 0);
	}
}
