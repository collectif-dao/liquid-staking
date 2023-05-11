// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ClFILToken} from "./ClFIL.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {MinerAPI, CommonTypes, MinerTypes} from "filecoin-solidity/contracts/v0.8/MinerAPI.sol";
import {FilAddresses} from "filecoin-solidity/contracts/v0.8/utils/FilAddresses.sol";
import {FilAddress} from "fevmate/utils/FilAddress.sol";
import {SendAPI} from "filecoin-solidity/contracts/v0.8/SendAPI.sol";

import {ILiquidStaking} from "./interfaces/ILiquidStaking.sol";
import {IBeneficiaryManager} from "./interfaces/IBeneficiaryManager.sol";
import {ILiquidStakingControllerClient as IStakingControllerClient} from "./interfaces/ILiquidStakingControllerClient.sol";
import {IStorageProviderCollateralClient as ICollateralClient} from "./interfaces/IStorageProviderCollateralClient.sol";
import {IStorageProviderRegistryClient as IRegistryClient} from "./interfaces/IStorageProviderRegistryClient.sol";
import {IResolverClient} from "./interfaces/IResolverClient.sol";
import {IBigInts} from "./libraries/BigInts.sol";

/**
 * @title LiquidStaking contract allows users to stake/unstake FIL to earn
 * Filecoin mining rewards. Staked FIL is allocated to Storage Providers (SPs) that
 * perform filecoin storage mining operations. This contract acts as a beneficiary address
 * for each SP that uses FIL capital for pledges.
 *
 * While staking FIL user would get clFIL token in exchange, the token follows ERC4626
 * standard and it's price is recalculated once mining rewards are distributed to the
 * liquid staking pool and once new FIL is deposited. Please note that LiquidStaking contract
 * performs wrapping of the native FIL into Wrapped Filecoin (WFIL) token.
 */
contract LiquidStaking is
	ILiquidStaking,
	Initializable,
	ClFILToken,
	ReentrancyGuardUpgradeable,
	AccessControlUpgradeable,
	UUPSUpgradeable
{
	using SafeTransferLib for *;
	using FilAddress for address;

	error InvalidAccess();
	error InvalidCall();
	error InvalidAddress();
	error ERC4626ZeroShares();
	error InactiveActor();
	error ActiveSlashing();
	error IncorrectWithdrawal();
	error BigNumConversion();
	error InsufficientFunds();

	uint256 private constant BASIS_POINTS = 10000;

	/// @notice The current total amount of FIL that is allocated to SPs.
	uint256 public totalFilPledged;

	IBigInts internal BigInts;
	IResolverClient internal resolver;

	bytes32 private constant LIQUID_STAKING_ADMIN = keccak256("LIQUID_STAKING_ADMIN");
	bytes32 private constant FEE_DISTRIBUTOR = keccak256("FEE_DISTRIBUTOR");

	modifier onlyAdmin() {
		if (!hasRole(LIQUID_STAKING_ADMIN, msg.sender)) revert InvalidAccess();
		_;
	}

	/**
	 * @dev Contract initializer function.
	 * @param _wFIL WFIL token contract address
	 * @param _bigIntsLib BigInts contract address
	 * @param _resolver Resolver contract address
	 */
	function initialize(address _wFIL, address _bigIntsLib, address _resolver) public initializer {
		__AccessControl_init();
		__ReentrancyGuard_init();
		ClFILToken.initialize(_wFIL);
		__UUPSUpgradeable_init();

		BigInts = IBigInts(_bigIntsLib);
		resolver = IResolverClient(_resolver);

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		grantRole(LIQUID_STAKING_ADMIN, msg.sender);
		_setRoleAdmin(LIQUID_STAKING_ADMIN, DEFAULT_ADMIN_ROLE);
		grantRole(FEE_DISTRIBUTOR, msg.sender);
		_setRoleAdmin(FEE_DISTRIBUTOR, DEFAULT_ADMIN_ROLE);
	}

	receive() external payable virtual {}

	fallback() external payable virtual {}

	/**
	 * @notice Stake FIL to the Liquid Staking pool and get clFIL in return
	 * native FIL is wrapped into WFIL and deposited into LiquidStaking
	 *
	 * @notice msg.value is the amount of FIL to stake
	 */
	function stake() external payable nonReentrant returns (uint256 shares) {
		uint256 assets = msg.value;
		address receiver = msg.sender.normalize();

		if (assets > maxDeposit(receiver)) revert ERC4626Overflow();
		shares = previewDeposit(assets);

		if (shares == 0) revert ERC4626ZeroShares();

		WFIL.deposit{value: assets}();

		_mint(receiver, shares);

		emit Deposit(_msgSender(), receiver, assets, shares);
	}

	/**
	 * @notice Unstake FIL from the Liquid Staking pool and burn clFIL tokens
	 * @param shares Total clFIL amount to burn (unstake)
	 * @param owner Original owner of clFIL tokens
	 * @param owner Receiver of FIL assets
	 * @dev Please note that unstake amount has to be clFIL shares (not FIL assets)
	 */
	function unstake(uint256 shares, address owner) external nonReentrant returns (uint256 assets) {
		if (shares > maxRedeem(owner)) revert ERC4626Overflow();

		address receiver = msg.sender.normalize();
		owner = owner.normalize();

		assets = previewRedeem(shares);

		if (receiver != owner) {
			_spendAllowance(owner, receiver, shares);
		}

		_burn(owner, shares);

		emit Unstaked(msg.sender, owner, assets, shares);

		_unwrapWFIL(receiver, assets);
	}

	/**
	 * @notice Unstake FIL from the Liquid Staking pool and burn clFIL tokens
	 * @param assets Total FIL amount to unstake
	 * @param owner Original owner of clFIL tokens
	 * @param owner Receiver of FIL assets
	 */
	function unstakeAssets(uint256 assets, address owner) external nonReentrant returns (uint256 shares) {
		if (assets > maxWithdraw(owner)) revert ERC4626Overflow();

		address receiver = msg.sender.normalize();
		owner = owner.normalize();

		shares = previewWithdraw(assets);
		if (receiver != owner) {
			_spendAllowance(owner, receiver, shares);
		}

		_burn(owner, shares);

		emit Unstaked(receiver, owner, assets, shares);

		_unwrapWFIL(receiver, assets);
	}

	/**
	 * @notice Pledge FIL assets from liquid staking pool to miner pledge for one sector
	 * @param amount Amount of FIL to pledge from Liquid Staking Pool
	 */
	function pledge(uint256 amount) external virtual nonReentrant {
		if (amount > totalAssets()) revert InvalidParams();

		address ownerAddr = msg.sender.normalize();
		(bool isID, uint64 ownerId) = ownerAddr.getActorID();
		if (!isID) revert InactiveActor();

		ICollateralClient collateral = ICollateralClient(resolver.getCollateral());
		if (collateral.activeSlashings(ownerId)) revert ActiveSlashing();

		collateral.lock(ownerId, amount);

		(, , uint64 minerId, ) = IRegistryClient(resolver.getRegistry()).getStorageProvider(ownerId);

		emit Pledge(ownerId, minerId, amount);

		WFIL.withdraw(amount);

		totalFilPledged += amount;

		SendAPI.send(CommonTypes.FilActorId.wrap(minerId), amount); // send FIL to the miner actor
	}

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

		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);

		CommonTypes.BigInt memory withdrawnBInt = MinerAPI.withdrawBalance(
			CommonTypes.FilActorId.wrap(minerId),
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

		(, , uint64 minerId, ) = registry.getStorageProvider(ownerId);

		CommonTypes.BigInt memory withdrawnBInt = MinerAPI.withdrawBalance(
			CommonTypes.FilActorId.wrap(minerId),
			BigInts.fromUint256(amount)
		);

		(vars.withdrawn, vars.abort) = BigInts.toUint256(withdrawnBInt);
		if (vars.abort) revert BigNumConversion();
		if (vars.withdrawn != amount) revert IncorrectWithdrawal();

		IStakingControllerClient controller = IStakingControllerClient(resolver.getLiquidStakingController());

		vars.stakingProfit = (vars.withdrawn * controller.getProfitShares(ownerId, address(this))) / BASIS_POINTS;
		vars.protocolFees = (vars.withdrawn * controller.adminFee()) / BASIS_POINTS;
		vars.protocolShare = vars.stakingProfit + vars.protocolFees;

		(vars.restakingRatio, vars.restakingAddress) = registry.restakings(ownerId);

		vars.isRestaking = vars.restakingRatio > 0 && vars.restakingAddress != address(0);

		if (vars.isRestaking) {
			vars.restakingAmt = ((vars.withdrawn - vars.protocolShare) * vars.restakingRatio) / BASIS_POINTS;
		}

		vars.spShare = vars.withdrawn - (vars.protocolShare + vars.restakingAmt);

		WFIL.deposit{value: vars.protocolShare}();
		WFIL.transfer(controller.rewardCollector(), vars.protocolFees);

		SendAPI.send(CommonTypes.FilActorId.wrap(ownerId), vars.spShare);

		registry.increaseRewards(ownerId, vars.stakingProfit);
		ICollateralClient(resolver.getCollateral()).fit(ownerId);

		if (vars.isRestaking) {
			_restake(vars.restakingAmt, vars.restakingAddress);
		}
	}

	/**
	 * @notice Restakes `assets` for a specified `target` address
	 * @param assets Amount of assets to restake
	 * @param receiver f4 address to receive clFIL tokens
	 */
	function _restake(uint256 assets, address receiver) internal returns (uint256 shares) {
		if (assets > maxDeposit(receiver)) revert ERC4626Overflow();
		shares = previewDeposit(assets);
		if (shares == 0) revert ERC4626ZeroShares();

		_mint(receiver, shares);

		emit Deposit(receiver, receiver, assets, shares);
	}

	/**
	 * @notice Returns total amount of assets backing clFIL, that includes
	 * buffered capital in the pool and pledged capital to the SPs.
	 */
	function totalAssets() public view virtual override returns (uint256) {
		return totalFilAvailable() + totalFilPledged;
	}

	/**
	 * @notice Returns total amount of fees held by LSP for a specific SP with `_ownerId`
	 * @param _ownerId Storage Provider owner ID
	 */
	function totalFees(uint64 _ownerId) external view virtual override returns (uint256) {
		return IStakingControllerClient(resolver.getLiquidStakingController()).totalFees(_ownerId, address(this));
	}

	/**
	 * @notice Returns pool usage ratio to determine what percentage of FIL
	 * is pledged compared to the total amount of FIL staked.
	 */
	function getUsageRatio() external view virtual returns (uint256) {
		return (totalFilPledged * BASIS_POINTS) / (totalFilAvailable() + totalFilPledged);
	}

	/**
	 * @notice Returns the amount of WFIL available on the liquid staking contract
	 */
	function totalFilAvailable() public view returns (uint256) {
		return WFIL.balanceOf(address(this));
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
	) external virtual {
		if (msg.sender != resolver.getRegistry()) revert InvalidAccess();
		if (targetPool != address(this)) revert InvalidAddress();

		IBeneficiaryManager(resolver.getBeneficiaryManager()).forwardChangeBeneficiary(
			minerId,
			targetPool,
			quota,
			expiration
		);
	}

	/**
	 * @notice Unwraps `_amount` of WFIL into FIL and transfers it to the `_recipient` address
	 * @param _recipient WFIL recipient address
	 */
	function _unwrapWFIL(address _recipient, uint256 _amount) internal {
		uint256 balanceWETH9 = WFIL.balanceOf(address(this));
		if (balanceWETH9 < _amount) revert InsufficientFunds();

		if (balanceWETH9 > 0) {
			WFIL.withdraw(_amount);
			_recipient.safeTransferETH(_amount);
		}
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
