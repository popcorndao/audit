// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ERC4626Upgradeable, IERC20Upgradeable as IERC20, IERC20MetadataUpgradeable as IERC20Metadata, ERC20Upgradeable as ERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { MathUpgradeable as Math } from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import { ACLAuth } from "../../../utils/ACLAuth.sol";
import { IStrategy } from "../../../interfaces/vault/IStrategy.sol";
import { IAdapter } from "../../../interfaces/vault/IAdapter.sol";
import { EIP165 } from "../../../utils/EIP165.sol";
import { OnlyStrategy } from "./OnlyStrategy.sol";
import { OwnedUpgradeable } from "../../../utils/OwnedUpgradeable.sol";

/*
 * @title Beefy ERC4626 Contract
 * @notice ERC4626 wrapper for beefy vaults
 * @author RedVeil
 *
 * Wraps https://github.com/beefyfinance/beefy-contracts/blob/master/contracts/BIFI/vaults/BeefyVaultV6.sol
 */
contract AdapterBase is ERC4626Upgradeable, PausableUpgradeable, OwnedUpgradeable, EIP165, OnlyStrategy {
  using SafeERC20 for IERC20;
  using Math for uint256;
  /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

  uint8 internal _decimals;

  error NotFactory();
  error StrategySetupFailed();

  /**
     @notice Initializes the Vault.
    */
  function __AdapterBase_init(bytes memory popERC4626InitData) public initializer {
    (
      address asset,
      address _owner,
      address _strategy,
      uint256 _harvestCooldown,
      bytes4[8] memory _requiredSigs,
      bytes memory _strategyConfig
    ) = abi.decode(popERC4626InitData, (address, address, address, uint256, bytes4[8], bytes));
    __Owned_init(_owner);
    __Pausable_init();
    __ERC4626_init(IERC20Metadata(asset));

    INITIAL_CHAIN_ID = block.chainid;
    INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

    _decimals = IERC20Metadata(asset).decimals();

    strategy = IStrategy(_strategy);
    strategyConfig = _strategyConfig;
    harvestCooldown = _harvestCooldown;

    if (_strategy != address(0)) _verifyAndSetupStrategy(_requiredSigs);

    feesUpdatedAt = block.timestamp;
  }

  function decimals() public view override(IERC20Metadata, ERC20) returns (uint8) {
    return _decimals;
  }

  /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

  function totalAssets() public view virtual override returns (uint256) {
    // Return assets in adapter if paused
    // Otherwise return assets held by the adapter in underlying protocol
  }

  function convertToUnderlyingShares(uint256 assets, uint256 shares) public view virtual returns (uint256) {
    // OPTIONAL - convert assets or shares into underlying shares if those are needed to deposit/withdraw in the underlying protocol
  }

  /** @dev See {IERC4262-maxDeposit}. */
  function maxDeposit(address) public view virtual override returns (uint256) {
    return paused() ? 0 : type(uint256).max;
  }

  /** @dev See {IERC4262-maxMint}. */
  function maxMint(address) public view virtual override returns (uint256) {
    return paused() ? 0 : type(uint256).max;
  }

  /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

  function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
    return paused() ? 0 : _convertToShares(assets, Math.Rounding.Down);
  }

  function previewMint(uint256 shares) public view virtual override returns (uint256) {
    return paused() ? 0 : _convertToAssets(shares, Math.Rounding.Up);
  }

  function _convertToShares(
    uint256 assets,
    Math.Rounding rounding
  ) internal view virtual override returns (uint256 shares) {
    uint256 _totalSupply = totalSupply();
    uint256 _totalAssets = totalAssets();
    return
      (assets == 0 || _totalSupply == 0 || _totalAssets == 0)
        ? assets
        : assets.mulDiv(_totalSupply, _totalAssets, rounding);
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

  /**
   * @dev Deposit/mint common workflow.
   */
  function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
    // If _asset is ERC777, `transferFrom` can trigger a reenterancy BEFORE the transfer happens through the
    // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
    // calls the vault, which is assumed not malicious.
    //
    // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
    // assets are transferred and before the shares are minted, which is a valid state.
    // slither-disable-next-line reentrancy-no-eth
    IERC20(asset()).safeTransferFrom(caller, address(this), assets);

    _protocolDeposit(assets, shares);

    _mint(receiver, shares);

    harvest();

    emit Deposit(caller, receiver, assets, shares);
  }

  function _protocolDeposit(uint256 assets, uint256 shares) internal virtual {
    // OPTIONAL - convertIntoUnderlyingShares(assets,shares)
    // deposit into underlying protocol
  }

  /**
   * @dev Withdraw/redeem common workflow.
   */
  function _withdraw(
    address caller,
    address receiver,
    address owner,
    uint256 assets,
    uint256 shares
  ) internal virtual override {
    if (caller != owner) {
      _spendAllowance(owner, caller, shares);
    }

    if (!paused()) {
      _protocolWithdraw(assets, shares);
    }

    // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
    // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
    // calls the vault, which is assumed not malicious.
    //
    // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
    // shares are burned and after the assets are transferred, which is a valid state.
    _burn(owner, shares);

    IERC20(asset()).safeTransfer(receiver, assets);

    harvest();

    emit Withdraw(caller, receiver, owner, assets, shares);
  }

  function _protocolWithdraw(uint256 assets, uint256 shares) internal virtual {
    // OPTIONAL - convertIntoUnderlyingShares(assets,shares)
    // withdraw from underlying protocol
  }

  /*//////////////////////////////////////////////////////////////
                      EIP-2612 LOGIC
  //////////////////////////////////////////////////////////////*/

  error PermitDeadlineExpired(uint256 deadline);
  error InvalidSigner(address signer);

  //  EIP-2612 STORAGE
  uint256 internal INITIAL_CHAIN_ID;
  bytes32 internal INITIAL_DOMAIN_SEPARATOR;
  mapping(address => uint256) public nonces;

  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public virtual {
    if (deadline < block.timestamp) revert PermitDeadlineExpired(deadline);

    // Unchecked because the only math done is incrementing
    // the owner's nonce which cannot realistically overflow.
    unchecked {
      address recoveredAddress = ecrecover(
        keccak256(
          abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR(),
            keccak256(
              abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonces[owner]++,
                deadline
              )
            )
          )
        ),
        v,
        r,
        s
      );

      if (recoveredAddress == address(0) || recoveredAddress != owner) revert InvalidSigner(recoveredAddress);

      _approve(recoveredAddress, spender, value);
    }
  }

  function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
    return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
  }

  function computeDomainSeparator() internal view virtual returns (bytes32) {
    return
      keccak256(
        abi.encode(
          keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
          keccak256(bytes(name())),
          keccak256("1"),
          block.chainid,
          address(this)
        )
      );
  }

  /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

  IStrategy public strategy;
  bytes public strategyConfig;
  uint256 public harvestCooldown;

  event Harvested();

  function harvest() public takeFees {
    if (address(strategy) != address(0) && ((feesUpdatedAt + harvestCooldown) < block.timestamp)) {
      // solhint-disable
      address(strategy).delegatecall(abi.encodeWithSignature("harvest()"));
    }

    emit Harvested();
  }

  function strategyDeposit(uint256 amount, uint256 shares) public onlyStrategy {
    _protocolDeposit(amount, shares);
  }

  function strategyWithdraw(uint256 amount, uint256 shares) public onlyStrategy {
    _protocolWithdraw(amount, shares);
  }

  function _verifyAndSetupStrategy(bytes4[8] memory requiredSigs) internal {
    strategy.verifyAdapterSelectorCompatibility(requiredSigs);
    strategy.verifyAdapterCompatibility(strategyConfig);
    strategy.setUp(strategyConfig);
  }

  /*//////////////////////////////////////////////////////////////
                      FEE LOGIC
  //////////////////////////////////////////////////////////////*/

  uint256 public managementFee = 5e16;
  uint256 internal constant MAX_FEE = 1e18;
  uint256 internal constant SECONDS_PER_YEAR = 365.25 days;

  // TODO use deterministic fee recipient proxy
  address FEE_RECIPIENT = address(0x4444);

  uint256 public assetsCheckpoint;
  uint256 public feesUpdatedAt;

  error InvalidManagementFee(uint256 fee);

  event ManagementFeeChanged(uint256 oldFee, uint256 newFee);

  function accruedManagementFee() public view returns (uint256) {
    uint256 area = (totalAssets() + assetsCheckpoint) * (block.timestamp - feesUpdatedAt);

    return (managementFee.mulDiv(area, 2, Math.Rounding.Down) / SECONDS_PER_YEAR) / MAX_FEE;
  }

  function setManagementFee(uint256 newFee) public onlyOwner {
    // Dont take more than 10% managementFee
    if (newFee >= 1e17) revert InvalidManagementFee(newFee);

    emit ManagementFeeChanged(managementFee, newFee);

    managementFee = newFee;
  }

  modifier takeFees() {
    _;

    uint256 _managementFee = accruedManagementFee();

    if (_managementFee > 0) {
      feesUpdatedAt = block.timestamp;
      _mint(FEE_RECIPIENT, convertToShares(_managementFee));
    }

    assetsCheckpoint = totalAssets();
  }

  /*//////////////////////////////////////////////////////////////
                      PAUSING LOGIC
  //////////////////////////////////////////////////////////////*/

  function pause() external onlyOwner {
    _protocolWithdraw(totalAssets(), totalSupply());
    _pause();
  }

  function unpause() external onlyOwner {
    _protocolDeposit(totalAssets(), totalSupply());
    _unpause();
  }

  /*//////////////////////////////////////////////////////////////
                      EIP-165 LOGIC
  //////////////////////////////////////////////////////////////*/

  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return interfaceId == type(IAdapter).interfaceId;
  }
}
