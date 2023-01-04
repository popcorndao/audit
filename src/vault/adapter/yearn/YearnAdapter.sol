// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { AdapterBase, ERC4626Upgradeable as ERC4626, IERC20, IERC20Metadata, ERC20, SafeERC20, Math, IStrategy, IAdapter } from "../abstracts/AdapterBase.sol";

interface VaultAPI is IERC20 {
  function deposit(uint256 amount) external returns (uint256);

  function withdraw(uint256 maxShares) external returns (uint256);

  function pricePerShare() external view returns (uint256);

  function totalAssets() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function depositLimit() external view returns (uint256);

  function token() external view returns (address);

  function lastReport() external view returns (uint256);

  function lockedProfit() external view returns (uint256);

  function lockedProfitDegradation() external view returns (uint256);

  function totalDebt() external view returns (uint256);
}

interface IYearnRegistry {
  function latestVault(address token) external view returns (address);
}

contract YearnAdapter is AdapterBase {
  using SafeERC20 for IERC20;
  using Math for uint256;

  /*//////////////////////////////////////////////////////////////
                          IMMUTABLES
  //////////////////////////////////////////////////////////////*/

  string internal _name;
  string internal _symbol;

  VaultAPI public yVault;
  uint256 constant DEGRADATION_COEFFICIENT = 10 ** 18;

  function initialize(bytes memory adapterInitData, address externalRegistry, bytes memory) external {
    (address _asset, , , , , ) = abi.decode(adapterInitData, (address, address, address, uint256, bytes4[8], bytes));
    __AdapterBase_init(adapterInitData);

    yVault = VaultAPI(IYearnRegistry(externalRegistry).latestVault(_asset));

    _name = string.concat("Popcorn Yearn", IERC20Metadata(asset()).name(), " Adapter");
    _symbol = string.concat("popY-", IERC20Metadata(asset()).symbol());

    IERC20(_asset).approve(address(yVault), type(uint256).max);
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

  function totalAssets() public view override returns (uint256) {
    return paused() ? IERC20(asset()).balanceOf(address(this)) : _shareValue(yVault.balanceOf(address(this)));
  }

  function _calculateLockedProfit() internal view returns (uint256) {
    uint256 lockedFundsRatio = (block.timestamp - yVault.lastReport()) * yVault.lockedProfitDegradation();

    if (lockedFundsRatio < DEGRADATION_COEFFICIENT) {
      uint256 lockedProfit = yVault.lockedProfit();
      return lockedProfit - ((lockedFundsRatio * lockedProfit) / DEGRADATION_COEFFICIENT);
    } else {
      return 0;
    }
  }

  function _shareValue(uint256 shares) internal view returns (uint256) {
    if (yVault.totalSupply() == 0) return shares;

    return shares.mulDiv(_freeFunds(), yVault.totalSupply(), Math.Rounding.Down);
  }

  function _totalAssets() internal view returns (uint256) {
    return IERC20(asset()).balanceOf(address(yVault)) + yVault.totalDebt();
  }

  function _freeFunds() internal view returns (uint256) {
    return _totalAssets() - _calculateLockedProfit();
  }

  function _sharesForAmount(uint256 amount) internal view returns (uint256) {
    uint256 freeFunds = _freeFunds();
    if (freeFunds > 0) {
      return ((amount * yVault.totalSupply()) / freeFunds);
    } else {
      return 0;
    }
  }

  function convertToUnderlyingShares(uint256, uint256 shares) public view override returns (uint256) {
    return shares.mulDiv(yVault.balanceOf(address(this)), totalSupply(), Math.Rounding.Up);
  }

  /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LIMIT LOGIC
  //////////////////////////////////////////////////////////////*/

  function maxDeposit(address) public view override returns (uint256) {
    if (paused()) return 0;

    VaultAPI _bestVault = yVault;
    uint256 assets = _bestVault.totalAssets();
    uint256 _depositLimit = _bestVault.depositLimit();
    if (assets >= _depositLimit) return 0;
    return _depositLimit - assets;
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

  function _protocolDeposit(uint256 amount, uint256) internal virtual override {
    yVault.deposit(amount);
  }

  function _protocolWithdraw(uint256 assets, uint256 shares) internal virtual override {
    yVault.withdraw(convertToUnderlyingShares(assets, shares));
  }
}
