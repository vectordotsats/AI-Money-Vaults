// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AIVault} from "../src/AIVaultV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

//////////////////////////////////////////////////////////////////
// ========== Using Mock USDC, Simple ERC20 for testing ==========
//////////////////////////////////////////////////////////////////

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

// ============ Mock Strategy — simulates AaveV3Strategy for testing ==============

contract MockStrategy {
    IERC20 public usdc;
    uint256 public totalDepositedInContract;
    uint256 public totalDeployed;

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }

    function receiveFromVault(uint256 amount) external {
        totalDepositedInContract += amount;
    }

    function withdrawToVault(uint256 amount) external {
        uint256 balance = usdc.balanceOf(address(this));
        uint256 toSend = amount > balance ? balance : amount;
        usdc.transfer(msg.sender, toSend);
        totalDepositedInContract -= toSend;
    }

    function totalStrategyAssets() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    // Simulate yield accruing in the strategy
    function simulateYield(address mockUsdc, uint256 amount) external {
        MockUSDC(mockUsdc).mint(address(this), amount);
    }
}

// ============ Malicious Strategy — for testing reentrancy =============

contract MaliciousStrategy {
    AIVault public vault;
    IERC20 public usdc;
    bool public attacked;

    constructor(address _vault, address _usdc) {
        vault = AIVault(_vault);
        usdc = IERC20(_usdc);
    }

    function receiveFromVault(uint256) external {
        // Try to reenter the vault during depositToStrategy
        if (!attacked) {
            attacked = true;
            vault.depositToStrategy(1e6);
        }
    }

    function withdrawToVault(uint256 amount) external {
        uint256 balance = usdc.balanceOf(address(this));
        uint256 toSend = amount > balance ? balance : amount;
        usdc.transfer(msg.sender, toSend);
    }

    function totalStrategyAssets() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
}

// ================ AIVault V2 Test Suite ===============

contract AIVaultTest is Test {
    AIVault public vault;
    MockUSDC public usdc;
    MockStrategy public strategy;

    address public owner = address(this);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public keeper = makeAddr("keeper");
    address public attacker = makeAddr("attacker");

    uint256 constant INITIAL_BALANCE = 10_000e6; // 10,000 USDC
    uint256 constant DEPOSIT_AMOUNT = 1_000e6; // 1,000 USDC

    function setUp() public {
        // Deploy contracts
        usdc = new MockUSDC();
        vault = new AIVault(IERC20(address(usdc)));
        strategy = new MockStrategy(address(usdc));

        // Configure vault
        vault.setStrategy(address(strategy));
        vault.setKeeper(keeper);

        // Fund test users
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
        usdc.mint(attacker, INITIAL_BALANCE);

        // Approve vault for all users
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(attacker);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ========== DEPOSIT TESTS ==========

    function test_deposit_basic() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, alice);

        assertGt(shares, 0, "Should receive shares");
        assertEq(
            vault.totalIdleDeposits(),
            DEPOSIT_AMOUNT,
            "Idle deposits should track"
        );
        assertEq(
            vault.allTimeDeposits(),
            DEPOSIT_AMOUNT,
            "All-time deposits should track"
        );
        assertEq(
            usdc.balanceOf(address(vault)),
            DEPOSIT_AMOUNT,
            "Vault should hold USDC"
        );
    }

    // function test_deposit_multipleUsers() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     vm.prank(bob);
    //     vault.deposit(DEPOSIT_AMOUNT * 2, bob);

    //     assertEq(vault.totalIdleDeposits(), DEPOSIT_AMOUNT * 3);
    //     assertEq(vault.allTimeDeposits(), DEPOSIT_AMOUNT * 3);
    // }

    // function test_deposit_revertsOnZero() public {
    //     vm.prank(alice);
    //     vm.expectRevert(AIVault.ZeroDepositsNotAllowed.selector);
    //     vault.deposit(0, alice);
    // }

    // function test_deposit_revertsOnZeroAddress() public {
    //     vm.prank(alice);
    //     vm.expectRevert(AIVault.WrongReceiverAddress.selector);
    //     vault.deposit(DEPOSIT_AMOUNT, address(0));
    // }

    // function test_deposit_emitsEvent() public {
    //     vm.prank(alice);
    //     vm.expectEmit(true, false, false, true);
    //     emit AIVault.Deposit(alice, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);
    // }

    // function test_deposit_onBehalfOfOther() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, bob);

    //     assertEq(
    //         vault.balanceOf(bob),
    //         DEPOSIT_AMOUNT,
    //         "Bob should receive shares"
    //     );
    //     assertEq(vault.balanceOf(alice), 0, "Alice should have no shares");
    // }

    // // ========== WITHDRAW TESTS ==========

    // function test_withdraw_basic() public {
    //     vm.startPrank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);
    //     vault.withdraw(DEPOSIT_AMOUNT, alice, alice);
    //     vm.stopPrank();

    //     assertEq(
    //         usdc.balanceOf(alice),
    //         INITIAL_BALANCE,
    //         "Alice should get all USDC back"
    //     );
    //     assertEq(vault.totalIdleDeposits(), 0, "Idle deposits should be zero");
    // }

    // function test_withdraw_partial() public {
    //     vm.startPrank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);
    //     vault.withdraw(DEPOSIT_AMOUNT / 2, alice, alice);
    //     vm.stopPrank();

    //     assertEq(vault.totalIdleDeposits(), DEPOSIT_AMOUNT / 2);
    //     assertEq(usdc.balanceOf(alice), INITIAL_BALANCE - DEPOSIT_AMOUNT / 2);
    // }

    // function test_withdraw_revertsOnZero() public {
    //     vm.startPrank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     vm.expectRevert(AIVault.ZeroWithdrawalsNotAllowed.selector);
    //     vault.withdraw(0, alice, alice);
    //     vm.stopPrank();
    // }

    // function test_withdraw_revertsOnZeroAddress() public {
    //     vm.startPrank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     vm.expectRevert(AIVault.WrongReceiverAddress.selector);
    //     vault.withdraw(DEPOSIT_AMOUNT, address(0), alice);
    //     vm.stopPrank();
    // }

    // function test_withdraw_pullsFromStrategy() public {
    //     // Alice deposits
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     // Keeper pushes all to strategy
    //     vm.prank(keeper);
    //     vault.depositToStrategy(DEPOSIT_AMOUNT);

    //     // Vault has 0 idle, strategy has DEPOSIT_AMOUNT
    //     assertEq(vault.totalIdleDeposits(), 0);
    //     assertEq(usdc.balanceOf(address(strategy)), DEPOSIT_AMOUNT);

    //     // Alice withdraws — vault should pull from strategy
    //     vm.prank(alice);
    //     vault.withdraw(DEPOSIT_AMOUNT, alice, alice);

    //     assertEq(
    //         usdc.balanceOf(alice),
    //         INITIAL_BALANCE,
    //         "Alice should get full amount back"
    //     );
    // }

    // function test_withdraw_pullsPartialFromStrategy() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     // Push 800 to strategy, keep 200 idle
    //     vm.prank(keeper);
    //     vault.depositToStrategy(800e6);

    //     assertEq(vault.totalIdleDeposits(), 200e6);

    //     // Alice withdraws 500 — needs 300 from strategy
    //     vm.prank(alice);
    //     vault.withdraw(500e6, alice, alice);

    //     assertEq(vault.totalIdleDeposits(), 0);
    // }

    // function test_withdraw_emitsEvent() public {
    //     vm.startPrank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     vm.expectEmit(true, false, false, true);
    //     emit AIVault.Withdraw(alice, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT);
    //     vault.withdraw(DEPOSIT_AMOUNT, alice, alice);
    //     vm.stopPrank();
    // }

    // // ========== STRATEGY ROUTING TESTS ==========

    // function test_depositToStrategy_basic() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     vm.prank(keeper);
    //     vault.depositToStrategy(DEPOSIT_AMOUNT);

    //     assertEq(
    //         vault.totalIdleDeposits(),
    //         0,
    //         "Idle should be zero after push"
    //     );
    //     assertEq(
    //         usdc.balanceOf(address(strategy)),
    //         DEPOSIT_AMOUNT,
    //         "Strategy should hold USDC"
    //     );
    //     assertEq(
    //         strategy.totalDepositedInContract(),
    //         DEPOSIT_AMOUNT,
    //         "Strategy accounting should update"
    //     );
    // }

    // function test_depositToStrategy_partial() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     vm.prank(keeper);
    //     vault.depositToStrategy(DEPOSIT_AMOUNT / 2);

    //     assertEq(vault.totalIdleDeposits(), DEPOSIT_AMOUNT / 2);
    //     assertEq(usdc.balanceOf(address(strategy)), DEPOSIT_AMOUNT / 2);
    // }

    // function test_depositToStrategy_revertsNoStrategy() public {
    //     // Deploy vault without strategy
    //     AIVault freshVault = new AIVault(IERC20(address(usdc)));
    //     freshVault.setKeeper(keeper);

    //     usdc.mint(address(freshVault), DEPOSIT_AMOUNT);

    //     vm.prank(keeper);
    //     vm.expectRevert(AIVault.NoStrategySet.selector);
    //     freshVault.depositToStrategy(DEPOSIT_AMOUNT);
    // }

    // function test_depositToStrategy_revertsZeroAmount() public {
    //     vm.prank(keeper);
    //     vm.expectRevert(AIVault.ZeroAmount.selector);
    //     vault.depositToStrategy(0);
    // }

    // function test_depositToStrategy_revertsInsufficientBalance() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     vm.prank(keeper);
    //     vm.expectRevert(AIVault.InsufficientIdleBalance.selector);
    //     vault.depositToStrategy(DEPOSIT_AMOUNT + 1);
    // }

    // function test_depositToStrategy_emitsEvent() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     vm.prank(keeper);
    //     vm.expectEmit(false, false, false, true);
    //     emit AIVault.FundsPushedToStrategy(DEPOSIT_AMOUNT);
    //     vault.depositToStrategy(DEPOSIT_AMOUNT);
    // }

    // // ========== TOTAL ASSETS & SHARE PRICE TESTS ==========

    // function test_totalAssets_idleOnly() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
    // }

    // function test_totalAssets_includesStrategy() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     vm.prank(keeper);
    //     vault.depositToStrategy(DEPOSIT_AMOUNT);

    //     // totalAssets should still equal DEPOSIT_AMOUNT (idle 0 + strategy DEPOSIT_AMOUNT)
    //     assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
    // }

    // function test_totalAssets_reflectsYield() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     vm.prank(keeper);
    //     vault.depositToStrategy(DEPOSIT_AMOUNT);

    //     // Simulate 100 USDC yield in strategy
    //     uint256 yield = 100e6;
    //     strategy.simulateYield(address(usdc), yield);

    //     // totalAssets should now include the yield
    //     assertEq(vault.totalAssets(), DEPOSIT_AMOUNT + yield);
    // }

    // function test_sharePrice_increasesWithYield() public {
    //     // Alice deposits first
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);
    //     uint256 aliceShares = vault.balanceOf(alice);

    //     // Push to strategy
    //     vm.prank(keeper);
    //     vault.depositToStrategy(DEPOSIT_AMOUNT);

    //     // Simulate yield
    //     strategy.simulateYield(address(usdc), 100e6);

    //     // Alice's shares should now be worth more than she deposited
    //     uint256 aliceAssets = vault.convertToAssets(aliceShares);
    //     assertGt(
    //         aliceAssets,
    //         DEPOSIT_AMOUNT,
    //         "Shares should be worth more after yield"
    //     );
    // }

    // function test_totalAssets_noStrategy() public {
    //     // Deploy vault without strategy
    //     AIVault freshVault = new AIVault(IERC20(address(usdc)));

    //     usdc.mint(alice, DEPOSIT_AMOUNT);
    //     vm.startPrank(alice);
    //     usdc.approve(address(freshVault), type(uint256).max);
    //     freshVault.deposit(DEPOSIT_AMOUNT, alice);
    //     vm.stopPrank();

    //     assertEq(freshVault.totalAssets(), DEPOSIT_AMOUNT);
    // }

    // // ============= ACCESS CONTROL TESTS ============

    // function test_depositToStrategy_onlyKeeper() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     // Random user can't push to strategy
    //     vm.prank(attacker);
    //     vm.expectRevert(AIVault.NotKeeper.selector);
    //     vault.depositToStrategy(DEPOSIT_AMOUNT);
    // }

    // function test_depositToStrategy_ownerCanCall() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     // Owner should also be able to call
    //     vault.depositToStrategy(DEPOSIT_AMOUNT);

    //     assertEq(vault.totalIdleDeposits(), 0);
    // }

    // function test_depositToStrategy_keeperCanCall() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     vm.prank(keeper);
    //     vault.depositToStrategy(DEPOSIT_AMOUNT);

    //     assertEq(vault.totalIdleDeposits(), 0);
    // }

    // function test_setStrategy_onlyOwner() public {
    //     vm.prank(attacker);
    //     vm.expectRevert();
    //     vault.setStrategy(address(strategy));
    // }

    // function test_setStrategy_revertsZeroAddress() public {
    //     vm.expectRevert(AIVault.ZeroAddress.selector);
    //     vault.setStrategy(address(0));
    // }

    // function test_setStrategy_emitsEvent() public {
    //     address newStrategy = makeAddr("newStrategy");
    //     address oldStrategy = address(strategy);

    //     vm.expectEmit(false, false, false, true);
    //     emit AIVault.StrategyUpdated(oldStrategy, newStrategy);
    //     vault.setStrategy(newStrategy);
    // }

    // function test_setKeeper_onlyOwner() public {
    //     vm.prank(attacker);
    //     vm.expectRevert();
    //     vault.setKeeper(makeAddr("newKeeper"));
    // }

    // function test_setKeeper_revertsZeroAddress() public {
    //     vm.expectRevert(AIVault.ZeroAddress.selector);
    //     vault.setKeeper(address(0));
    // }

    // function test_setKeeper_emitsEvent() public {
    //     address newKeeper = makeAddr("newKeeper");

    //     vm.expectEmit(false, false, false, true);
    //     emit AIVault.KeeperUpdated(keeper, newKeeper);
    //     vault.setKeeper(newKeeper);
    // }

    // // =========== ACCOUNTING INTEGRITY TESTS ==========

    // function test_allTimeDeposits_neverDecrements() public {
    //     vm.startPrank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);
    //     vault.withdraw(DEPOSIT_AMOUNT, alice, alice);
    //     vm.stopPrank();

    //     assertEq(
    //         vault.allTimeDeposits(),
    //         DEPOSIT_AMOUNT,
    //         "All-time should never decrease"
    //     );
    // }

    // function test_allTimeDeposits_accumulates() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     vm.prank(bob);
    //     vault.deposit(DEPOSIT_AMOUNT * 2, bob);

    //     assertEq(vault.allTimeDeposits(), DEPOSIT_AMOUNT * 3);
    // }

    // function test_idleDeposits_tracksCorrectly_fullCycle() public {
    //     // Deposit
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);
    //     assertEq(vault.totalIdleDeposits(), DEPOSIT_AMOUNT);

    //     // Push to strategy
    //     vm.prank(keeper);
    //     vault.depositToStrategy(DEPOSIT_AMOUNT);
    //     assertEq(vault.totalIdleDeposits(), 0);

    //     // Withdraw (pulls from strategy)
    //     vm.prank(alice);
    //     vault.withdraw(DEPOSIT_AMOUNT, alice, alice);
    //     assertEq(vault.totalIdleDeposits(), 0);
    // }

    // function test_idleBalance_viewFunction() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     assertEq(vault.idleBalance(), DEPOSIT_AMOUNT);

    //     vm.prank(keeper);
    //     vault.depositToStrategy(DEPOSIT_AMOUNT);

    //     assertEq(vault.idleBalance(), 0);
    // }

    // // ============ REENTRANCY TESTS =============

    // function test_depositToStrategy_reentrancyProtected() public {
    //     // Deploy malicious strategy
    //     MaliciousStrategy malicious = new MaliciousStrategy(
    //         address(vault),
    //         address(usdc)
    //     );
    //     vault.setStrategy(address(malicious));

    //     // Alice deposits
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     // Keeper pushes — malicious strategy tries to reenter
    //     vm.prank(keeper);
    //     vm.expectRevert(); // ReentrancyGuard should catch this
    //     vault.depositToStrategy(DEPOSIT_AMOUNT / 2);
    // }

    // // ========== EDGE CASES ===========

    // function test_withdraw_withNoStrategySet() public {
    //     // Deploy vault without strategy
    //     AIVault freshVault = new AIVault(IERC20(address(usdc)));

    //     usdc.mint(alice, DEPOSIT_AMOUNT);
    //     vm.startPrank(alice);
    //     usdc.approve(address(freshVault), type(uint256).max);
    //     freshVault.deposit(DEPOSIT_AMOUNT, alice);
    //     freshVault.withdraw(DEPOSIT_AMOUNT, alice, alice);
    //     vm.stopPrank();

    //     // Should work fine without strategy
    //     assertEq(usdc.balanceOf(alice), DEPOSIT_AMOUNT);
    // }

    // function test_multipleDepositsAndWithdrawals() public {
    //     // Alice deposits 3 times
    //     vm.startPrank(alice);
    //     vault.deposit(100e6, alice);
    //     vault.deposit(200e6, alice);
    //     vault.deposit(300e6, alice);

    //     assertEq(vault.totalIdleDeposits(), 600e6);
    //     assertEq(vault.allTimeDeposits(), 600e6);

    //     // Withdraw 150
    //     vault.withdraw(150e6, alice, alice);
    //     assertEq(vault.totalIdleDeposits(), 450e6);
    //     assertEq(vault.allTimeDeposits(), 600e6); // unchanged

    //     // Withdraw rest
    //     vault.withdraw(450e6, alice, alice);
    //     assertEq(vault.totalIdleDeposits(), 0);
    //     vm.stopPrank();
    // }

    // function test_strategySwap() public {
    //     vm.prank(alice);
    //     vault.deposit(DEPOSIT_AMOUNT, alice);

    //     vm.prank(keeper);
    //     vault.depositToStrategy(DEPOSIT_AMOUNT);

    //     // Deploy new strategy and swap
    //     MockStrategy newStrategy = new MockStrategy(address(usdc));
    //     vault.setStrategy(address(newStrategy));

    //     // Old strategy still holds funds — vault now points to new one
    //     assertEq(usdc.balanceOf(address(strategy)), DEPOSIT_AMOUNT);
    //     assertEq(address(vault.strategy()), address(newStrategy));
    // }

    // // ========== FUZZ TESTS ==========

    // function testFuzz_deposit(uint256 amount) public {
    //     amount = bound(amount, 1, INITIAL_BALANCE);

    //     vm.prank(alice);
    //     uint256 shares = vault.deposit(amount, alice);

    //     assertGt(shares, 0);
    //     assertEq(vault.totalIdleDeposits(), amount);
    // }

    // function testFuzz_depositAndWithdraw(
    //     uint256 depositAmt,
    //     uint256 withdrawAmt
    // ) public {
    //     depositAmt = bound(depositAmt, 1, INITIAL_BALANCE);
    //     withdrawAmt = bound(withdrawAmt, 1, depositAmt);

    //     vm.startPrank(alice);
    //     vault.deposit(depositAmt, alice);
    //     vault.withdraw(withdrawAmt, alice, alice);
    //     vm.stopPrank();

    //     assertEq(vault.totalIdleDeposits(), depositAmt - withdrawAmt);
    // }

    // function testFuzz_depositToStrategy(
    //     uint256 depositAmt,
    //     uint256 strategyAmt
    // ) public {
    //     depositAmt = bound(depositAmt, 2, INITIAL_BALANCE);
    //     strategyAmt = bound(strategyAmt, 1, depositAmt);

    //     vm.prank(alice);
    //     vault.deposit(depositAmt, alice);

    //     vm.prank(keeper);
    //     vault.depositToStrategy(strategyAmt);

    //     assertEq(vault.totalIdleDeposits(), depositAmt - strategyAmt);
    //     assertEq(usdc.balanceOf(address(strategy)), strategyAmt);
    // }
}
