// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/src/Script.sol";
import "src/CryptoSwap.sol";

contract DeployCryptoSwap is Script {
    function run() external {
        // Parameters for the constructor of CryptoSwap
        address settledStableToken = vm.envAddress("SETTLED_STABLE_TOKEN");
        address priceFeedsAddress = vm.envAddress("PRICE_FEEDS_ADDRESS");
        address YieldStrategiesAddress = vm.envAddress("YIELD_STRATEGYS_ADDRESS");

        // Example notional IDs and values for the constructor
        uint8[] memory notionalIds = new uint8[](3);
        uint256[] memory notionalValues = new uint256[](3);
        notionalIds[0] = 1;
        notionalIds[1] = 2;
        notionalIds[2] = 3;
        notionalValues[0] = 100;
        notionalValues[1] = 1000;
        notionalValues[2] = 3000;

        // Deploy the contract
        CryptoSwap cryptoSwap = new CryptoSwap(
            settledStableToken,
            priceFeedsAddress,
            YieldStrategiesAddress,
            notionalIds,
            notionalValues
        );

        // Log the address of the deployed contract
        console.log("CryptoSwap deployed to:", address(cryptoSwap));
    }
}
