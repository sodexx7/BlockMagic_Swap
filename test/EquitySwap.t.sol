// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.25;

// import { Test } from "forge-std/src/Test.sol";
// import { console2 } from "forge-std/src/console2.sol";
// import { EquitySwap } from "../src/EquitySwap.sol";

// import "../src/test/mocks/MockV3Aggregator.sol";
// import "../src/test/mocks/MockERC20.sol";

// import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// contract EquitySwapTest is Test {
//     EquitySwap internal equitySwap;
//     address internal ethTokenAddress;
//     address internal btcTokenAddress;
//     address internal swaper = address(0x991);
//     address internal pairer = address(0x992);
//     address ethPriceFeedAddress;
//     address btcPriceFeedAddress;
//     MockERC20 internal usdcContractAddress;

//     event NoProfitWhileSettle(uint256 indexed legId, address indexed swaper, address indexed pairer);
    
//     /// @dev A function invoked before each test case is run.
//     /**
//     Initial price for ETH/USD: 1000, BTC/USD: 60_000, whose decimals are 8
//     */
//     function setUp() public virtual {
//         // default caller: 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, the ower of equitySwap,USDC
//         // priceFeed for ETH/USD, BTC/USD, mock USDC, ETH, BTC
//         ethPriceFeedAddress = mockPriceFeed("ETH/USD",1000e8); //ETH
//         btcPriceFeedAddress = mockPriceFeed("BTC/USD",60_000e8); //BTC
//         usdcContractAddress = new MockERC20("USDC", "USDC", 6);// USDC default value on arb is 6 
//         ethTokenAddress = address(new MockERC20("ETH", "ETH", 18));
//         btcTokenAddress = address(new MockERC20("WBTC", "WBTC", 8));// WBTC default value on arb is 8 

//         // create EquitySwap contract meanwhile priceFeed for ETH/USD, BTC/USD
//         equitySwap = new EquitySwap(30, address(usdcContractAddress), ethTokenAddress, ethPriceFeedAddress);
//         equitySwap.addPriceFeed(btcTokenAddress, btcPriceFeedAddress);
//     }

//     /// @dev Basic test. Run it with `forge test -vvv` to see the console log.
//     function test_openSwap() external {
//         uint256 startDate = block.timestamp + 1 days;
//         uint256 swaperUsdcAmount = 10_000e6;
//         mintTestUSDC(swaper, swaperUsdcAmount);
//         uint256 selectedNotional = 10**ERC20(ethTokenAddress).decimals(); // 1 ETH

//         vm.startPrank(swaper);
//         usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount);
//         equitySwap.openSwap(swaperUsdcAmount, ethTokenAddress, selectedNotional, uint64(startDate));
//         vm.stopPrank();
//         // check the corresponding leg info
//         EquitySwap.Leg memory result = equitySwap.queryLeg(1);
//         showLegInfo(result);

//         (
//             ,
//             /* uint80 roundID */
//             int256 price,
//             ,
//             ,
//         ) = AggregatorV3Interface(ethPriceFeedAddress).latestRoundData();
//         assertEq(result.benchPrice, price); 
//         assertEq(result.notional, selectedNotional);
//         assertEq(result.pairLegId, 0);
//         assertEq(result.startDate, startDate);
//         assertEq(uint256(result.status), uint256(EquitySwap.Status.Open));
//         assertEq(result.swaper, swaper);
//         assertEq(result.tokenAddress, ethTokenAddress);
//     }

//     function test_pairSwap() external {
//         uint256 startDate = block.timestamp + 1 days;
//         uint256 swaperUsdcAmount = 10_000e6;
//         mintTestUSDC(swaper, swaperUsdcAmount);
//         uint256 selectedNotional = 10*10**ERC20(ethTokenAddress).decimals(); // 10 ETH

//         vm.startPrank(swaper);
//         usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount);
//         equitySwap.openSwap(swaperUsdcAmount, ethTokenAddress, selectedNotional, uint64(startDate));
//         vm.stopPrank();

//         uint64 originalLegId = 1;
//         uint256 pairUsdcAmount = 60_000e6;
//         mintTestUSDC(pairer, pairUsdcAmount);
//         uint256 pairTokenNotional = 1*10**ERC20(btcTokenAddress).decimals(); // 1 WBTC

//         vm.startPrank(pairer);
//         usdcContractAddress.approve(address(equitySwap), pairUsdcAmount);
//         equitySwap.pairSwap(pairUsdcAmount, originalLegId, btcTokenAddress, pairTokenNotional);
//         vm.stopPrank();

//         EquitySwap.Leg memory originalLeg = equitySwap.queryLeg(1);
//         EquitySwap.Leg memory pairLeg = equitySwap.queryLeg(originalLeg.pairLegId);
//         showLegInfo(pairLeg);

//         (
//             ,
//             /* uint80 roundID */
//             int256 price,
//             ,
//             ,
//         ) = AggregatorV3Interface(btcPriceFeedAddress).latestRoundData();
//         assertEq(pairLeg.benchPrice, price);
//         assertEq(pairLeg.notional, pairTokenNotional);
//         assertEq(pairLeg.settledStableTokenAmount, pairUsdcAmount);
//         assertEq(pairLeg.pairLegId, originalLegId);
//         assertEq(pairLeg.startDate, startDate);
//         assertEq(uint256(pairLeg.status), uint256(EquitySwap.Status.Active));
//         assertEq(uint256(originalLeg.status), uint256(EquitySwap.Status.Active));
//         assertEq(pairLeg.swaper, pairer);
//         assertEq(pairLeg.tokenAddress, btcTokenAddress);
//     }

//     function test_settleEqual() external {
//         ///////////////////////////////////////////////  opener  ///////////////////////////////////////////////  
//         uint256 startDate = block.timestamp + 1 days;
//         uint256 swaperUsdcAmount = 10_000e6;
//         mintTestUSDC(swaper, swaperUsdcAmount);
//         uint256 selectedNotional = 1*10**ERC20(ethTokenAddress).decimals(); // 1 ETH

//         vm.startPrank(swaper);
//         usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount);
//         equitySwap.openSwap(swaperUsdcAmount, ethTokenAddress, selectedNotional, uint64(startDate));
//         vm.stopPrank();
//         ///////////////////////////////////////////////  opener  ///////////////////////////////////////////////

//         ///////////////////////////////////////////////  pairer  ///////////////////////////////////////////////
//         uint64 originalLegId = 1;
//         uint256 pairUsdcAmount = 60_000e6;
//         usdcContractAddress.mint(pairer, pairUsdcAmount);
//         uint256 pairTokenNotional = 1*10**ERC20(btcTokenAddress).decimals(); // 1 WBTC

//         vm.startPrank(pairer);
//         usdcContractAddress.approve(address(equitySwap), pairUsdcAmount);
//         equitySwap.pairSwap(pairUsdcAmount, originalLegId, btcTokenAddress, pairTokenNotional);
//         vm.stopPrank();
//         ///////////////////////////////////////////////  pairer  ///////////////////////////////////////////////
        
//         vm.warp(startDate + 30 days);
//         // price for ETH/USD, BTC/USD hasn't  changed
//         vm.expectEmit(true, true, true, true);
//         emit NoProfitWhileSettle(1, swaper, pairer);
//         equitySwap.settleSwap(1);
//     }

//     function test_settleOpenerWin() external {
//         ///////////////////////////////////////////////  opener  ///////////////////////////////////////////////  
//         uint256 startDate = block.timestamp + 1 days;
//         uint256 swaperUsdcAmount = 10_000e6;
//         mintTestUSDC(swaper, swaperUsdcAmount);
//         uint256 selectedNotional = 1*10**ERC20(ethTokenAddress).decimals(); // 1 ETH

//         vm.startPrank(swaper);
//         usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount);
//         equitySwap.openSwap(swaperUsdcAmount, ethTokenAddress, selectedNotional, uint64(startDate));
//         vm.stopPrank();
//         ///////////////////////////////////////////////  opener  ///////////////////////////////////////////////

//         ///////////////////////////////////////////////  pairer  ///////////////////////////////////////////////
//         uint64 originalLegId = 1;
//         uint256 pairUsdcAmount = 60_000e6;
//         usdcContractAddress.mint(pairer, pairUsdcAmount);
//         uint256 pairTokenNotional = 1*10**ERC20(btcTokenAddress).decimals(); // 1 WBTC

//         vm.startPrank(pairer);
//         usdcContractAddress.approve(address(equitySwap), pairUsdcAmount);
//         equitySwap.pairSwap(pairUsdcAmount, originalLegId, btcTokenAddress, pairTokenNotional);
//         vm.stopPrank();
//         ///////////////////////////////////////////////  pairer  ///////////////////////////////////////////////

//         vm.warp(startDate + 30 days);
//         // the increased price of the eth > btc
//         mockupdatePriceFeed("ETH/USD", 1500e8); // 1000e8 => 1500e8
//         mockupdatePriceFeed("BTC/USD", 60_000e8); // doesn't change

//         uint256 equitySwapUsdcAmountBefore = usdcContractAddress.balanceOf(address(equitySwap));
//         uint256 swaperUsdcAmountBefore = usdcContractAddress.balanceOf(swaper);
//         equitySwap.settleSwap(1);
//         uint256 swaperUsdcAmountAfter = usdcContractAddress.balanceOf(swaper);
//         uint256 equitySwapUsdcAmountAfter = usdcContractAddress.balanceOf(address(equitySwap));

//         // 1000e8 => 1500e8,legToken increased 5%, bench amount of USDC:  10_000. profit 500USDC
//          assertEq(500e6, swaperUsdcAmountAfter-swaperUsdcAmountBefore);
//          assertEq(500e6, equitySwapUsdcAmountBefore-equitySwapUsdcAmountAfter);
//     }

//     function test_settlePairerWin() external {
//         ///////////////////////////////////////////////  opener  ///////////////////////////////////////////////
//         uint256 startDate = block.timestamp + 1 days;
//         uint256 swaperUsdcAmount = 10_000e6;
//         mintTestUSDC(swaper, swaperUsdcAmount);
//         uint256 selectedNotional = 1*10**ERC20(ethTokenAddress).decimals(); // 1 ETH

//         vm.startPrank(swaper);
//         usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount);
//         equitySwap.openSwap(swaperUsdcAmount, ethTokenAddress, selectedNotional, uint64(startDate));
//         vm.stopPrank();
//         ///////////////////////////////////////////////  opener  ///////////////////////////////////////////////

//         ///////////////////////////////////////////////  pairer  ///////////////////////////////////////////////
//         uint64 originalLegId = 1;
//         uint256 pairUsdcAmount = 60_000e6;
//         mintTestUSDC(pairer, pairUsdcAmount);
//         uint256 pairTokenNotional = 1*10**ERC20(btcTokenAddress).decimals(); // 1 WBTC

//         vm.startPrank(pairer);
//         usdcContractAddress.approve(address(equitySwap), pairUsdcAmount);
//         equitySwap.pairSwap(pairUsdcAmount, originalLegId, btcTokenAddress, pairTokenNotional);
//         vm.stopPrank();
//         ///////////////////////////////////////////////  pairer  ///////////////////////////////////////////////

//         // after 30 days
//         vm.warp(startDate + 30 days);
//         // the increased price of the eth > btc
//         mockupdatePriceFeed("ETH/USD", 1000e8); // price doesn't change
//         mockupdatePriceFeed("BTC/USD", 60_300e8); // 60_000e8 => 60_300e8

//         uint256 equitySwapUsdcAmountBefore = usdcContractAddress.balanceOf(address(equitySwap));
//         uint256 pairerUsdcAmountBefore = usdcContractAddress.balanceOf(pairer);
//         equitySwap.settleSwap(1);
//         uint256 pairerUsdcAmountAfter = usdcContractAddress.balanceOf(pairer);
//         uint256 equitySwapUsdcAmountAfter = usdcContractAddress.balanceOf(address(equitySwap));

//         // 60_000e8 => 60_300e8, pairlegToken increased 0.005 bench amount of USDC:  10_000. profit 5USDC
//         assertEq(5e6, pairerUsdcAmountAfter-pairerUsdcAmountBefore);
//         assertEq(5e6, equitySwapUsdcAmountBefore-equitySwapUsdcAmountAfter);
//     }

//     /**
//     case1
//     1.1. startDate: opener: 1 BTC, actual value: 10,000; pairer: 10,000 USDC

//     1.2. endDate: BTC increase: 5%. Now BTC market value: 10,500, USDC price don't change. the relative increase rates
//     of the BTC comparing to the USDC: 5%.

//     - 5% \* 10,000 = 500 USDC to BTC depositer.

//       1.3. updating opener: 1 BTC, actual value: 10,500; pairer: 9,500 USDC

//     case2
//     2.1 startDate: opener: 1 BTC, actual value: 10,000; pairer: 5,000 USDC

//     2.2 endDate: BTC increase: 5%. Now BTC market value: 10,500, USDC price don't change.

//     - DealEngine: 5% \* 5,000 = 250 USDC to BTC depositer.

//     2.3. updating opener: 1 BTC, actual value: 10,500; pairer: 4,750 USDC
//     */
//     function test_SettleCase1() external {
//         mockupdatePriceFeed("ETH/USD", 10_00e8);
//         mockupdatePriceFeed("BTC/USD", 10_000e8); 
//         ///////////////////////////////////////////////  opener  ///////////////////////////////////////////////  
//         uint256 startDate = block.timestamp + 1 days;
//         uint256 swaperUsdcAmount = 10_000e6;
//         mintTestUSDC(swaper, swaperUsdcAmount);
//         uint256 selectedNotional = 1*10**ERC20(btcTokenAddress).decimals(); // 1 WBTC

//         vm.startPrank(swaper);
//         usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount);
//         equitySwap.openSwap(swaperUsdcAmount, btcTokenAddress, selectedNotional, uint64(startDate));
//         vm.stopPrank();
//         ///////////////////////////////////////////////  opener  ///////////////////////////////////////////////


//          ///////////////////////////////////////////////  pairer  ///////////////////////////////////////////////
//          uint64 originalLegId = 1;
//          uint256 pairUsdcAmount = 10_000e6;
//          mintTestUSDC(pairer, pairUsdcAmount);
//          uint256 pairTokenNotional = 10*10**ERC20(ethTokenAddress).decimals(); // 10 ETH
 
//          vm.startPrank(pairer);
//          usdcContractAddress.approve(address(equitySwap), pairUsdcAmount);
//          equitySwap.pairSwap(pairUsdcAmount, originalLegId, ethTokenAddress, pairTokenNotional);
//          vm.stopPrank();
//          ///////////////////////////////////////////////  pairer  ///////////////////////////////////////////////

//         mockupdatePriceFeed("BTC/USD", 10_500e8);  // BTC increase: 5%. Now BTC market value: 10,500


//         uint256 equitySwapUsdcAmountBefore = usdcContractAddress.balanceOf(address(equitySwap));
//         uint256 swaperrUsdcAmountBefore = usdcContractAddress.balanceOf(swaper);
//         equitySwap.settleSwap(1);
//         uint256 swaperUsdcAmountAfter = usdcContractAddress.balanceOf(swaper);
//         uint256 equitySwapUsdcAmountAfter = usdcContractAddress.balanceOf(address(equitySwap));

//         console2.log("swaperrUsdcAmountBefore", swaperrUsdcAmountBefore / 10**ERC20(usdcContractAddress).decimals() ,"USDC");
//         console2.log("swaperUsdcAmountAfter", swaperUsdcAmountAfter / 10**ERC20(usdcContractAddress).decimals(),"USDC");
//         console2.log("equitySwapUsdcAmountBefore", equitySwapUsdcAmountBefore / 10**ERC20(usdcContractAddress).decimals(),"USDC");
//         console2.log("equitySwapUsdcAmountAfter", equitySwapUsdcAmountAfter / 10**ERC20(usdcContractAddress).decimals(),"USDC");
//         // BTC 10_000e8 => 10_500e8, legToken increased 5% bench amount of USDC:  10_000. profit 500USDC
//         assertEq(500e6, swaperUsdcAmountAfter-swaperrUsdcAmountBefore);
//         assertEq(500e6, equitySwapUsdcAmountBefore-equitySwapUsdcAmountAfter);
//     }

//     function test_SettleCase2() external {
//         mockupdatePriceFeed("ETH/USD", 10_00e8);
//         mockupdatePriceFeed("BTC/USD", 10_000e8); 
//         ///////////////////////////////////////////////  opener  ///////////////////////////////////////////////  
//         uint256 startDate = block.timestamp + 1 days;
//         uint256 swaperUsdcAmount = 10_000e6;
//         mintTestUSDC(swaper, swaperUsdcAmount);
//         uint256 selectedNotional = 1*10**ERC20(btcTokenAddress).decimals(); // 1 WBTC

//         vm.startPrank(swaper);
//         usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount);
//         equitySwap.openSwap(swaperUsdcAmount, btcTokenAddress, selectedNotional, uint64(startDate));
//         vm.stopPrank();
//         ///////////////////////////////////////////////  opener  ///////////////////////////////////////////////


//          ///////////////////////////////////////////////  pairer  ///////////////////////////////////////////////
//          uint64 originalLegId = 1;
//          uint256 pairUsdcAmount = 5_000e6; // 5_000e8 = 1/2* swaperUsdcAmount   
//          mintTestUSDC(pairer, pairUsdcAmount);
//          uint256 pairTokenNotional = 5*10**ERC20(ethTokenAddress).decimals(); // 5 ETH
 
//          vm.startPrank(pairer);
//          usdcContractAddress.approve(address(equitySwap), pairUsdcAmount);
//          equitySwap.pairSwap(pairUsdcAmount, originalLegId, ethTokenAddress, pairTokenNotional);
//          vm.stopPrank();
//          ///////////////////////////////////////////////  pairer  ///////////////////////////////////////////////

//         mockupdatePriceFeed("BTC/USD", 10_500e8);  // BTC increase: 5%. Now BTC market value: 10,500


//         uint256 equitySwapUsdcAmountBefore = usdcContractAddress.balanceOf(address(equitySwap));
//         uint256 swaperrUsdcAmountBefore = usdcContractAddress.balanceOf(swaper);
//         equitySwap.settleSwap(1);
//         uint256 swaperUsdcAmountAfter = usdcContractAddress.balanceOf(swaper);
//         uint256 equitySwapUsdcAmountAfter = usdcContractAddress.balanceOf(address(equitySwap));

//         console2.log("swaperrUsdcAmountBefore", swaperrUsdcAmountBefore / 10**ERC20(usdcContractAddress).decimals() ,"USDC");
//         console2.log("swaperUsdcAmountAfter", swaperUsdcAmountAfter / 10**ERC20(usdcContractAddress).decimals(),"USDC");
//         console2.log("equitySwapUsdcAmountBefore", equitySwapUsdcAmountBefore / 10**ERC20(usdcContractAddress).decimals(),"USDC");
//         console2.log("equitySwapUsdcAmountAfter", equitySwapUsdcAmountAfter / 10**ERC20(usdcContractAddress).decimals(),"USDC");
//         // BTC 10_000e8 => 10_500e8, legToken increased 5% bench amount of USDC:  5_000. profit 250USDC
//         assertEq(250e6, swaperUsdcAmountAfter-swaperrUsdcAmountBefore);
//         assertEq(250e6, equitySwapUsdcAmountBefore-equitySwapUsdcAmountAfter);

//         // TODO
//         // 1. Test the EquitySwap contract how to record each user's deposited USDC
//     }
    

//     // todo add fuzzy funciton based on below test
//     function test_showLegsInfo() external {

//         address swaper1 = address(0x66666);
//         uint256 swaperUsdcAmount1 = 10_000e6;
//         mintTestUSDC(swaper1, swaperUsdcAmount1);

//         address swaper2 = address(0x77777);
//         uint256 swaperUsdcAmount2 = 10_000e6;
//         mintTestUSDC(swaper2, swaperUsdcAmount2);

//         address swaper3 = address(0x88889);
//         uint256 swaperUsdcAmount3 = 200_000e6; 
//         mintTestUSDC(swaper3, swaperUsdcAmount3);

//         address pairer1 = address(0x66666999);
//         uint256 pairerUsdcAmount1= 150_000e6;
//         mintTestUSDC(pairer1, pairerUsdcAmount1);

//         address pairer2 = address(0x77777999);
//         uint256 pairerUsdcAmount2 = 300_000e6;
//         mintTestUSDC(pairer2, pairerUsdcAmount2);

        
//         uint256 startDate = block.timestamp + 1 days;
//         vm.startPrank(swaper1);
//         usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount1);
//         uint256 selectedNotional1 = 5*10**ERC20(ethTokenAddress).decimals(); // 5 ETH
//         equitySwap.openSwap(swaperUsdcAmount1, ethTokenAddress, selectedNotional1, uint64(startDate)); // legId = 1
//         vm.stopPrank();

//         uint256 startDate2 = block.timestamp + 2 days;
//         vm.startPrank(swaper2);
//         usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount2);
//         uint256 selectedNotional2 = 10*10**ERC20(ethTokenAddress).decimals(); // 10 ETH
//         equitySwap.openSwap(swaperUsdcAmount2, ethTokenAddress, selectedNotional2, uint64(startDate2)); // legId = 2
//         vm.stopPrank();

//         uint256 startDate3 = block.timestamp + 3 days;
//         vm.startPrank(swaper3);
//         usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount3);
//         uint256 selectedNotional3= 3*10**ERC20(btcTokenAddress).decimals(); // 3 WBTC 180_000e8
//         equitySwap.openSwap(swaperUsdcAmount3, btcTokenAddress, selectedNotional3, uint64(startDate3)); // legId = 3
//         vm.stopPrank();

//         vm.startPrank(pairer1);
//         usdcContractAddress.approve(address(equitySwap), pairerUsdcAmount1);
//         uint256 pairTokenNotional1 = 1*10**ERC20(btcTokenAddress).decimals(); // 1 WBTC
//         equitySwap.pairSwap(pairerUsdcAmount1, 1, btcTokenAddress, pairTokenNotional1); // pair legId = 1
//         vm.stopPrank();

//         vm.startPrank(pairer2);
//         usdcContractAddress.approve(address(equitySwap), pairerUsdcAmount2);
//         uint256 pairTokenNotional2 = 2*10**ERC20(btcTokenAddress).decimals(); // 2 WBTC
//         equitySwap.pairSwap(pairerUsdcAmount2, 2, btcTokenAddress, pairTokenNotional2); // pair legId = 2
//         vm.stopPrank();

//         uint64 maxId = equitySwap.maxLegId();
//         console2.log("print all legs info");
//         for (uint256 i = 1; i < maxId; i++) {
//             EquitySwap.Leg memory leg = equitySwap.queryLeg(uint64(i));
//             console2.log("legId:", i);
//             showLegInfo(leg);
//             console2.log("====================================");
//         }
//     }

//     // todo
//     // 1. openSwap
//     // 1.1 The user should have enough token to open the swap
//     // 1.2 The legToken's market value shouldn't less than legTokenPrice* notional
//     // 1.3 swaper should approve the USDC to the equitySwap contract
//     // 2. pairSwap
//     // 2.1 The user should have enough token to open the swap
//     // 2.2 The legToken's market value shouldn't less than legTokenPrice* notional
//     // 2.3 swaper should approve the USDC to the equitySwap contract

//     // More test cases
//     // 1. opener cancel the swap
//     // 2. the openLeg was expired, blocktimestampe beyond startDate
//     // 3. time check
//     // pairswap, check current blocktimestampe should less than the originalLeg.startDate
//     // periodTime check.
//     // 4. Accesss control check
//     // 4.1 who can call settleSwap(Both swaper and pairer?)
//     // 4.2 only the owner can call add more token price feed and add yieldStrategy
//     // 5. event check
//     // 5.1 main functions, openSwap, pairSwap, settleSwap, should check the  event info
//     // 6. Status check
//     // Open, Active, Settled, Cancelled // No one pair or user cancled the swap
//     // 7. Test differet scenarios when the settleSwap was called
//     // win, lose, equal
//     // check the profit's claculation is right
//     // should add minimum profit check(such as less than 10Dollar, the result as equal ?)
//     // 8. Test the yieldStrategy
//     // 9. settleSwap security check
//     // 9.1 access control check
//     // 9.2 can be called only once
//     // 9.3 prevent the potential lost of the reserve in smart contracts.
//     // 10. Dealing with different decimials of the token while calculating the profit

    
//     /** 
//         Mock the token's price based on USD.  
//         1. current test Equities:  ETH/USD, 2. BTC/USD
//         2. decimials = 8(chainlink arb default value)
//         3. price type is int256, comptatible with chainlink
    
//     **/
//     function mockPriceFeed(
//         string memory description,
//         int256 price
//     )
//         internal
//         returns (address priceFeed)
//     {
//         uint8 DECIMALS = 8;
//         return address(new MockV3Aggregator(DECIMALS, price, description)); 
//     }
//     //  Mock the token's price has changed

//     function mockupdatePriceFeed(string memory description, int256 price) internal returns (address priceFeed) {
//         if (keccak256(abi.encodePacked("ETH/USD")) == keccak256(abi.encodePacked(description))) {
//             MockV3Aggregator(ethPriceFeedAddress).updateAnswer(price);
//         } else if (keccak256(abi.encodePacked("BTC/USD")) == keccak256(abi.encodePacked(description))) {
//             MockV3Aggregator(btcPriceFeedAddress).updateAnswer(price);
//         } else {
//             //
//         }
//     }

//     function showLegInfo(EquitySwap.Leg memory result) internal view {
        
//         console2.log("benchPrice:", uint256(result.benchPrice) / 10**equitySwap.priceFeedDecimals(result.tokenAddress), equitySwap.description(result.tokenAddress));
//         console2.log("notional:", result.notional / 10**ERC20(result.tokenAddress).decimals(), ERC20(result.tokenAddress).symbol());
//         console2.log("settledStableTokenAmount:", result.settledStableTokenAmount / 10**usdcContractAddress.decimals(), usdcContractAddress.symbol());
//         console2.log("pairLegId:", result.pairLegId);
//         console2.log("startDate:", result.startDate);
//         console2.log("status:", uint256(result.status));
//         console2.log("swaper:", result.swaper);
//         console2.log("tokenAddress:", result.tokenAddress, ERC20(result.tokenAddress).symbol());
//     }

//     function mintTestUSDC(address receiver, uint256 amount) internal {
//         // default caller: 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, the ower of equitySwap,USDC
//         vm.startPrank(address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496)); 
//         usdcContractAddress.mint(receiver, amount);
//         vm.stopPrank();
        
//     }
// }
