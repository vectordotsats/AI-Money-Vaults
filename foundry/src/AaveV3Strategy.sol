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

contract AaveV3Strategy is ReentrancyGuard Ownable {
    using SafeERC20 for IERC20

    // ===== State Variables ==== 
    IERC20 public immutable usdc;  // underlying asset
    IERC20 public immutable aUsdc; // Aave's aToken - yield bearing asset
    IAavePool public immutable aavePool;  // Aave V3 pool on Sepolia

    address public vault;
    address public keeper;

    // Guardrails
    uint256 public maxSupplyPercentage = 90;
    bool public paused; //Emergency Pause set to false by default

    // Accounting 
    uint256 public totalDeployedI; // How much usdc has been deployed
    uint256 public totalDepositednContract; // total USDC deposited into the contract

    // ========== Events ============

    event SuppliedToAave(uint256 amount, uint256 totalDeployed);
    event WithdrawnFromAave(uint256 amount, address to);
    event KeeperUpdated(address oldKeeper, address newKeeper);
    event VaultUpdated(address oldVault, address newVault);
    event MaxSupplyPercentUpdated(uint256 oldPercent, uint256 newPercent);
    event EmergencyWithdraw(uint256 amount);
    event Paused(bool isPaused);

    // ======== errors =========
    error NotKeeper();
    error NotVault();
    error IsPaused();
    error ZeroAmount();
    error ZeroAddress();
    error ExceedsMaxSupply();
    error InsufficientBalance();
    error InvalidPercent();
 
    // ======== Modifiers ========
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

    // ======= Constructor ======= 
    /// @param _usdc  // usdc token address on Sepolia 
    /// @param _aUsdc  // aUsdc aToken address on Sepolia 
    /// @param _aavePool  // Aave V3 pool address on Sepolia
    /// @param _vault  // AI Vault contract address
    /// @param _keeper   // Keeper's address

    constructor (
        address _usdc, 
        address _aUsdc, 
        address _aavePool, 
        address _vault, 
        address _keeper) Ownable(msg.sender) {
            if(
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


    ////////////////////////////////////
    /////////// FUNCTIONS //////////////
    ////////////////////////////////////

    // ====== Keeper Functions =======

    /// @notice Supply deposited USDC to Aave to earn yields
    /// @dev Only the keeper can call these functions, 
    ///      the usdc must have already been deposited into the contract.
    /// @param amount How much usdc to be supplied to Aave

    function supplyToAave(uint256 amount) external onlyKeeper whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();

        // Guardrail: check to se if >90% isn't being supplied to Aave
        uint256 idleTracked = totalDepositedInContract - totalDeployed;
        uint256 totalAssets = totalDepositedInContract;

        // After Supply, the new total deployed should be, and it musn't exceed the 90% mark placed 
        uint256 newDeployed = totalDeployed + amount;

        if (totalAssets > 0 &&
            (newDeployed * 100) / totalAssets > maxSupplyPercentage
        ) revert ExceedsMaxSupply();

        if (amount > idleTracked) revert InsufficientBalance();

        // Approve Aave Pool to pull our USDC
        usdc.safeIncreaseAllowance(address(aavePool), amount);

        // Supply to Aave — we receive aUSDC in return
        aavePool.supply(address(usdc), amount, address(this), 0);

        // Update accounting
        totalDeployed += amount;

        emit SuppliedToAave(amount, totalDeployed);
    }

    function receiveFromVault(uint256 amount) external onlyVault {
        totalReceived += amount;
    }
}