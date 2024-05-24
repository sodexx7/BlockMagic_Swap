// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";
import { CryptoSwap } from "../src/CryptoSwap.sol";
import { PriceFeeds } from "../src/PriceFeeds.sol";
import { YieldStrategies } from "../src/YieldStrategies.sol";

import "../src/test/mocks/MockV3Aggregator.sol";
import "../src/test/mocks/MockERC20.sol";
import "../src/test/mocks/MockyvUSDC.sol";
import "../src/test/mocks/MockPriceFeeds.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CryptoSwap_withdrawTest is Test {
    CryptoSwap internal cryptoSwap;
    address internal ethTokenAddress;
    address internal btcTokenAddress;
    address internal swaper = address(0x991);
    address internal pairer = address(0x992);
    address ethPriceFeedAddress;
    address btcPriceFeedAddress;
    MockERC20 internal usdcContract;
    MockyvUSDC internal yvUSDCContract;
    address internal yvUSDCContractAddress;

    MockPriceFeeds internal priceFeeds;
    YieldStrategies internal yieldStrategies;

    uint8[] yieldIds;
    int256 ETHInitialPrice = 1000e8;
    int256 BTCInitialPrice = 60_000e8;

    event NoProfitWhileSettle(uint256 indexed legId, address indexed swaper, address indexed pairer);
    event BatchOpenSwap(
        address indexed swaper,
        address indexed tokenAddress,
        uint64[] legIds,
        uint256 totoalAmountOfSettleToken,
        uint8 notionalCount,
        uint256 startDate
    );

    /// @dev A function invoked before each test case is run.
    /**
     * Initial price for ETH/USD: 1000, BTC/USD: 60_000, whose decimals are 8
     */
    function setUp() public virtual {
        // default caller: 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, the ower of cryptoSwap,USDC
        // priceFeed for ETH/USD, BTC/USD, mock USDC, ETH, BTC
        ethPriceFeedAddress = mockPriceFeed("ETH/USD", ETHInitialPrice); //ETH
        btcPriceFeedAddress = mockPriceFeed("BTC/USD", BTCInitialPrice); //BTC
        usdcContract = new MockERC20("USDC", "USDC", 6); // USDC default value on arb is 6
        ethTokenAddress = address(new MockERC20("ETH", "ETH", 18));
        btcTokenAddress = address(new MockERC20("WBTC", "WBTC", 8)); // WBTC default value on arb is 8
        yvUSDCContract = new MockyvUSDC("YvUSDC", "YvUSDC", 6, address(usdcContract)); // mock yearn yvUSDC

        // create priceFeeds contract TODO ownership transfer
        priceFeeds = new MockPriceFeeds(ethTokenAddress, ethPriceFeedAddress);
        priceFeeds.addPriceFeed(btcTokenAddress, btcPriceFeedAddress);

        // Mock history price
        setHistoryPriceForTest(ethTokenAddress, block.timestamp, 1000e8); //ETH
        setHistoryPriceForTest(btcTokenAddress, block.timestamp, 60_000e8); //BTC

        // create YieldStrategies contract
        yieldIds = new uint8[](1);
        yieldIds[0] = 1; // yearn
        address[] memory yieldAddress = new address[](1);
        yieldAddress[0] = address(yvUSDCContract);
        yieldStrategies = new YieldStrategies(yieldIds, yieldAddress, address(usdcContract));

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
    }

    // opener wins, withdraw
    /**
     * Test cases:
     *     1. typicail  call withdrawRouter
     *     2. First period not called, then will call withdraw
     *     3. check in different periods, the results is right
     */
    function test_OpenerWithdrawRouter() external {
        ///  opener  ///
        uint256 startDate = block.timestamp + 1 days;
        // set the price for ETH/USD, BTC/USD in StartDate
        setHistoryPriceForTest(ethTokenAddress, startDate, ETHInitialPrice); //ETH 1000e8
        setHistoryPriceForTest(btcTokenAddress, startDate, BTCInitialPrice); //BTC 60_000e8

        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        mintTestUSDC(swaper, swaperUsdcAmount);

        vm.startPrank(swaper);

        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount);
        cryptoSwap.openSwap({
            notionalId: 4,
            notionalCount: 1,
            legToken: ethTokenAddress,
            _startDate: uint64(startDate),
            _periodType: CryptoSwap.PeriodInterval.MONTHLY,
            _totalIntervals: 1,
            yieldId: yieldIds[0]
        }); // yieldId yearn

        vm.stopPrank();
        ///  opener  ///

        ///  pairer  ///
        uint64 originalLegId = 1;
        uint256 pairUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        usdcContract.mint(pairer, pairUsdcAmount);

        vm.startPrank(pairer);
        usdcContract.approve(address(cryptoSwap), pairUsdcAmount);
        cryptoSwap.pairSwap(originalLegId, pairUsdcAmount, btcTokenAddress, yieldIds[0]); // yieldId yearn
        vm.stopPrank();
        ///  pairer  ///

        vm.warp(startDate + 30 days);
        // the increased price of the eth > btc
        // mockupdatePriceFeed("ETH/USD", 1500e8); // 1000e8 => 1500e8
        // mockupdatePriceFeed("BTC/USD", 60_000e8); // doesn't change

        // price for ETH/USD increased, BTC/USD keep same
        // set the price for ETH/USD, BTC/USD in first fixDate
        uint256 updateDateForPrice = getUpdateDateBySwapDeanInfo(cryptoSwap.querySwapDealInfo(1));
        console2.log("updateDateForPrice", updateDateForPrice);
        setHistoryPriceForTest(ethTokenAddress, updateDateForPrice, ETHInitialPrice + 500e8); //ETH
        setHistoryPriceForTest(btcTokenAddress, updateDateForPrice, BTCInitialPrice); //BTC

        uint256 cryptoSwapUsdcAmountBefore = usdcContract.balanceOf(address(cryptoSwap));
        uint256 swaperUsdcAmountBefore = usdcContract.balanceOf(swaper);
        vm.prank(swaper);
        cryptoSwap.withdrawRouter(originalLegId);
        uint256 swaperUsdcAmountAfter = usdcContract.balanceOf(swaper);
        uint256 cryptoSwapUsdcAmountAfter = usdcContract.balanceOf(address(cryptoSwap));

        // 1000e8 => 1500e8,legToken increased 50%, bench amount of USDC:  10_000. profit 5000USDC
        assertEq(5000e6, swaperUsdcAmountAfter - swaperUsdcAmountBefore);
        // assertEq(5000e6, cryptoSwapUsdcAmountBefore - cryptoSwapUsdcAmountAfter); cryptoSwap don't store USDC
    }

    function test_OpenerWithdrawHistoryProfit() external {
        ///  opener  ///
        uint256 startDate = block.timestamp + 1 days;
        uint8 totalIntervals = 4;
        // set the price for ETH/USD, BTC/USD in StartDate
        setHistoryPriceForTest(ethTokenAddress, startDate, ETHInitialPrice); //ETH 1000e8
        setHistoryPriceForTest(btcTokenAddress, startDate, BTCInitialPrice); //BTC 60_000e8

        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        mintTestUSDC(swaper, swaperUsdcAmount);

        vm.startPrank(swaper);

        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount);
        cryptoSwap.openSwap({
            notionalId: 4,
            notionalCount: 1,
            legToken: ethTokenAddress,
            _startDate: uint64(startDate),
            _periodType: CryptoSwap.PeriodInterval.MONTHLY,
            _totalIntervals: totalIntervals,
            yieldId: yieldIds[0]
        }); // yieldId yearn

        vm.stopPrank();
        ///  opener  ///

        ///  pairer  ///
        uint64 originalLegId = 1;
        uint256 pairUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        usdcContract.mint(pairer, pairUsdcAmount);

        vm.startPrank(pairer);
        usdcContract.approve(address(cryptoSwap), pairUsdcAmount);
        cryptoSwap.pairSwap(originalLegId, pairUsdcAmount, btcTokenAddress, yieldIds[0]); // yieldId yearn
        vm.stopPrank();
        ///  pairer  ///

        vm.warp(startDate + 60 days); // Two months later, the first period has passed
        // the increased price of the eth > btc
        // mockupdatePriceFeed("ETH/USD", 1500e8); // 1000e8 => 1500e8
        // mockupdatePriceFeed("BTC/USD", 60_000e8); // doesn't change

        // price for ETH/USD increased, BTC/USD keep same
        // set the price for ETH/USD, BTC/USD in first fixDate
        CryptoSwap.SwapDealInfo memory SwapDealInfo = cryptoSwap.querySwapDealInfo(1);
        uint256 updateDateForPrice = getUpdateDateBySwapDeanInfo(SwapDealInfo);
        console2.log("updateDateForPrice", updateDateForPrice);
        setHistoryPriceForTest(ethTokenAddress, updateDateForPrice, ETHInitialPrice + 500e8); //ETH
        setHistoryPriceForTest(btcTokenAddress, updateDateForPrice, BTCInitialPrice); //BTC

        // set the price for ETH/USD, BTC/USD in second fixDate
        setHistoryPriceForTest(
            ethTokenAddress, updateDateForPrice + SwapDealInfo.periodInterval, ETHInitialPrice + 500e8
        ); //ETH
        setHistoryPriceForTest(btcTokenAddress, updateDateForPrice + SwapDealInfo.periodInterval, BTCInitialPrice); //BTC

        uint256 cryptoSwapUsdcAmountBefore = usdcContract.balanceOf(address(cryptoSwap));
        uint256 swaperUsdcAmountBefore = usdcContract.balanceOf(swaper);
        console2.log("swaperUsdcAmountBefore", swaperUsdcAmountBefore);
        vm.prank(swaper);
        cryptoSwap.withdrawRouter(originalLegId);
        uint256 swaperUsdcAmountAfter = usdcContract.balanceOf(swaper);
        console2.log("swaperUsdcAmountAfter", swaperUsdcAmountAfter);
        uint256 cryptoSwapUsdcAmountAfter = usdcContract.balanceOf(address(cryptoSwap));

        // 1000e8 => 1500e8,legToken increased 50%, bench amount of USDC:  10_000. profit 5000USDC
        assertEq(5000e6, swaperUsdcAmountAfter - swaperUsdcAmountBefore);
        // assertEq(5000e6, cryptoSwapUsdcAmountBefore - cryptoSwapUsdcAmountAfter); cryptoSwap don't store USDC
    }

    /**
     * Mock the token's price based on USD.
     *     1. current test Equities:  ETH/USD, 2. BTC/USD
     *     2. decimals = 8(chainlink arb default value)
     *     3. price type is int256, compatible with chainlink
     *
     *
     */
    function mockPriceFeed(string memory description, int256 price) internal returns (address priceFeed) {
        uint8 DECIMALS = 8;
        return address(new MockV3Aggregator(DECIMALS, price, description));
    }
    //  Mock the token's price has changed

    function mockupdatePriceFeed(string memory description, int256 price) internal returns (address priceFeed) {
        if (keccak256(abi.encodePacked("ETH/USD")) == keccak256(abi.encodePacked(description))) {
            MockV3Aggregator(ethPriceFeedAddress).updateAnswer(price);
        } else if (keccak256(abi.encodePacked("BTC/USD")) == keccak256(abi.encodePacked(description))) {
            MockV3Aggregator(btcPriceFeedAddress).updateAnswer(price);
        } else {
            //
        }
    }

    function showLegInfo(CryptoSwap.Leg memory result) internal view {
        console2.log(
            "benchPrice:",
            uint256(result.benchPrice) / 10 ** priceFeeds.priceFeedDecimals(result.tokenAddress),
            priceFeeds.description(result.tokenAddress)
        );
        console2.log("balance:", uint256(result.balance) / 10 ** usdcContract.decimals(), usdcContract.symbol());
        console2.log("pairLegId:", result.pairLegId);
        // console2.log("startDate:", result.startDate);
        // console2.log("status:", uint256(result.status));
        console2.log("swaper:", result.swaper);
        console2.log("tokenAddress:", result.tokenAddress, ERC20(result.tokenAddress).symbol());
    }

    function mintTestUSDC(address receiver, uint256 amount) internal {
        // default caller: 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, the ower of cryptoSwap,USDC
        vm.startPrank(address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496));
        usdcContract.mint(receiver, amount);
        vm.stopPrank();
    }

    function setHistoryPriceForTest(address tokenAddress, uint256 timestamp, int256 price) internal {
        // console2.log("setHistoryPriceForTest");
        // console2.log("tokenAddress", tokenAddress);
        // console2.log("timestamp", timestamp);
        // console2.log("price", price);
        priceFeeds.setHistoryPrice(tokenAddress, timestamp, price);
    }

    function getUpdateDateBySwapDeanInfo(CryptoSwap.SwapDealInfo memory swapDealInfo)
        internal
        returns (uint256 timestamp)
    {
        console2.log("block.timestamp", block.timestamp);
        console2.log("swapDealInfo.startDate", swapDealInfo.startDate);
        console2.log("swapDealInfo.periodInterval", swapDealInfo.periodInterval);

        uint256 thPeriods = (block.timestamp - swapDealInfo.startDate) / swapDealInfo.periodInterval;
        timestamp = swapDealInfo.startDate + swapDealInfo.periodInterval * thPeriods;
        console2.log("updateDate", timestamp);
    }
}
