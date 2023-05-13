// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {RewardCollector, IRewardCollector, IBeneficiaryManager, MinerTypes, FilAddresses, IRegistryClient, CommonTypes, BigInts, ICollateralClient, IResolverClient, IWFIL, IStakingControllerClient, ILiquidStakingClient} from "../../RewardCollector.sol";
import {IMinerActorMock} from "./MinerActorMock.sol";
import {MinerMockAPI as MockAPI} from "filecoin-solidity/contracts/v0.8/mocks/MinerMockAPI.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeTransferLib} from "../../libraries/SafeTransferLib.sol";

/**
 * @title Reward Collector Mock contract
 */
contract RewardCollectorMock is RewardCollector {
	using SafeTransferLib for *;

	IMinerActorMock private minerActorMock;
	MockAPI private mockAPI;

	uint64 public ownerId;
	address private ownerAddr;
	uint256 private BASIS_POINTS;
	bytes32 private constant FEE_DISTRIBUTOR = keccak256("FEE_DISTRIBUTOR");

	/**
	 * @dev Contract initializer function.
	 * @param _resolver Resolver contract address
	 */
	function initialize(
		address _minerApiMock,
		address minerActor,
		uint64 _ownerId,
		address _ownerAddr,
		address _wFIL,
		address _resolver
	) public initializer {
		__AccessControl_init();
		__ReentrancyGuard_init();
		__UUPSUpgradeable_init();

		BASIS_POINTS = 10000;

		WFIL = IWFIL(_wFIL);
		resolver = IResolverClient(_resolver);

		mockAPI = MockAPI(_minerApiMock);
		minerActorMock = IMinerActorMock(minerActor);
		ownerId = _ownerId;
		ownerAddr = _ownerAddr;

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		grantRole(FEE_DISTRIBUTOR, msg.sender);
		_setRoleAdmin(FEE_DISTRIBUTOR, DEFAULT_ADMIN_ROLE);
	}

	/**
	 * @notice Withdraw initial pledge from Storage Provider's Miner Actor by `ownerId`
	 * This function is triggered when sector is not extended by miner actor and initial pledge unlocked
	 * @param ownerId Storage provider owner ID
	 * @param amount Initial pledge amount
	 */
	function withdrawPledge(uint64 ownerId, uint256 amount) external virtual override nonReentrant {
		if (!hasRole(FEE_DISTRIBUTOR, msg.sender)) revert InvalidAccess();
		if (amount == 0) revert InvalidParams();

		IRegistryClient registry = IRegistryClient(resolver.getRegistry());

		(, address stakingPool, uint64 minerId, ) = registry.getStorageProvider(ownerId);
		CommonTypes.FilActorId minerActorId = CommonTypes.FilActorId.wrap(minerId);

		CommonTypes.BigInt memory withdrawnBInt = minerActorMock.withdrawBalance(
			minerActorId,
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

		(, address stakingPool, uint64 minerId, ) = registry.getStorageProvider(ownerId);
		CommonTypes.BigInt memory withdrawnBInt = minerActorMock.withdrawBalance(
			CommonTypes.FilActorId.wrap(minerId),
			BigInts.fromUint256(amount)
		);

		(vars.withdrawn, vars.abort) = BigInts.toUint256(withdrawnBInt);
		if (vars.abort) revert BigNumConversion();
		if (vars.withdrawn != amount) revert IncorrectWithdrawal();

		IStakingControllerClient controller = IStakingControllerClient(resolver.getLiquidStakingController());

		uint256 profitShare = controller.getProfitShares(ownerId, stakingPool);
		vars.stakingProfit = (vars.withdrawn * profitShare) / BASIS_POINTS;
		vars.protocolFees = (vars.withdrawn * controller.adminFee()) / BASIS_POINTS;
		vars.protocolShare = vars.stakingProfit + vars.protocolFees;

		(vars.restakingRatio, vars.restakingAddress) = registry.restakings(ownerId);

		vars.isRestaking = vars.restakingRatio > 0 && vars.restakingAddress != address(0);

		if (vars.isRestaking) {
			vars.restakingAmt = ((vars.withdrawn - vars.protocolShare) * vars.restakingRatio) / BASIS_POINTS;
		}

		vars.protocolShare = vars.stakingProfit + vars.protocolFees + vars.restakingAmt;
		vars.spShare = vars.withdrawn - vars.protocolShare;

		WFIL.deposit{value: vars.withdrawn}();
		WFIL.transfer(stakingPool, vars.protocolShare - vars.protocolFees);

		WFIL.withdraw(vars.spShare);
		ownerAddr.safeTransferETH(vars.spShare);

		registry.increaseRewards(ownerId, vars.stakingProfit);
		ICollateralClient(resolver.getCollateral()).fit(ownerId);

		if (vars.isRestaking) {
			ILiquidStakingClient(stakingPool).restake(vars.restakingAmt, vars.restakingAddress);
		}
	}

	/**
	 * @notice Forwards the changeBeneficiary Miner actor call as Liquid Staking
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
	) external virtual override {
		address registry = resolver.getRegistry();
		if (msg.sender != registry) revert InvalidAccess();
		if (!IRegistryClient(registry).isActivePool(targetPool)) revert InactivePool();

		MinerTypes.ChangeBeneficiaryParams memory params;
		params.new_beneficiary = FilAddresses.fromEthAddress(address(this));
		params.new_quota = BigInts.fromUint256(quota);
		params.new_expiration = CommonTypes.ChainEpoch.wrap(expiration);

		mockAPI.changeBeneficiary(params);

		IBeneficiaryManager(resolver.getBeneficiaryManager()).updateBeneficiaryStatus(minerId, true);

		emit BeneficiaryAddressUpdated(address(this), targetPool, minerId, quota, expiration);
	}
}
