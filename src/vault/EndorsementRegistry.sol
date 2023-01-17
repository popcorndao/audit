// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Owned } from "../utils/Owned.sol";
import { IEndorsementRegistry } from "../interfaces/vault/IEndorsementRegistry.sol";

/**
 * @title   EndorsementRegistry
 * @author  RedVeil
 * @notice  Allows the DAO to endorse and reject addresses for security purposes.
 */
contract EndorsementRegistry is Owned {
  /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
    //////////////////////////////////////////////////////////////*/

  /// @param _owner `AdminProxy`
  constructor(address _owner) Owned(_owner) {}

  /*//////////////////////////////////////////////////////////////
                          ENDORSEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

  mapping(address => bool) public endorsed;

  event EndorsementToggled(address target, bool oldEndorsement, bool newEndorsement);

  error Mismatch();

  /// @notice Toggle endorsements for a list of targets. Caller must be owner. (`VaultController` via `AdminProxy`)
  function toggleEndorsements(address[] memory targets) external onlyOwner {
    bool oldEndorsement;
    bool newEndorsement;
    address target;

    uint256 len = targets.length;
    for (uint256 i = 0; i < len; i++) {
      target = targets[i];
      oldEndorsement = endorsed[target];
      newEndorsement = !oldEndorsement;

      if (newEndorsement && rejected[target]) revert Mismatch();

      emit EndorsementToggled(target, oldEndorsement, newEndorsement);

      endorsed[target] = newEndorsement;
    }
  }

  /*//////////////////////////////////////////////////////////////
                          REJECTION LOGIC
    //////////////////////////////////////////////////////////////*/

  mapping(address => bool) public rejected;

  event RejectionToggled(address target, bool oldRejection, bool newRejection);

  /// @notice Toggle rejections for a list of targets. Caller must be owner. (`VaultController` via `AdminProxy`)
  function toggleRejections(address[] memory targets) external onlyOwner {
    bool oldRejection;
    bool newRejection;

    address target;

    uint256 len = targets.length;
    for (uint256 i = 0; i < len; i++) {
      target = targets[i];
      oldRejection = rejected[target];
      newRejection = !oldRejection;

      if (newRejection && endorsed[target]) revert Mismatch();

      emit RejectionToggled(target, oldRejection, newRejection);

      rejected[target] = newRejection;
    }
  }
}
