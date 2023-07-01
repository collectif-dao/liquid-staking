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

A **Storage Provider Registry** is a database that maintains a record of all the Storage Providers on the network. This registry allows Liquid Staking Pool to interact with Storage Providers, and determine their risk profile and FIL allocation.

A **Storage Provider Collateral** is a system that allows Storage Providers to put collateral in order to pledge FIL from the liquid staking pool. Storage Provider Collateral covers the slashing risks for stakers when SP is misbehaving on the network.

**Resolver** is the main contract for collecting list of addresses used in the Collectif DAO liquid staking protocol

**Reward Collector** is the contract responsible for distributing mining rewards from SP's miner actors to the liquid staking pool.

## Filecoin native features

Protocol interacts with Filecoin built-in Miner actors via [Filecoin Solidity libraries](https://github.com/Zondax/filecoin-solidity) MinerAPI methods.

## Deployments

### Filecoin Calibration testnet

- WFIL: [`0xaC26a4Ab9cF2A8c5DBaB6fb4351ec0F4b07356c4`](https://calibration.filfox.info/en/address/0xaC26a4Ab9cF2A8c5DBaB6fb4351ec0F4b07356c4)

- Liquid Staking Pool: [`0x19AAB7dD96E9EedF9E232fE56d1736f53205834a`](https://calibration.filfox.info/en/address/0x19AAB7dD96E9EedF9E232fE56d1736f53205834a)

  - Implementation: [`0xa9D2d7F420D24fC92E8A5cB5bcb6445F74940270`](https://calibration.filfox.info/en/address/0xa9D2d7F420D24fC92E8A5cB5bcb6445F74940270)

- Liquid Staking Controller: [`0xE5222EC4A4B3A64320A04EA81d51D110ca329Df2`](https://calibration.filfox.info/en/address/0xE5222EC4A4B3A64320A04EA81d51D110ca329Df2)

  - Implementation: [`0x5262A885B18c9536001952f909f000c4DD13faDF`](https://calibration.filfox.info/en/address/0x5262A885B18c9536001952f909f000c4DD13faDF)

- Storage Provider Registry: [`0xCc6C40Da237F2311e6D8e8e7832b1f76aA6115E4`](https://calibration.filfox.info/en/address/0xCc6C40Da237F2311e6D8e8e7832b1f76aA6115E4)

  - Implementation: [`0x4cEf33B5022b8e3A7f431E6D146DB8748f7Fa1a5`](https://calibration.filfox.info/en/address/0x4cEf33B5022b8e3A7f431E6D146DB8748f7Fa1a5)

- Storage Provider Collateral: [`0x98A79c415aF7b4c0c2C8fB440796D02652AbDF87`](https://calibration.filfox.info/en/address/0x98A79c415aF7b4c0c2C8fB440796D02652AbDF87)

  - Implementation: [`0x34Df18Bd874A48699c87FCd6c4aA6f97BAdF0C7d`](https://calibration.filfox.info/en/address/0x34Df18Bd874A48699c87FCd6c4aA6f97BAdF0C7d)

- Resolver: [`0x4867b084C9F5DE0705376d6dcef966c69f8d37a3`](https://calibration.filfox.info/en/address/0x4867b084C9F5DE0705376d6dcef966c69f8d37a3)

  - Implementation: [`0xbD4a58BfAB72F5b11De69ED120467B51358FDf08`](https://calibration.filfox.info/en/address/0xbD4a58BfAB72F5b11De69ED120467B51358FDf08)

- Reward Collector: [`0x577AA248DeB2EAaAfDb1137339F367C54cAf9B3d`](https://calibration.filfox.info/en/address/0x577AA248DeB2EAaAfDb1137339F367C54cAf9B3d)
  - Implementation: [`0xC5Ef60783Fd1C6e7A6f37537BA3062466bcdc5D1`](https://calibration.filfox.info/en/address/0xC5Ef60783Fd1C6e7A6f37537BA3062466bcdc5D1)

## Documentation

If you want to use Collectif DAO to cover your initial pledge requirements, take a look at the extensive [Collectif DAO documentation](http://docs.collectif.finance/).

## Community

General discussion happens most frequently on the [Collectif DAO discord](https://discord.gg/xnenkym3y6).
Latest news and announcements on the [Collectif DAO twitter](https://twitter.com/collectifDAO)
