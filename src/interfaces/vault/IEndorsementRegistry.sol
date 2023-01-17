// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { IOwned } from "../IOwned.sol";

interface IEndorsementRegistry is IOwned {
  function endorsed(address target) external view returns (bool);

  function toggleEndorsements(address[] memory targets) external;

  function rejected(address target) external view returns (bool);

  function toggleRejections(address[] memory targets) external;
}
