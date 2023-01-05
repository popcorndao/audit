# PopcornDAO Vault Audit

This repo contains PopcornDAO's vault contracts that are based on [EIP-4626](https://eips.ethereum.org/EIPS/eip-4626) vaults.

They are part of a new protocol for the permisionless creation of modular vaults.

The full system contains 3 different types of contracts:

-   **Vault:** A simple ERC-4626 implementation which allows the creator to add various types of fees and interact with other protocols via any ERC-4626 compliant **Adapter**. Fees and **Adapter** can be changed by the creator after a ragequit period.
-   **Adapter:** An immutable wrapper for existing contract to allow for ERC-4626 compatability. Optionally adapters can utilize a **Strategy** to perform various additional tasks besides simply depositing and withdrawing token from the wrapped protocol. PopcornDAO will collect management fees via these **Adapter**.
-   **Strategy:** An arbitrary module to perform various tasks from compouding, leverage or simply forwarding rewards. Strategies can be attached to an **Adapter** to give it additionaly utility.

To ensure safety and allow for easy creation of new **Vaults**, **Adapter** and **Strategies** all these contracts will be created via an additional suite of contracts that are not scope of this audit.


![vaultFlow](./vaultFlow.PNG)


Additionally we included 2 utility contracts that can be used along side the vault system.
-   **MultiRewardStaking:** A simple ERC-4626 implementation of a staking contract. A user can provide an asset and receive rewards in multiple tokens. Adding these rewards is done by the contract owner. They can be either paid out over time or instantly. Rewards can optionally also be vested on claim.
-   **MultiRewardEscrow:** Allows anyone to lock up and vest arbitrary tokens over a given time. Will be used mainly in conjuction with **MultiRewardStaking**.

## Overview
```
src
├── interfaces
├── test
│   ├── utils
│   ├── vault
│   │   ├── integration
│   │   │   ├── beefy
│   │   │   │   ├── BeefyAdapter.t.sol
│   │   │   │   ├── BeefyVault.t.sol
│   │   │   ├── yearn
│   │   │   │   ├── YearnAdapter.t.sol
│   │   │   │   ├── YearnVault.t.sol
│   │   ├── Vault.t.sol
│   ├── MultiRewardEscrow.t.sol
│   ├── MultiRewardStaking.t.sol
├── utils
│   ├── MultiRewardEscrow.sol
│   ├── MultiRewardStaking.sol
├── vault
│   ├── adapter
│   │   ├── abstracts
│   │   │   ├── AdapterBase.sol
│   │   │   ├── OnlyStrategy.sol
│   │   │   ├── WithRewards.sol
│   │   ├── beefy
│   │   │   ├── BeefyAdapter.sol
│   │   ├── yearn
│   │   │   ├── YearnAdapter.sol
│   ├── strategy
│   ├── Vault.sol
```

In scope for this audit are the following contracts:
- Vault.sol
- AdapterBase.sol
- OnlyStrategy.sol
- WithRewards.sol
- BeefyAdapter.sol
- YearnAdapter.sol
- MultiRewardEscrow.sol
- MultiRewardStaking.sol

Some of these contracts depend on older utility contracts which is why this repo contains more than just these contracts. These dependencies have been audited previously.
Additionally there are some wip sample strategies which might help to illustrate how strategies can be used in conjuction with adapters.

**Note:** The `AdapterBase.sol` still has a TODO to use a deterministic address for `feeRecipient`. As we didnt deploy this proxy yet on our target chains it remains a placeholder value for the moment. Once the proxy exists we will simply switch out the palceholder address.

# Developer Notes

## Prerequisites

-   [Node.js](https://nodejs.org/en/) v16.16.0 (you may wish to use [nvm][1])
-   [yarn](https://yarnpkg.com/)
-   [foundry](https://github.com/foundry-rs/foundry)

## Installing Dependencies
```
foundryup

forge install

yarn install
```

## Testing

```
Add RPC urls to .env

forge build

forge test --no-match-contract 'Abstract'
```