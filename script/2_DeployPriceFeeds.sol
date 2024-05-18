// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/src/Script.sol";
import "src/PriceFeeds.sol";

contract DeployPriceFeeds is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address ethTokenAddress = address(0xFcF4a6b4Ca4CB125A69a2878628e4C078fE1a0c8);

        // 0x694AA1769357215DE4FAC081bf1f309aDC325306 ETH / USD  SEPOLIA
        // 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43 BTC / USD  SEPOLIA
        // vm.envAddress("PRICE_FEED_ADDRESS");
        address ethPriceFeedAddress = address(0x694AA1769357215DE4FAC081bf1f309aDC325306);

        // Deploy the PriceFeeds contract
        PriceFeeds priceFeeds = new PriceFeeds(ethTokenAddress, ethPriceFeedAddress);

        // add btc price feed
        // Output the address of the deployed contract
        console.log("PriceFeeds deployed to:", address(priceFeeds));

        vm.stopBroadcast();
    }
}
