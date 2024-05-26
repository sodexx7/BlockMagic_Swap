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

    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC Token on Arbitrum
    address ethUsdPriceFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address btcUsdPriceFeed = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address usdcWhale = 0xD160Ab0327B307a7b23436242198Dc02f850CB7C; // USDC whale
    
    address owner;
    address userA;
    address userB;

    function setUp() public {
        mainnetFork = vm.createFork({ urlOrAlias: "mainnet" });
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

        emit log_named_uint("Whale USDC Balance before transfer", usdc.balanceOf(usdcWhale));
        vm.prank(usdcWhale);
        bool success = usdc.transfer(userA, 10000e6);
        require(success, "Transfer of USDC failed");
        emit log_named_uint("User A USDC Balance after transfer", usdc.balanceOf(userA));
        
        vm.prank(userA);
        usdc.approve(address(cryptoSwap), 1000e6);
    }

    function testOpenSwap() public {
        vm.startPrank(userA);
        uint256 contractCreationCount = 1;
        uint256 notionalAmount = 500e6;  // Assuming USDC has 6 decimals like on mainnet
        uint64 startDate = uint64(block.timestamp + 1 days);
        uint16 feedIdA = 0; // ARB
        uint16 feedIdB = 1; // BTC
        uint8 periodType = 0;  // Weekly
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
        assertEq(uint(swapContract.status), uint(CryptoSwap.Status.OPEN));
    }
}
