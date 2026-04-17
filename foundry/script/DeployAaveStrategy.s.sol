// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AaveStrategy} from "../src/AaveV3Strategy.sol";

contract DeployAaveStrategy is Script {
    address constant SEPOLIA_USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address constant SEPOLIA_AUSDC = 0x16dA4541aD1807f4443d92D26044C1147406EB80;
    address constant SEPOLIA_AAVE_POOL =
        0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;

    function run() external returns (AaveStrategy) {
        address keeper;
        AaveStrategy strategy;

        address deployerKey = vm.envUint("PRIVATE_KEY");
        address vaultAddress = vm.envAddress("Vault_Address");
        address mockAddress = vm.envAddress("Mock_Address");
        address deployer = vm.addr(deployerKey);

        keeper = deployer;

        vm.startBroadcast(deployerKey);
        strategy = new AaveStrategy(
            SEPOLIA_USDC,
            SEPOLIA_AUSDC,
            SEPOLIA_AAVE_POOL,
            vaultAddress,
            keeper
        )
        vm.stopBroadcast();

         console.log("========================================");
        console.log("AaveV3Strategy deployed");
        console.log("========================================");
        console.log("Strategy address:", address(strategy));
        console.log("Vault (linked):", vaultAddress);
        console.log("Keeper:", keeper);
        console.log("USDC:", SEPOLIA_USDC);
        console.log("aUSDC:", SEPOLIA_AUSDC);
        console.log("Aave Pool:", SEPOLIA_AAVE_POOL);
        console.log("========================================");
        console.log("");
        console.log("NEXT: Run SetupVault script to wire them together");
    }
}
