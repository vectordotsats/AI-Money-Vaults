// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AIVault} from "../src/AIVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {DeployAIVault} from "../script/DeployAIVault.s.sol";

contract AIVaultTest is Test {
    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");

    AIVault public aiVault;
    MockUSDC public usdc;

    uint256 public constant INITIAL_BALANCE = 1000e18;

    // uint256 public constant TEST_AMOUNT = 100e18;

    function setUp() public {
        DeployAIVault deployer = new DeployAIVault();
        (aiVault, usdc) = deployer.run();
        // Mint initial USDC to Alice and Bob
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
    }

    //////////////////////
    // Deposit Test /////
    /////////////////////

    function testUserCanDeposit() public {
        vm.startPrank(alice);
        usdc.approve(address(aiVault), INITIAL_BALANCE);
        uint256 shares = aiVault.deposit(INITIAL_BALANCE, alice);
        vm.stopPrank();

        assertEq(aiVault.balanceOf(alice), shares);
        assertEq(shares, INITIAL_BALANCE);
        assertEq(usdc.balanceOf(alice), 0);
    }

    function testDepositUpdatesTimestamp() public {
        vm.startPrank(alice);
        usdc.approve(address(aiVault), INITIAL_BALANCE);
        aiVault.deposit(INITIAL_BALANCE, alice);
        vm.stopPrank();

        assertEq(aiVault.depositTimestamps(alice), block.timestamp);
    }

    function test_DepositUpdatesTotalDeposits() public {
        vm.startPrank(alice);
        usdc.approve(address(aiVault), INITIAL_BALANCE);
        aiVault.deposit(INITIAL_BALANCE, alice);
        vm.stopPrank();

        assertEq(aiVault.totalDeposits(), INITIAL_BALANCE);
    }

    function testZeroDepositsFails() public {
        vm.startPrank(alice);
        usdc.approve(address(aiVault), INITIAL_BALANCE);
        vm.expectRevert(AIVault.ZeroDepositsNotAllowed.selector);
        aiVault.deposit(0, alice);
        vm.stopPrank();
    }

    function testWrongReceiverAddressFails() public {
        vm.startPrank(alice);
        usdc.approve(address(aiVault), INITIAL_BALANCE);
        vm.expectRevert(AIVault.WrongReceiverAddress.selector);
        aiVault.deposit(INITIAL_BALANCE, address(0));
        vm.stopPrank();
    }

    ////////////////////////
    //// Withdraw Test /////
    ////////////////////////

    function testUserCanWithdraw() public {
        vm.startPrank(alice);
        usdc.approve(address(aiVault), INITIAL_BALANCE);
        aiVault.deposit(INITIAL_BALANCE, alice);

        uint256 shares = aiVault.balanceOf(alice);
        aiVault.withdraw(shares, alice, alice);
        vm.stopPrank();

        assertEq(aiVault.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(alice), shares);
    }

    function testUserCannotWithdrawOnBehalfOfAnother() public {
        vm.startPrank(alice);
        usdc.approve(address(aiVault), INITIAL_BALANCE);
        aiVault.deposit(INITIAL_BALANCE, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(aiVault), INITIAL_BALANCE);
        aiVault.deposit(INITIAL_BALANCE, bob);
        vm.expectRevert();
        aiVault.withdraw(INITIAL_BALANCE, bob, alice);
        vm.stopPrank();
    }

    function testUserCannotWithdrawMoreThanDeposited() public {
        vm.startPrank(alice);
        usdc.approve(address(aiVault), INITIAL_BALANCE);
        aiVault.deposit(INITIAL_BALANCE, alice);

        vm.expectRevert();
        aiVault.withdraw(INITIAL_BALANCE + 1e18, alice, alice);
        vm.stopPrank();
    }

    function test_WithdrawUpdatesTotalDeposits() public {
        vm.startPrank(alice);
        usdc.approve(address(aiVault), INITIAL_BALANCE);
        aiVault.deposit(INITIAL_BALANCE, alice);

        aiVault.withdraw(INITIAL_BALANCE, alice, alice);
        vm.stopPrank();

        assertEq(aiVault.totalDeposits(), 0);
    }

    function testZeroWithrawalsFails() public {
        vm.startPrank(alice);
        usdc.approve(address(aiVault), INITIAL_BALANCE);
        vm.expectRevert();
        aiVault.withdraw(0, alice, alice);
        vm.stopPrank();
    }

    function testWrongReceiverAddressFailsOnWithdrawals() public {
        vm.startPrank(alice);
        usdc.approve(address(aiVault), INITIAL_BALANCE);
        vm.expectRevert(AIVault.WrongReceiverAddress.selector);
        aiVault.withdraw(INITIAL_BALANCE, address(0), alice);
        vm.stopPrank();
    }

    function testWithdrawUpdatesTimestamp() public {
        vm.startPrank(alice);
        usdc.approve(address(aiVault), INITIAL_BALANCE);
        aiVault.deposit(INITIAL_BALANCE, alice);

        aiVault.withdraw(INITIAL_BALANCE, alice, alice);
        vm.stopPrank();

        assertEq(aiVault.depositTimestamps(alice), 0);
    }
}
