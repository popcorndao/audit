// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { IKeeperIncentiveV2, KeeperConfig } from "../interfaces/IKeeperIncentiveV2.sol";

/**
 *  @notice Provides modifiers and internal functions for processing keeper incentives
 *  @dev Derived contracts using `KeeperIncentivized` must also inherit `ContractRegistryAccess`
 *   and override `_getContract`.
 */
abstract contract KeeperIncentivized {
  IKeeperIncentiveV2 public keeperIncentiveV2;

  event KeeperConfigUpdated(KeeperConfig oldConfig, KeeperConfig newConfig);

  constructor(IKeeperIncentiveV2 keeperIncentive_) {
    keeperIncentiveV2 = keeperIncentive_;
  }

  /**
   *  @notice Process the specified incentive with `msg.sender` as the keeper address
   *  @param _index uint8 incentive ID
   */
  modifier keeperIncentive(uint8 _index) {
    _handleKeeperIncentive(_index, msg.sender);
    _;
  }

  /**
   *  @notice Process a keeper incentive
   *  @param _index uint8 incentive ID
   *  @param _keeper address of keeper to reward
   */
  function _handleKeeperIncentive(uint8 _index, address _keeper) internal {
    keeperIncentiveV2.handleKeeperIncentive(_index, _keeper);
  }

  /**
   * @notice Tip a keeper
   * @param _rewardToken address of token to tip keeper with
   * @param _keeper address of keeper receiving the tip
   * @param _i incentive index
   * @param _amount amount of reward token to tip
   */
  function _tip(address _rewardToken, address _keeper, uint256 _i, uint256 _amount) internal {
    return keeperIncentiveV2.tip(_rewardToken, _keeper, _i, _amount);
  }
}
