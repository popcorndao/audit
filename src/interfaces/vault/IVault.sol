// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import { IERC4626, IERC20 } from "./IERC4626.sol";
import { IKeeperIncentiveV2, KeeperConfig } from "../IKeeperIncentiveV2.sol";

// Fees are set in 1e18 for 100% (1 BPS = 1e14)
// Raise Fees in BPS by 1e14 to get an accurate value
struct FeeStructure {
  uint256 deposit;
  uint256 withdrawal;
  uint256 management;
  uint256 performance;
}

struct VaultParams {
  IERC20 asset;
  IERC4626 adapter;
  FeeStructure feeStructure;
  address feeRecipient;
  IKeeperIncentiveV2 keeperIncentive;
  KeeperConfig keeperConfig;
  address owner;
}

interface IVault is IERC4626 {
  // FEE VIEWS

  function accruedManagementFee() external view returns (uint256);

  function accruedPerformanceFee() external view returns (uint256);

  function vaultShareHWM() external view returns (uint256);

  function assetsCheckpoint() external view returns (uint256);

  function feesUpdatedAt() external view returns (uint256);

  function feeStructure() external view returns (FeeStructure memory);

  function proposedFees() external view returns (FeeStructure memory);

  function proposedFeeTimeStamp() external view returns (uint256);

  function feeRecipient() external view returns (address);

  // USER INTERACTIONS

  function deposit(uint256 assets) external returns (uint256);

  function mint(uint256 shares) external returns (uint256);

  function withdraw(uint256 assets) external returns (uint256);

  function redeem(uint256 shares) external returns (uint256);

  function takeManagementAndPerformanceFees() external;

  // MANAGEMENT FUNCTIONS - STRATEGY

  function adapter() external view returns (address);

  function proposedAdapter() external view returns (address);

  function proposalTimeStamp() external view returns (uint256);

  function proposeAdapter(IERC4626 newAdapter) external;

  function changeAdapter() external;

  // MANAGEMENT FUNCTIONS - FEES

  function proposeFees(FeeStructure memory) external;

  function changeFees() external;

  function withdrawAccruedFees() external;

  function setFeeRecipient(address feeRecipient) external;

  // MANAGEMENT FUNCTIONS - OTHER

  function quitPeriod() external view returns (uint256);

  function setQuitPeriod(uint256 _quitPeriod) external;

  function setKeeperConfig(KeeperConfig memory _config) external;

  // INITIALIZE

  function initialize(
    IERC20 asset_,
    IERC4626 adapter_,
    FeeStructure memory feeStructure_,
    address feeRecipient_,
    IKeeperIncentiveV2 keeperIncentive_,
    KeeperConfig memory keeperConfig_,
    address owner
  ) external;
}
