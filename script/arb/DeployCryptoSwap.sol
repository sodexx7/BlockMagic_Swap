// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/src/Script.sol";
import "src/PriceFeeds.sol";
import "src/YieldStrategies.sol";
import "src/CryptoSwap.sol";

contract DeployPriceFeeds is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ////////////////////////////////////////  1. Deploy priceFeeds contract  ////////////////////////////////////////
        // 0xd0C7101eACbB49F3deCcCc166d238410D6D46d57  WBTC / USD price feed
        // 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612 ETH / USD  price feed
        // ETH 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
        // WBTC 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f
        address ethTokenAddress = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        address ethPriceFeedAddress = address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);

        address wbtcTokenAddress = address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
        address wbtcPriceFeedAddress = address(0xd0C7101eACbB49F3deCcCc166d238410D6D46d57);

        // Deploy the PriceFeeds contract
        PriceFeeds priceFeeds = new PriceFeeds(ethTokenAddress, ethPriceFeedAddress);
        priceFeeds.addPriceFeed(wbtcTokenAddress, wbtcPriceFeedAddress);
        console.log("PriceFeeds deployed to:", address(priceFeeds));

        //////////////////////////////////////// 2. Deploy priceFeeds contract ////////////////////////////////////////
        // Define yield IDs and their corresponding addresses
        uint8[] memory yieldIds = new uint8[](1);
        address[] memory yieldAddresses = new address[](1);

        // Example yield IDs and addresses
        yieldIds[0] = 1; //  yield ID

        // Mock addresses for example (use actual addresses of yield strategy contracts)
        yieldAddresses[0] = address(0x6FAF8b7fFeE3306EfcFc2BA9Fec912b4d49834C1); // https://arbiscan.io/address/0x6FAF8b7fFeE3306EfcFc2BA9Fec912b4d49834C1#code

        // Address of the stable token used in the YieldStrategies contract
        address settledStableToken = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831); // https://arbiscan.io/token/0xaf88d065e77c8cc2239327c5edb3a432268e5831?a=0x6FAF8b7fFeE3306EfcFc2BA9Fec912b4d49834C1

        // Deploy the YieldStrategies contract
        YieldStrategies yieldStrategies = new YieldStrategies(yieldIds, yieldAddresses, settledStableToken);
        console.log("YieldStrategies deployed to:", address(yieldStrategies));

        //////////////////////////////////////// 3. Deploy cryptoSwap contract ////////////////////////////////////////
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
            settledStableToken, address(priceFeeds), address(yieldStrategies), notionalIds, notionalValues
        );
        console.log("cryptoSwap deployed to:", address(cryptoSwap));
        vm.stopBroadcast();
    }
}
