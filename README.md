# What is Collectif DAO?

Collectif DAO is a novel approach to Filecoin network collateral requirements that leverages a non-custodial liquid staking protocol built on FVM. Using Collectif DAO storage providers can cover their capital needs to grow the storage capacity. Holders of Filecoin can securely deposit their FIL and get yield out of the network storage mining.

## Introduction

`@collective-dao/liquid-staking` contains the various Solidity smart contracts used within the Filecoin ecosystem. Those smart contracts are meant to be deployed on Filecoin network on top of FVM.

## Developers guide

### Setup

Please make sure to install the following before working with codebase:

[Node.js (16+)](https://nodejs.org/en/download)

[Rust](https://www.rust-lang.org/tools/install)

[Foundry](https://book.getfoundry.sh/getting-started/installation)

[npm](https://docs.npmjs.com/getting-started)

### Clone the repo:

```
git clone https://github.com/collective-dao/liquid-staking.git
cd liquid-staking
```

### Install `npm` packages:

```
npm install
```

### Running Tests

Tests are executed via Foundry:

`npm test`

To run specific tests by giving a path to the file you want to run:

`forge test --match-contract <CONTRACT_NAME>`

### Gas reports:

`forge test --gas-report`

### Compiling and Building

`forge build`

## Liquid Staking Components

**Liquid Staking Pool**, which is the main contract that allows stakers to easily deposit their FIL and get yield out of the network storage mining, and Storage Providers to access this FIL for their sector pledges. Liquid staking pool is ERC4626 vault and in future can be connected to other staking pools via **Staking Router** contract

A **Storage Providers Registry** is a database that maintains a record of all the Storage Providers on the network. This registry allows Liquid Staking Pool to interact with Storage Providers, and determine their risk profile and FIL allocation.

A **Miner Collateral Module** is a system that allows Storage Providers to pledge collateral in order to participate in the staking process. The Miner collateral module can help to reduce the risks associated with staking, such as the risk of being penalized (or "slashed") for misbehaving on the network.

** Pledge Oracle ** provides an estimation of the current size of collateral for pledging a sector


## Filcoin native features
Protocol interacts with Filecoin built-in Miner actors via [Filecoin Solidity libraries](https://github.com/Zondax/filecoin-solidity) MinerAPI methods.

## Deployments

### Hyperspace
* Liquid Staking Pool: [`0xc740192CD9d6DBFF71f59AD2Ee25DFbEE24c77B3`](https://hyperspace.filfox.info/en/address/0xc740192CD9d6DBFF71f59AD2Ee25DFbEE24c77B3)
* Router: [`0x4dA1f1a8AbA46a0d8A6F9fe30794417A980ae558`](https://hyperspace.filfox.info/en/address/0x4dA1f1a8AbA46a0d8A6F9fe30794417A980ae558)
* Miner Collateral Module: [`0xFE5fc48a62Ed2B1B314Ba6140b332F37b3Af6807`](https://hyperspace.filfox.info/en/address/0xFE5fc48a62Ed2B1B314Ba6140b332F37b3Af6807)
* Miner Registry: [`0x0D99cC53138F1911fd8eE7A86a451F583B02566d`](https://hyperspace.filfox.info/en/address/0x0D99cC53138F1911fd8eE7A86a451F583B02566d)
* WFIL: [`0xaa191D1a5bdD60AB5386864eaDA6B1Ac5CA711A7`](https://hyperspace.filfox.info/en/address/0xaa191D1a5bdD60AB5386864eaDA6B1Ac5CA711A7)
* Pledge Oracle: [`0x5C45838965514236AB58BFd1305fCA21718B1200`](https://hyperspace.filfox.info/en/address/0x5C45838965514236AB58BFd1305fCA21718B1200)

## Documentation

If you want to use Collectif DAO to cover your initial pledge requirements, take a look at the extensive [Collectif DAO documentation](http://docs.collectif.finance/).

## Community

General discussion happens most frequently on the [Collectif DAO discord](https://discord.gg/xnenkym3y6).
Latest news and announcements on the [Collectif DAO twitter](https://twitter.com/collectifDAO)
