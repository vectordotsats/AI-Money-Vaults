// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/////////////////////////////////////////////////////////
// Aave V3 Interface - only functions that we call //////
/////////////////////////////////////////////////////////

interface IAavePool {
    /// @notice Supply an asset to the Aave Pool
    /// @param asset          address of the underlying asset
    /// @param amount         how much to supply
    /// @param onBehalfOf     who recieves the aTokens (this contract)
    /// @param referralCode   Aave referral code -0 for none

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /// @notice Withdraw an asset from the Aave Pool
    /// @param asset The underlying asset to withdraw
    /// @param amount  how much to be withdrawn (type(uint256).max for all)
    /// @param to  who recieves the withrawn tokens
    /// @return The actual amount withdrawn

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint156);
}

//////////////////////////////////////
////////// AaveV3interface ///////////
//////////////////////////////////////

// This contract sits between the AIVault and Aave V3.
// It holds the aTokens and enforces guardrails on how much
// can be deployed, who can call what, and how fast.
//
// Access control:
//   - onlyKeeper  → supplyToAave(), rebalance logic
//   - onlyVault   → withdrawToVault()
//   - onlyOwner   → setKeeper(), setVault(), emergency functions
