// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { IOwned } from "../IOwned.sol";

struct VaultMetadata {
  address vaultAddress; // address of vault
  address staking; // address of vault staking contract
  address submitter; // address of vault submitter
  string metadataCID; // ipfs CID of vault metadata
  address[8] swapTokenAddresses; // underlying assets to deposit and recieve LP token
  address swapAddress; // ex: stableSwapAddress for Curve
  uint256 exchange; // number specifying exchange (1 = curve)
}

interface IVaultRegistry is IOwned {
  function vaults(address vault) external view returns (VaultMetadata memory);

  function getSubmitter(address vault) external view returns (address);

  function registerVault(VaultMetadata memory metadata) external;
}
