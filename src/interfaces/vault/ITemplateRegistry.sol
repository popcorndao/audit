// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { IOwned } from "../IOwned.sol";

struct Template {
  address implementation;
  string metadataCid;
  bool requiresInitData;
  address registry;
  bytes4[8] requiredSigs; // Only for Strategies
}

interface ITemplateRegistry is IOwned {
  function templates(bytes32 templateType, bytes32 templateId) external view returns (Template memory);

  function templateTypeExists(bytes32 templateType) external view returns (bool);

  function templateExists(bytes32 templateId) external view returns (bool);

  function getTemplateTypes() external view returns (bytes32[] memory);

  function getTemplateIds(bytes32 templateType) external view returns (bytes32[] memory);

  function addTemplate(bytes32 templateType, bytes32 templateId, Template memory template) external;

  function addTemplateType(bytes32 templateType) external;
}
