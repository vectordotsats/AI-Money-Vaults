// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {AIVault} from "../src/AIVault.sol";
import {MockUSDC} from "../test//mocks/MockUSDC.sol";

contract DeployAIVault is Script {
    AIVault public aiVault;
    MockUSDC public usdc;

    function run() public returns (AIVault, MockUSDC) {
        vm.startBroadcast();
        usdc = new MockUSDC();
        aiVault = new AIVault(usdc);
        vm.stopBroadcast();

        return (aiVault, usdc);
    }
}
