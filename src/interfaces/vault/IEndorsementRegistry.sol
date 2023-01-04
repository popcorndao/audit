// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { IOwned } from "../IOwned.sol";

interface IEndorsementRegistry is IOwned {
  function endorsed(address target) external view returns (bool);

  function toggleEndorsement(address[] memory targets) external;
}
