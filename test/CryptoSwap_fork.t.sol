// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "./InitForkTest.t.sol";

contract CryptoSwapTestFork is InitForkTest {
    /// @dev Basic test. Run it with `forge test -vvv` to see the console log.
    function test_openSwap() external {
        vm.selectFork(mainnetFork);

        uint256 startDate = block.timestamp + 1 days;
        // TODO: swapterUsdcAmount should not be total notional amount, for example divided by 10
        // uint256 swaperUsdcAmount = (cryptoSwap.notionalValueOptions(4)) / 10; // 10_000e6 10,000 USDC
        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        deal(usdcContractAddress, swaper, swaperUsdcAmount);

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

        // check the corresponding leg info
        CryptoSwap.Leg memory result = cryptoSwap.queryLeg(1);
        showLegInfo(result);

        assertEq(result.benchPrice, 0); // only when pairSwap, the benchPrice will be updated, if front-end need to
        // the benchPrice, should directly get the price
        assertEq(result.pairLegId, 0);
        // assertEq(result.startDate, startDate);
        // assertEq(uint256(result.status), uint256(CryptoSwap.Status.Open));
        assertEq(result.swaper, swaper);
        assertEq(result.tokenAddress, ethTokenAddress);
    }

    function test_openBatchSwap() external {
        vm.selectFork(mainnetFork);

        uint256 startDate = block.timestamp + 1 days;
        uint8 notionalCount = 5;
        // TODO: swapterUsdcAmount should not be total notional amount, for example divided by 10
        // uint256 swaperUsdcAmount = (cryptoSwap.notionalValueOptions(4) * notionalCount) / 10; // 10_000e6 10,000 USDC
        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4) * notionalCount; // 50_000e6 50,000 USDC
        deal(usdcContractAddress, swaper, swaperUsdcAmount);

        vm.startPrank(swaper);

        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount);
        uint64[] memory legIds = new uint64[](5);
        legIds[0] = uint64(1);
        legIds[1] = uint64(2);
        legIds[2] = uint64(3);
        legIds[3] = uint64(4);
        legIds[4] = uint64(5);
        emit BatchOpenSwap(swaper, ethTokenAddress, legIds, swaperUsdcAmount, notionalCount, startDate);
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

        for (uint8 i = 1; i <= notionalCount; i++) {
            CryptoSwap.Leg memory result = cryptoSwap.queryLeg(i);
            showLegInfo(result);
            assertEq(result.benchPrice, 0);
            assertEq(result.pairLegId, 0);
            // assertEq(result.startDate, startDate);
            // assertEq(uint256(result.status), uint256(CryptoSwap.Status.Open));
            assertEq(result.swaper, swaper);
            assertEq(result.tokenAddress, ethTokenAddress);
        }
    }

    function test_pairSwap() external {
        vm.selectFork(mainnetFork);

        uint256 startDate = block.timestamp + 1 days;
        // TODO: swapterUsdcAmount should not be total notional amount, for example divided by 10
        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        deal(usdcContractAddress, swaper, swaperUsdcAmount);

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

        uint64 originalLegId = 1;
        uint256 pairUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        deal(usdcContractAddress, pairer, pairUsdcAmount);

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
        // assertEq(pairLeg.startDate, startDate);
        // assertEq(uint256(pairLeg.status), uint256(CryptoSwap.Status.Active));
        // assertEq(uint256(originalLeg.status), uint256(CryptoSwap.Status.Active));
        assertEq(pairLeg.swaper, pairer);
        assertEq(pairLeg.tokenAddress, btcTokenAddress);
    }

    function test_settleEqual() external {
        vm.selectFork(mainnetFork);
        ///  opener  ///
        uint256 startDate = block.timestamp + 1 days;
        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        deal(usdcContractAddress, swaper, swaperUsdcAmount);

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
        deal(usdcContractAddress, pairer, pairUsdcAmount);

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

    function test_settlePairerWinForkBullishMarket() external {
        makeSettlementFromFortk(mainnetFork_15032024);
    }

    // 20/03/2024   BTC: ~61_930 USD, ETH: ~3_158 USD
    // 02/05/2024 - BTC: ~58_253 USD, ETH: ~2_969 USD
    function test_settlePairerWinForkBearishMarket() external {
        makeSettlementFromFortk(mainnetFork_02052024);
    }

    // 20/03/2024 BTC: ~61_930 USD, ETH: ~3_158 USD
    // 15/03/2024 BTC: ~71_387 USD, ETH: ~3_888 USD

    //  openerLeg benchPrice: 3227 ETH / USD 322766776503
    //  openerLeg latestPrice: 3707 ETH / USD 370766673501
    function makeSettlementFromFortk(uint256 fork) private {
        uint256 startDate = block.timestamp + 1 days;

        ///  opener  ///
        uint256 swaperUsdcAmount = cryptoSwap.notionalValueOptions(4); // 10_000e6 10,000 USDC
        deal(usdcContractAddress, swaper, swaperUsdcAmount);

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
        deal(usdcContractAddress, pairer, pairUsdcAmount);

        vm.startPrank(pairer);
        usdcContract.approve(address(cryptoSwap), pairUsdcAmount);
        cryptoSwap.pairSwap(originalLegId, pairUsdcAmount, btcTokenAddress, yieldIds[0]); // yieldId yearn
        vm.stopPrank();

        ///  pairer  ///

        // Make persistent account
        address[] memory persistantAddresses = new address[](5);
        persistantAddresses[0] = yearnYvUSDC;
        persistantAddresses[1] = address(cryptoSwap);
        persistantAddresses[2] = usdcContractAddress;
        persistantAddresses[3] = address(priceFeeds);
        persistantAddresses[4] = address(yieldStrategies);

        vm.makePersistent(persistantAddresses);

        // select a different fork
        vm.selectFork(fork);
        CryptoSwap.Leg memory openerLeg = cryptoSwap.queryLeg(1);
        CryptoSwap.Leg memory pairLeg = cryptoSwap.queryLeg(2);

        uint256 cryptoSwapUsdcAmountBefore = usdcContract.balanceOf(address(cryptoSwap));
        uint256 swaperUsdcAmountBefore = usdcContract.balanceOf(swaper);
        uint256 pairerUsdcAmountBefore = usdcContract.balanceOf(pairer);
        console2.log("Settle the swap");
        cryptoSwap.settleSwap(1);
        printAfterSettlement(
            swaper,
            pairer,
            cryptoSwap,
            swaperUsdcAmountBefore,
            pairerUsdcAmountBefore,
            cryptoSwapUsdcAmountBefore,
            openerLeg,
            pairLeg
        );
    }

    function printAfterSettlement(
        address swaper,
        address pairer,
        CryptoSwap cryptoSwap,
        uint256 swaperUsdcAmountBefore,
        uint256 pairerUsdcAmountBefore,
        uint256 cryptoSwapUsdcAmountBefore,
        CryptoSwap.Leg memory openerLeg,
        CryptoSwap.Leg memory pairLeg
    )
        private
        view
    {
        console2.log("Get swaperUsdcAmountAfter");
        uint256 swaperUsdcAmountAfter = usdcContract.balanceOf(swaper);
        uint256 pairerUsdcAmountAfter = usdcContract.balanceOf(pairer);
        uint256 cryptoSwapUsdcAmountAfter = usdcContract.balanceOf(address(cryptoSwap));
        console2.log("swaperUsdcAmountBefore", swaperUsdcAmountBefore / 10 ** ERC20(usdcContract).decimals(), "USDC");
        console2.log("swaperUsdcAmountAfter", swaperUsdcAmountAfter / 10 ** ERC20(usdcContract).decimals(), "USDC");
        console2.log("pairerUsdcAmountBefore", pairerUsdcAmountBefore / 10 ** ERC20(usdcContract).decimals(), "USDC");
        console2.log("pairerUsdcAmountAfter", pairerUsdcAmountAfter / 10 ** ERC20(usdcContract).decimals(), "USDC");
        CryptoSwap.Leg memory openerLegAfter = cryptoSwap.queryLeg(1);
        console2.log(
            "openerLeg benchPrice:",
            uint256(openerLeg.benchPrice) / 10 ** priceFeeds.priceFeedDecimals(openerLeg.tokenAddress),
            priceFeeds.description(openerLeg.tokenAddress),
            uint256(openerLeg.benchPrice)
        );
        console2.log(
            "openerLeg latestPrice:",
            uint256(openerLegAfter.benchPrice) / 10 ** priceFeeds.priceFeedDecimals(openerLegAfter.tokenAddress),
            priceFeeds.description(openerLegAfter.tokenAddress),
            uint256(openerLegAfter.benchPrice)
        );
        CryptoSwap.Leg memory pairLegAfter = cryptoSwap.queryLeg(2);
        console2.log(
            "pairLeg benchPrice:",
            uint256(pairLeg.benchPrice) / 10 ** priceFeeds.priceFeedDecimals(pairLeg.tokenAddress),
            priceFeeds.description(pairLeg.tokenAddress),
            uint256(pairLeg.benchPrice)
        );

        console2.log(
            "pairLeg latestPrice:",
            uint256(pairLegAfter.benchPrice) / 10 ** priceFeeds.priceFeedDecimals(pairLegAfter.tokenAddress),
            priceFeeds.description(pairLegAfter.tokenAddress),
            uint256(pairLegAfter.benchPrice)
        );
        console2.log("cryptoSwapUsdcAmountBefore", cryptoSwapUsdcAmountBefore);
        console2.log("cryptoSwapUsdcAmountAfter", cryptoSwapUsdcAmountAfter);
    }

    // todo add fuzzy funciton based on below test
    function test_showLegsInfo() external {
        vm.selectFork(mainnetFork);
        address swaper1 = address(0x66666);
        uint256 swaperUsdcAmount1 = cryptoSwap.notionalValueOptions(1); // 10e6 10 USDC
        deal(usdcContractAddress, swaper1, swaperUsdcAmount1);

        address swaper2 = address(0x77777);
        uint256 swaperUsdcAmount2 = cryptoSwap.notionalValueOptions(2); // 100e6 100 USDC
        deal(usdcContractAddress, swaper2, swaperUsdcAmount2);

        address swaper3 = address(0x88889);
        uint256 swaperUsdcAmount3 = cryptoSwap.notionalValueOptions(3); // 1000e6 1000 USDC
        deal(usdcContractAddress, swaper3, swaperUsdcAmount3);

        address pairer1 = address(0x66666999);
        uint256 pairerUsdcAmount1 = cryptoSwap.notionalValueOptions(1); // 10e6 10 USDC
        deal(usdcContractAddress, pairer1, pairerUsdcAmount1);

        address pairer2 = address(0x77777999);
        uint256 pairerUsdcAmount2 = cryptoSwap.notionalValueOptions(2); // 100e6 100 USDC
        deal(usdcContractAddress, pairer2, pairerUsdcAmount2);

        uint256 startDate = block.timestamp + 1 days;
        vm.startPrank(swaper1);

        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount1);
        cryptoSwap.openSwap({
            notionalId: 1,
            notionalCount: 1,
            legToken: ethTokenAddress,
            _startDate: uint64(startDate),
            _periodType: CryptoSwap.PeriodInterval.MONTHLY,
            _totalIntervals: 1,
            yieldId: yieldIds[0]
        }); // yieldId yearn

        vm.stopPrank();

        uint256 startDate2 = block.timestamp + 2 days;
        vm.startPrank(swaper2);

        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount2);
        cryptoSwap.openSwap({
            notionalId: 2,
            notionalCount: 1,
            legToken: ethTokenAddress,
            _startDate: uint64(startDate2),
            _periodType: CryptoSwap.PeriodInterval.MONTHLY,
            _totalIntervals: 1,
            yieldId: yieldIds[0]
        }); // yieldId yearn

        vm.stopPrank();

        uint256 startDate3 = block.timestamp + 3 days;
        vm.startPrank(swaper3);

        usdcContract.approve(address(cryptoSwap), swaperUsdcAmount3);
        cryptoSwap.openSwap({
            notionalId: 3,
            notionalCount: 1,
            legToken: btcTokenAddress,
            _startDate: uint64(startDate3),
            _periodType: CryptoSwap.PeriodInterval.MONTHLY,
            _totalIntervals: 1,
            yieldId: yieldIds[0]
        }); // yieldId yearn

        vm.stopPrank();

        vm.startPrank(pairer1);
        usdcContract.approve(address(cryptoSwap), pairerUsdcAmount1);
        cryptoSwap.pairSwap(1, pairerUsdcAmount1, btcTokenAddress, yieldIds[0]); // pair legId = 1
        vm.stopPrank();

        vm.startPrank(pairer2);
        usdcContract.approve(address(cryptoSwap), pairerUsdcAmount2);
        cryptoSwap.pairSwap(2, pairerUsdcAmount2, btcTokenAddress, yieldIds[0]); // pair legId = 2
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
}
