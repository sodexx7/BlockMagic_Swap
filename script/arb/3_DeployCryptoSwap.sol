// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/src/Script.sol";
import "src/CryptoSwap.sol";

contract DeployCryptoSwap is Script {
    function run() external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Parameters for the constructor of CryptoSwap
        // address settledStableToken = vm.envAddress("SETTLED_STABLE_TOKEN");
        address settledStableToken = address(0xeA67D3A83b9Fd211410682Bc3A0De11e29748610); // mock usdc
        
        // address priceFeedsAddress = vm.envAddress("PRICE_FEEDS_ADDRESS");
        address priceFeedsAddress = address(0x64D392194d45727c061684c394035CfF240480D1);

        // address YieldStrategiesAddress = vm.envAddress("YIELD_STRATEGYS_ADDRESS");
        address YieldStrategiesAddress = address(0xfa12B0c5Af2D60a4748F4038163854E8FaAd26d8);

        // Example notional IDs and values for the constructor
        uint8[] memory notionalIds = new uint8[](5);
        uint256[] memory notionalValues = new uint256[](5);
        notionalIds[0] = 1;
        notionalIds[1] = 2;
        notionalIds[2] = 3;
        notionalIds[3] = 4;
        notionalIds[4] = 5;
        // for arb test, add 1$,5$,10$
        notionalValues[0] = 1;
        notionalValues[1] = 5;
        notionalValues[2] = 10;
        notionalValues[3] = 1000;
        notionalValues[4] = 3000;

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

        vm.stopBroadcast();
    }
}
