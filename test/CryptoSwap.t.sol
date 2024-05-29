// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/src/Test.sol";
import "../src/CryptoSwap.sol";
import "../src/PriceFeedManager.sol";
import "../src/YieldStrategyManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CryptoSwapTest is Test {
    uint256 mainnetFork;

    CryptoSwap cryptoSwap;
    PriceFeedManager priceFeedManager;
    YieldStrategyManager yieldStrategyManager;

    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC Token on ETH
    address ethUsdPriceFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address btcUsdPriceFeed = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address usdcWhale = 0xD160Ab0327B307a7b23436242198Dc02f850CB7C; // USDC whale
    
    address owner;
    address userA;
    address userB;

    function setUp() public {
        uint256 blockNumber = 19934641;
        mainnetFork = vm.createFork(vm.rpcUrl("mainnet"), blockNumber);
        vm.selectFork(mainnetFork);

        owner = makeAddr("owner");
        userA = makeAddr("userA");
        userB = makeAddr("userB");

        priceFeedManager = new PriceFeedManager();
        yieldStrategyManager = new YieldStrategyManager();

        priceFeedManager.addPriceFeed(0, ethUsdPriceFeed);
        priceFeedManager.addPriceFeed(1, btcUsdPriceFeed);

        // Deploy the CryptoSwap with actual manager implementations
        cryptoSwap = new CryptoSwap(address(priceFeedManager), address(yieldStrategyManager));
        cryptoSwap.addSettlementToken(1, address(usdc));

        vm.prank(usdcWhale);
        usdc.transfer(userA, 10000e6);
        
        vm.prank(userA);
        usdc.approve(address(cryptoSwap), 1000e6);
    }

    function test_openSwap() public {
        vm.startPrank(userA);
        uint256 contractCreationCount = 1;
        uint256 notionalAmount = 1000e6;  // Assuming USDC has 6 decimals like on mainnet
        uint64 startDate = uint64(block.timestamp + 1 days);
        uint16 feedIdA = 0; // ETH
        uint16 feedIdB = 1; // BTC
        uint8 periodType = 0;  // Daily
        uint8 totalIntervals = 4;
        uint8 settlementTokenId = 1;
        uint8 yieldId = 0;  // No yield strategy for simplicity

        // Open a new swap
        cryptoSwap.openSwap(contractCreationCount, notionalAmount, startDate, feedIdA, feedIdB, CryptoSwap.PeriodInterval(periodType), totalIntervals, settlementTokenId, yieldId);

        // Check for event and state changes if necessary
        vm.stopPrank();

        // Check if the contract was created
        assertEq(cryptoSwap.contractCreationCount(0), 1);
        CryptoSwap.SwapContract memory swapContract = cryptoSwap.getSwapContract(0, 0);
        assertEq(swapContract.notionalAmount, notionalAmount);
        assertEq(swapContract.period.startDate, startDate);
        assertEq(swapContract.legA.feedId, feedIdA);
        assertEq(swapContract.legB.feedId, feedIdB);
        // assertEq(swapContract.period.periodInterval, 7 days);
        assertEq(swapContract.period.totalIntervals, totalIntervals);
        assertEq(swapContract.settlementTokenId, settlementTokenId);
        assertEq(swapContract.yieldId, yieldId);
        assertEq(swapContract.notionalAmount, notionalAmount);
        assertEq(uint(swapContract.status), uint(CryptoSwap.Status.OPEN));
    }

    function test_pairSwap() public {
        // Open a swap
        test_openSwap();

        vm.prank(userA);
        usdc.transfer(userB, 500e6);

        vm.startPrank(userB);
        usdc.approve(address(cryptoSwap), 500e6);

        // Pair the swap
        cryptoSwap.pairSwap(0, 0);
        vm.stopPrank();

        // Check for event and state changes if necessary
        CryptoSwap.SwapContract memory swapContract = cryptoSwap.getSwapContract(0, 0);
        assertEq(uint(swapContract.status), uint(CryptoSwap.Status.ACTIVE));
        assertEq(swapContract.userA, userA);
        assertEq(swapContract.userB, userB);
        assertEq(swapContract.legA.balance, 500e6);
        assertEq(swapContract.legB.balance, 500e6);
        assertEq(swapContract.legA.legPosition, true);
        assertEq(swapContract.legB.legPosition, false);
        assertEq(usdc.balanceOf(address(cryptoSwap)), 1000e6);

        emit log_named_int("originalPrice", swapContract.legA.originalPrice);
        emit log_named_int("originalPrice", swapContract.legB.originalPrice);
    }

    function test_getPricesForPeriod() public {
        test_pairSwap();

        CryptoSwap.SwapContract memory swapContract = cryptoSwap.getSwapContract(0, 0);

        uint16 feedA = swapContract.legA.feedId;
        uint16 feedB = swapContract.legB.feedId;
        uint256 startDate = uint256(swapContract.period.startDate - 30 days);
        uint256 endDate = uint256(swapContract.period.startDate - 10 days);

        // Get the prices for the period
        (int256 startPriceA, int256 endPriceA) = cryptoSwap.getPricesForPeriod(feedA, startDate, endDate);
        (int256 startPriceB, int256 endPriceB) = cryptoSwap.getPricesForPeriod(feedB, startDate, endDate);

        // Check the prices
        emit log_named_int("startPriceA", startPriceA);
        emit log_named_int("endPriceA", endPriceA);
        emit log_named_int("startPriceB", startPriceB);
        emit log_named_int("endPriceB", endPriceB);

        uint256 notional = swapContract.notionalAmount;
        emit log_named_uint("notional", notional);

        emit log_named_uint("profitCalculation", 
        (uint256(endPriceB * startPriceA - endPriceA * startPriceB) * notional)
        / uint256(startPriceA * startPriceB));
    }

    function testFail_CannotSettleUntil() public {
        test_pairSwap();

        emit log_named_uint("block.timestamp", block.timestamp);

        CryptoSwap.SwapContract memory swapContract = cryptoSwap.getSwapContract(0, 0);

        vm.warp(swapContract.period.startDate + 1 days);

        vm.prank(userA);
        cryptoSwap.settleSwap(0, 0);
    }
}
