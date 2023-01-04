// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { IOwned } from "../IOwned.sol";

interface ICloneFactory is IOwned {
  function deploy(bytes32 templateType, bytes32 templateKey, bytes memory data) external returns (address);
}
