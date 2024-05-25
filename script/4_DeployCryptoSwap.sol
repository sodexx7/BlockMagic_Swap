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
        address settledStableToken = address(0xD1dFe211482A70165960dBdEF6077739a2483acf); // mock usdc

        // address priceFeedsAddress = vm.envAddress("PRICE_FEEDS_ADDRESS");
        address priceFeedsAddress = address(0x7A517083bbD52c59558fF9530C3f683840B60aCb); //Mock price Feeds

        // address YieldStrategiesAddress = vm.envAddress("YIELD_STRATEGYS_ADDRESS");
        address YieldStrategiesAddress = address(0x2bA9Ffe137d71b6f6e65f1Ca89C5bC5F42119bF0);

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
        CryptoSwap cryptoSwap =
            new CryptoSwap(settledStableToken, priceFeedsAddress, YieldStrategiesAddress, notionalIds, notionalValues);

        // Log the address of the deployed contract
        console.log("CryptoSwap deployed to:", address(cryptoSwap));

        vm.stopBroadcast();
    }
}
