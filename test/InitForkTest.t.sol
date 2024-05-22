// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { Test } from "forge-std/src/Test.sol";
import "forge-std/src/StdUtils.sol";

import { console2 } from "forge-std/src/console2.sol";
import { CryptoSwap } from "../src/CryptoSwap.sol";

import { PriceFeeds } from "../src/PriceFeeds.sol";
import { YieldStrategies } from "../src/YieldStrategies.sol";

import "../src/test/mocks/MockV3Aggregator.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract InitForkTest is Test {
    // the identifiers of the forks
    uint256 mainnetFork;
    uint256 mainnetFork2;
    uint256 mainnetFork_15032024;
    uint256 mainnetFork_02052024;
    uint256 mainnetFork_20032024;

    CryptoSwap internal cryptoSwap;
    address internal ethTokenAddress = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH Ethereum Mainnet
    address internal btcTokenAddress = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599); // WBTC Ethereum Mainnet
    address internal swaper = address(0x991);
    address internal pairer = address(0x992);
    address ethPriceFeedAddress = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // ETH/USD Ethereum Mainnet
    address btcPriceFeedAddress = address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c); // BTC/USD Ethereum Mainnet
    address usdcContractAddress = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC contract address on
        // Ethereum Mainnet
    address yearnYvUSDC = address(0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE); // ethereum mainnet yvUSDC
    ERC20 internal usdcContract;

    PriceFeeds internal priceFeeds;
    YieldStrategies internal yieldStrategies;

    uint8[] yieldIds;

    event NoProfitWhileSettle(uint256 indexed legId, address indexed swaper, address indexed pairer);
    event BatchOpenSwap(
        address indexed swaper,
        address indexed tokenAddress,
        uint64[] legIds,
        uint256 totoalAmountOfSettleToken,
        uint8 notionalCount,
        uint256 startDate
    );

    /**
     * Initial price for ETH/USD: 1000, BTC/USD: 60_000, whose decimals are 8
     */
    function setUp() public virtual {
        // 20/03/2024 BTC: ~61_930 USD, ETH: ~3_158 USD
        //            BTC: ~63109 00000000, ETH: 322766776503
        mainnetFork = vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 19_475_400 });

        // 24/04/2024 - BTC: ~65_548 USD, ETH: ~3_393 USD
        // mainnetFork = vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 19_505_400 }); // before 30 days

        // 14/05/2024 - BTC: ~62_619 USD, ETH: ~2_947 USD
        mainnetFork2 = vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 19_865_400 }); // around today

        // 15/03/2024 BTC: ~71_387 USD, ETH: ~3_888 USD
        //            BTC: 6806426901487 ETH:3370766673501

        mainnetFork_15032024 = vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 19_440_948 });

        // 02/05/2024 - BTC: ~58_253 USD, ETH: ~2_969 USD
        //            BTC: 5876778000000 ETH: 298507459000
        mainnetFork_02052024 = vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 19_785_026 });

        vm.selectFork(mainnetFork);
        usdcContract = ERC20(usdcContractAddress);

        // default caller: 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, the owner of cryptoSwap, USDC

        // create priceFeeds contract TODO ownership transfer
        priceFeeds = new PriceFeeds(ethTokenAddress, ethPriceFeedAddress);
        priceFeeds.addPriceFeed(btcTokenAddress, btcPriceFeedAddress);

        // create YieldStrategies contract
        yieldIds = new uint8[](1);
        yieldIds[0] = 1; // yearn
        address[] memory yieldAddress = new address[](1);
        yieldAddress[0] = yearnYvUSDC;
        yieldStrategies = new YieldStrategies(yieldIds, yieldAddress, usdcContractAddress);

        // user can select the notional value from the following options
        uint8[] memory notionalIds = new uint8[](4);
        notionalIds[0] = 1;
        notionalIds[1] = 2;
        notionalIds[2] = 3;
        notionalIds[3] = 4;
        uint256[] memory notionalValues = new uint256[](4);
        notionalValues[0] = 10e6;
        notionalValues[1] = 100e6;
        notionalValues[2] = 1000e6;
        notionalValues[3] = 10_000e6;

        // create cryptoSwap contract meanwhile priceFeed for ETH/USD, BTC/USD
        cryptoSwap = new CryptoSwap(
            address(usdcContract), address(priceFeeds), address(yieldStrategies), notionalIds, notionalValues
        );

        // showPriceAtBlockTime(ethTokenAddress,btcTokenAddress,mainnetFork); For show price at block number
    }

    function showLegInfo(CryptoSwap.Leg memory result) internal view {
        console2.log(
            "benchPrice:",
            uint256(result.benchPrice) / 10 ** priceFeeds.priceFeedDecimals(result.tokenAddress),
            priceFeeds.description(result.tokenAddress)
        );
        console2.log("balance:", uint256(result.balance) / 10 ** usdcContract.decimals(), usdcContract.symbol());
        console2.log("pairLegId:", result.pairLegId);
        console2.log("startDate:", result.startDate);
        console2.log("status:", uint256(result.status));
        console2.log("swaper:", result.swaper);
        console2.log("tokenAddress:", result.tokenAddress, ERC20(result.tokenAddress).symbol());
    }

    function showPriceAtBlockTime(address ethTokenAddress, address btcTokenAddress, uint256 forkVersion) internal {
        address[] memory persistantAddresses = new address[](5);
        persistantAddresses[0] = yearnYvUSDC;
        persistantAddresses[1] = address(cryptoSwap);
        persistantAddresses[2] = usdcContractAddress;
        persistantAddresses[3] = address(priceFeeds);
        persistantAddresses[4] = address(yieldStrategies);

        vm.makePersistent(persistantAddresses);
        vm.selectFork(forkVersion);
        int256 ethPrice = priceFeeds.getLatestPrice(ethTokenAddress);
        int256 btcPrice = priceFeeds.getLatestPrice(btcTokenAddress);
        uint256 blockNumer = block.number;
        console2.log("block number", blockNumer);
        console2.log("ethPrice", ethPrice);
        console2.log("btcPrice", btcPrice);

        // return mainnetFork
        persistantAddresses = new address[](5);
        persistantAddresses[0] = yearnYvUSDC;
        persistantAddresses[1] = address(cryptoSwap);
        persistantAddresses[2] = usdcContractAddress;
        persistantAddresses[3] = address(priceFeeds);
        persistantAddresses[4] = address(yieldStrategies);
        vm.selectFork(mainnetFork);
    }
}
