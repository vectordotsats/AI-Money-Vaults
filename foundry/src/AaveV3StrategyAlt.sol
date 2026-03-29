// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ──────────────────────────────────────────────────────────────
// Aave V3 interface — only the functions we actually call
// ──────────────────────────────────────────────────────────────
interface IAavePool {
    /// @notice Supply an asset to the Aave pool
    /// @param asset        The address of the underlying asset (USDC)
    /// @param amount       How much to supply
    /// @param onBehalfOf   Who receives the aTokens (this contract)
    /// @param referralCode Aave referral code — 0 for none
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /// @notice Withdraw an asset from the Aave pool
    /// @param asset   The underlying asset to withdraw
    /// @param amount  How much to withdraw (type(uint256).max for all)
    /// @param to      Where to send the withdrawn tokens
    /// @return The actual amount withdrawn
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

// ──────────────────────────────────────────────────────────────
// AaveV3Strategy
// ──────────────────────────────────────────────────────────────
// This contract sits between the AIVault and Aave V3.
// It holds the aTokens and enforces guardrails on how much
// can be deployed, who can call what, and how fast.
//
// Access control:
//   - onlyKeeper  → supplyToAave(), rebalance logic
//   - onlyVault   → withdrawToVault()
//   - onlyOwner   → setKeeper(), setVault(), emergency functions
// ──────────────────────────────────────────────────────────────

contract AaveV3Strategy is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ─── State Variables ────────────────────────────────────────

    IERC20 public immutable usdc; // The underlying asset
    IERC20 public immutable aUsdc; // Aave's aToken (interest-bearing)
    IAavePool public immutable aavePool; // Aave V3 Pool on Sepolia

    address public vault; // The AIVault contract
    address public keeper; // The off-chain keeper bot

    // Guardrails
    uint256 public maxSupplyPercent = 90; // Max % of received USDC that can go to Aave (0-100)
    bool public paused; // Emergency pause

    // Accounting
    uint256 public totalDeployed; // How much USDC is currently in Aave

    // ─── Events ─────────────────────────────────────────────────

    event SuppliedToAave(uint256 amount, uint256 totalDeployed);
    event WithdrawnFromAave(uint256 amount, address to);
    event KeeperUpdated(address oldKeeper, address newKeeper);
    event VaultUpdated(address oldVault, address newVault);
    event MaxSupplyPercentUpdated(uint256 oldPercent, uint256 newPercent);
    event EmergencyWithdraw(uint256 amount);
    event Paused(bool isPaused);

    // ─── Errors ─────────────────────────────────────────────────

    error NotKeeper();
    error NotVault();
    error IsPaused();
    error ZeroAmount();
    error ZeroAddress();
    error ExceedsMaxSupply();
    error InsufficientBalance();
    error InvalidPercent();

    // ─── Modifiers ──────────────────────────────────────────────

    modifier onlyKeeper() {
        if (msg.sender != keeper) revert NotKeeper();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert IsPaused();
        _;
    }

    // ─── Constructor ────────────────────────────────────────────

    /// @param _usdc      USDC token address on Sepolia
    /// @param _aUsdc     aUSDC aToken address on Sepolia
    /// @param _aavePool  Aave V3 Pool address on Sepolia
    /// @param _vault     The AIVault contract address
    /// @param _keeper    The keeper bot address
    constructor(
        address _usdc,
        address _aUsdc,
        address _aavePool,
        address _vault,
        address _keeper
    ) Ownable(msg.sender) {
        if (
            _usdc == address(0) ||
            _aUsdc == address(0) ||
            _aavePool == address(0)
        ) revert ZeroAddress();

        usdc = IERC20(_usdc);
        aUsdc = IERC20(_aUsdc);
        aavePool = IAavePool(_aavePool);
        vault = _vault;
        keeper = _keeper;
    }

    // ─── Keeper Functions (offensive — deploy capital) ───────────

    /// @notice Supply USDC to Aave V3 to earn lending yield
    /// @dev    Only the keeper can call this. The USDC must already
    ///         be sitting in this contract (sent by the vault).
    /// @param amount How much USDC to supply to Aave
    function supplyToAave(
        uint256 amount
    ) external onlyKeeper whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();

        // Guardrail: check we're not exceeding max supply percentage
        // of total USDC this strategy has ever been given
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 totalAssets = usdcBalance + totalDeployed;

        // After this supply, totalDeployed would be:
        uint256 newDeployed = totalDeployed + amount;
        // That must not exceed maxSupplyPercent of totalAssets
        if (
            totalAssets > 0 &&
            (newDeployed * 100) / totalAssets > maxSupplyPercent
        ) {
            revert ExceedsMaxSupply();
        }

        if (amount > usdcBalance) revert InsufficientBalance();

        // Approve Aave Pool to pull our USDC
        usdc.safeIncreaseAllowance(address(aavePool), amount);

        // Supply to Aave — we receive aUSDC in return
        aavePool.supply(address(usdc), amount, address(this), 0);

        // Update accounting
        totalDeployed += amount;

        emit SuppliedToAave(amount, totalDeployed);
    }

    // ─── Vault Functions (defensive — return capital) ────────────

    /// @notice Withdraw USDC from Aave and send it to the vault
    /// @dev    Only the vault can call this — triggered when a user
    ///         wants to redeem and there's not enough idle USDC.
    /// @param amount How much USDC the vault needs back
    function withdrawToVault(uint256 amount) external onlyVault nonReentrant {
        if (amount == 0) revert ZeroAmount();

        // First, check if we have enough idle USDC without touching Aave
        uint256 idleBalance = usdc.balanceOf(address(this));

        uint256 withdrawFromAave = 0;
        if (idleBalance < amount) {
            // Need to pull the shortfall from Aave
            withdrawFromAave = amount - idleBalance;

            // Safety check: we can't withdraw more than we've deployed
            if (withdrawFromAave > totalDeployed) {
                withdrawFromAave = totalDeployed;
            }

            // Withdraw from Aave — tokens come back to this contract
            uint256 actualWithdrawn = aavePool.withdraw(
                address(usdc),
                withdrawFromAave,
                address(this)
            );

            // Update accounting with what Aave actually returned
            totalDeployed = totalDeployed > actualWithdrawn
                ? totalDeployed - actualWithdrawn
                : 0;
        }

        // Send the requested amount to the vault
        uint256 toSend = usdc.balanceOf(address(this));
        if (toSend > amount) toSend = amount;

        usdc.safeTransfer(vault, toSend);

        emit WithdrawnFromAave(toSend, vault);
    }

    // ─── View Functions ─────────────────────────────────────────

    /// @notice Total USDC value this strategy controls (idle + deployed)
    /// @dev    aToken balance = deployed principal + accrued interest
    function totalStrategyAssets() external view returns (uint256) {
        uint256 idleBalance = usdc.balanceOf(address(this));
        uint256 aTokenBalance = aUsdc.balanceOf(address(this));
        return idleBalance + aTokenBalance;
    }

    /// @notice How much yield has accrued from Aave (aToken balance - principal)
    function accruedYield() external view returns (uint256) {
        uint256 aTokenBalance = aUsdc.balanceOf(address(this));
        if (aTokenBalance <= totalDeployed) return 0;
        return aTokenBalance - totalDeployed;
    }

    /// @notice Idle USDC sitting in the strategy (not yet deployed)
    function idleBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    // ─── Owner/Admin Functions ──────────────────────────────────

    /// @notice Update the keeper address
    function setKeeper(address _newKeeper) external onlyOwner {
        if (_newKeeper == address(0)) revert ZeroAddress();
        emit KeeperUpdated(keeper, _newKeeper);
        keeper = _newKeeper;
    }

    /// @notice Update the vault address
    function setVault(address _newVault) external onlyOwner {
        if (_newVault == address(0)) revert ZeroAddress();
        emit VaultUpdated(vault, _newVault);
        vault = _newVault;
    }

    /// @notice Update the max supply percentage guardrail
    /// @param _newPercent Value between 0 and 100
    function setMaxSupplyPercent(uint256 _newPercent) external onlyOwner {
        if (_newPercent > 100) revert InvalidPercent();
        emit MaxSupplyPercentUpdated(maxSupplyPercent, _newPercent);
        maxSupplyPercent = _newPercent;
    }

    /// @notice Pause/unpause the strategy
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    /// @notice Emergency: pull ALL funds from Aave back to this contract
    /// @dev    Only owner. Does not send to vault — owner must then
    ///         decide where funds go (prevents hasty mistakes).
    function emergencyWithdrawAll() external onlyOwner nonReentrant {
        uint256 aTokenBalance = aUsdc.balanceOf(address(this));
        if (aTokenBalance == 0) revert ZeroAmount();

        uint256 withdrawn = aavePool.withdraw(
            address(usdc),
            type(uint256).max, // withdraw everything
            address(this)
        );

        totalDeployed = 0;
        paused = true; // auto-pause after emergency

        emit EmergencyWithdraw(withdrawn);
        emit Paused(true);
    }

    /// @notice Rescue tokens accidentally sent to this contract
    /// @dev    Cannot rescue USDC or aUSDC — those are managed assets
    function rescueToken(address token, uint256 amount) external onlyOwner {
        if (token == address(usdc) || token == address(aUsdc))
            revert ZeroAddress(); // Reusing error — means "not allowed"
        IERC20(token).safeTransfer(owner(), amount);
    }
}
