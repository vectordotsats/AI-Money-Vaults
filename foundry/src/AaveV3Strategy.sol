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
    /// @param to  who recieves the withdrawn tokens
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
    uint256 public totalDeployed; // How much usdc has been deployed
    uint256 public totalDepositedInContract; // total USDC deposited into the contract

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
    error WrongAddress();
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

    // ====== Keeper Function (offensive — deploy capital) =======

    /// @notice Supply deposited USDC to Aave to earn yields
    /// @dev Only the keeper can call this function, 
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

    // ====== Vault Function (defensive — return capital) =======

    /// @notice Withrawing USDC from Aave to vault. 
    /// @dev Only the vault can call this function, thisis triggered
    ///      when user wants to withraw USDC and there's not enough balance in the vault.
    /// @param amount How much usdc the vault need back

    function withdrawToVault(uint256 amount) external onlyVault nonReentrant {
        if (amount == 0) revert ZeroAmount();

        // check if there's sufficient usdc in the vault before going to aave
        uint256 idleBalance = totalDepositedInContract - totalDeployed;

        uint256 amountToBeWithdrawn = 0;
        if(amount > idleBalance) {
            amountToBeWithdrawn = amount - idleBalance; // how much we need to withdraw from Aave

            // Make sure we don't try to withdraw more than what we have deployed
            if (amountToBeWithdrawn > totalDeployed) {
                amountToBeWithdrawn = totalDeployed;
            }

            uint256 actualWithdrawn = aavePool.withdraw(
                address(usdc), 
                amountToBeWithdrawn, 
                address(this)
            );

            totalDeployed = totalDeployed > actualWithdrawn
                ? totalDeployed - actualWithdrawn
                : 0;
        }

        uint256 toSend = amount;
        uint256 available = totalDepositedInContract - totalDeployed;
        if (toSend > available) {
            toSend = available;
        }

        totalDepositedInContract -= toSend;
        usdc.safeTransfer(vault, toSend);

        emit WithdrawnFromAave(toSend, vault);
    }


    function receiveFromVault(uint256 amount) external onlyVault {
        totalReceived += amount;
    }
}


// ====== View Functions ======

/// @notice Get total USDC balance (deployed + idle)
/// @dev aTokens are tokens + accrued interest.
function totalStrategyAsset() external view returns (uint256) {
    uint256 idleBalance = totalDepositedInContract - totalDeployed;
    uint256 aTokenBalance = aUsdc.balanceOf(address(this));

    return idleBalance + aTokenBalance;    
}

/// @notice Get total interest accrued in USDC
function accruedYield() external view returns (uint256) {
    uint256 aTokenBalance = aUsdc.balanceOf(address(this));
    if (aTokenBalance <= totalDeployed) {
        return 0;
    }
    return aTokenBalance - totalDeployed;
}

///@notice Get current Usdc sitting in vault (idle balance)
function idleBalanceInVault() external view returns (uint256) {
    return totalDepositedInContract - totalDeployed;
}

// ====== Owner/Admin Functions ======

/// @notice Update keeper address
function updateKeeper(address _newKeeper) external onlyOwner {
    if (_newKeeper == address(0)) revert ZeroAddress();
    keeper = _neKeeper;
    emit KeeperUpdated(keeper, _newKeeper);
}

/// @notice Update vault address 
function updateVault(address _newVault) external onlyOwner {
    if (_newVault == address(0)) revert ZeroAddress();
    vault = _newVault;
    emit VaultUpdated(vault, _newVault);
}

/// @notice Update the new max supply percentage guardrail
/// @param _newPercent vaule between 0-100
function updateMaxSupplyPercentage(uint256 _newPercent) external onlyOwner {
    if (_newPercent > 100) revert invalidPercent();
    maxSupplyPercentage = _newPercent;
    emit MaxSupplyPercentUpdated(maxSupplyPercentage, _newPercent);
}

/// @notice pause and unpause the contract in case of emergency
function setPauseStatus(bool _paused) external onlyOwner {
    if (paused == _paused) revert IsPaused()
    paused = _paused;
    emit Paused(_paused);
}

/// @notice pause and unpause the contract in case of emergency 
function emergencyWithdrawAll() external onlyOwner nonReentrant {
    uint256 aTokenBalance = aUsdc.balanceOf(address(this));
    if (aTokenBalance == 0) revert ZeroAmount();

    uint256 withdrawn = aavePool.withdraw(
        address(usdc),
        type(uint256).max,
        address(this)
    );

    // Sending directly to vault so owner never touches funds
    totalDepositedInContract += withdrawn - totalDeployed;
    totalDeployed = 0;
    paused = true;

    usdc.safeTransfer(vault, withdrawn);

    emit EmergencyWithdraw(withdrawn);
    emit Paused(true);
}

/// @notice In the case we need to recover tokens sent to the contract by mistake.
/// @dev cannot rescue usdc and aUsdc - these are managed assets
function rescueToken(address token, uint256 amount) external onlyOwner {
    if (token == address(usdc) || token == address(aUsdc)) revert WrongAddress();
    IERC20(token).safeTransfer(owner(), amount);
}
