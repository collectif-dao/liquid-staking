exports.getAddress = require("./general/get-address");
exports.checkNode = require("./general/check-node");
exports.contracts = require("./general/contracts");

// --- Storage Provider Registry ----
exports.register = require("./storage-provider-registry/register");
exports.onboard = require("./storage-provider-registry/onboard");
exports.acceptBeneficiary = require("./storage-provider-registry/accept-beneficiary");
exports.setRestaking = require("./storage-provider-registry/set-restaking");
exports.requestAllocationUpdate = require("./storage-provider-registry/request-allocation-update");
exports.updateAllocationLimit = require("./storage-provider-registry/update-allocation-limit");
exports.getSPInfo = require("./storage-provider-registry/get-sp-info");
exports.deactivateStorageProvider = require("./storage-provider-registry/deactivate-storage-provider");

// --- Storage Provider Collateral ----
exports.deposit = require("./storage-provider-collateral/deposit");
exports.getCollateral = require("./storage-provider-collateral/get-collateral");
exports.reportSlashing = require("./storage-provider-collateral/report-slashing");
exports.reportRecovery = require("./storage-provider-collateral/report-recovery");

// --- Liquid Staking ----
exports.stake = require("./liquid-staking/stake");
exports.pledge = require("./liquid-staking/pledge");
exports.totalFIL = require("./liquid-staking/total-fil");
exports.getBalance = require("./liquid-staking/get-balance");

// --- Reward Collector ---
exports.withdrawRewards = require("./reward-collector/withdraw-rewards");
exports.withdrawPledge = require("./reward-collector/withdraw-pledge");

// --- Storage Provider Stats ---
exports.getPledgeHistory = require("./storage-provider-stats/get-pledge-history");

// --- Pool Stats ---
exports.getStakingHistory = require("./pool-stats/get-staking-history");