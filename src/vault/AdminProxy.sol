// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Owned } from "../utils/Owned.sol";

contract AdminProxy is Owned {
  constructor(address _owner) Owned(_owner) {}

  function execute(
    address target,
    bytes memory callData
  ) external onlyOwner returns (bool success, bytes memory returndata) {
    return target.call(callData);
  }
}
