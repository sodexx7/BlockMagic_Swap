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

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CryptoSwapTest is Test {
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

    /// @dev A function invoked before each test case is run.
    /**
     * Initial price for ETH/USD: 1000, BTC/USD: 60_000, whose decimals are 8
     */
    function setUp() public virtual {
        // default caller: 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, the ower of cryptoSwap,USDC
        // priceFeed for ETH/USD, BTC/USD, mock USDC, ETH, BTC
        ethPriceFeedAddress = mockPriceFeed("ETH/USD", 1000e8); //ETH
        btcPriceFeedAddress = mockPriceFeed("BTC/USD", 60_000e8); //BTC
        usdcContract = new MockERC20("USDC", "USDC", 6); // USDC default value on arb is 6
        ethTokenAddress = address(new MockERC20("ETH", "ETH", 18));
        btcTokenAddress = address(new MockERC20("WBTC", "WBTC", 8)); // WBTC default value on arb is 8
        yvUSDCContract = new MockyvUSDC("YvUSDC", "YvUSDC", 6, address(usdcContract)); // mock yearn yvUSDC

        // create priceFeeds contract TODO ownership transfer
        priceFeeds = new PriceFeeds(ethTokenAddress, ethPriceFeedAddress);
        priceFeeds.addPriceFeed(btcTokenAddress, btcPriceFeedAddress);

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

    /// @dev Basic test. Run it with `forge test -vvv` to see the console log.
    function test_openSwap() external {
        uint256 startDate = block.timestamp + 1 days;
        // TODO: swapterUsdcAmount should not be total notional amount, for example divided by 10
        // uint256 swaperUsdcAmount = (cryptoSwap.notionalValueOptions(4)) / 10; // 10_000e6 10,000 USDC
        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        mintTestUSDC(swaper, swaperUsdcAmount);

        vm.startPrank(swaper);
        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount);
        cryptoSwap.openSwap(4, 1, ethTokenAddress, uint64(startDate), yieldIds[0]); // yieldId yearn
        vm.stopPrank();

        // check the corresponding leg info
        CryptoSwap.Leg memory result = cryptoSwap.queryLeg(1);
        showLegInfo(result);

        assertEq(result.benchPrice, 0); // only when pairSwap, the benchPrice will be updated, if front-end need to show
            // the benchPrice, should directly get the price
        assertEq(result.pairLegId, 0);
        assertEq(result.startDate, startDate);
        assertEq(uint256(result.status), uint256(CryptoSwap.Status.Open));
        assertEq(result.swaper, swaper);
        assertEq(result.tokenAddress, ethTokenAddress);
    }

    function test_openBatchSwap() external {
        uint256 startDate = block.timestamp + 1 days;
        uint8 notionalCount = 5;
        // TODO: swapterUsdcAmount should not be total notional amount, for example divided by 10
        // uint256 swaperUsdcAmount = (cryptoSwap.notionalValueOptions(4) * notionalCount) / 10; // 10_000e6 10,000 USDC
        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4) * notionalCount; // 50_000e6 50,000 USDC
        mintTestUSDC(swaper, swaperUsdcAmount);

        vm.startPrank(swaper);
        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount);
        uint64[] memory legIds = new uint64[](5);
        legIds[0] = uint64(1);
        legIds[1] = uint64(2);
        legIds[2] = uint64(3);
        legIds[3] = uint64(4);
        legIds[4] = uint64(5);
        emit BatchOpenSwap(swaper, ethTokenAddress, legIds, swaperUsdcAmount, notionalCount, startDate);
        cryptoSwap.openSwap(4, notionalCount, ethTokenAddress, uint64(startDate), yieldIds[0]); // yieldId yearn
        vm.stopPrank();

        for (uint8 i = 1; i <= notionalCount; i++) {
            CryptoSwap.Leg memory result = cryptoSwap.queryLeg(i);
            showLegInfo(result);
            assertEq(result.benchPrice, 0);
            assertEq(result.pairLegId, 0);
            assertEq(result.startDate, startDate);
            assertEq(uint256(result.status), uint256(CryptoSwap.Status.Open));
            assertEq(result.swaper, swaper);
            assertEq(result.tokenAddress, ethTokenAddress);
        }
    }

    function test_pairSwap() external {
        uint256 startDate = block.timestamp + 1 days;
        // TODO: swapterUsdcAmount should not be total notional amount, for example divided by 10
        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        mintTestUSDC(swaper, swaperUsdcAmount);

        vm.startPrank(swaper);
        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount);
        cryptoSwap.openSwap(4, 1, ethTokenAddress, uint64(startDate), yieldIds[0]); // yieldId yearn
        vm.stopPrank();

        uint64 originalLegId = 1;
        uint256 pairUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        mintTestUSDC(pairer, pairUsdcAmount);

        vm.startPrank(pairer);
        usdcContract.approve(address(cryptoSwap), pairUsdcAmount);
        cryptoSwap.pairSwap(originalLegId, pairUsdcAmount, btcTokenAddress, yieldIds[0]); // yieldId yearn
        vm.stopPrank();

        CryptoSwap.Leg memory originalLeg = cryptoSwap.queryLeg(1);
        CryptoSwap.Leg memory pairLeg = cryptoSwap.queryLeg(originalLeg.pairLegId);
        showLegInfo(pairLeg);

        (
            ,
            /* uint80 roundID */
            int256 price,
            ,
            ,
        ) = AggregatorV3Interface(btcPriceFeedAddress).latestRoundData();
        assertEq(pairLeg.benchPrice, price);
        assertEq(uint256(pairLeg.balance), pairUsdcAmount);
        assertEq(pairLeg.pairLegId, originalLegId);
        assertEq(pairLeg.startDate, startDate);
        assertEq(uint256(pairLeg.status), uint256(CryptoSwap.Status.Active));
        assertEq(uint256(originalLeg.status), uint256(CryptoSwap.Status.Active));
        assertEq(pairLeg.swaper, pairer);
        assertEq(pairLeg.tokenAddress, btcTokenAddress);
    }

    function test_settleEqual() external {
        ///  opener  ///
        uint256 startDate = block.timestamp + 1 days;
        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        mintTestUSDC(swaper, swaperUsdcAmount);

        vm.startPrank(swaper);
        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount);
        cryptoSwap.openSwap(4, 1, ethTokenAddress, uint64(startDate), yieldIds[0]); // yieldId yearn
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
        // price for ETH/USD, BTC/USD hasn't  changed
        vm.expectEmit(true, true, true, true);
        emit NoProfitWhileSettle(1, swaper, pairer);
        cryptoSwap.settleSwap(1);
    }

    function test_settleOpenerWin() external {
        ///  opener  ///
        uint256 startDate = block.timestamp + 1 days;
        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        mintTestUSDC(swaper, swaperUsdcAmount);

        vm.startPrank(swaper);
        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount);
        cryptoSwap.openSwap(4, 1, ethTokenAddress, uint64(startDate), yieldIds[0]); // yieldId yearn
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
        mockupdatePriceFeed("ETH/USD", 1500e8); // 1000e8 => 1500e8
        mockupdatePriceFeed("BTC/USD", 60_000e8); // doesn't change

        uint256 cryptoSwapUsdcAmountBefore = usdcContract.balanceOf(address(cryptoSwap));
        uint256 swaperUsdcAmountBefore = usdcContract.balanceOf(swaper);
        cryptoSwap.settleSwap(1);
        uint256 swaperUsdcAmountAfter = usdcContract.balanceOf(swaper);
        uint256 cryptoSwapUsdcAmountAfter = usdcContract.balanceOf(address(cryptoSwap));

        // 1000e8 => 1500e8,legToken increased 50%, bench amount of USDC:  10_000. profit 5000USDC
        assertEq(5000e6, swaperUsdcAmountAfter - swaperUsdcAmountBefore);
        // assertEq(5000e6, cryptoSwapUsdcAmountBefore - cryptoSwapUsdcAmountAfter); cryptoSwap don't store USDC
    }

    function test_settlePairerWin() external {
        ///  opener  ///
        uint256 startDate = block.timestamp + 1 days;
        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        mintTestUSDC(swaper, swaperUsdcAmount);

        vm.startPrank(swaper);
        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount);
        cryptoSwap.openSwap(4, 1, ethTokenAddress, uint64(startDate), yieldIds[0]); // yieldId yearn
        vm.stopPrank();
        ///  opener  ///

        ///  pairer  ///
        uint64 originalLegId = 1;
        uint256 pairUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        mintTestUSDC(pairer, pairUsdcAmount);
        uint256 pairTokenNotional = 1 * 10 ** ERC20(btcTokenAddress).decimals(); // 1 WBTC

        vm.startPrank(pairer);
        usdcContract.approve(address(cryptoSwap), pairUsdcAmount);
        cryptoSwap.pairSwap(originalLegId, pairUsdcAmount, btcTokenAddress, yieldIds[0]); // yieldId yearn
        vm.stopPrank();
        ///  pairer  ///

        // after 30 days
        vm.warp(startDate + 30 days);
        // the increased price of the eth > btc
        mockupdatePriceFeed("ETH/USD", 1000e8); // price doesn't change
        mockupdatePriceFeed("BTC/USD", 60_300e8); // 60_000e8 => 60_300e8

        uint256 cryptoSwapUsdcAmountBefore = usdcContract.balanceOf(address(cryptoSwap));
        uint256 pairerUsdcAmountBefore = usdcContract.balanceOf(pairer);
        cryptoSwap.settleSwap(1);
        uint256 pairerUsdcAmountAfter = usdcContract.balanceOf(pairer);
        uint256 cryptoSwapUsdcAmountAfter = usdcContract.balanceOf(address(cryptoSwap));

        // 60_000e8 => 60_300e8, pairlegToken increased 0.005 bench amount of USDC:  10_000. profit 50USDC
        assertEq(50e6, pairerUsdcAmountAfter - pairerUsdcAmountBefore);
        // assertEq(50e6, cryptoSwapUsdcAmountBefore - cryptoSwapUsdcAmountAfter); cryptoSwap don't store USDC
    }

    // /**
    // case 1
    // 1.1. startDate: opener: 1 BTC, actual value: 10,000; pairer: 10,000 USDC

    // 1.2. endDate: BTC increase: 5%. Now BTC market value: 10,500, USDC price don't change. the relative increase
    // rates
    // of the BTC comparing to the USDC: 5%.

    // - 5% \* 10,000 = 500 USDC to BTC depositer.

    //   1.3. updating opener: 1 BTC, actual value: 10,500; pairer: 9,500 USDC

    // case 2
    // 2.1 startDate: opener: 1 BTC, actual value: 10,000; pairer: 5,000 USDC

    // 2.2 endDate: BTC increase: 5%. Now BTC market value: 10,500, USDC price don't change.

    // - DealEngine: 5% \* 5,000 = 250 USDC to BTC depositer.

    // 2.3. updating opener: 1 BTC, actual value: 10,500; pairer: 4,750 USDC
    // */
    function test_SettleCase1() external {
        mockupdatePriceFeed("ETH/USD", 1000e8);
        mockupdatePriceFeed("BTC/USD", 10_000e8);
        console2.log("case 1");
        ///  opener  ///
        console2.log("opener");
        uint256 startDate = block.timestamp + 1 days;
        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        mintTestUSDC(swaper, swaperUsdcAmount);

        vm.startPrank(swaper);
        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount);
        cryptoSwap.openSwap(4, 1, btcTokenAddress, uint64(startDate), yieldIds[0]); // yieldId yearn
        vm.stopPrank();
        ///  opener  ///

        ///  pairer  ///
        console2.log("pairer");
        uint64 originalLegId = 1;
        uint256 pairUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        mintTestUSDC(pairer, pairUsdcAmount);

        vm.startPrank(pairer);
        usdcContract.approve(address(cryptoSwap), pairUsdcAmount);
        cryptoSwap.pairSwap(originalLegId, pairUsdcAmount, ethTokenAddress, yieldIds[0]); // yieldId yearn
        vm.stopPrank();
        ///  pairer  ///

        console2.log("mock the price feed");
        mockupdatePriceFeed("BTC/USD", 10_500e8); // BTC increase: 5%. Now BTC market value: 10,500

        console2.log("Get cryptoSwapUsdcAmountBefore");
        uint256 cryptoSwapUsdcAmountBefore = usdcContract.balanceOf(address(cryptoSwap));
        console2.log("Get swaperrUsdcAmountBefore");
        uint256 swaperUsdcAmountBefore = usdcContract.balanceOf(swaper);
        console2.log("Settle the swap");
        cryptoSwap.settleSwap(1);
        console2.log("Get swaperUsdcAmountAfter");
        uint256 swaperUsdcAmountAfter = usdcContract.balanceOf(swaper);
        console2.log("Get cryptoSwapUsdcAmountAfter");
        uint256 cryptoSwapUsdcAmountAfter = usdcContract.balanceOf(address(cryptoSwap));

        console2.log("swaperrUsdcAmountBefore", swaperUsdcAmountBefore / 10 ** ERC20(usdcContract).decimals(), "USDC");
        console2.log("swaperUsdcAmountAfter", swaperUsdcAmountAfter / 10 ** ERC20(usdcContract).decimals(), "USDC");
        console2.log(
            "cryptoSwapUsdcAmountBefore", cryptoSwapUsdcAmountBefore / 10 ** ERC20(usdcContract).decimals(), "USDC"
        );
        console2.log(
            "cryptoSwapUsdcAmountAfter", cryptoSwapUsdcAmountAfter / 10 ** ERC20(usdcContract).decimals(), "USDC"
        );
        // BTC 10_000e8 => 10_500e8, legToken increased 5% bench amount of USDC:  10_000. profit 500USDC
        assertEq(500e6, swaperUsdcAmountAfter - swaperUsdcAmountBefore);
        // assertEq(500e6, cryptoSwapUsdcAmountBefore - cryptoSwapUsdcAmountAfter); cryptoSwap don't store USDC
    }

    // function test_SettleCase2() external {
    //     mockupdatePriceFeed("ETH/USD", 10_00e8);
    //     mockupdatePriceFeed("BTC/USD", 10_000e8);
    //     ///  opener  ///
    //     uint256 startDate = block.timestamp + 1 days;
    //     uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
    //     mintTestUSDC(swaper, swaperUsdcAmount);

    //     vm.startPrank(swaper);
    //     usdcContract.approve(address(cryptoSwap), swaperUsdcAmount);
    //     cryptoSwap.openSwap(4, btcTokenAddress, uint64(startDate));
    //     vm.stopPrank();
    //     ///  opener  ///

    //      ///  pairer  ///
    //      uint64 originalLegId = 1;
    //      uint256 pairUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
    //      mintTestUSDC(pairer, pairUsdcAmount);

    //      vm.startPrank(pairer);
    //      usdcContract.approve(address(cryptoSwap), pairUsdcAmount);
    //      cryptoSwap.pairSwap(originalLegId,pairUsdcAmount, ethTokenAddress);
    //      vm.stopPrank();
    //      ///  pairer  ///

    //     mockupdatePriceFeed("BTC/USD", 10_500e8);  // BTC increase: 5%. Now BTC market value: 10,500

    //     uint256 cryptoSwapUsdcAmountBefore = usdcContract.balanceOf(address(cryptoSwap));
    //     uint256 swaperrUsdcAmountBefore = usdcContract.balanceOf(swaper);
    //     cryptoSwap.settleSwap(1);
    //     uint256 swaperUsdcAmountAfter = usdcContract.balanceOf(swaper);
    //     uint256 cryptoSwapUsdcAmountAfter = usdcContract.balanceOf(address(cryptoSwap));

    //     console2.log("swaperrUsdcAmountBefore", swaperrUsdcAmountBefore / 10**ERC20(usdcContract).decimals()
    // ,"USDC");
    //     console2.log("swaperUsdcAmountAfter", swaperUsdcAmountAfter /
    // 10**ERC20(usdcContract).decimals(),"USDC");
    //     console2.log("cryptoSwapUsdcAmountBefore", cryptoSwapUsdcAmountBefore /
    // 10**ERC20(usdcContract).decimals(),"USDC");
    //     console2.log("cryptoSwapUsdcAmountAfter", cryptoSwapUsdcAmountAfter /
    // 10**ERC20(usdcContract).decimals(),"USDC");
    //     // BTC 10_000e8 => 10_500e8, legToken increased 5% bench amount of USDC:  10,000. profit 250USDC
    //     assertEq(250e6, swaperUsdcAmountAfter-swaperrUsdcAmountBefore);
    //     assertEq(250e6, cryptoSwapUsdcAmountBefore-cryptoSwapUsdcAmountAfter);

    //     // TODO
    //     // 1. Test the cryptoSwap contract how to record each user's deposited USDC
    // }

    // todo add fuzzy funciton based on below test
    function test_showLegsInfo() external {
        address swaper1 = address(0x66666);
        uint256 swaperUsdcAmount1 = cryptoSwap.notionalValueOptions(1); // 10e6 10 USDC
        mintTestUSDC(swaper1, swaperUsdcAmount1);

        address swaper2 = address(0x77777);
        uint256 swaperUsdcAmount2 = cryptoSwap.notionalValueOptions(2); // 100e6 100 USDC
        mintTestUSDC(swaper2, swaperUsdcAmount2);

        address swaper3 = address(0x88889);
        uint256 swaperUsdcAmount3 = cryptoSwap.notionalValueOptions(3); // 1000e6 1000 USDC
        mintTestUSDC(swaper3, swaperUsdcAmount3);

        address pairer1 = address(0x66666999);
        uint256 pairerUsdcAmount1 = cryptoSwap.notionalValueOptions(1); // 10e6 10 USDC
        mintTestUSDC(pairer1, pairerUsdcAmount1);

        address pairer2 = address(0x77777999);
        uint256 pairerUsdcAmount2 = cryptoSwap.notionalValueOptions(2); // 100e6 100 USDC
        mintTestUSDC(pairer2, pairerUsdcAmount2);

        uint256 startDate = block.timestamp + 1 days;
        vm.startPrank(swaper1);
        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount1);
        cryptoSwap.openSwap(1, 1, ethTokenAddress, uint64(startDate), yieldIds[0]); // yieldId yearn legId = 1
        vm.stopPrank();

        uint256 startDate2 = block.timestamp + 2 days;
        vm.startPrank(swaper2);
        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount2);
        cryptoSwap.openSwap(2, 1, ethTokenAddress, uint64(startDate2), yieldIds[0]); // yieldId yearn legId = 2
        vm.stopPrank();

        uint256 startDate3 = block.timestamp + 3 days;
        vm.startPrank(swaper3);
        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount3);
        cryptoSwap.openSwap(3, 1, btcTokenAddress, uint64(startDate3), yieldIds[0]); // yieldId yearn legId = 3
        vm.stopPrank();

        vm.startPrank(pairer1);
        usdcContract.approve(address(cryptoSwap), pairerUsdcAmount1);
        cryptoSwap.pairSwap(1, pairerUsdcAmount1, btcTokenAddress, yieldIds[0]); // yieldId yearn pair legId = 1
        vm.stopPrank();

        vm.startPrank(pairer2);
        usdcContract.approve(address(cryptoSwap), pairerUsdcAmount2);
        cryptoSwap.pairSwap(2, pairerUsdcAmount2, btcTokenAddress, yieldIds[0]); // yieldId yearn pair legId = 2
        vm.stopPrank();

        uint64 maxId = cryptoSwap.maxLegId();
        console2.log("print all legs info");
        for (uint256 i = 1; i < maxId; i++) {
            CryptoSwap.Leg memory leg = cryptoSwap.queryLeg(uint64(i));
            console2.log("legId:", i);
            showLegInfo(leg);
            console2.log("====================================");
        }
    }

    // todo
    // 1. openSwap
    // 1.1 The user should have enough token to open the swap
    // 1.2 The legToken's market value shouldn't less than legTokenPrice* notional
    // 1.3 swaper should approve the USDC to the cryptoSwap contract
    // 2. pairSwap
    // 2.1 The user should have enough token to open the swap
    // 2.2 The legToken's market value shouldn't less than legTokenPrice* notional
    // 2.3 swaper should approve the USDC to the cryptoSwap contract

    // More test cases
    // 1. opener cancel the swap
    // 2. the openLeg was expired, blocktimestampe beyond startDate
    // 3. time check
    // pairswap, check current blocktimestampe should less than the originalLeg.startDate
    // periodTime check.
    // 4. Accesss control check
    // 4.1 who can call settleSwap(Both swaper and pairer?)
    // 4.2 only the owner can call add more token price feed and add yieldStrategy
    // 5. event check
    // 5.1 main functions, openSwap, pairSwap, settleSwap, should check the  event info
    // 6. Status check
    // Open, Active, Settled, Cancelled // No one pair or user cancled the swap
    // 7. Test differet scenarios when the settleSwap was called
    // win, lose, equal
    // check the profit's claculation is right
    // should add minimum profit check(such as less than 10Dollar, the result as equal ?)
    // 8. Test the yieldStrategy
    // 9. settleSwap security check
    // 9.1 access control check
    // 9.2 can be called only once
    // 9.3 prevent the potential lost of the reserve in smart contracts.
    // 10. Dealing with different decimials of the token while calculating the profit

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
        console2.log("startDate:", result.startDate);
        console2.log("status:", uint256(result.status));
        console2.log("swaper:", result.swaper);
        console2.log("tokenAddress:", result.tokenAddress, ERC20(result.tokenAddress).symbol());
    }

    function mintTestUSDC(address receiver, uint256 amount) internal {
        // default caller: 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, the ower of cryptoSwap,USDC
        vm.startPrank(address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496));
        usdcContract.mint(receiver, amount);
        vm.stopPrank();
    }

    // temp function, for test only in arb
    function test_withDrawUSDC() external {
        uint256 amount = 1000e6;
        mintTestUSDC(address(cryptoSwap), amount);
        uint256 cryptoSwapUsdcAmountBefore = usdcContract.balanceOf(address(cryptoSwap));
        cryptoSwap.withDrawUSDC(amount);
        uint256 cryptoSwapUsdcAmountAfter = usdcContract.balanceOf(address(cryptoSwap));
        assertEq(amount, cryptoSwapUsdcAmountBefore - cryptoSwapUsdcAmountAfter);
    }
}
