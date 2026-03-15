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

    constructor(
        IERC20 _asset
    ) ERC4626(_asset) ERC20("AIVault Shares", "aiVLT") {}

    function deposit(
        uint256 amount,
        address receiver
    ) public override nonReentrant returns (uint256 shares) {
        depositTimestamps[receiver] = block.timestamp;
        totalDeposits += amount;
        shares = super.deposit(amount, receiver);
        return shares;
    }

    function timeInVault(address user) public view returns (uint256) {
        if (depositTimestamps[user] == 0) {
            return 0;
        } else {
            return block.timestamp - depositTimestamps[user];
        }
    }
}
