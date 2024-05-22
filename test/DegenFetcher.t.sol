// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { Test } from "forge-std/src/Test.sol";
// import "forge-std/src/StdUtils.sol";

import { console2 } from "forge-std/src/console2.sol";
import { DegenFetcherV2 } from "../src/DegenFetcherV2.sol";

contract DegenFetcherTest is Test {
    // the identifiers of the forks
    uint256 mainnetFork_60_983;
    uint256 mainnetFork_61_491;
    uint256 mainnetFork_15032024;
    uint256 mainnetFork_02052024;

    DegenFetcherV2 internal degenFetcherV2;
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
        mainnetFork_60_983 = vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 19_902_982 });

        mainnetFork_61_491 = vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 19_902_798 });

        // 15/03/2024 BTC: ~71_387 USD, ETH: ~3_888 USD
        mainnetFork_15032024 = vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 19_440_948 });

        // 02/05/2024 - BTC: ~58_253 USD, ETH: ~2_969 USD
        mainnetFork_02052024 = vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 19_785_026 });
    }

    //TODO two different prices(61_491 60_983) for BTC/USD queryed in 20240415 and 20240416
    // 61_491 (20240418 10:45)
    function test_getHistoricalPriceSame_60_983() external {
        vm.selectFork(mainnetFork_60_983);
        degenFetcherV2 = new DegenFetcherV2();

        int32 price =
            degenFetcherV2.fetchPriceDataForFeed(address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c), 1_715_499_660);

        console2.log("price: ", price);
        // assertEq(prices[0], 61_491);
        // assertEq(prices[0], 60_983);
        /**
         * 20240521
         *         lhRound:  110680464442257325429 rhRound:  110680464442257325430
         *         guessRound:  110680464442257325429
         *         Round picked:  110680464442257325430
         *         Timestamp:  1715500535
         *         price:  60710
         */
    }

    function test_getHistoricalPriceSame_61_491() external {
        vm.selectFork(mainnetFork_61_491);
        degenFetcherV2 = new DegenFetcherV2();

        int32 price =
            degenFetcherV2.fetchPriceDataForFeed(address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c), 1_715_499_660);
        // 1715502600

        console2.log("price: ", price);
        // assertEq(prices[0], 61_491);
        // assertEq(prices[0], 60_983);
        /**
         * 20240521
         *         logs:
         *         lhRound:  110680464442257325442 rhRound:  110680464442257325443
         *         guessRound:  110680464442257325443
         *         Round picked:  110680464442257325443
         *         Timestamp:  1715532947
         *         price:  61484
         */
    }

    function test_getHistoricalPriceSame1715532900_60_983() external {
        vm.selectFork(mainnetFork_60_983);
        degenFetcherV2 = new DegenFetcherV2();

        int32 price =
            degenFetcherV2.fetchPriceDataForFeed(address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c), 1_715_532_900);

        console2.log("price: ", price);
        // assertEq(prices[0], 61_491);
        // assertEq(prices[0], 60_983);

        /**
         * 20240521
         *         lhRound:  110680464442257325429 rhRound:  110680464442257325430
         *         guessRound:  110680464442257325429
         *         Round picked:  110680464442257325430
         *         Timestamp:  1715500535
         *         price:  60710
         */
    }

    function test_getHistoricalPriceSame1715532900_61_491() external {
        vm.selectFork(mainnetFork_61_491);
        degenFetcherV2 = new DegenFetcherV2();

        int32 price =
            degenFetcherV2.fetchPriceDataForFeed(address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c), 1_715_532_900);

        console2.log("price: ", price);
        // assertEq(prices[0], 61_491);
        // assertEq(prices[0], 60_983);
        /**
         * 20240521
         *         lhRound:  110680464442257325429 rhRound:  110680464442257325430
         *         guessRound:  110680464442257325430
         *         Round picked:  110680464442257325430
         *         Timestamp:  1715500535
         *         price:  60710
         */
    }

    function test_getHistoricalPrice15032024() external {
        vm.selectFork(mainnetFork_15032024);
        degenFetcherV2 = new DegenFetcherV2();

        int32 price =
            degenFetcherV2.fetchPriceDataForFeed(address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c), 1_704_067_200);

        console2.log("price: ", price);
        // assertEq(prices[0], 42_651);
        /**
         * 20240521
         *           lhRound:  110680464442257319086 rhRound:  110680464442257319087
         *           guessRound:  110680464442257319087
         *           Round picked:  110680464442257319086
         *           Timestamp:  1704066923
         *           price:  42214
         */
    }

    function test_getHistoricalPrice_02052024() external {
        vm.selectFork(mainnetFork_02052024);
        degenFetcherV2 = new DegenFetcherV2();

        int32 price =
            degenFetcherV2.fetchPriceDataForFeed(address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c), 1_704_067_200);

        console2.log("price: ", price);
        // assertEq(prices[0], 42_651);
        /**
         * 20240521
         *            Logs:
         *             lhRound:  110680464442257319086 rhRound:  110680464442257319087
         *             guessRound:  110680464442257319086
         *             Round picked:  110680464442257319086
         *             Timestamp:  1704066923
         *             price:  42214
         */
    }
}
