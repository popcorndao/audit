// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import { Test } from "forge-std/Test.sol";
import { EndorsementRegistry } from "../../src/vault/EndorsementRegistry.sol";

contract EndorsementRegistryTest is Test {
  EndorsementRegistry registry;

  address nonOwner = address(0x666);
  address target1 = address(0x1111);
  address target2 = address(0x2222);

  address[] addressArray;

  event EndorsementToggled(address target, bool oldEndorsement, bool newEndorsement);
  event RejectionToggled(address target, bool oldRejection, bool newRejection);

  function setUp() public {
    registry = new EndorsementRegistry(address(this));
  }

  /*//////////////////////////////////////////////////////////////
                          ENDORSEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

  function test__toggleEndorsements() public {
    addressArray.push(target1);
    vm.expectEmit(true, true, true, false, address(registry));
    emit EndorsementToggled(target1, false, true);
    registry.toggleEndorsements(addressArray);

    assertTrue(registry.endorsed(target1));

    addressArray.push(target2);
    vm.expectEmit(true, true, true, false, address(registry));
    emit EndorsementToggled(target1, true, false);
    vm.expectEmit(true, true, true, false, address(registry));
    emit EndorsementToggled(target2, false, true);
    registry.toggleEndorsements(addressArray);

    assertFalse(registry.endorsed(target1));
    assertTrue(registry.endorsed(target2));
  }

  function testFail__toggleEndorsements_endorsement_rejection_mismatch() public {
    addressArray.push(target1);
    registry.toggleRejections(addressArray);

    registry.toggleEndorsements(addressArray);
  }

  function testFail__toggleEndorsements_nonOwner() public {
    addressArray.push(target1);

    vm.prank(nonOwner);
    registry.toggleEndorsements(addressArray);
  }

  /*//////////////////////////////////////////////////////////////
                          REJECTION LOGIC
    //////////////////////////////////////////////////////////////*/

  function test__toggleRejections() public {
    addressArray.push(target1);
    vm.expectEmit(true, true, true, false, address(registry));
    emit RejectionToggled(target1, false, true);
    registry.toggleRejections(addressArray);

    assertTrue(registry.rejected(target1));

    addressArray.push(target2);
    vm.expectEmit(true, true, true, false, address(registry));
    emit RejectionToggled(target1, true, false);
    vm.expectEmit(true, true, true, false, address(registry));
    emit RejectionToggled(target2, false, true);
    registry.toggleRejections(addressArray);

    assertFalse(registry.rejected(target1));
    assertTrue(registry.rejected(target2));
  }

  function testFail__toggleRejections_endorsement_rejection_mismatch() public {
    addressArray.push(target1);
    registry.toggleEndorsements(addressArray);

    registry.toggleRejections(addressArray);
  }

  function testFail__toggleRejections_nonOwner() public {
    addressArray.push(target1);

    vm.prank(nonOwner);
    registry.toggleRejections(addressArray);
  }
}
