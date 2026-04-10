// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AaveV3Strategy} from "../src/AaveV3Strategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ============== Mock USDC ==============

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

// =========== Mock aUSDC — simulates Aave's rebasing aToken =============

contract MockAToken is ERC20 {
    constructor() ERC20("Mock aUSDC", "aUSDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

// ========= Mock Aave Pool — simulates supply/withdraw ==========

contract MockAavePool {
    MockUSDC public usdc;
    MockAToken public aToken;

    constructor(address _usdc, address _aToken) {
        usdc = MockUSDC(_usdc);
        aToken = MockAToken(_aToken);
    }

    function supply(
        address,
        uint256 amount,
        address onBehalfOf,
        uint16
    ) external {
        // Pull USDC from caller
        usdc.transferFrom(msg.sender, address(this), amount);
        // Mint aTokens to the supplier
        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(
        address,
        uint256 amount,
        address to
    ) external returns (uint256) {
        uint256 aBalance = aToken.balanceOf(msg.sender);
        uint256 toWithdraw = amount == type(uint256).max ? aBalance : amount;
        if (toWithdraw > aBalance) toWithdraw = aBalance;

        // Burn aTokens from caller
        aToken.burn(msg.sender, toWithdraw);
        // Send USDC to recipient
        usdc.mint(to, toWithdraw); // Mint fresh since we're simulating
        return toWithdraw;
    }

    // Simulate yield by minting extra aTokens
    function simulateYield(address holder, uint256 amount) external {
        aToken.mint(holder, amount);
    }
}

/////////////////////////////////////////////////
// ================ Test Suite =================
////////////////////////////////////////////////

contract AaveV3StrategyTest is Test {
    AaveV3Strategy public strategy;
    MockUSDC public usdc;
    MockAToken public aUsdc;
    MockAavePool public aavePool;

    address public owner = address(this);
    address public vault = makeAddr("vault");
    address public keeper = makeAddr("keeper");
    address public attacker = makeAddr("attacker");

    uint256 constant DEPOSIT_AMOUNT = 1_000e6;
    uint256 constant LARGE_DEPOSIT = 10_000e6;

    function setUp() public {
        usdc = new MockUSDC();
        aUsdc = new MockAToken();
        aavePool = new MockAavePool(address(usdc), address(aUsdc));

        strategy = new AaveV3Strategy(
            address(usdc),
            address(aUsdc),
            address(aavePool),
            vault,
            keeper
        );
    }

    // Helper: fund the strategy as if vault sent USDC
    function _fundStrategy(uint256 amount) internal {
        usdc.mint(address(strategy), amount);
        vm.prank(vault);
        strategy.receiveFromVault(amount);
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_constructor_setsValues() public view {
        assertEq(address(strategy.USDC()), address(usdc));
        assertEq(address(strategy.aUSDC()), address(aUsdc));
        assertEq(address(strategy.aavePool()), address(aavePool));
        assertEq(strategy.vault(), vault);
        assertEq(strategy.keeper(), keeper);
        assertEq(strategy.maxSupplyPercentage(), 90);
        assertEq(strategy.paused(), false);
    }

    function test_constructor_revertsZeroUsdc() public {
        vm.expectRevert(AaveV3Strategy.ZeroAddress.selector);
        new AaveV3Strategy(
            address(0),
            address(aUsdc),
            address(aavePool),
            vault,
            keeper
        );
    }

    function test_constructor_revertsZeroAUsdc() public {
        vm.expectRevert(AaveV3Strategy.ZeroAddress.selector);
        new AaveV3Strategy(
            address(usdc),
            address(0),
            address(aavePool),
            vault,
            keeper
        );
    }

    function test_constructor_revertsZeroPool() public {
        vm.expectRevert(AaveV3Strategy.ZeroAddress.selector);
        new AaveV3Strategy(
            address(usdc),
            address(aUsdc),
            address(0),
            vault,
            keeper
        );
    }

    // ============ SUPPLY TO AAVE TESTS =============

    function test_supplyToAave_basic() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(keeper);
        strategy.supplyToAave(500e6); // Supply 500 of 1000 (50%)

        assertEq(strategy.totalDeployed(), 500e6);
        assertEq(aUsdc.balanceOf(address(strategy)), 500e6);
    }

    function test_supplyToAave_maxAllocation() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        // Supply exactly 90% — should work
        vm.prank(keeper);
        strategy.supplyToAave(900e6);

        assertEq(strategy.totalDeployed(), 900e6);
    }

    function test_supplyToAave_revertsExceedsMax() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        // Try to supply 91% — should revert
        vm.prank(keeper);
        vm.expectRevert(AaveV3Strategy.ExceedsMaxSupply.selector);
        strategy.supplyToAave(910e6);
    }

    function test_supplyToAave_revertsZeroAmount() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(keeper);
        vm.expectRevert(AaveV3Strategy.ZeroAmount.selector);
        strategy.supplyToAave(0);
    }

    function test_supplyToAave_revertsInsufficientBalance() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(keeper);
        vm.expectRevert(AaveV3Strategy.InsufficientBalance.selector);
        strategy.supplyToAave(DEPOSIT_AMOUNT + 1);
    }

    function test_supplyToAave_revertsWhenPaused() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        strategy.setPauseStatus(true);

        vm.prank(keeper);
        vm.expectRevert(AaveV3Strategy.IsPaused.selector);
        strategy.supplyToAave(500e6);
    }

    function test_supplyToAave_multipleSupplies() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.startPrank(keeper);
        strategy.supplyToAave(300e6);
        strategy.supplyToAave(300e6);
        strategy.supplyToAave(300e6); // Total 900 = 90%
        vm.stopPrank();

        assertEq(strategy.totalDeployed(), 900e6);
    }

    function test_supplyToAave_emitsEvent() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(keeper);
        vm.expectEmit(false, false, false, true);
        emit AaveV3Strategy.SuppliedToAave(500e6, 500e6);
        strategy.supplyToAave(500e6);
    }

    // ============= WITHDRAW TO VAULT TESTS ==============

    function test_withdrawToVault_fromIdle() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        // Don't supply to Aave — all idle
        vm.prank(vault);
        strategy.withdrawToVault(500e6);

        assertEq(usdc.balanceOf(vault), 500e6);
        assertEq(strategy.totalDepositedInContract(), 500e6);
    }

    function test_withdrawToVault_fromAave() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        // Supply 900 to Aave, 100 idle
        vm.prank(keeper);
        strategy.supplyToAave(900e6);

        // Vault asks for 500 — needs 400 from Aave
        vm.prank(vault);
        strategy.withdrawToVault(500e6);

        assertEq(usdc.balanceOf(vault), 500e6);
        assertEq(strategy.totalDeployed(), 500e6);
    }

    function test_withdrawToVault_allFromAave() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        // Supply 900 to Aave
        vm.prank(keeper);
        strategy.supplyToAave(900e6);

        // Vault asks for full amount
        vm.prank(vault);
        strategy.withdrawToVault(DEPOSIT_AMOUNT);

        assertEq(usdc.balanceOf(vault), DEPOSIT_AMOUNT);
        assertEq(strategy.totalDeployed(), 0);
    }

    function test_withdrawToVault_revertsZero() public {
        vm.prank(vault);
        vm.expectRevert(AaveV3Strategy.ZeroAmount.selector);
        strategy.withdrawToVault(0);
    }

    function test_withdrawToVault_worksWhenPaused() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        strategy.setPauseStatus(true);

        // Withdrawals should ALWAYS work — even when paused
        vm.prank(vault);
        strategy.withdrawToVault(500e6);

        assertEq(usdc.balanceOf(vault), 500e6);
    }

    function test_withdrawToVault_emitsEvent() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(vault);
        vm.expectEmit(false, false, false, true);
        emit AaveV3Strategy.WithdrawnFromAave(500e6, vault);
        strategy.withdrawToVault(500e6);
    }

    // =========== RECEIVE FROM VAULT TESTS ===========

    function test_receiveFromVault_updatesAccounting() public {
        usdc.mint(address(strategy), DEPOSIT_AMOUNT);

        vm.prank(vault);
        strategy.receiveFromVault(DEPOSIT_AMOUNT);

        assertEq(strategy.totalDepositedInContract(), DEPOSIT_AMOUNT);
    }

    function test_receiveFromVault_onlyVault() public {
        vm.prank(attacker);
        vm.expectRevert(AaveV3Strategy.NotVault.selector);
        strategy.receiveFromVault(DEPOSIT_AMOUNT);
    }

    function test_receiveFromVault_multipleCalls() public {
        usdc.mint(address(strategy), DEPOSIT_AMOUNT * 3);

        vm.startPrank(vault);
        strategy.receiveFromVault(DEPOSIT_AMOUNT);
        strategy.receiveFromVault(DEPOSIT_AMOUNT);
        strategy.receiveFromVault(DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(strategy.totalDepositedInContract(), DEPOSIT_AMOUNT * 3);
    }

    // =========== ACCESS CONTROL TESTS ============

    function test_supplyToAave_onlyKeeper() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(attacker);
        vm.expectRevert(AaveV3Strategy.NotKeeper.selector);
        strategy.supplyToAave(500e6);
    }

    function test_supplyToAave_ownerCantCall() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        // Owner is NOT the keeper — should revert
        vm.expectRevert(AaveV3Strategy.NotKeeper.selector);
        strategy.supplyToAave(500e6);
    }

    function test_withdrawToVault_onlyVault() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(attacker);
        vm.expectRevert(AaveV3Strategy.NotVault.selector);
        strategy.withdrawToVault(500e6);
    }

    function test_withdrawToVault_keeperCantCall() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(keeper);
        vm.expectRevert(AaveV3Strategy.NotVault.selector);
        strategy.withdrawToVault(500e6);
    }

    function test_updateKeeper_onlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        strategy.updateKeeper(makeAddr("newKeeper"));
    }

    function test_updateVault_onlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        strategy.updateVault(makeAddr("newVault"));
    }

    function test_updateMaxSupplyPercentage_onlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        strategy.updateMaxSupplyPercentage(50);
    }

    function test_setPauseStatus_onlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        strategy.setPauseStatus(true);
    }

    function test_emergencyWithdrawAll_onlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        strategy.emergencyWithdrawAll();
    }

    function test_rescueToken_onlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        strategy.rescueToken(address(usdc), 100);
    }

    // ============ VIEW FUNCTION TESTS ===============

    function test_totalStrategyAsset_idleOnly() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        assertEq(strategy.totalStrategyAsset(), DEPOSIT_AMOUNT);
    }

    function test_totalStrategyAsset_withDeployed() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(keeper);
        strategy.supplyToAave(500e6);

        // idle (500) + aToken balance (500) = 1000
        assertEq(strategy.totalStrategyAsset(), DEPOSIT_AMOUNT);
    }

    function test_totalStrategyAsset_withYield() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(keeper);
        strategy.supplyToAave(500e6);

        // Simulate 50 USDC yield
        aavePool.simulateYield(address(strategy), 50e6);

        // idle (500) + aToken (500 + 50 yield) = 1050
        assertEq(strategy.totalStrategyAsset(), 1050e6);
    }

    function test_accruedYield_noYield() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(keeper);
        strategy.supplyToAave(500e6);

        assertEq(strategy.accruedYield(), 0);
    }

    function test_accruedYield_withYield() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(keeper);
        strategy.supplyToAave(500e6);

        aavePool.simulateYield(address(strategy), 50e6);

        assertEq(strategy.accruedYield(), 50e6);
    }

    function test_idleBalanceInVault() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        assertEq(strategy.idleBalanceInVault(), DEPOSIT_AMOUNT);

        vm.prank(keeper);
        strategy.supplyToAave(700e6);

        assertEq(strategy.idleBalanceInVault(), 300e6);
    }

    // ========== ADMIN FUNCTION TESTS ==========

    function test_updateKeeper() public {
        address newKeeper = makeAddr("newKeeper");

        vm.expectEmit(false, false, false, true);
        emit AaveV3Strategy.KeeperUpdated(keeper, newKeeper);
        strategy.updateKeeper(newKeeper);

        assertEq(strategy.keeper(), newKeeper);
    }

    function test_updateKeeper_revertsZeroAddress() public {
        vm.expectRevert(AaveV3Strategy.ZeroAddress.selector);
        strategy.updateKeeper(address(0));
    }

    function test_updateVault() public {
        address newVault = makeAddr("newVault");

        vm.expectEmit(false, false, false, true);
        emit AaveV3Strategy.VaultUpdated(vault, newVault);
        strategy.updateVault(newVault);

        assertEq(strategy.vault(), newVault);
    }

    function test_updateVault_revertsZeroAddress() public {
        vm.expectRevert(AaveV3Strategy.ZeroAddress.selector);
        strategy.updateVault(address(0));
    }

    function test_updateMaxSupplyPercentage() public {
        vm.expectEmit(false, false, false, true);
        emit AaveV3Strategy.MaxSupplyPercentUpdated(90, 50);
        strategy.updateMaxSupplyPercentage(50);

        assertEq(strategy.maxSupplyPercentage(), 50);
    }

    function test_updateMaxSupplyPercentage_revertsOver100() public {
        vm.expectRevert(AaveV3Strategy.InvalidPercent.selector);
        strategy.updateMaxSupplyPercentage(101);
    }

    function test_updateMaxSupplyPercentage_allowsZero() public {
        strategy.updateMaxSupplyPercentage(0);
        assertEq(strategy.maxSupplyPercentage(), 0);
    }

    function test_setPauseStatus() public {
        strategy.setPauseStatus(true);
        assertEq(strategy.paused(), true);

        strategy.setPauseStatus(false);
        assertEq(strategy.paused(), false);
    }

    // =========== EMERGENCY WITHDRAW TESTS ================

    function test_emergencyWithdrawAll() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(keeper);
        strategy.supplyToAave(900e6);

        strategy.emergencyWithdrawAll();

        // Funds go to vault, not owner
        assertEq(usdc.balanceOf(vault), 900e6);
        assertEq(strategy.totalDeployed(), 0);
        assertEq(strategy.paused(), true);
    }

    function test_emergencyWithdrawAll_withYield() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(keeper);
        strategy.supplyToAave(900e6);

        // Simulate 100 USDC yield
        aavePool.simulateYield(address(strategy), 100e6);

        strategy.emergencyWithdrawAll();

        // Vault receives principal + yield
        assertEq(usdc.balanceOf(vault), 1000e6); // 900 + 100 yield
        assertEq(strategy.totalDeployed(), 0);
        assertEq(strategy.paused(), true);
    }

    function test_emergencyWithdrawAll_revertsNoBalance() public {
        vm.expectRevert(AaveV3Strategy.ZeroAmount.selector);
        strategy.emergencyWithdrawAll();
    }

    function test_emergencyWithdrawAll_accountingUpdates() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(keeper);
        strategy.supplyToAave(900e6);

        aavePool.simulateYield(address(strategy), 100e6);

        // Before: totalDepositedInContract = 1000
        assertEq(strategy.totalDepositedInContract(), DEPOSIT_AMOUNT);

        strategy.emergencyWithdrawAll();

        // After: totalDepositedInContract should include yield
        // withdrawn (1000) - totalDeployed before (900) = 100 yield added
        // 1000 + 100 = 1100
        assertEq(strategy.totalDepositedInContract(), 1100e6);
    }

    // ============= RESCUE TOKEN TESTS ===============

    function test_rescueToken() public {
        // Create a random token and send it to strategy
        MockUSDC randomToken = new MockUSDC();
        randomToken.mint(address(strategy), 1000e6);

        strategy.rescueToken(address(randomToken), 1000e6);

        assertEq(randomToken.balanceOf(owner), 1000e6);
    }

    function test_rescueToken_revertsForUsdc() public {
        vm.expectRevert(AaveV3Strategy.WrongAddress.selector);
        strategy.rescueToken(address(usdc), 100);
    }

    function test_rescueToken_revertsForAUsdc() public {
        vm.expectRevert(AaveV3Strategy.WrongAddress.selector);
        strategy.rescueToken(address(aUsdc), 100);
    }

    // ======== GUARDRAIL TESTS ==========

    function test_guardrail_maxPercentageEnforced() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        // Supply 90% — works
        vm.prank(keeper);
        strategy.supplyToAave(900e6);

        // Add more funds
        _fundStrategy(DEPOSIT_AMOUNT);

        // Now totalDeposited = 2000, totalDeployed = 900
        // Try to supply 910 more — that would be 1810/2000 = 90.5% — should revert
        vm.prank(keeper);
        vm.expectRevert(AaveV3Strategy.ExceedsMaxSupply.selector);
        strategy.supplyToAave(910e6);
    }

    function test_guardrail_updatedPercentage() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        // Lower max to 50%
        strategy.updateMaxSupplyPercentage(50);

        // Try to supply 60% — should revert
        vm.prank(keeper);
        vm.expectRevert(AaveV3Strategy.ExceedsMaxSupply.selector);
        strategy.supplyToAave(600e6);

        // Supply 50% — should work
        vm.prank(keeper);
        strategy.supplyToAave(500e6);

        assertEq(strategy.totalDeployed(), 500e6);
    }

    function test_guardrail_zeroPercentBlocksAll() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        strategy.updateMaxSupplyPercentage(0);

        vm.prank(keeper);
        vm.expectRevert(AaveV3Strategy.ExceedsMaxSupply.selector);
        strategy.supplyToAave(1);
    }

    // ========= ACCOUNTING INTEGRITY TESTS ===========

    function test_accounting_fullCycle() public {
        // Fund strategy
        _fundStrategy(DEPOSIT_AMOUNT);
        assertEq(strategy.totalDepositedInContract(), DEPOSIT_AMOUNT);
        assertEq(strategy.totalDeployed(), 0);

        // Supply to Aave
        vm.prank(keeper);
        strategy.supplyToAave(800e6);
        assertEq(strategy.totalDeployed(), 800e6);
        assertEq(strategy.idleBalanceInVault(), 200e6);

        // Withdraw to vault
        vm.prank(vault);
        strategy.withdrawToVault(500e6);
        assertEq(strategy.totalDeployed(), 500e6);
        assertEq(strategy.totalDepositedInContract(), 500e6);
        assertEq(usdc.balanceOf(vault), 500e6);

        // Withdraw remaining
        vm.prank(vault);
        strategy.withdrawToVault(500e6);
        assertEq(strategy.totalDeployed(), 0);
        assertEq(strategy.totalDepositedInContract(), 0);
    }

    function test_accounting_withdrawMoreThanDeployed() public {
        _fundStrategy(DEPOSIT_AMOUNT);

        vm.prank(keeper);
        strategy.supplyToAave(500e6);

        // Vault asks for full amount — 500 idle + 500 from Aave
        vm.prank(vault);
        strategy.withdrawToVault(DEPOSIT_AMOUNT);

        assertEq(strategy.totalDeployed(), 0);
        assertEq(strategy.totalDepositedInContract(), 0);
    }

    // ========== FUZZ TESTS =========

    function testFuzz_supplyToAave(uint256 deposit, uint256 supply) public {
        deposit = bound(deposit, 100, 100_000e6);
        supply = bound(supply, 1, (deposit * 90) / 100); // Stay within 90%

        _fundStrategy(deposit);

        vm.prank(keeper);
        strategy.supplyToAave(supply);

        assertEq(strategy.totalDeployed(), supply);
    }

    function testFuzz_withdrawToVault(
        uint256 deposit,
        uint256 supply,
        uint256 withdraw
    ) public {
        deposit = bound(deposit, 100, 100_000e6);
        supply = bound(supply, 1, (deposit * 90) / 100);
        withdraw = bound(withdraw, 1, deposit);

        _fundStrategy(deposit);

        vm.prank(keeper);
        strategy.supplyToAave(supply);

        vm.prank(vault);
        strategy.withdrawToVault(withdraw);

        assertEq(usdc.balanceOf(vault), withdraw);
    }

    function testFuzz_receiveFromVault(uint256 amount) public {
        amount = bound(amount, 1, 100_000e6);

        usdc.mint(address(strategy), amount);

        vm.prank(vault);
        strategy.receiveFromVault(amount);

        assertEq(strategy.totalDepositedInContract(), amount);
    }
}
