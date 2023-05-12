exports.getAddress = require("./general/get-address");
exports.checkNode = require("./general/check-node");
exports.registerPool = require("./storage-provider-registry/register-pool");
exports.getSPInfo = require("./storage-provider-registry/get-sp-info");

// --- Storage Provider Registry ----
exports.register = require("./storage-provider-registry/register");
exports.onboard = require("./storage-provider-registry/onboard");
exports.changeBeneficiary = require("./storage-provider-registry/change-beneficiary");
exports.acceptBeneficiary = require("./storage-provider-registry/accept-beneficiary");

// --- Storage Provider Collateral ----
exports.deposit = require("./storage-provider-collateral/deposit");
exports.getCollateral = require("./storage-provider-collateral/get-collateral");

// --- Liquid Staking ----
exports.stake = require("./liquid-staking/stake");
exports.pledge = require("./liquid-staking/pledge");
exports.totalFIL = require("./liquid-staking/total-fil");
