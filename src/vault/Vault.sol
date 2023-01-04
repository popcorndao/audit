// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { SafeERC20Upgradeable as SafeERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import { KeeperIncentivizedUpgradeable, KeeperConfig } from "../utils/KeeperIncentivizedUpgradeable.sol";
import { IERC4626, IERC20 } from "../interfaces/vault/IERC4626.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { FeeStructure } from "../interfaces/vault/IVault.sol";
import { IKeeperIncentiveV2 } from "../interfaces/IKeeperIncentiveV2.sol";
import { MathUpgradeable as Math } from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import { OwnedUpgradeable } from "../utils/OwnedUpgradeable.sol";
import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract Vault is
  ERC20Upgradeable,
  ReentrancyGuardUpgradeable,
  PausableUpgradeable,
  OwnedUpgradeable,
  KeeperIncentivizedUpgradeable
{
  using SafeERC20 for IERC20;
  using Math for uint256;

  /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

  uint256 constant SECONDS_PER_YEAR = 365.25 days;
  uint256 internal ONE;

  IERC20 public asset;
  uint8 internal _decimals;

  bytes32 public contractName;

  event VaultInitialized(bytes32 contractName, address indexed asset);

  function initialize(
    IERC20 asset_,
    IERC4626 adapter_,
    FeeStructure memory feeStructure_,
    address feeRecipient_,
    IKeeperIncentiveV2 keeperIncentive_,
    KeeperConfig memory keeperConfig_,
    address owner
  ) external initializer {
    __ERC20_init(
      string.concat("Popcorn ", IERC20Metadata(address(asset_)).name(), " Vault"),
      string.concat("pop-", IERC20Metadata(address(asset_)).symbol())
    );
    __Owned_init(owner);
    __KeeperIncentivized_init(keeperIncentive_);

    asset = asset_;
    adapter = adapter_;

    asset.approve(address(adapter_), type(uint256).max);

    _decimals = IERC20Metadata(address(asset_)).decimals();

    INITIAL_CHAIN_ID = block.chainid;
    INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

    ONE = 10 ** decimals();
    vaultShareHWM = ONE;

    feesUpdatedAt = block.timestamp;
    feeStructure = feeStructure_;

    keeperConfig = keeperConfig_;
    quitPeriod = 3 days;

    if (feeRecipient_ == address(0)) revert InvalidFeeRecipient();
    feeRecipient = feeRecipient_;

    contractName = keccak256(abi.encodePacked("Popcorn", name(), block.timestamp, "Vault"));

    emit VaultInitialized(contractName, address(asset));
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

  event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
  event Withdraw(
    address indexed caller,
    address indexed receiver,
    address indexed owner,
    uint256 assets,
    uint256 shares
  );

  error InvalidReceiver();

  /**
   * @notice Deposit exactly `assets` amount of tokens, issuing vault shares to caller.
   * @param assets Quantity of tokens to deposit.
   * @return Quantity of vault shares issued to caller.
   * @dev This s `deposit(uint256)` from the parent `AffiliateToken` contract. It therefore needs to be public since the `AffiliateToken` function is public
   */
  function deposit(uint256 assets) public returns (uint256) {
    return deposit(assets, msg.sender);
  }

  /**
   * @notice Deposit exactly `assets` amount of tokens, issuing vault shares to `receiver`.
   * @param assets Quantity of tokens to deposit.
   * @param receiver Receiver of issued vault shares.
   * @return shares of the vault issued to `receiver`.
   */
  function deposit(
    uint256 assets,
    address receiver
  ) public nonReentrant whenNotPaused syncFeeCheckpoint returns (uint256 shares) {
    if (receiver == address(0)) revert InvalidReceiver();

    uint256 feeShares = convertToShares(assets.mulDiv(feeStructure.deposit, 1e18, Math.Rounding.Down));

    shares = convertToShares(assets) - feeShares;

    if (feeShares > 0) _mint(address(this), feeShares);

    _mint(receiver, shares);

    asset.safeTransferFrom(msg.sender, address(this), assets);

    adapter.deposit(assets, address(this));

    emit Deposit(msg.sender, receiver, assets, shares);
  }

  /**
   * @notice Mint exactly `shares` vault shares to `msg.sender`. Caller must approve a sufficient number of underlying
   *   `asset` tokens to mint the requested quantity of vault shares.
   * @param shares Quantity of shares to mint.
   * @return assets of underlying that have been deposited.
   */
  function mint(uint256 shares) external returns (uint256) {
    return mint(shares, msg.sender);
  }

  /**
   * @notice Mint exactly `shares` vault shares to `receiver`. Caller must approve a sufficient number of underlying
   *   `asset` tokens to mint the requested quantity of vault shares.
   * @param shares Quantity of shares to mint.
   * @param receiver Receiver of issued vault shares.
   * @return assets of underlying that have been deposited.
   */
  function mint(
    uint256 shares,
    address receiver
  ) public nonReentrant whenNotPaused syncFeeCheckpoint returns (uint256 assets) {
    if (receiver == address(0)) revert InvalidReceiver();

    uint256 depositFee = feeStructure.deposit;

    uint256 feeShares = shares.mulDiv(depositFee, 1e18 - depositFee, Math.Rounding.Down);

    assets = convertToAssets(shares + feeShares);

    if (feeShares > 0) _mint(address(this), feeShares);

    _mint(receiver, shares);

    asset.safeTransferFrom(msg.sender, address(this), assets);

    adapter.deposit(assets, address(this));

    emit Deposit(msg.sender, receiver, assets, shares);
  }

  /**
   * @notice Burn shares from caller in exchange for exactly `assets` amount of underlying token.
   * @param assets Quantity of underlying `asset` token to withdraw.
   * @return shares of vault burned in exchange for underlying `asset` tokens.
   * @dev This s `withdraw(uint256)` from the parent `AffiliateToken` contract.
   */
  function withdraw(uint256 assets) public returns (uint256) {
    return withdraw(assets, msg.sender, msg.sender);
  }

  /**
   * @notice Burn shares from caller in exchange for `assets` amount of underlying token. Send underlying to caller.
   * @param assets Quantity of underlying `asset` token to withdraw.
   * @param receiver Receiver of underlying token.
   * @param owner Owner of burned vault shares.
   * @return shares of vault burned in exchange for underlying `asset` tokens.
   */
  function withdraw(
    uint256 assets,
    address receiver,
    address owner
  ) public nonReentrant syncFeeCheckpoint returns (uint256 shares) {
    if (receiver == address(0)) revert InvalidReceiver();

    shares = convertToShares(assets);

    uint256 withdrawalFee = feeStructure.withdrawal;

    uint256 feeShares = shares.mulDiv(withdrawalFee, 1e18 - withdrawalFee, Math.Rounding.Down);

    shares += feeShares;

    if (msg.sender != owner) _approve(owner, msg.sender, allowance(owner, msg.sender) - shares);

    _burn(owner, shares);

    _mint(address(this), feeShares);

    adapter.withdraw(assets, receiver, address(this));

    emit Withdraw(msg.sender, receiver, owner, assets, shares);
  }

  /**
   * @notice Burn exactly `shares` vault shares from owner and send underlying `asset` tokens to `receiver`.
   * @param shares Quantity of vault shares to exchange for underlying tokens.
   * @return assets of underlying sent to `receiver`.
   */
  function redeem(uint256 shares) external returns (uint256) {
    return redeem(shares, msg.sender, msg.sender);
  }

  /**
   * @notice Burn exactly `shares` vault shares from owner and send underlying `asset` tokens to `receiver`.
   * @param shares Quantity of vault shares to exchange for underlying tokens.
   * @param receiver Receiver of underlying tokens.
   * @param owner Owner of burned vault shares.
   * @return assets of underlying sent to `receiver`.
   */
  function redeem(uint256 shares, address receiver, address owner) public nonReentrant returns (uint256 assets) {
    if (receiver == address(0)) revert InvalidReceiver();

    if (msg.sender != owner) _approve(owner, msg.sender, allowance(owner, msg.sender) - shares);

    uint256 feeShares = shares.mulDiv(feeStructure.withdrawal, 1e18, Math.Rounding.Down);

    assets = convertToAssets(shares - feeShares);

    _burn(owner, shares);

    _mint(address(this), feeShares);

    adapter.withdraw(assets, receiver, address(this));

    emit Withdraw(msg.sender, receiver, owner, assets, shares);
  }

  /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

  /**
   * @return Total amount of underlying `asset` token managed by vault.
   */
  function totalAssets() public view returns (uint256) {
    return adapter.convertToAssets(adapter.balanceOf(address(this)));
  }

  /**
   * @notice Amount of shares the vault would exchange for given amount of assets, in an ideal scenario.
   * @param assets Exact amount of assets
   * @return Exact amount of shares
   */
  function convertToShares(uint256 assets) public view returns (uint256) {
    uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

    return supply == 0 ? assets : assets.mulDiv(supply, totalAssets(), Math.Rounding.Down);
  }

  /**
   * @notice Amount of assets the vault would exchange for given amount of shares, in an ideal scenario.
   * @param shares Exact amount of shares
   * @return Exact amount of assets
   */
  function convertToAssets(uint256 shares) public view returns (uint256) {
    uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

    return supply == 0 ? shares : shares.mulDiv(totalAssets(), supply, Math.Rounding.Down);
  }

  /**
   * @notice Simulate the effects of a deposit at the current block, given current on-chain conditions.
   * @param assets Exact amount of underlying `asset` token to deposit
   * @return shares of the vault issued in exchange to the user for `assets`
   * @dev This method accounts for issuance of accrued fee shares.
   */
  function previewDeposit(uint256 assets) public view returns (uint256 shares) {
    shares = adapter.previewDeposit(assets - assets.mulDiv(feeStructure.deposit, 1e18, Math.Rounding.Down));
  }

  /**
   * @notice Simulate the effects of a mint at the current block, given current on-chain conditions.
   * @param shares Exact amount of vault shares to mint.
   * @return assets quantity of underlying needed in exchange to mint `shares`.
   * @dev This method accounts for issuance of accrued fee shares.
   */
  function previewMint(uint256 shares) public view returns (uint256 assets) {
    uint256 depositFee = feeStructure.deposit;

    shares += shares.mulDiv(depositFee, 1e18 - depositFee, Math.Rounding.Up);

    assets = adapter.previewMint(shares);
  }

  /**
   * @notice Simulate the effects of a withdrawal at the current block, given current on-chain conditions.
   * @param assets Exact amount of `assets` to withdraw
   * @return shares to be burned in exchange for `assets`
   * @dev This method accounts for both issuance of fee shares and withdrawal fee.
   */
  function previewWithdraw(uint256 assets) external view returns (uint256 shares) {
    uint256 withdrawalFee = feeStructure.withdrawal;

    assets += assets.mulDiv(withdrawalFee, 1e18 - withdrawalFee, Math.Rounding.Up);

    shares = adapter.previewWithdraw(assets);
  }

  /**
   * @notice Simulate the effects of a redemption at the current block, given current on-chain conditions.
   * @param shares Exact amount of `shares` to redeem
   * @return assets quantity of underlying returned in exchange for `shares`.
   * @dev This method accounts for both issuance of fee shares and withdrawal fee.
   */
  function previewRedeem(uint256 shares) public view returns (uint256 assets) {
    assets = adapter.previewRedeem(shares);

    assets -= assets.mulDiv(feeStructure.withdrawal, 1e18, Math.Rounding.Down);
  }

  /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

  /**
   * @return Maximum amount of underlying `asset` token that may be deposited for a given address.
   */
  function maxDeposit(address caller) public view returns (uint256) {
    return adapter.maxDeposit(caller);
  }

  /**
   * @return Maximum amount of vault shares that may be minted to given address.
   */
  function maxMint(address caller) external view returns (uint256) {
    return adapter.maxMint(caller);
  }

  /**
   * @return Maximum amount of underlying `asset` token that can be withdrawn by `caller` address.
   */
  function maxWithdraw(address caller) external view returns (uint256) {
    return adapter.maxWithdraw(caller);
  }

  /**
   * @return Maximum amount of shares that may be redeemed by `caller` address.
   */
  function maxRedeem(address caller) external view returns (uint256) {
    return adapter.maxRedeem(caller);
  }

  /*//////////////////////////////////////////////////////////////
                        FEE ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Management fee that has accrued since last fee harvest.
   * @return Accrued management fee in underlying `asset` token.
   * @dev Management fee is annualized per minute, based on 525,600 minutes per year. Total assets are calculated using
   *  the average of their current value and the value at the previous fee harvest checkpoint. This method is similar to
   *  calculating a definite integral using the trapezoid rule.
   */
  function accruedManagementFee() public view returns (uint256) {
    uint256 area = (totalAssets() + assetsCheckpoint) * (block.timestamp - feesUpdatedAt);

    return (feeStructure.management.mulDiv(area, 2, Math.Rounding.Down) / SECONDS_PER_YEAR) / 1e18;
  }

  /**
   * @notice Performance fee that has accrued since last fee harvest.
   * @return Accrued performance fee in underlying `asset` token.
   * @dev Performance fee is based on a vault share high water mark value. If vault share value has increased above the
   *   HWM in a fee period, issue fee shares to the vault equal to the performance fee.
   */
  function accruedPerformanceFee() public view returns (uint256) {
    uint256 shareValue = convertToAssets(ONE);

    if (shareValue > vaultShareHWM) {
      return
        feeStructure.performance.mulDiv((shareValue - vaultShareHWM) * totalSupply(), 1e18 * ONE, Math.Rounding.Down);
    } else {
      return 0;
    }
  }

  /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

  uint256 public vaultShareHWM;
  uint256 public assetsCheckpoint;
  uint256 public feesUpdatedAt;

  error InsufficientWithdrawalAmount(uint256 amount);

  /**
   * @notice Collect management and performance fees and update vault share high water mark.
   */
  function takeManagementAndPerformanceFees() external nonReentrant takeFees {}

  modifier takeFees() {
    uint256 managementFee = accruedManagementFee();
    uint256 totalFee = managementFee + accruedPerformanceFee();
    uint256 currentAssets = totalAssets();

    uint256 shareValue = convertToAssets(ONE);

    if (shareValue > vaultShareHWM) vaultShareHWM = shareValue;

    if (managementFee > 0 || currentAssets == 0) {
      feesUpdatedAt = block.timestamp;
    }

    if (totalFee > 0 && currentAssets > 0) {
      _mint(address(this), convertToShares(totalFee));
    }

    _;
    assetsCheckpoint = totalAssets();
  }

  modifier syncFeeCheckpoint() {
    _;
    vaultShareHWM = convertToAssets(ONE);
    assetsCheckpoint = totalAssets();
  }

  /**
   * @notice Transfer accrued fees to rewards manager contract. Caller must be a registered keeper.
   * @dev we send funds now to the feeRecipient which is set on in the contract registry. We must make sure that this is not address(0) before withdrawing fees
   */
  function withdrawAccruedFees() external keeperIncentive(0) takeFees nonReentrant {
    uint256 accruedFees = balanceOf(address(this));
    uint256 incentiveVig = keeperConfig.incentiveVigBps;

    if (accruedFees < keeperConfig.minWithdrawalAmount) revert InsufficientWithdrawalAmount(accruedFees);

    uint256 tipAmount = (accruedFees * incentiveVig) / 1e18;

    accruedFees -= tipAmount;

    _burn(address(this), accruedFees);

    _mint(feeRecipient, accruedFees);

    IKeeperIncentiveV2 _keeperIncentive = keeperIncentiveV2;

    _approve(address(this), address(_keeperIncentive), tipAmount);

    _keeperIncentive.tip(address(this), msg.sender, 0, tipAmount);
  }

  /*//////////////////////////////////////////////////////////////
                            FEE MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

  FeeStructure public feeStructure;

  FeeStructure public proposedFees;
  uint256 proposedFeeTimeStamp;

  address public feeRecipient;

  event NewFeesProposed(FeeStructure newFees);
  event FeesUpdated(FeeStructure previousFees, FeeStructure newFees);
  event FeeRecipientUpdated(address indexed previousFeeRecipient, address indexed newFeeRecipient);

  error InvalidFeeStructure();
  error InvalidFeeRecipient();
  error NotPassedQuitPeriod(uint256 quitPeriod);

  /**
   * @notice Propose a new feeStructure for this vault. Caller must have VAULTS_CONTROlLER from ACLRegistry.
   * @param newFees New `feeStructure`.
   * @dev Value is in 1e18, e.g. 100% = 1e18 - 1 BPS = 1e12
   */
  function proposeFees(FeeStructure memory newFees) external onlyOwner {
    if (
      newFees.deposit >= 1e18 || newFees.withdrawal >= 1e18 || newFees.management >= 1e18 || newFees.performance >= 1e18
    ) revert InvalidFeeStructure();

    proposedFees = newFees;
    proposedFeeTimeStamp = block.timestamp;

    emit NewFeesProposed(newFees);
  }

  /**
   * @notice Set fees in BPS to proposed fees from proposeNewFees function
   */
  function changeFees() external {
    if (block.timestamp < proposedFeeTimeStamp + quitPeriod) revert NotPassedQuitPeriod(quitPeriod);

    emit FeesUpdated(feeStructure, proposedFees);
    feeStructure = proposedFees;
  }

  /**
   * @notice Change feeRecipient. Caller must have VAULTS_CONTROLLER from ACLRegistry.
   */
  function setFeeRecipient(address _feeRecipient) external onlyOwner {
    if (_feeRecipient == address(0)) revert InvalidFeeRecipient();

    emit FeeRecipientUpdated(feeRecipient, _feeRecipient);

    feeRecipient = _feeRecipient;
  }

  /*//////////////////////////////////////////////////////////////
                          STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

  IERC4626 public adapter;
  IERC4626 public proposedAdapter;
  uint256 public proposalTimeStamp;

  event NewAdapterProposed(IERC4626 newAdapter, uint256 timestamp);
  event ChangedAdapter(IERC4626 oldAdapter, IERC4626 newAdapter);

  error VaultAssetMismatchNewAdapterAsset();

  /**
   * @notice Propose a new adapter for this vault. Caller must have VAULTS_CONTROlLER from ACLRegistry.
   * @param newAdapter A new ERC4626 that should be used as a yield adapter for this asset.
   * @dev The new adapter can be active 3 Days by default after proposal. This allows user to rage quit.
   */
  function proposeAdapter(IERC4626 newAdapter) external onlyOwner {
    if (newAdapter.asset() != address(asset)) revert VaultAssetMismatchNewAdapterAsset();

    proposedAdapter = newAdapter;
    proposalTimeStamp = block.timestamp;

    emit NewAdapterProposed(newAdapter, block.timestamp);
  }

  /**
   * @notice Set a new Adapter for this Vault.
   * @dev This migration function will remove all assets from the old Vault and move them into the new vault
   * @dev Additionally it will zero old allowances and set new ones
   * @dev Last we update HWM and assetsCheckpoint for fees to make sure they adjust to the new adapter
   */
  function changeAdapter() external takeFees {
    if (block.timestamp < proposalTimeStamp + quitPeriod) revert NotPassedQuitPeriod(quitPeriod);

    adapter.redeem(adapter.balanceOf(address(this)), address(this), address(this));

    asset.approve(address(adapter), 0);

    emit ChangedAdapter(adapter, proposedAdapter);

    adapter = proposedAdapter;

    asset.approve(address(adapter), type(uint256).max);

    adapter.deposit(asset.balanceOf(address(this)), address(this));
  }

  /*//////////////////////////////////////////////////////////////
                          RAGE QUIT LOGIC
    //////////////////////////////////////////////////////////////*/

  uint256 public quitPeriod; // default is 3 days

  event QuitPeriodSet(uint256 quitPeriod);

  error InvalidQuitPeriod();

  /**
   * @notice Set a quitPeriod for rage quitting after new adapter or fees are proposed. Caller must have VAULTS_CONTROlLER from ACLRegistry.
   * @param _quitPeriod time to rage quit after proposal, if not set defaults to 3 days
   * @dev The new adapter can be active 3 Days by default after proposal. This allows user to rage quit.
   */
  function setQuitPeriod(uint256 _quitPeriod) external onlyOwner {
    if (_quitPeriod < 1 days || _quitPeriod > 7 days) revert InvalidQuitPeriod();

    quitPeriod = _quitPeriod;

    emit QuitPeriodSet(quitPeriod);
  }

  /*//////////////////////////////////////////////////////////////
                          KEEPER LOGIC
    //////////////////////////////////////////////////////////////*/

  KeeperConfig public keeperConfig;

  error InvalidVig();
  error InvalidMinWithdrawal();

  /**
   * @notice Change keeper config. Caller must have VAULTS_CONTROLLER from ACLRegistry.
   */
  function setKeeperConfig(KeeperConfig memory _config) external onlyOwner {
    if (_config.incentiveVigBps > 1e18) revert InvalidVig();
    if (_config.minWithdrawalAmount < 0) revert InvalidMinWithdrawal();

    emit KeeperConfigUpdated(keeperConfig, _config);

    keeperConfig = _config;
  }

  /*//////////////////////////////////////////////////////////////
                          PAUSING LOGIC
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Pause deposits. Caller must have VAULTS_CONTROLLER from ACLRegistry.
   */
  function pause() external onlyOwner {
    _pause();
  }

  /**
   * @notice Unpause deposits. Caller must have VAULTS_CONTROLLER from ACLRegistry.
   */
  function unpause() external onlyOwner {
    _unpause();
  }

  /*//////////////////////////////////////////////////////////////
                      EIP-2612 LOGIC
  //////////////////////////////////////////////////////////////*/

  //  EIP-2612 STORAGE
  uint256 internal INITIAL_CHAIN_ID;
  bytes32 internal INITIAL_DOMAIN_SEPARATOR;
  mapping(address => uint256) public nonces;

  error PermitDeadlineExpired(uint256 deadline);
  error InvalidSigner(address signer);

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

  function DOMAIN_SEPARATOR() public view returns (bytes32) {
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
}
