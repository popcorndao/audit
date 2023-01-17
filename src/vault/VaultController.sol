// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import { Owned } from "../utils/Owned.sol";
import { IVault, VaultInitParams, VaultFees } from "../interfaces/vault/IVault.sol";
import { IMultiRewardStaking } from "../interfaces/IMultiRewardStaking.sol";
import { IMultiRewardEscrow } from "../interfaces/IMultiRewardEscrow.sol";
import { IDeploymentController, ICloneRegistry } from "../interfaces/vault/IDeploymentController.sol";
import { ITemplateRegistry, Template } from "../interfaces/vault/ITemplateRegistry.sol";
import { IEndorsementRegistry } from "../interfaces/vault/IEndorsementRegistry.sol";
import { IVaultRegistry, VaultMetadata } from "../interfaces/vault/IVaultRegistry.sol";
import { IAdminProxy } from "../interfaces/vault/IAdminProxy.sol";
import { IERC4626, IERC20 } from "../interfaces/vault/IERC4626.sol";
import { IStrategy } from "../interfaces/vault/IStrategy.sol";
import { IAdapter } from "../interfaces/vault/IAdapter.sol";
import { IPausable } from "../interfaces/IPausable.sol";
import { DeploymentArgs } from "../interfaces/vault/IVaultController.sol";

/**
 * @title   VaultController
 * @author  RedVeil
 * @notice  Admin contract for the vault ecosystem.
 *
 * Deploys Vaults, Adapter, Strategies and Staking contracts.
 * Calls admin functions on deployed contracts.
 */
contract VaultController is Owned {
  /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

  bytes32 public immutable VAULT = "Vault";
  bytes32 public immutable ADAPTER = "Adapter";
  bytes32 public immutable STRATEGY = "Strategy";
  bytes32 public immutable STAKING = "Staking";
  bytes4 internal immutable DEPLOY_SIG = bytes4(keccak256("deploy(bytes32,bytes32,bytes)"));

  error UnderlyingError(bytes revertReason);

  /**
   * @notice Constructor of this contract.
   * @param _owner Owner of the contract. Controls management functions.
   * @param _adminProxy `AdminProxy` ownes contracts in the vault ecosystem.
   * @param _deploymentController `DeploymentController` with auxiliary deployment contracts.
   * @param _vaultRegistry `VaultRegistry` to safe vault metadata.
   * @param _endorsementRegistry `EndorsementRegistry` to add endorsements and rejections.
   * @param _escrow `MultiRewardEscrow` To escrow rewards of staking contracts.
   */
  constructor(
    address _owner,
    IAdminProxy _adminProxy,
    IDeploymentController _deploymentController,
    IVaultRegistry _vaultRegistry,
    IEndorsementRegistry _endorsementRegistry,
    IMultiRewardEscrow _escrow
  ) Owned(_owner) {
    adminProxy = _adminProxy;
    vaultRegistry = _vaultRegistry;
    endorsementRegistry = _endorsementRegistry;
    escrow = _escrow;

    _setDeploymentController(_deploymentController);

    activeTemplateId[STAKING] = "MultiRewardStaking";
    activeTemplateId[VAULT] = "V1";
  }

  /*//////////////////////////////////////////////////////////////
                          VAULT DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

  event VaultDeployed(address indexed vault, address indexed staking, address indexed adapter);

  /**
   * @notice Deploy a new Vault. Optionally with an Adapter and Staking. Caller must be owner.
   * @param vaultData Vault init params.
   * @param adapterData Encoded adapter init data.
   * @param strategyData Encoded strategy init data.
   * @param staking Address of staking contract to use for the vault. If 0, a new staking contract will be deployed.
   * @param rewardsData Encoded data to add a rewards to the staking contract
   * @param metadata Vault metadata for the `VaultRegistry` (Will be used by the frontend for additional informations)
   * @dev This function is the one stop solution to create a new vault with all necessary admin functions or auxiliery contracts.
   */
  function deployVault(
    VaultInitParams memory vaultData,
    DeploymentArgs memory adapterData,
    DeploymentArgs memory strategyData,
    address staking,
    bytes memory rewardsData,
    VaultMetadata memory metadata
  ) external onlyOwner returns (address vault) {
    IDeploymentController _deploymentController = deploymentController;

    _verifyToken(vaultData.asset);
    _verifyAdapterConfiguration(address(vaultData.adapter), adapterData.id);

    if (adapterData.id > 0)
      vaultData.adapter = IERC4626(_deployAdapter(vaultData.asset, adapterData, strategyData, _deploymentController));

    vault = _deployVault(vaultData, _deploymentController);

    if (staking == address(0)) staking = _deployStaking(IERC20(address(vault)), _deploymentController);

    _registerCreatedVault(vault, staking, metadata);

    if (rewardsData.length > 0) _handleVaultStakingRewards(vault, rewardsData);

    emit VaultDeployed(vault, staking, address(vaultData.adapter));
  }

  /// @notice Deploys a new vault contract using the `activeTemplateId`.
  function _deployVault(VaultInitParams memory vaultData, IDeploymentController _deploymentController)
    internal
    returns (address vault)
  {
    vaultData.owner = address(adminProxy);

    (bool success, bytes memory returnData) = adminProxy.execute(
      address(_deploymentController),
      abi.encodeWithSelector(
        DEPLOY_SIG,
        VAULT,
        activeTemplateId[VAULT],
        abi.encodeWithSelector(IVault.initialize.selector, vaultData)
      )
    );
    if (!success) revert UnderlyingError(returnData);

    vault = abi.decode(returnData, (address));
  }

  /// @notice Registers newly created vault metadata.
  function _registerCreatedVault(
    address vault,
    address staking,
    VaultMetadata memory metadata
  ) internal {
    metadata.vault = vault;
    metadata.staking = staking;
    metadata.submitter = msg.sender;

    _registerVault(vault, metadata);
  }

  /// @notice Prepares and calls `addStakingRewardsTokens` for the newly created staking contract.
  function _handleVaultStakingRewards(address vault, bytes memory rewardsData) internal {
    address[] memory vaultContracts = new address[](1);
    bytes[] memory rewardsDatas = new bytes[](1);

    vaultContracts[0] = vault;
    rewardsDatas[0] = rewardsData;

    addStakingRewardsTokens(vaultContracts, rewardsDatas);
  }

  /*//////////////////////////////////////////////////////////////
                      ADAPTER DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploy a new Adapter with our without a strategy. Caller must be owner.
   * @param asset Asset which will be used by the adapter.
   * @param adapterData Encoded adapter init data.
   * @param strategyData Encoded strategy init data.
   */
  function deployAdapter(
    IERC20 asset,
    DeploymentArgs memory adapterData,
    DeploymentArgs memory strategyData
  ) public onlyOwner returns (address) {
    _verifyToken(asset);

    return _deployAdapter(asset, adapterData, strategyData, deploymentController);
  }

  /**
   * @notice Deploys an adapter and optionally a strategy.
   * @dev Adds the newly deployed strategy to the adapter.
   */
  function _deployAdapter(
    IERC20 asset,
    DeploymentArgs memory adapterData,
    DeploymentArgs memory strategyData,
    IDeploymentController _deploymentController
  ) internal returns (address) {
    address strategy;
    bytes4[8] memory requiredSigs;
    if (strategyData.id > 0) {
      strategy = _deployStrategy(strategyData, _deploymentController);
      requiredSigs = templateRegistry.getTemplate(STRATEGY, strategyData.id).requiredSigs;
    }

    return
      __deployAdapter(
        adapterData,
        abi.encode(asset, address(adminProxy), IStrategy(strategy), harvestCooldown, requiredSigs, strategyData.data),
        _deploymentController
      );
  }

  /// @notice Deploys an adapter and sets the management fee via `AdminProxy`
  function __deployAdapter(
    DeploymentArgs memory adapterData,
    bytes memory baseAdapterData,
    IDeploymentController _deploymentController
  ) internal returns (address adapter) {
    (bool success, bytes memory returnData) = adminProxy.execute(
      address(_deploymentController),
      abi.encodeWithSelector(DEPLOY_SIG, ADAPTER, adapterData.id, _encodeAdapterData(adapterData, baseAdapterData))
    );
    if (!success) revert UnderlyingError(returnData);

    adapter = abi.decode(returnData, (address));

    adminProxy.execute(adapter, abi.encodeWithSelector(IAdapter.setManagementFee.selector, managementFee));
  }

  /// @notice Encodes adapter init call. Was moved into its own function to fix "stack too deep" error.
  function _encodeAdapterData(DeploymentArgs memory adapterData, bytes memory baseAdapterData)
    internal
    returns (bytes memory)
  {
    return
      abi.encodeWithSelector(
        IAdapter.initialize.selector,
        baseAdapterData,
        templateRegistry.getTemplate(ADAPTER, adapterData.id).registry,
        adapterData.data
      );
  }

  /// @notice Deploys a new strategy contract.
  function _deployStrategy(DeploymentArgs memory strategyData, IDeploymentController _deploymentController)
    internal
    returns (address strategy)
  {
    (bool success, bytes memory returnData) = adminProxy.execute(
      address(_deploymentController),
      abi.encodeWithSelector(DEPLOY_SIG, STRATEGY, strategyData.id, "")
    );
    if (!success) revert UnderlyingError(returnData);

    strategy = abi.decode(returnData, (address));
  }

  /*//////////////////////////////////////////////////////////////
                    STAKING DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploy a new staking contract. Caller must be owner.
   * @param asset The staking token for the new contract.
   * @dev Deploys `MultiRewardsStaking` based on the latest templateTemplateKey.
   */
  function deployStaking(IERC20 asset) public onlyOwner returns (address) {
    _verifyToken(asset);
    return _deployStaking(asset, deploymentController);
  }

  /// @notice Deploys a new staking contract using the activeTemplateId.
  function _deployStaking(IERC20 asset, IDeploymentController _deploymentController)
    internal
    returns (address staking)
  {
    (bool success, bytes memory returnData) = adminProxy.execute(
      address(_deploymentController),
      abi.encodeWithSelector(
        DEPLOY_SIG,
        STAKING,
        activeTemplateId[STAKING],
        abi.encodeWithSelector(IMultiRewardStaking.initialize.selector, asset, escrow, adminProxy)
      )
    );
    if (!success) revert UnderlyingError(returnData);

    staking = abi.decode(returnData, (address));
  }

  /*//////////////////////////////////////////////////////////////
                    VAULT MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

  error DoesntExist(address adapter);

  /**
   * @notice Propose a new Adapter. Caller must be submitter of the vaults.
   * @param vaults Vaults to propose the new adapter for.
   * @param newAdapter New adapters to propose.
   */
  function proposeVaultAdapters(address[] memory vaults, IERC4626[] memory newAdapter) external {
    uint8 len = uint8(vaults.length);

    _verifyEqualArrayLength(len, newAdapter.length);

    ICloneRegistry _cloneRegistry = cloneRegistry;
    for (uint8 i = 0; i < len; i++) {
      _verifySubmitter(vaults[i]);
      if (!_cloneRegistry.cloneExists(address(newAdapter[i]))) revert DoesntExist(address(newAdapter[i]));

      (bool success, bytes memory returnData) = adminProxy.execute(
        vaults[i],
        abi.encodeWithSelector(IVault.proposeAdapter.selector, newAdapter[i])
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /**
   * @notice Change adapter of a vault to the previously proposed adapter.
   * @param vaults Addresses of the vaults to change
   */
  function changeVaultAdapters(address[] memory vaults) external {
    uint8 len = uint8(vaults.length);
    for (uint8 i = 0; i < len; i++) {
      (bool success, bytes memory returnData) = adminProxy.execute(
        vaults[i],
        abi.encodeWithSelector(IVault.changeAdapter.selector)
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /**
   * @notice Sets new fees per vault. Caller must be submitter of the vaults.
   * @param vaults Addresses of the vaults to change
   * @param fees New fee structures for these vaults
   * @dev Value is in 1e18, e.g. 100% = 1e18 - 1 BPS = 1e12
   */
  function proposeVaultFees(address[] memory vaults, VaultFees[] memory fees) external {
    uint8 len = uint8(vaults.length);

    _verifyEqualArrayLength(len, fees.length);

    for (uint8 i = 0; i < len; i++) {
      _verifySubmitter(vaults[i]);

      (bool success, bytes memory returnData) = adminProxy.execute(
        vaults[i],
        abi.encodeWithSelector(IVault.proposeFees.selector, fees[i])
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /**
   * @notice Change adapter of a vault to the previously proposed adapter.
   * @param vaults Addresses of the vaults
   */
  function changeVaultFees(address[] memory vaults) external {
    uint8 len = uint8(vaults.length);
    for (uint8 i = 0; i < len; i++) {
      (bool success, bytes memory returnData) = adminProxy.execute(
        vaults[i],
        abi.encodeWithSelector(IVault.changeFees.selector)
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /*//////////////////////////////////////////////////////////////
                    RETROACTIVE REGISTRY LOGIC
    //////////////////////////////////////////////////////////////*/

  IVaultRegistry public vaultRegistry;

  /**
   * @notice Registers metadata for vaults that havent been created by this contract. Caller must be owner.
   * @param vaults Addresses of the vaults to add.
   * @param metadata VaultMetadata (See IVaultRegistry for more details)
   * @dev See `VaultRegistry` for more details
   */
  function registerVaults(address[] memory vaults, VaultMetadata[] memory metadata) external onlyOwner {
    uint8 len = uint8(vaults.length);

    _verifyEqualArrayLength(len, metadata.length);

    for (uint8 i = 0; i < len; i++) {
      _registerVault(vaults[i], metadata[i]);
    }
  }

  /// @notice Call the `VaultRegistry` to register a vault via `AdminProxy`
  function _registerVault(address vault, VaultMetadata memory metadata) internal {
    (bool success, bytes memory returnData) = adminProxy.execute(
      address(vaultRegistry),
      abi.encodeWithSelector(IVaultRegistry.registerVault.selector, metadata)
    );
    if (!success) revert UnderlyingError(returnData);
  }

  /**
   * @notice Adds a clones to the registry which were not created via this contract. Caller must be owner.
   * @dev See `CloneRegistry` for more details
   */
  function addClones(address[] memory clones) external onlyOwner {
    uint8 len = uint8(clones.length);
    for (uint8 i = 0; i < len; i++) {
      (bool success, bytes memory returnData) = adminProxy.execute(
        address(deploymentController),
        abi.encodeWithSelector(IDeploymentController.addClone.selector, clones[i])
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /*//////////////////////////////////////////////////////////////
                    ENDORSEMENT / REJECTION LOGIC
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Toggles whether an address is endorsed. Caller must be owner.
   * @param targets Addresses of the contracts to change endorsement
   * @dev See `EndorsementRegistry` for more details
   */
  function toggleEndorsements(address[] memory targets) external onlyOwner {
    (bool success, bytes memory returnData) = adminProxy.execute(
      address(endorsementRegistry),
      abi.encodeWithSelector(IEndorsementRegistry.toggleEndorsements.selector, targets)
    );
    if (!success) revert UnderlyingError(returnData);
  }

  /**
   * @notice Toggles whether an address is rejected. Caller must be owner.
   * @param targets Addresses of the contracts to change endorsement
   * @dev See `EndorsementRegistry` for more details
   */
  function toggleRejections(address[] memory targets) external onlyOwner {
    (bool success, bytes memory returnData) = adminProxy.execute(
      address(endorsementRegistry),
      abi.encodeWithSelector(IEndorsementRegistry.toggleRejections.selector, targets)
    );
    if (!success) revert UnderlyingError(returnData);
  }

  /*//////////////////////////////////////////////////////////////
                      STAKING MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/
  /**
   * @notice Adds a new rewardToken which can be earned via staking. Caller must be submitter of the Vault or owner.
   * @param vaults Vaults of which the staking contracts should be targeted
   * @param rewardTokenData Token that can be earned by staking.
   * @dev `rewardToken` - Token that can be earned by staking.
   * @dev `rewardsPerSecond` - The rate in which `rewardToken` will be accrued.
   * @dev `amount` - Initial funding amount for this reward.
   * @dev `useEscrow Bool` - if the rewards should be escrowed on claim.
   * @dev `escrowPercentage` - The percentage of the reward that gets escrowed in 1e18. (1e18 = 100%, 1e14 = 1 BPS)
   * @dev `escrowDuration` - The duration of the escrow.
   * @dev `offset` - A cliff after claim before the escrow starts.
   * @dev See `MultiRewardsStaking` for more details.
   */
  function addStakingRewardsTokens(address[] memory vaults, bytes[] memory rewardTokenData) public {
    _verifyEqualArrayLength(vaults.length, rewardTokenData.length);
    address staking;
    uint8 len = uint8(vaults.length);
    for (uint256 i = 0; i < len; i++) {
      (
        address rewardsToken,
        uint160 rewardsPerSecond,
        uint256 amount,
        bool useEscrow,
        uint224 escrowDuration,
        uint24 escrowPercentage,
        uint256 offset
      ) = abi.decode(rewardTokenData[i], (address, uint160, uint256, bool, uint224, uint24, uint256));
      _verifyToken(IERC20(rewardsToken));
      staking = _verifySubmitterOrOwner(vaults[i]).staking;

      (bool success, bytes memory returnData) = adminProxy.execute(
        rewardsToken,
        abi.encodeWithSelector(IERC20.approve.selector, staking, type(uint256).max)
      );
      if (!success) revert UnderlyingError(returnData);

      IERC20(rewardsToken).approve(staking, type(uint256).max);
      IERC20(rewardsToken).transferFrom(msg.sender, address(adminProxy), amount);

      (success, returnData) = adminProxy.execute(
        staking,
        abi.encodeWithSelector(
          IMultiRewardStaking.addRewardToken.selector,
          rewardsToken,
          rewardsPerSecond,
          amount,
          useEscrow,
          escrowDuration,
          escrowPercentage,
          offset
        )
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /**
   * @notice Changes rewards speed for a rewardToken. This works only for rewards that accrue over time. Caller must be submitter of the Vault.
   * @param vaults Vaults of which the staking contracts should be targeted
   * @param rewardTokens Token that can be earned by staking.
   * @param rewardsSpeeds The rate in which `rewardToken` will be accrued.
   * @dev See `MultiRewardsStaking` for more details.
   */
  function changeStakingRewardsSpeeds(
    address[] memory vaults,
    IERC20[] memory rewardTokens,
    uint160[] memory rewardsSpeeds
  ) external {
    uint8 len = uint8(vaults.length);

    _verifyEqualArrayLength(len, rewardTokens.length);
    _verifyEqualArrayLength(len, rewardsSpeeds.length);

    address staking;
    for (uint256 i = 0; i < len; i++) {
      staking = _verifySubmitter(vaults[i]).staking;

      (bool success, bytes memory returnData) = adminProxy.execute(
        staking,
        abi.encodeWithSelector(IMultiRewardStaking.changeRewardSpeed.selector, rewardTokens[i], rewardsSpeeds[i])
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /**
   * @notice Funds rewards for a rewardToken.
   * @param vaults Vaults of which the staking contracts should be targeted
   * @param rewardTokens Token that can be earned by staking.
   * @param amounts The amount of rewardToken that will fund this reward.
   * @dev See `MultiRewardStaking` for more details.
   */
  function fundStakingRewards(
    address[] memory vaults,
    IERC20[] memory rewardTokens,
    uint256[] memory amounts
  ) external {
    uint8 len = uint8(vaults.length);

    _verifyEqualArrayLength(len, rewardTokens.length);
    _verifyEqualArrayLength(len, amounts.length);

    address staking;
    for (uint256 i = 0; i < len; i++) {
      staking = vaultRegistry.getVault(vaults[i]).staking;

      rewardTokens[i].transferFrom(msg.sender, address(this), amounts[i]);
      IMultiRewardStaking(staking).fundReward(rewardTokens[i], amounts[i]);
    }
  }

  /*//////////////////////////////////////////////////////////////
                      ESCROW MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

  IMultiRewardEscrow public escrow;

  /**
   * @notice Set fees for multiple tokens. Caller must be the owner.
   * @param tokens Array of tokens.
   * @param fees Array of fees for `tokens` in 1e18. (1e18 = 100%, 1e14 = 1 BPS)
   * @dev See `MultiRewardEscrow` for more details.
   */
  function setEscrowTokenFees(IERC20[] memory tokens, uint256[] memory fees) external onlyOwner {
    _verifyEqualArrayLength(tokens.length, fees.length);
    (bool success, bytes memory returnData) = adminProxy.execute(
      address(escrow),
      abi.encodeWithSelector(IMultiRewardEscrow.setFees.selector, tokens, fees)
    );
    if (!success) revert UnderlyingError(returnData);
  }

  /*//////////////////////////////////////////////////////////////
                          TEMPLATE LOGIC
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Adds a new templateCategory to the registry. Caller must be owner.
   * @param templateCategories A new category of templates.
   * @dev See `TemplateRegistry` for more details.
   */
  function addTemplateCategories(bytes32[] memory templateCategories) external onlyOwner {
    address _deploymentController = address(deploymentController);
    uint8 len = uint8(templateCategories.length);
    for (uint256 i = 0; i < len; i++) {
      (bool success, bytes memory returnData) = adminProxy.execute(
        _deploymentController,
        abi.encodeWithSelector(IDeploymentController.addTemplateCategory.selector, templateCategories[i])
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /**
   * @notice Toggles the endorsement of a templates. Caller must be owner.
   * @param templateCategories TemplateCategory of the template to endorse.
   * @param templateIds TemplateId of the template to endorse.
   * @dev See `TemplateRegistry` for more details.
   */
  function toggleTemplateEndorsements(bytes32[] memory templateCategories, bytes32[] memory templateIds)
    external
    onlyOwner
  {
    uint8 len = uint8(templateCategories.length);
    _verifyEqualArrayLength(len, templateIds.length);

    address _deploymentController = address(deploymentController);
    for (uint256 i = 0; i < len; i++) {
      (bool success, bytes memory returnData) = adminProxy.execute(
        address(_deploymentController),
        abi.encodeWithSelector(
          ITemplateRegistry.toggleTemplateEndorsement.selector,
          templateCategories[i],
          templateIds[i]
        )
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /*//////////////////////////////////////////////////////////////
                          PAUSING LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @notice Pause Deposits and withdraw all funds from the underlying protocol. Caller must be owner or submitter of the Vault.
  function pauseAdapters(address[] calldata vaults) external {
    uint8 len = uint8(vaults.length);
    for (uint256 i = 0; i < len; i++) {
      _verifySubmitterOrOwner(vaults[i]);
      (bool success, bytes memory returnData) = adminProxy.execute(
        IVault(vaults[i]).adapter(),
        abi.encodeWithSelector(IPausable.pause.selector)
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /// @notice Pause deposits. Caller must be owner or submitter of the Vault.
  function pauseVaults(address[] calldata vaults) external {
    uint8 len = uint8(vaults.length);
    for (uint256 i = 0; i < len; i++) {
      _verifySubmitterOrOwner(vaults[i]);
      (bool success, bytes memory returnData) = adminProxy.execute(
        vaults[i],
        abi.encodeWithSelector(IPausable.pause.selector)
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /// @notice Unpause Deposits and deposit all funds into the underlying protocol. Caller must be owner or submitter of the Vault.
  function unpauseAdapters(address[] calldata vaults) external {
    uint8 len = uint8(vaults.length);
    for (uint256 i = 0; i < len; i++) {
      _verifySubmitterOrOwner(vaults[i]);
      (bool success, bytes memory returnData) = adminProxy.execute(
        IVault(vaults[i]).adapter(),
        abi.encodeWithSelector(IPausable.unpause.selector)
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /// @notice Unpause deposits. Caller must be owner or submitter of the Vault.
  function unpauseVaults(address[] calldata vaults) external {
    uint8 len = uint8(vaults.length);
    for (uint256 i = 0; i < len; i++) {
      _verifySubmitterOrOwner(vaults[i]);
      (bool success, bytes memory returnData) = adminProxy.execute(
        vaults[i],
        abi.encodeWithSelector(IPausable.unpause.selector)
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /*//////////////////////////////////////////////////////////////
                       VERIFICATION LOGIC
    //////////////////////////////////////////////////////////////*/

  error NotSubmitterNorOwner(address caller);
  error NotSubmitter(address caller);
  error TokenNotAllowed(IERC20 token);
  error AdapterConfigFaulty();
  error ArrayLengthMissmatch();

  /// @notice Verify that the caller is the submitter of the vault or owner of `VaultController` (admin rights).
  function _verifySubmitterOrOwner(address vault) internal returns (VaultMetadata memory metadata) {
    metadata = vaultRegistry.getVault(vault);
    if (msg.sender != metadata.submitter || msg.sender != owner) revert NotSubmitterNorOwner(msg.sender);
  }

  /// @notice Verify that the caller is the submitter of the vault.
  function _verifySubmitter(address vault) internal view returns (VaultMetadata memory metadata) {
    metadata = vaultRegistry.getVault(vault);
    if (msg.sender != metadata.submitter) revert NotSubmitter(msg.sender);
  }

  /// @notice Verify that the token is not rejected nor a clone.
  function _verifyToken(IERC20 token) internal view {
    if (endorsementRegistry.rejected(address(token)) || cloneRegistry.cloneExists(address(token)))
      revert TokenNotAllowed(token);
  }

  /// @notice Verify that the adapter configuration is valid.
  function _verifyAdapterConfiguration(address adapter, bytes32 adapterId) internal view {
    if (adapter != address(0)) {
      if (adapterId > 0) revert AdapterConfigFaulty();
      if (!cloneRegistry.cloneExists(adapter)) revert AdapterConfigFaulty();
    }
  }

  /// @notice Verify that the array lengths are equal.
  function _verifyEqualArrayLength(uint256 length1, uint256 length2) internal pure {
    if (length1 != length2) revert ArrayLengthMissmatch();
  }

  /*//////////////////////////////////////////////////////////////
                          OWNERSHIP LOGIC
    //////////////////////////////////////////////////////////////*/

  IAdminProxy public adminProxy;

  /**
   * @notice Nominates a new owner of `AdminProxy`. Caller must be owner.
   * @dev Must be called if the `VaultController` gets swapped out or upgraded
   */
  function nominateNewAdminProxyOwner(address newOwner) external onlyOwner {
    adminProxy.nominateNewOwner(newOwner);
  }

  /**
   * @notice Accepts ownership of `AdminProxy`. Caller must be nominated owner.
   * @dev Must be called after construction
   */
  function acceptAdminProxyOwnership() external {
    adminProxy.acceptOwnership();
  }

  /*//////////////////////////////////////////////////////////////
                          MANAGEMENT FEE LOGIC
    //////////////////////////////////////////////////////////////*/

  uint256 public managementFee;

  error InvalidManagementFee(uint256 fee);

  event ManagementFeeChanged(uint256 oldFee, uint256 newFee);

  /**
   * @notice Set a new managementFee for all new adapters. Caller must be owner.
   * @param newFee mangement fee in 1e18.
   * @dev Fees can be 0 but never more than 2e17 (1e18 = 100%, 1e14 = 1 BPS)
   * @dev Can be retroactively applied to existing adapters.
   */
  function setManagementFee(uint256 newFee) external onlyOwner {
    // Dont take more than 20% managementFee
    if (newFee > 2e17) revert InvalidManagementFee(newFee);

    emit ManagementFeeChanged(managementFee, newFee);

    managementFee = newFee;
  }

  /**
   * @notice Set a new managementFee for existing adapters. Caller must be owner.
   * @param adapters array of adapters to set the management fee for.
   */
  function setAdapterManagementFees(address[] calldata adapters) external onlyOwner {
    uint8 len = uint8(adapters.length);
    for (uint256 i = 0; i < len; i++) {
      (bool success, bytes memory returnData) = adminProxy.execute(
        adapters[i],
        abi.encodeWithSelector(IAdapter.setManagementFee.selector, managementFee)
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /*//////////////////////////////////////////////////////////////
                          HARVEST COOLDOWN LOGIC
    //////////////////////////////////////////////////////////////*/

  uint256 public harvestCooldown;

  error InvalidHarvestCooldown(uint256 cooldown);

  event HarvestCooldownChanged(uint256 oldCooldown, uint256 newCooldown);

  /**
   * @notice Set a new harvestCooldown for all new adapters. Caller must be owner.
   * @param newCooldown Time in seconds that must pass before a harvest can be called again.
   * @dev Cant be longer than 1 day.
   * @dev Can be retroactively applied to existing adapters.
   */
  function setHarvestCooldown(uint256 newCooldown) external onlyOwner {
    // Dont wait more than X seconds
    if (newCooldown > 1 days) revert InvalidHarvestCooldown(newCooldown);

    emit HarvestCooldownChanged(harvestCooldown, newCooldown);

    harvestCooldown = newCooldown;
  }

  /**
   * @notice Set a new harvestCooldown for existing adapters. Caller must be owner.
   * @param adapters Array of adapters to set the cooldown for.
   */
  function setAdapterHarvestCooldowns(address[] calldata adapters) external onlyOwner {
    uint8 len = uint8(adapters.length);
    for (uint256 i = 0; i < len; i++) {
      (bool success, bytes memory returnData) = adminProxy.execute(
        adapters[i],
        abi.encodeWithSelector(IAdapter.setHarvestCooldown.selector, harvestCooldown)
      );
      if (!success) revert UnderlyingError(returnData);
    }
  }

  /*//////////////////////////////////////////////////////////////
                      DEPLYOMENT CONTROLLER LOGIC
    //////////////////////////////////////////////////////////////*/

  IDeploymentController public deploymentController;
  ICloneRegistry public cloneRegistry;
  ITemplateRegistry public templateRegistry;
  IEndorsementRegistry public endorsementRegistry;

  event DeploymentControllerChanged(address oldController, address newController);

  error InvalidDeploymentController(address deploymentController);

  /**
   * @notice Sets a new `DeploymentController` and saves its auxilary contracts. Caller must be owner.
   * @param _deploymentController New DeploymentController.
   */
  function setDeploymentController(IDeploymentController _deploymentController) external onlyOwner {
    _setDeploymentController(_deploymentController);
  }

  function _setDeploymentController(IDeploymentController _deploymentController) internal {
    if (address(_deploymentController) == address(0) || address(deploymentController) == address(_deploymentController))
      revert InvalidDeploymentController(address(_deploymentController));

    emit DeploymentControllerChanged(address(deploymentController), address(_deploymentController));

    deploymentController = _deploymentController;
    cloneRegistry = _deploymentController.cloneRegistry();
    templateRegistry = _deploymentController.templateRegistry();
  }

  /*//////////////////////////////////////////////////////////////
                      TEMPLATE KEY LOGIC
    //////////////////////////////////////////////////////////////*/

  mapping(bytes32 => bytes32) public activeTemplateId;

  error SameKey(bytes32 templateKey);

  event ActiveTemplateIdChanged(bytes32 oldKey, bytes32 newKey);

  /**
   * @notice Set a templateId which shall be used for deploying certain contracts. Caller must be owner.
   * @param templateCategory TemplateCategory to set an active key for.
   * @param templateId TemplateId that should be used when creating a new contract of `templateCategory`
   * @dev Currently `Vault` and `Staking` use a template set via `activeTemplateId`.
   * @dev If this contract should deploy Vaults of a second generation this can be set via the `activeTemplateId`.
   */
  function setActiveTemplateId(bytes32 templateCategory, bytes32 templateId) external onlyOwner {
    bytes32 oldTemplateId = activeTemplateId[templateCategory];
    if (oldTemplateId == templateId) revert SameKey(templateId);

    emit ActiveTemplateIdChanged(oldTemplateId, templateId);

    activeTemplateId[templateCategory] = templateId;
  }
}
