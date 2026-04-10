// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ========== Strategy Interface - the functions only the vault calls ===========
interface IStrategy {
    ///@notice This pulls USDC back from the strategy to the vault
    function withdrawToVault(uint256 amount) external;

    ///@notice This tells the strategy we sent it USDC (updates internal accounting)
    function receiveFromVault(uint256 amount) external;

    ///@notice This checks how much the strategy controls (idle + deployed + yield)
    function totalStrategyAssets() external view returns (uint256);
}

// ========== AI Vault V2 ===========
// ERC-4626 vault with strategy routing.
// Users deposit USDC, receive aiVLT shares.
// Idle USDC can be pushed to a strategy (Aave, Morpho, etc.) to earn yields. Withdrawals pull from strategy if needed.
// ==================================

contract AIVault is ERC4626, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ======== State Variables ========
    IStrategy public strategy;
    address public keeper;
    uint256 public allTimeDeposits;
    uint256 public totalIdleDeposits;

    // ======= Events =======
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);
    event StrategyUpdated(address oldStrategy, address newStrategy);
    event KeeperUpdated(address oldKeeper, address newKeeper);
    event FundsPushedToStrategy(uint256 amount);
    event FundsPulledFromStrategy(uint256 amount);

    // ======== Errors ========
    error ZeroAddress();
    error ZeroAmount();
    error NotKeeper();
    error NoStrategySet();
    error ZeroDepositsNotAllowed();
    error ZeroWithdrawalsNotAllowed();
    error WrongReceiverAddress();
    error InsufficientIdleBalance();

    // ======= Modifiers =======
    modifier onlyKeeper() {
        if (msg.sender != keeper && msg.sender != owner()) {
            revert NotKeeper();
        }
        _;
    }

    constructor(
        IERC20 _asset
    ) ERC4626(_asset) ERC20("AIVault Shares", "aiVLT") Ownable(msg.sender) {}

    // ========= User Functions ==========

    /// @notice Deposit USDC into the vault, receive aiVLT shares
    function deposit(
        uint256 amount,
        address receiver
    ) public override nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroDepositsNotAllowed();
        if (receiver == address(0)) revert WrongReceiverAddress();

        shares = super.deposit(amount, receiver);
        allTimeDeposits += amount;
        totalIdleDeposits += amount;

        emit Deposit(receiver, amount, shares);
        return shares;
    }

    /// @notice Withdraw USDC from the vault by burning aiVLT shares
    /// @dev    If the vault doesn't have enough idle USDC, it pulls
    ///         the shortfall from the strategy automatically.
    function withdraw(
        uint256 assets,
        address receiver,
        address _owner
    ) public override nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroWithdrawalsNotAllowed();
        if (receiver == address(0)) revert WrongReceiverAddress();

        // Check if we need to pull funds from strategy
        uint256 idleBalance = totalIdleDeposits;

        if (idleBalance < assets && address(strategy) != address(0)) {
            uint256 shortfall = assets - idleBalance;
            strategy.withdrawToVault(shortfall);
            totalIdleDeposits += shortfall;

            emit FundsPulledFromStrategy(shortfall);
        }

        shares = super.withdraw(assets, receiver, _owner);
        totalIdleDeposits -= assets;

        emit Withdraw(receiver, assets, shares);
        return shares;
    }

    // ========= Strategy Routing Function ==========

    /// @notice Push idle USDC from the vault to the strategy
    /// @dev    Only keeper or owner can call this.
    ///         The strategy's receiveFromVault() updates its internal accounting.
    /// @param amount How much USDC to send to the strategy
    function depositToStrategy(
        uint256 amount
    ) external onlyKeeper nonReentrant {
        if (address(strategy) == address(0)) revert NoStrategySet();
        if (amount == 0) revert ZeroAmount();

        uint256 idleBalance = totalIdleDeposits;
        if (amount > idleBalance) revert InsufficientIdleBalance();

        IERC20(asset()).safeTransfer(address(strategy), amount);

        // Tell the strategy to update its internal accounting
        strategy.receiveFromVault(amount);

        totalIdleDeposits -= amount;

        emit FundsPushedToStrategy(amount);
    }

    // ====== View Functions ======
    /// @notice Total assets the vault controls (idle USDC + strategy assets)
    /// @dev    Overrides ERC4626's totalAssets so share price reflects
    ///         the yield earned in the strategy.
    function totalAssets() public view override returns (uint256) {
        uint256 idleBalance = totalIdleDeposits;

        if (address(strategy) != address(0)) {
            return idleBalance + strategy.totalStrategyAssets();
        }

        return idleBalance;
    }

    /// @notice How much USDC is sitting idle in the vault (not deployed)
    function idleBalance() external view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    // ====== Admin Functions ======
    /// @notice Set or update the strategy contract
    function setStrategy(address _strategy) external onlyOwner {
        if (_strategy == address(0)) revert ZeroAddress();
        address oldStrategy = address(strategy);
        strategy = IStrategy(_strategy);
        emit StrategyUpdated(oldStrategy, _strategy);
    }

    /// @notice Set or update the keeper address
    function setKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) revert ZeroAddress();
        address oldKeeper = keeper;
        keeper = _keeper;
        emit KeeperUpdated(oldKeeper, _keeper);
    }
}
