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
		address _ownerAddr,
		address _minerApiMock,
		address _resolver,
		uint256 _initialDeposit
	) public initializer {
		__AccessControl_init();
		__ReentrancyGuard_init();
		__ClFILToken_init(_wFIL);
		__UUPSUpgradeable_init();

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

		if (_initialDeposit > 0) deposit(_initialDeposit, address(this));
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
}
