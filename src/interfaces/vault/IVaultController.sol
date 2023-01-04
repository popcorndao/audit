// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { KeeperConfig } from "../IKeeperIncentiveV2.sol";
import { VaultParams, FeeStructure } from "./IVault.sol";
import { VaultMetadata } from "./IVaultRegistry.sol";
import { IERC4626, IERC20 } from "./IERC4626.sol";

struct DeploymentArgs {
  /// @Notice templateId
  bytes32 id;
  /// @Notice encoded init params
  bytes data;
}

interface IVaultController {
  function deployVault(
    DeploymentArgs memory strategyData,
    DeploymentArgs memory adapterData,
    bytes memory rewardsData,
    VaultParams memory vaultData,
    VaultMetadata memory metadata,
    bytes memory addKeeperData
  ) external returns (address);

  function deployAdapter(
    IERC20 asset,
    DeploymentArgs memory adapterData,
    DeploymentArgs memory strategyData
  ) external returns (address);

  function deployStaking(IERC20 asset) external returns (address);

  function proposeVaultAdapter(address[] memory vaults, IERC4626[] memory newAdapter) external;

  function changeVaultAdapter(address[] memory vaults) external;

  function proposeVaultFees(address[] memory vaults, FeeStructure[] memory newFees) external;

  function changeVaultFees(address[] memory vaults) external;

  function setVaultKeeperConfig(address[] memory vaults, KeeperConfig[] memory keeperConfigs) external;

  function toggleEndorsement(address[] memory targets) external;

  function addStakingRewardsToken(address[] memory vaults, bytes[] memory rewardsTokenData) external;

  function changeStakingRewardsSpeed(address[] memory vaults, bytes[] memory rewardsTokenData) external;

  function fundStakingReward(address[] memory vaults, bytes[] memory rewardsTokenData) external;

  function setEscrowTokenFee(IERC20[] memory tokens, uint256[] memory fees) external;

  function setEscrowKeeperPerc(uint256 keeperPerc) external;

  function addTemplateType(bytes32[] memory templateTypes) external;

  function pauseAdapter(address[] calldata vaults) external;

  function pauseVault(address[] calldata vaults) external;

  function unpauseAdapter(address[] calldata vaults) external;

  function unpauseVault(address[] calldata vaults) external;

  function nominateNewAdminProxyOwner(address newOwner) external;

  function acceptAdminProxyOwnership() external;

  function setManagementFee(uint256 newFee) external;

  function managementFee() external view returns (uint256);

  function setHarvestCooldown(uint256 newCooldown) external;

  function harvestCooldown() external view returns (uint256);

  function setLatestTemplateKey(bytes32 templateKey, bytes32 latestKey) external;

  function latestTemplateKey(bytes32 templateKey, bytes32 latestKey) external view returns (bytes32);
}
