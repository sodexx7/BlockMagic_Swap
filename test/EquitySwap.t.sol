// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";
import { EquitySwap } from "../src/EquitySwap.sol";

import "../src/test/mocks/MockV3Aggregator.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract EquitySwapTest is Test {
    EquitySwap internal equitySwap;
    address internal ethTokenAddress =address(0x99);
    address internal btcTokenAddress =address(0x55);
    address internal swaper = address(0x991);
    address internal pairer = address(0x992);
    address ethPriceFeedAddress;
    address btcPriceFeedAddress;

    


    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        ethPriceFeedAddress = mockPriceFeed(1);//eth
        btcPriceFeedAddress = mockPriceFeed(2);//btc
        // Instantiate the contract-under-test.
        equitySwap = new EquitySwap(30,ethTokenAddress,ethPriceFeedAddress);
        equitySwap.addPriceFeed(btcTokenAddress, btcPriceFeedAddress);
    }

    // /// @dev Basic test. Run it with `forge test -vvv` to see the console log.
    function test_openSwap() external  {
        uint256 startDate = block.timestamp + 1 days;
        vm.prank(swaper);
        equitySwap.openSwap(ethTokenAddress, 10, uint64(startDate));
        EquitySwap.Leg memory result = equitySwap.queryLeg(1);
        console2.log("benchPrice:",result.benchPrice);
        console2.log("notional:",result.notional);
        console2.log("pairLegId:",result.pairLegId);
        console2.log("startDate:",result.startDate);
        console2.log("status:",uint(result.status));
        console2.log("swaper:",result.swaper);
        console2.log("tokenAddress:",result.tokenAddress);


        (
            ,
            /* uint80 roundID */
            int256 price,
            ,
            ,

        ) = AggregatorV3Interface(ethPriceFeedAddress).latestRoundData();
        assertEq(result.benchPrice, uint256(price));
        assertEq(result.notional, 10);
        assertEq(result.pairLegId, 0);
        assertEq(result.startDate, startDate);
        assertEq(uint(result.status), uint(EquitySwap.Status.Open));
        assertEq(result.swaper, swaper);
        assertEq(result.tokenAddress, ethTokenAddress);

    }

    function test_pairSwap() external  {
        uint256 startDate = block.timestamp + 1 days;
        vm.prank(swaper);
        equitySwap.openSwap(ethTokenAddress, 1, uint64(startDate));
        
        
        uint64 originalLegId = 1;
        vm.prank(pairer);
        equitySwap.pairSwap(originalLegId, btcTokenAddress, 1);

        EquitySwap.Leg memory originalLeg = equitySwap.queryLeg(1);
        EquitySwap.Leg memory pairLeg =  equitySwap.queryLeg(originalLeg.pairLegId);
        
        console2.log("pairLeg benchPrice:",pairLeg.benchPrice);
        console2.log("pairLeg notional:",pairLeg.notional);
        console2.log("pairLeg pairLegId:",pairLeg.pairLegId);
        console2.log("pairLeg startDate:",pairLeg.startDate);
        console2.log("pairLeg status:",uint(pairLeg.status));
        console2.log("pairLeg swaper:",pairLeg.swaper);
        console2.log("pairLeg tokenAddress:",pairLeg.tokenAddress);

        (
            ,
            /* uint80 roundID */
            int256 price,
            ,
            ,

        ) = AggregatorV3Interface(btcPriceFeedAddress).latestRoundData();
        assertEq(pairLeg.benchPrice, uint256(price));
        assertEq(pairLeg.notional, 1);
        assertEq(pairLeg.pairLegId, originalLegId);
        assertEq(pairLeg.startDate, startDate);
        assertEq(uint(pairLeg.status), uint(EquitySwap.Status.Active));
        assertEq(uint(originalLeg.status), uint(EquitySwap.Status.Active));
        assertEq(pairLeg.swaper, pairer);
        assertEq(pairLeg.tokenAddress, btcTokenAddress);

    }

    function test_settleSwapOpenerWin() external {
        uint256 startDate = block.timestamp + 1 days;
        vm.prank(swaper);
        equitySwap.openSwap(ethTokenAddress, 1, uint64(startDate));
        
        uint64 originalLegId = 1;
        vm.prank(pairer);
        equitySwap.pairSwap(originalLegId, btcTokenAddress, 1);

        // after 30 days
        vm.warp(startDate + 30 days);
        // the increased price of the eth > btc
        mockupdatePriceFeed(1,3000e18);
        mockupdatePriceFeed(2,8000e18);
        equitySwap.settleSwap(1);
   
    }

    function test_settleSwaperWin() external {
        uint256 startDate = block.timestamp + 1 days;
        vm.prank(swaper);
        equitySwap.openSwap(ethTokenAddress, 1, uint64(startDate));
        
        uint64 originalLegId = 1;
        vm.prank(pairer);
        equitySwap.pairSwap(originalLegId, btcTokenAddress, 1);

        // after 30 days
        vm.warp(startDate + 30 days);
        // the increased price of the eth > btc
        mockupdatePriceFeed(1,2000e18);
        mockupdatePriceFeed(2,8000e18);
        equitySwap.settleSwap(1);
   
    }


    function test_showLegsInfo() external {
        uint256 startDate = block.timestamp + 1 days;
        vm.prank(address(0x66666));
        equitySwap.openSwap(ethTokenAddress, 5, uint64(startDate)); // legId = 1 

        startDate = block.timestamp + 2 days;
        vm.prank(address(0x77777));
        equitySwap.openSwap(ethTokenAddress, 10, uint64(startDate)); // legId = 2 

        startDate = block.timestamp + 3 days;
        vm.prank(address(0x8888));
        equitySwap.openSwap(btcTokenAddress, 3, uint64(startDate)); // legId = 3 



        vm.prank(address(0x66666999));
        equitySwap.pairSwap(1, btcTokenAddress, 1);  


        vm.prank(address(0x77777999));
        equitySwap.pairSwap(2, btcTokenAddress, 2);



        uint64 maxId = equitySwap.maxLegId();
        console2.log("print all legs info");
        for(uint i = 1; i <= maxId; i++) {
            EquitySwap.Leg memory leg = equitySwap.queryLeg(uint64(i));
            console2.log("legId:",i);
            console2.log("benchPrice:",leg.benchPrice);
            console2.log("notional:",leg.notional);
            console2.log("pairLegId:",leg.pairLegId);
            console2.log("startDate:",leg.startDate);
            console2.log("status:",uint(leg.status));
            console2.log("swaper:",leg.swaper);
            console2.log("tokenAddress:",leg.tokenAddress);
            console2.log("====================================");
        }

    }

    // todo
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

    // tokenType 1:ETH, 2:BTC, 3:USDC
    function mockPriceFeed(uint tokenType) internal returns(address priceFeed) {
        // mock price
        uint8  DECIMALS = 18;
        int256  INITIAL_ANSWER = 2000e18;
        
        if(tokenType == 1) {
            //  apply default value
        } else if (tokenType == 2) {
              DECIMALS = 18;
              INITIAL_ANSWER = 7000e18;
        } else {
              DECIMALS = 10;
              INITIAL_ANSWER = 1e10;
        }
       
        return address(new MockV3Aggregator(DECIMALS, INITIAL_ANSWER));
    }
    //  Mock the token's price has changed
    function mockupdatePriceFeed(uint tokenType,int256 price) internal returns(address priceFeed) {
        if(tokenType == 1) {
              MockV3Aggregator(ethPriceFeedAddress).updateAnswer(price);
        } else if (tokenType == 2) {
              MockV3Aggregator(btcPriceFeedAddress).updateAnswer(price);
        } else {
            // 
        }
    }
}

