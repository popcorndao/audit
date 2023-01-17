// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import { IERC20Upgradeable as IERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

struct Fee {
  /// @notice Accrued fee amount
  uint256 accrued;
  /// @notice Fee percentage in 1e18 for 100% (1 BPS = 1e14)
  uint256 feePerc;
}

interface IMultiRewardEscrow {
  function lock(IERC20 token, address account, uint256 amount, uint32 duration, uint32 offset) external;

  function setFees(IERC20[] memory tokens, uint256[] memory tokenFees) external;

  function fees(IERC20 token) external view returns (Fee memory);
}
