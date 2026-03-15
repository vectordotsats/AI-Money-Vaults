// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AIVault} from "../src/AIVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {AIVault} from "../src/AIVault.sol";

contract AIVaultTest is Test {
    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");

    AIVault public aiVault;
    MockUSDC public usdc;

    uint256 public constant InitialBalance = 1000e18;

    function setUp() public {
        usdc = new MockUSDC();
        aiVault = new AIVault(usdc);
    }
}
