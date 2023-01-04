// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ICloneFactory } from "./ICloneFactory.sol";
import { ICloneRegistry } from "./ICloneRegistry.sol";
import { IEndorsementRegistry } from "./IEndorsementRegistry.sol";
import { Template } from "./ITemplateRegistry.sol";

interface IDeploymentController is ICloneFactory, ICloneRegistry {
  function templateTypeExists(bytes32 templateType) external view returns (bool);

  function templateExists(bytes32 templateId) external view returns (bool);

  function addTemplate(bytes32 templateType, bytes32 templateId, Template memory template) external;

  function addTemplateType(bytes32 templateType) external;

  function getTemplate(bytes32 templateType, bytes32 templateId) external view returns (Template memory);
}
