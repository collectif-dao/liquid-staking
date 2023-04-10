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

	constructor(address _wFIL, address minerActor, address _oracle, uint64 _ownerId) LiquidStaking(_wFIL, _oracle) {
		minerActorMock = IMinerActorMock(minerActor);
		ownerId = _ownerId;
	}

	/**
	 * @notice Pledge FIL assets from liquid staking pool to miner pledge for one sector
	 * @param sectorNumber Sector number to be sealed
	 * @param proof Sector proof for sealing
	 */
	function pledge(uint64 sectorNumber, bytes memory proof) external virtual override nonReentrant {
		uint256 assets = oracle.getPledgeFees();
		require(assets <= totalAssets(), "PLEDGE_WITHDRAWAL_OVERFLOW");

		collateral.lock(ownerId, assets);

		(, , uint64 minerId, , , , , , , ) = registry.getStorageProvider(ownerId);
		CommonTypes.FilActorId minerActorId = CommonTypes.FilActorId.wrap(minerId);

		emit Pledge(minerId, assets, sectorNumber);

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

		collateral.lock(ownerId, totalPledge);

		(, , uint64 minerId, , , , , , , ) = registry.getStorageProvider(ownerId);
		CommonTypes.FilActorId minerActorId = CommonTypes.FilActorId.wrap(minerId);

		for (uint256 i = 0; i < sectorNumbers.length; i++) {
			emit Pledge(minerId, pledgePerSector, sectorNumbers[i]);
		}

		WFIL.withdraw(totalPledge);

		totalFilPledged += totalPledge;

		msg.sender.safeTransferETH(totalPledge);
	}

	function withdrawRewards(uint64 minerId, uint256 amount) external virtual override nonReentrant {
		CommonTypes.FilActorId minerActorId = CommonTypes.FilActorId.wrap(minerId);
		CommonTypes.BigInt memory amountBInt = BigInts.fromUint256(amount);

		CommonTypes.BigInt memory withdrawnBInt = minerActorMock.withdrawBalance(minerActorId, amountBInt);

		(uint256 withdrawn, bool abort) = BigInts.toUint256(withdrawnBInt);
		require(!abort, "INCORRECT_BIG_NUM");
		require(withdrawn == amount, "INCORRECT_WITHDRAWAL_AMOUNT");

		WFIL.deposit{value: withdrawn}();

		registry.increaseRewards(minerId, withdrawn, 0);
	}
}
