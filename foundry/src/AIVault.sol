// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract AIVault is ERC4626, ReentrancyGuard {
    // Track when each user deposits
    mapping(address => uint256) public depositTimestamps;

    // Track the total deposits in the vault
    uint256 public totalDeposits;

    // Events
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);

    // Errors
    error ZeroDepositsNotAllowed();
    error ZeroWithdrawalsNotAllowed();
    error WrongReceiverAddress();

    constructor(
        IERC20 _asset
    ) ERC4626(_asset) ERC20("AIVault Shares", "aiVLT") {}

    function deposit(
        uint256 amount,
        address receiver
    ) public override nonReentrant returns (uint256 shares) {
        if (amount == 0) {
            revert ZeroDepositsNotAllowed();
        }
        if (receiver == address(0)) {
            revert WrongReceiverAddress();
        }

        depositTimestamps[receiver] = block.timestamp;
        totalDeposits += amount;
        shares = super.deposit(amount, receiver);

        emit Deposit(receiver, amount, shares);
        return shares;
    }

    function timeInVault(address user) public view returns (uint256) {
        if (depositTimestamps[user] == 0) {
            return 0;
        } else {
            return block.timestamp - depositTimestamps[user];
        }
    }

    // @notice User is allowedto withraw thier funds any time they chose, but the longer they stay in the vault, the more rewards they will earn(though rewards are not implemented in this version).
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        if (receiver == address(0)) {
            revert WrongReceiverAddress();
        }
        if (assets == 0) {
            revert ZeroWithdrawalsNotAllowed();
        }
        // Reset the user's deposit timestamp when they withdraw, so they don't earn rewards for the time they were in the vault before withrawing.
        depositTimestamps[owner] = 0;
        totalDeposits -= assets;
        shares = super.withdraw(assets, receiver, owner);
        emit Withdraw(receiver, assets, shares);

        return shares;
    }
}

// 0: contract AIVault 0x2a3584548D96E6807Ca4884Cb8CA98f69d0Ca7ca
// 1: contract MockUSDC 0x94E60fBd4a1a40402F70B67d79c89c3E3BdE8620
