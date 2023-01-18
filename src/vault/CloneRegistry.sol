// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Owned } from "../utils/Owned.sol";

/**
 * @title   CloneRegistry
 * @author  RedVeil
 * @notice  Registers clones created by `CloneFactory`.
 *
 * Clones get saved on creation via `DeploymentController`.
 * Is used by `VaultController` to check if a target is a registerd clone.
 */
contract CloneRegistry is Owned {
  /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
    //////////////////////////////////////////////////////////////*/

  /// @param _owner `AdminProxy`
  constructor(address _owner) Owned(_owner) {}

  /*//////////////////////////////////////////////////////////////
                          ENDORSEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

  mapping(address => bool) public cloneExists;

  event CloneAdded(address clone);

  /// @notice Add a clone to the registry. Caller must be owner. (`DeploymentController`)
  function addClone(address clone) external onlyOwner {
    cloneExists[clone] = true;

    emit CloneAdded(clone);
  }
}
