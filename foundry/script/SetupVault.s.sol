// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AIVault} from "../src/AIVault.sol";

/// @title Setup Vault — wire vault to strategy and set keeper
/// @notice Run AFTER both DeployAIVault and DeployAaveV3Strategy
/// @dev    Requires VAULT_ADDRESS and STRATEGY_ADDRESS in env
///         Run with:
///         forge script script/SetupVault.s.sol:SetupVault \
///           --rpc-url $SEPOLIA_RPC_URL \
///           --private-key $PRIVATE_KEY \
///           --broadcast
contract SetupVault is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS_V2");
        address strategyAddress = vm.envAddress("STRATEGY_ADDRESS");
        address deployer = vm.addr(deployerKey);

        AIVault vault = AIVault(vaultAddress);

        vm.startBroadcast(deployerKey);

        // Link strategy to vault
        vault.setStrategy(strategyAddress);

        // Set keeper (deployer for now)
        vault.setKeeper(deployer);

        vm.stopBroadcast();

        console.log("========================================");
        console.log("Setup complete");
        console.log("========================================");
        console.log("Vault:", vaultAddress);
        console.log("Strategy linked:", address(vault.strategy()));
        console.log("Keeper set:", vault.keeper());
        console.log("========================================");
    }
}
