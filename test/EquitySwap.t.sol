// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";
import { EquitySwap } from "../src/EquitySwap.sol";

import "../src/test/mocks/MockV3Aggregator.sol";
import "../src/test/mocks/MockERC20.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract EquitySwapTest is Test {
    EquitySwap internal equitySwap;
    address internal ethTokenAddress;
    address internal btcTokenAddress;
    address internal swaper = address(0x991);
    address internal pairer = address(0x992);
    address ethPriceFeedAddress;
    address btcPriceFeedAddress;

    MockERC20 internal usdcContractAddress;

    // default caller: 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        ethPriceFeedAddress = mockPriceFeed(1, 1000e6, "ETH/USDC"); //eth
        btcPriceFeedAddress = mockPriceFeed(2, 60_000e6, "BTC/USDC"); //btc
        usdcContractAddress = new MockERC20("USDC", "USDC", 6);
        ethTokenAddress = address(new MockERC20("ETH", "ETH", 18));
        btcTokenAddress = address(new MockERC20("BTC", "BTC", 18));
        equitySwap = new EquitySwap(30, address(usdcContractAddress), ethTokenAddress, ethPriceFeedAddress);
        equitySwap.addPriceFeed(btcTokenAddress, btcPriceFeedAddress);

        // transfer 10 000USDC to swaper and pairer
        usdcContractAddress.mint(swaper, 10_000e6);
        usdcContractAddress.mint(pairer, 10_000e6);
    }

    /// @dev Basic test. Run it with `forge test -vvv` to see the console log.
    function test_openSwap() external {
        uint256 startDate = block.timestamp + 1 days;
        uint256 swaperUsdcAmount = 10_000e6;

        vm.startPrank(swaper);
        usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount);
        equitySwap.openSwap(swaperUsdcAmount, ethTokenAddress, 10, uint64(startDate));
        vm.stopPrank();
        EquitySwap.Leg memory result = equitySwap.queryLeg(1);
        showLegInfo(result);

        (
            ,
            /* uint80 roundID */
            int256 price,
            ,
            ,
        ) = AggregatorV3Interface(ethPriceFeedAddress).latestRoundData();
        // assertEq(result.benchPrice, uint256(price)); when opernSwap, take the price as 0
        assertEq(result.notional, 10);
        assertEq(result.pairLegId, 0);
        assertEq(result.startDate, startDate);
        assertEq(uint256(result.status), uint256(EquitySwap.Status.Open));
        assertEq(result.swaper, swaper);
        assertEq(result.tokenAddress, ethTokenAddress);
    }

    function test_pairSwap() external {
        uint256 startDate = block.timestamp + 1 days;
        uint256 swaperUsdcAmount = 10_000e6;

        vm.startPrank(swaper);
        usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount);
        equitySwap.openSwap(swaperUsdcAmount, ethTokenAddress, 10, uint64(startDate));
        vm.stopPrank();

        uint64 originalLegId = 1;
        uint256 pairUsdcAmount = 600_000e6;
        vm.startPrank(address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496));
        usdcContractAddress.mint(pairer, pairUsdcAmount);
        vm.stopPrank();

        vm.startPrank(pairer);
        usdcContractAddress.approve(address(equitySwap), pairUsdcAmount);
        equitySwap.pairSwap(pairUsdcAmount, originalLegId, btcTokenAddress, 1);
        vm.stopPrank();

        EquitySwap.Leg memory originalLeg = equitySwap.queryLeg(1);
        EquitySwap.Leg memory pairLeg = equitySwap.queryLeg(originalLeg.pairLegId);
        showLegInfo(pairLeg);

        (
            ,
            /* uint80 roundID */
            int256 price,
            ,
            ,
        ) = AggregatorV3Interface(btcPriceFeedAddress).latestRoundData();
        assertEq(pairLeg.benchPrice, uint256(price));
        assertEq(pairLeg.notional, 1);
        assertEq(pairLeg.settledStableTokenAmount, pairUsdcAmount);
        assertEq(pairLeg.pairLegId, originalLegId);
        assertEq(pairLeg.startDate, startDate);
        assertEq(uint256(pairLeg.status), uint256(EquitySwap.Status.Active));
        assertEq(uint256(originalLeg.status), uint256(EquitySwap.Status.Active));
        assertEq(pairLeg.swaper, pairer);
        assertEq(pairLeg.tokenAddress, btcTokenAddress);
    }

    function test_settlePairerWin() external {
        uint256 startDate = block.timestamp + 1 days;
        uint256 swaperUsdcAmount = 10_000e6;
        vm.startPrank(swaper);
        usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount);
        equitySwap.openSwap(swaperUsdcAmount, ethTokenAddress, 1, uint64(startDate));
        vm.stopPrank();

        uint64 originalLegId = 1;
        uint256 pairUsdcAmount = 6 * 10_000e6;
        vm.startPrank(address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496));
        usdcContractAddress.mint(pairer, pairUsdcAmount);
        vm.stopPrank();

        vm.startPrank(pairer);
        usdcContractAddress.approve(address(equitySwap), pairUsdcAmount);
        equitySwap.pairSwap(pairUsdcAmount, originalLegId, btcTokenAddress, 1);
        vm.stopPrank();

        // after 30 days
        vm.warp(startDate + 30 days);
        // the increased price of the eth > btc
        mockupdatePriceFeed(1, 3000e6);
        mockupdatePriceFeed(2, 8000e6);
        equitySwap.settleSwap(1);
    }

    function test_settleOpenerWin() external {
        uint256 startDate = block.timestamp + 1 days;
        uint256 swaperUsdcAmount = 10_000e6;
        vm.startPrank(swaper);
        usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount);
        equitySwap.openSwap(swaperUsdcAmount, ethTokenAddress, 1, uint64(startDate));
        vm.stopPrank();

        uint64 originalLegId = 1;
        uint256 pairUsdcAmount = 6 * 10_000e6;
        vm.startPrank(address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496));
        usdcContractAddress.mint(pairer, pairUsdcAmount);
        vm.stopPrank();

        vm.startPrank(pairer);
        usdcContractAddress.approve(address(equitySwap), pairUsdcAmount);
        equitySwap.pairSwap(pairUsdcAmount, originalLegId, btcTokenAddress, 1);
        vm.stopPrank();

        // after 30 days
        vm.warp(startDate + 30 days);
        // the increased price of the eth > btc
        mockupdatePriceFeed(1, 2000e6);
        mockupdatePriceFeed(2, 8000e6);
        equitySwap.settleSwap(1);
    }

    // todo add fuzzy funciton based on below test
    function test_showLegsInfo() external {
        uint256 startDate = block.timestamp + 1 days;
        uint256 swaperUsdcAmount = 10_000e6;
        // prepare USDC
        vm.startPrank(address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496));
        usdcContractAddress.mint(address(0x66666), swaperUsdcAmount);
        uint256 swaperUsdcAmount2 = 10_000e6;
        usdcContractAddress.mint(address(0x77777), swaperUsdcAmount2);
        uint256 swaperUsdcAmount3 = 10_000e6 * 20;
        usdcContractAddress.mint(address(0x8888), swaperUsdcAmount3);
        uint256 swaperUsdcAmount4 = 10_000e6 * 15;
        usdcContractAddress.mint(address(0x66666999), swaperUsdcAmount4);
        uint256 swaperUsdcAmount5 = 10_000e6 * 30;
        usdcContractAddress.mint(address(0x77777999), swaperUsdcAmount5);
        vm.stopPrank();
        // prepare USDC

        vm.startPrank(address(0x66666));
        usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount);
        equitySwap.openSwap(swaperUsdcAmount, ethTokenAddress, 5, uint64(startDate)); // legId = 1
        vm.stopPrank();

        uint256 startDate2 = block.timestamp + 2 days;
        vm.startPrank(address(0x77777));
        usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount2);
        equitySwap.openSwap(swaperUsdcAmount2, ethTokenAddress, 10, uint64(startDate2)); // legId = 2
        vm.stopPrank();

        uint256 startDate3 = block.timestamp + 3 days;
        vm.startPrank(address(0x8888));
        usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount3);
        equitySwap.openSwap(swaperUsdcAmount3, btcTokenAddress, 3, uint64(startDate3)); // legId = 3
        vm.stopPrank();

        vm.startPrank(address(0x66666999));
        usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount4);
        equitySwap.pairSwap(swaperUsdcAmount4, 1, btcTokenAddress, 1);
        vm.stopPrank();

        vm.startPrank(address(0x77777999));
        usdcContractAddress.approve(address(equitySwap), swaperUsdcAmount4);
        equitySwap.pairSwap(swaperUsdcAmount4, 2, btcTokenAddress, 2);
        vm.stopPrank();

        uint64 maxId = equitySwap.maxLegId();
        console2.log("print all legs info");
        for (uint256 i = 1; i < maxId; i++) {
            EquitySwap.Leg memory leg = equitySwap.queryLeg(uint64(i));
            console2.log("legId:", i);
            showLegInfo(leg);
            console2.log("====================================");
        }
    }

    // todo
    // 1. openSwap
    // 1.1 The user should have enough token to open the swap
    // 1.2 The legToken's market value shouldn't less than legTokenPrice* notional
    // 1.3 swaper should approve the USDC to the equitySwap contract
    // 2. pairSwap
    // 2.1 The user should have enough token to open the swap
    // 2.2 The legToken's market value shouldn't less than legTokenPrice* notional
    // 2.3 swaper should approve the USDC to the equitySwap contract

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
    function mockPriceFeed(
        uint256 tokenType,
        uint256 price,
        string memory description
    )
        internal
        returns (address priceFeed)
    {
        // mock price
        uint8 DECIMALS = 6;
        int256 INITIAL_ANSWER = 1000e6;

        if (tokenType == 1) {
            //  apply default value
        } else if (tokenType == 2) {
            DECIMALS = 6;
            INITIAL_ANSWER = 2000e6;
        } else {
            DECIMALS = 6;
            INITIAL_ANSWER = 1e6;
        }

        return address(new MockV3Aggregator(DECIMALS, int256(price), description)); //TODO, price convert problem?
    }
    //  Mock the token's price has changed

    function mockupdatePriceFeed(uint256 tokenType, int256 price) internal returns (address priceFeed) {
        if (tokenType == 1) {
            MockV3Aggregator(ethPriceFeedAddress).updateAnswer(price);
        } else if (tokenType == 2) {
            MockV3Aggregator(btcPriceFeedAddress).updateAnswer(price);
        } else {
            //
        }
    }

    function showLegInfo(EquitySwap.Leg memory result) internal view {
        console2.log("benchPrice:", result.benchPrice, equitySwap.description(result.tokenAddress));
        console2.log("notional:", result.notional, ERC20(result.tokenAddress).symbol());
        console2.log("settledStableTokenAmount:", result.settledStableTokenAmount, usdcContractAddress.symbol());
        console2.log("pairLegId:", result.pairLegId);
        console2.log("startDate:", result.startDate);
        console2.log("status:", uint256(result.status));
        console2.log("swaper:", result.swaper);
        console2.log("tokenAddress:", result.tokenAddress, ERC20(result.tokenAddress).symbol());
    }
}
