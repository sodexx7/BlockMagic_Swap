// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "src/YieldStrategies.sol";

contract DeployYieldStrategies is Script {
    function run() external {
        // Define yield IDs and their corresponding addresses
        uint8[] memory yieldIds = new uint8[](2);
        address[] memory yieldAddresses = new address[](2);

        // Example yield IDs and addresses
        yieldIds[0] = 1; // Example yield ID
        yieldIds[1] = 2; // Example yield ID

        // Mock addresses for example (use actual addresses of yield strategy contracts)
        yieldAddresses[0] = address(0x123); // Example address
        yieldAddresses[1] = address(0x456); // Example address

        // Address of the stable token used in the YieldStrategies contract
        address settledStableToken = address(0x789); // Example stable token address

        // Deploy the YieldStrategies contract
        YieldStrategies yieldStrategies = new YieldStrategies(
            yieldIds,
            yieldAddresses,
            settledStableToken
        );

        // Log the address of the deployed contract
        console.log("YieldStrategies deployed to:", address(yieldStrategies));
    }
}
