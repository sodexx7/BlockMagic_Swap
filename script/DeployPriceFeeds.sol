// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/src/Script.sol";
import "src/PriceFeeds.sol";

contract DeployPriceFeeds is Script {
    function run() external {
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address priceFeedAddress = vm.envAddress("PRICE_FEED_ADDRESS");

        // Deploy the PriceFeeds contract
        PriceFeeds priceFeeds = new PriceFeeds(tokenAddress, priceFeedAddress);

        // Output the address of the deployed contract
        console.log("PriceFeeds deployed to:", address(priceFeeds));
    }
}
