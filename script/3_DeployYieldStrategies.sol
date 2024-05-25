// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/src/Script.sol";
import "src/YieldStrategies.sol";

contract DeployYieldStrategies is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Define yield IDs and their corresponding addresses
        uint8[] memory yieldIds = new uint8[](1);
        address[] memory yieldAddresses = new address[](1);

        // Example yield IDs and addresses
        yieldIds[0] = 1; // Example yield ID
        // yieldIds[1] = 2; // Example yield ID

        // Mock addresses for example (use actual addresses of yield strategy contracts)
        yieldAddresses[0] = address(0xef4e8d48B1a246ce84198f6bB153c17827Ff2AB2); // mock yusdc
        // yieldAddresses[1] = address(0x456); // Example address

        // Address of the stable token used in the YieldStrategies contract
        address settledStableToken = address(0xD1dFe211482A70165960dBdEF6077739a2483acf); // mock usdc

        // Deploy the YieldStrategies contract
        YieldStrategies yieldStrategies = new YieldStrategies(yieldIds, yieldAddresses, settledStableToken);

        // Log the address of the deployed contract
        console.log("YieldStrategies deployed to:", address(yieldStrategies));

        vm.stopBroadcast();
    }
}
