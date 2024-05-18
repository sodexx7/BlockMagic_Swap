// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { Test } from "forge-std/src/Test.sol";
// import "forge-std/src/StdUtils.sol";

import { console2 } from "forge-std/src/console2.sol";
import { DegenFetcher } from "../src/DegenFetcher.sol";

contract DegenFetcherTest is Test {
    // the identifiers of the forks
    uint256 mainnetFork;

    DegenFetcher internal degenFetcher;
    address internal ethTokenAddress = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH Ethereum Mainnet
    address internal btcTokenAddress = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599); // WBTC Ethereum Mainnet
    address internal swaper = address(0x991);
    address internal pairer = address(0x992);
    address ethPriceFeedAddress = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // ETH/USD Ethereum Mainnet
    address btcPriceFeedAddress = address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c); // BTC/USD Ethereum Mainnet
    address usdcContractAddress = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC contract address on

    /// @dev A function invoked before each test case is run.
    /**
     * Initial price for ETH/USD: 1000, BTC/USD: 60_000, whose decimals are 8
     */
    function setUp() public virtual {
        mainnetFork = vm.createFork({ urlOrAlias: "mainnet" });
        vm.selectFork(mainnetFork);

        degenFetcher = new DegenFetcher();
    }

    //TODO two different prices(61_491 60983) for BTC/USD queryed in 20240415 and 20240416
    // 61_491 (20240418 10:45)
    function test_getHistoricalPrice() external {
        int32[] memory prices = degenFetcher.fetchPriceDataForFeed(
            address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c), 1_715_499_660, uint80(1), uint256(2)
        );
        console2.log("prices", prices[0]);
        // assertEq(prices[0], 61_491);
    }
}
