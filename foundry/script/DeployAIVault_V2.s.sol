// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AIVault} from "../src/AIVaultV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployAIVaultV2 is Script {
    AIVault public aiVault;
    address constant SEPOLIA_USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;

    function run() external returns (AIVault vault) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        aiVault = new AIVault(IERC20(SEPOLIA_USDC));
        vm.stopBroadcast();

        console.log("========================================");
        console.log("AIVault V2 deployed");
        console.log("========================================");
        console.log("Vault address:", address(vault));
        console.log("Underlying (USDC):", SEPOLIA_USDC);
        // console.log("Owner:", vault.owner());
        console.log("========================================");
        return aiVault;
    }
}
