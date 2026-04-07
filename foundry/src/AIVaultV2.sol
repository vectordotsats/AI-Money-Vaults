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
    function recieveFromVault(uint256 amount) external;

    ///@notice This checks how much the strategy controls (idle + deployed + yield)
    function totalStrategyAssets() external view returns (uint256);
}

// ========== AI Vault V2 ===========
// ERC-4626 vault with strategy routing.
// Users deposit USDC, receive aiVLT shares.
// Idle USDC can be pushed to a strategy (Aave, Morpho, etc.) to earn yields. Withdrawals pull from strategy if needed.
// ==================================

contract AIVault is ERC4626, ReentrancyGaurd, Ownable {
    using SafeERC20 for IERC20;

    // ======== State Variables ========
    IStrategy public strategy;
    address public keeper;
    uint256 public totalDeposits;

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
}
