// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter } from "../abstracts/AdapterBase.sol";
import { WithRewards, IWithRewards } from "../abstracts/WithRewards.sol";

interface IBeefyVault {
  function want() external view returns (address);

  function deposit(uint256 _amount) external;

  function withdraw(uint256 _shares) external;

  function withdrawAll() external;

  function balanceOf(address _account) external view returns (uint256);

  //Returns total balance of underlying token in the vault and its strategies
  function balance() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function earn() external;

  function getPricePerFullShare() external view returns (uint256);

  function strategy() external view returns (address);
}

interface IBeefyBooster {
  function earned(address _account) external view returns (uint256);

  function balanceOf(address _account) external view returns (uint256);

  function stakedToken() external view returns (address);

  function rewardToken() external view returns (address);

  function periodFinish() external view returns (uint256);

  function rewardPerToken() external view returns (uint256);

  function stake(uint256 _amount) external;

  function withdraw(uint256 _shares) external;

  function exit() external;

  function getReward() external;
}

interface IBeefyBalanceCheck {
  function balanceOf(address _account) external view returns (uint256);
}

/**
 * @title Beefy ERC4626 Contract
 * @notice ERC4626 wrapper for beefy vaults
 * @author RedVeil
 *
 * Wraps https://github.com/beefyfinance/beefy-contracts/blob/master/contracts/BIFI/vaults/BeefyVaultV6.sol
 */
contract BeefyAdapter is AdapterBase, WithRewards {
  using SafeERC20 for IERC20;
  using Math for uint256;

  /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

  string internal _name;
  string internal _symbol;

  IBeefyVault public beefyVault;
  IBeefyBooster public beefyBooster;
  IBeefyBalanceCheck public beefyBalanceCheck;

  uint256 public beefyWithdrawalFee;
  uint256 public constant BPS_DENOMINATOR = 10_000;

  error InvalidBeefyWithdrawalFee(uint256 fee);
  error InvalidBeefyVault(address beefyVault);
  error InvalidBeefyBooster(address beefyBooster);

  /**
     @notice Initializes the Vault.
     @param beefyInitData The Beefy Vault contract,  An optional booster contract which rewards additional token for the vault,beefyStrategy withdrawalFee in 10_000 (BPS)
    */
  function initialize(bytes memory adapterInitData, address, bytes memory beefyInitData) public {
    (address _beefyVault, address _beefyBooster, uint256 _beefyWithdrawalFee) = abi.decode(
      beefyInitData,
      (address, address, uint256)
    );
    __AdapterBase_init(adapterInitData);

    // Defined in the FeeManager of beefy. Strats can never have more than 50 BPS withdrawal fees
    if (_beefyWithdrawalFee > 50) revert InvalidBeefyWithdrawalFee(_beefyWithdrawalFee);
    if (IBeefyVault(_beefyVault).want() != asset()) revert InvalidBeefyVault(_beefyVault);
    if (_beefyBooster != address(0) && IBeefyBooster(_beefyBooster).stakedToken() != _beefyVault)
      revert InvalidBeefyBooster(_beefyBooster);

    _name = string.concat("Popcorn Beefy", IERC20Metadata(asset()).name(), " Adapter");
    _symbol = string.concat("popB-", IERC20Metadata(asset()).symbol());

    beefyVault = IBeefyVault(_beefyVault);
    beefyBooster = IBeefyBooster(_beefyBooster);
    beefyWithdrawalFee = _beefyWithdrawalFee;

    beefyBalanceCheck = IBeefyBalanceCheck(_beefyBooster == address(0) ? _beefyVault : _beefyBooster);

    IERC20(asset()).approve(_beefyVault, type(uint256).max);

    if (_beefyBooster != address(0)) IERC20(_beefyVault).approve(_beefyBooster, type(uint256).max);
  }

  function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
    return _name;
  }

  function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
    return _symbol;
  }

  /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @notice Calculates the total amount of underlying tokens the Vault holds.
  /// @return The total amount of underlying tokens the Vault holds.
  function totalAssets() public view override returns (uint256) {
    return
      paused()
        ? IERC20(asset()).balanceOf(address(this))
        : beefyBalanceCheck.balanceOf(address(this)).mulDiv(
          beefyVault.balance(),
          beefyVault.totalSupply(),
          Math.Rounding.Down
        );
  }

  // takes as argument the internal ERC4626 shares to redeem
  // returns the external BeefyVault shares to withdraw
  function convertToUnderlyingShares(uint256, uint256 shares) public view override returns (uint256) {
    uint256 supply = totalSupply();
    return supply == 0 ? shares : shares.mulDiv(beefyBalanceCheck.balanceOf(address(this)), supply, Math.Rounding.Up);
  }

  function rewardTokens() external view override returns (address[] memory) {
    address[] memory _rewardTokens = new address[](1);
    _rewardTokens[0] = beefyBooster.rewardToken();
    return _rewardTokens;
  }

  /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

  function previewWithdraw(uint256 assets) public view override returns (uint256) {
    uint256 beefyFee = beefyWithdrawalFee == 0
      ? 0
      : assets.mulDiv(beefyWithdrawalFee, BPS_DENOMINATOR, Math.Rounding.Up);

    return _convertToShares(assets - beefyFee, Math.Rounding.Up);
  }

  function previewRedeem(uint256 shares) public view override returns (uint256) {
    uint256 assets = _convertToAssets(shares, Math.Rounding.Down);

    return
      beefyWithdrawalFee == 0 ? assets : assets - assets.mulDiv(beefyWithdrawalFee, BPS_DENOMINATOR, Math.Rounding.Up);
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

  function _protocolDeposit(uint256 amount, uint256) internal virtual override {
    beefyVault.deposit(amount);
    if (address(beefyBooster) != address(0)) beefyBooster.stake(beefyVault.balanceOf(address(this)));
  }

  function _protocolWithdraw(uint256, uint256 shares) internal virtual override {
    uint256 beefyShares = convertToUnderlyingShares(0, shares);
    if (address(beefyBooster) != address(0)) beefyBooster.withdraw(beefyShares);
    beefyVault.withdraw(beefyShares);
  }

  /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

  function claim() public override onlyStrategy {
    beefyBooster.getReward();
  }

  /*//////////////////////////////////////////////////////////////
                      EIP-165 LOGIC
  //////////////////////////////////////////////////////////////*/

  function supportsInterface(bytes4 interfaceId) public pure override(WithRewards, AdapterBase) returns (bool) {
    return interfaceId == type(IWithRewards).interfaceId || interfaceId == type(IAdapter).interfaceId;
  }
}
