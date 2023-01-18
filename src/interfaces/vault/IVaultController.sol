// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { VaultInitParams, VaultFees } from "./IVault.sol";
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
    VaultInitParams memory vaultData,
    VaultMetadata memory metadata,
    bytes memory addKeeperData
  ) external returns (address);

  function deployAdapter(
    IERC20 asset,
    DeploymentArgs memory adapterData,
    DeploymentArgs memory strategyData
  ) external returns (address);

  function deployStaking(IERC20 asset) external returns (address);

  function proposeVaultAdapters(address[] memory vaults, IERC4626[] memory newAdapter) external;

  function changeVaultAdapters(address[] memory vaults) external;

  function proposeVaultFees(address[] memory vaults, VaultFees[] memory newFees) external;

  function changeVaultFees(address[] memory vaults) external;

  function toggleEndorsements(address[] memory targets) external;

  function addStakingRewardsTokens(address[] memory vaults, bytes[] memory rewardsTokenData) external;

  function changeStakingRewardsSpeeds(address[] memory vaults, bytes[] memory rewardsTokenData) external;

  function fundStakingRewards(address[] memory vaults, bytes[] memory rewardsTokenData) external;

  function setEscrowTokenFees(IERC20[] memory tokens, uint256[] memory fees) external;

  function setEscrowKeeperPerc(uint256 keeperPerc) external;

  function addTemplateCategory(bytes32[] memory templateCategorys) external;

  function pauseAdapters(address[] calldata vaults) external;

  function pauseVaults(address[] calldata vaults) external;

  function unpauseAdapters(address[] calldata vaults) external;

  function unpauseVaultss(address[] calldata vaults) external;

  function nominateNewAdminProxyOwner(address newOwner) external;

  function acceptAdminProxyOwnership() external;

  function setManagementFee(uint256 newFee) external;

  function managementFee() external view returns (uint256);

  function setHarvestCooldown(uint256 newCooldown) external;

  function harvestCooldown() external view returns (uint256);

  function setLatestTemplateId(bytes32 templateCategory, bytes32 latestId) external;

  function latestTemplateId(bytes32 templateCategory, bytes32 latestId) external view returns (bytes32);
}
