// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { console2 } from "forge-std/src/console2.sol";
import "./interfaces/IPriceFeeds.sol";
import "./interfaces/IYieldStrategies.sol";

contract CryptoSwap is Ownable {
    using SafeERC20 for IERC20;

    IPriceFeeds private immutable priceFeeds;
    IYieldStrategies private immutable YieldStrategies;

    /// @notice The balances of the users
    /// @return balances the balances of the users
    mapping(address => uint256) public balances;

    // // uint8 public period; // as the global period time or can be set per swap by user?
    uint64 public maxLegId = 1; // maxLegId's init value is 1
    address private immutable settledStableToken; // users should deposit the stable coin to the contract when openSwap
        // or pairSwap TODO  only support one stableCoin?
    mapping(uint8 => uint256) public notionalValueOptions; // notion value options, 1: 100, 2: 1000, 3: 3000 owner can
        // modified

    // TODO: when user deposit token; how to deal with yield?
    // TODO: maintian the yield info for each leg
    mapping(uint64 => uint256) public legIdShares;

    enum Status {
        Open,
        Active,
        Settled,
        Cancelled // User cancelled the order or no taker

    }

    // TODO: Period should be set by the user
    enum PeriodInterval {
        WEEKLY,
        MONTHLY,
        QUARTERLY,
        YEARLY
    }

    /**
     * @notice The Leg struct
     * @param swaper The address of the swaper
     * @param tokenAddress The address of the token
     * @param notionalAmount The notional value of the swap, users should select a option for the notional value
     * // //  * @param settledStableTokenAmount The amount of the stable token
     * @param balance The balance of the leg
     * @param benchPrice The price of the token when open the swap
     * @param startDate The start date of the swap
     * @param pairLegId The pair leg id
     * @param status The status of the swap
     */
    struct Leg {
        address swaper;
        address tokenAddress;
        uint256 notionalAmount;
        // uint256 settledStableTokenAmount;
        uint8 yieldId;
        int256 balance;
        int256 benchPrice;
        uint64 startDate;
        /// @dev 0: not taken (open status), pairLegId>1: taken (active status)
        uint64 pairLegId;
        Status status;
        Period period;
    }

    struct Period {
        uint64 startDate;
        uint32 periodInterval;
        uint8 totalIntervals;
        uint8 intervalCount;
    }

    /// @notice The legs
    /// @dev legId,
    /// @notice get legInfo by querying the legId, get all legs info by combing maxLegId
    /// @notice if want to used by external service, like chainlink, can use the legId
    mapping(uint256 => Leg) public legs;

    event OpenSwap(
        uint64 indexed legId,
        address indexed swaper,
        address indexed tokenAddress,
        uint256 amountOfSettleToken,
        uint256 startDate
    );
    event BatchOpenSwap(
        address indexed swaper,
        address indexed tokenAddress,
        uint64[] legIds,
        uint256 totoalAmountOfSettleToken,
        uint8 notionalCount,
        uint256 startDate
    );
    // TODO check PairSwap
    event PairSwap(uint256 indexed originalLegId, uint256 indexed pairlegId, address pairer);
    // TODO more PairSwap event cases
    event SettleSwap(uint256 indexed legId, address indexed winner, address payToken, uint256 profit);
    event NoProfitWhileSettle(uint256 indexed legId, address indexed swaper, address indexed pairer);

    // event, who win the swap, how much profit
    // event, the latest notional of the swaper and pairer after the settleSwap

    // init the contract with the period and the yield strategy
    // TODO check Ownable(msg.sender)
    constructor(
        // // uint8 _period,
        address _settledStableToken,
        address priceFeedsAddress,
        address YieldStrategiesAddress,
        uint8[] memory notionalIds,
        uint256[] memory notionalValues
    )
        Ownable(msg.sender)
    {
        // // period = _period;
        settledStableToken = _settledStableToken;
        priceFeeds = IPriceFeeds(priceFeedsAddress);
        YieldStrategies = IYieldStrategies(YieldStrategiesAddress);

        require(
            notionalIds.length == notionalValues.length,
            "The length of the notionalIds and notionalValues should be equal"
        );
        for (uint8 i; i < notionalIds.length; i++) {
            notionalValueOptions[notionalIds[i]] = notionalValues[i];
        }
    }

    // TODO: When open the swap, should grant the contract can use the legToken along with the notional
    // TODO: more conditions check, such as user should have enough token to open the swap
    // TODO: For the legToken, should supply options for user's selection. (NOW, BTC, ETH, USDC)
    // TODO: TYPE? Deposited stable coin or directly apply legToken.(Now only support Deposited stable coin)
    // TODO: Maybe need to use wETH instead of ETH directly to apply yield
    function openSwap(
        uint8 notionalId,
        uint8 notionalCount,
        address legToken,
        uint64 _startDate,
        uint8 _periodType,
        uint8 _totalIntervals,
        uint8 yieldId
    )
        external
    {
        require(notionalId >= 1, "The notionalId should be greater than 0");
        require(_startDate > block.timestamp, "_startDate should be greater than now"); // TODO change to custom error

        uint256 balance = notionalValueOptions[notionalId] * notionalCount;
        require(
            IERC20(settledStableToken).allowance(msg.sender, address(this)) >= balance,
            "The user should have grant enough settleStable token to open the swap"
        );

        // When transfer USDC to the contract, immediatly or when pairSwap?
        // TODO below logic should optimize, involved two approves and two transfers, should check
        // address yieldAddress = YieldStrategies.getYieldStrategy(yieldId);
        IERC20(settledStableToken).transferFrom(msg.sender, address(this), balance);
        IERC20(settledStableToken).approve(address(YieldStrategies), balance);
        uint256 shares = YieldStrategies.depositYield(yieldId, balance, address(this));
        legIdShares[maxLegId] = shares;

        // Adding Period to the Leg
        Period memory period = _handlePeriod(_startDate, _periodType, _totalIntervals);

        uint64 legId = maxLegId;
        for (uint256 i; i < notionalCount; i++) {
            _createLeg({
                legToken: legToken,
                notionalAmount: notionalValueOptions[notionalId],
                period: period,
                balance: int256(notionalValueOptions[notionalId]),
                status: Status.Open,
                startDate: _startDate,
                pairLegId: 0,
                benchPrice: 0,
                yieldId: yieldId
            });
        }
        if (notionalCount == 1) {
            emit OpenSwap(legId, msg.sender, legToken, balance, _startDate);
        } else {
            uint64[] memory legIds = new uint64[](notionalCount);
            for (uint256 i; i < notionalCount; i++) {
                legIds[i] = uint64(legId++);
            }
            emit BatchOpenSwap(msg.sender, legToken, legIds, balance, notionalCount, _startDate);
        }
    }

    function pairSwap(uint64 originalLegId, uint256 notionalAmount, address pairToken, uint8 yieldId) external {
        require(notionalAmount == legs[originalLegId].notionalAmount, "Notional amount should pair the leg Value");

        Leg memory originalLeg = legs[originalLegId];
        require(originalLeg.status == Status.Open, "The leg is not open");
        require(originalLeg.startDate > block.timestamp, "The leg is expired");

        // Transfer the settledStableToken to the contract
        require(
            IERC20(settledStableToken).balanceOf(msg.sender) >= notionalAmount,
            "The user should have enough token to pair the swap"
        );

        // TODO below logic should optimize
        // address yieldAddress = YieldStrategies.getYieldStrategy(yieldId);
        IERC20(settledStableToken).transferFrom(msg.sender, address(this), notionalAmount);
        IERC20(settledStableToken).approve(address(YieldStrategies), notionalAmount);
        uint256 shares = YieldStrategies.depositYield(yieldId, notionalAmount, address(this));
        legIdShares[maxLegId] = shares;

        // TODO: benchPrice should be 0 and updated on the startDate
        int256 pairLegTokenLatestPrice = priceFeeds.getLatestPrice(pairToken);

        uint64 pairLegId = _createLeg(
            pairToken,
            notionalAmount,
            int256(notionalAmount),
            Status.Active,
            originalLeg.startDate,
            originalLegId,
            pairLegTokenLatestPrice,
            yieldId
        );

        legs[originalLegId].pairLegId = pairLegId;
        legs[originalLegId].status = Status.Active;

        int256 originalLegPrice = priceFeeds.getLatestPrice(originalLeg.tokenAddress);
        legs[originalLegId].benchPrice = originalLegPrice;

        emit PairSwap(originalLegId, pairLegId, msg.sender);
    }

    // This function was called by chainlink or by the user
    // TODO Use historical price instead
    /**
     * @dev The function will settle the swap, and the winner will get the profit. the profit was calculated by the
     * increased rate mulitiply the benchSettlerAmount
     *    x : the price of the original leg's underlying at startDate
     *    x`: the price of the original leg's underlying at fixingDate
     *    y : the price of the pair leg's underlying at startDate
     *    y`: the price of the pair leg's underlying at fixingDate
     *    notionalAmount: the notional value of the two legs
     *
     *    when x`/x > y`/y, the profit is (x`*y - x*y`) * notionalAmount / (x*y)
     *    when y`/y > x`/x, the profit is (y`*x - y*x`) * notionalAmount / (x*y)
     *    How to get the formula:
     *    if y`/y > x`/x
     *    (y`/y - x`/x) * notionalAmount => (y`*x - y*x`) / y*x*notionalAmount => (y`*x - y*x`) * notionalAmount / (x*y)
     */
    function settleSwap(uint64 legId) external {
        // TODO more conditions check
        // 1. time check
        Leg memory originalLeg = legs[legId];
        Leg memory pairLeg = legs[originalLeg.pairLegId];
        require(originalLeg.status == Status.Active && pairLeg.status == Status.Active, "The leg is not active");

        uint256 notionalAmount = originalLeg.notionalAmount;

        // TODO precious and arithmetic calculation check, security check
        int256 originalLegTokenLatestPrice = priceFeeds.getLatestPrice(originalLeg.tokenAddress);
        int256 pairLegTokenLatestPrice = priceFeeds.getLatestPrice(pairLeg.tokenAddress);

        // compare the price change for the two legs
        address winner;
        uint256 profit;
        uint64 loserLegId = legId;
        // TODO, It's rare that existed the equal, should limited in a range(as 0.1% -> 0.2%)
        if (originalLegTokenLatestPrice * pairLeg.benchPrice == pairLegTokenLatestPrice * originalLeg.benchPrice) {
            // the increased rates of  both legToken price are all equal
            emit NoProfitWhileSettle(legId, originalLeg.swaper, pairLeg.swaper);
            return;
        } else if (originalLegTokenLatestPrice * pairLeg.benchPrice > pairLegTokenLatestPrice * originalLeg.benchPrice)
        {
            profit = (
                uint256(
                    originalLegTokenLatestPrice * pairLeg.benchPrice - originalLeg.benchPrice * pairLegTokenLatestPrice
                ) * notionalAmount
            ) / uint256(originalLeg.benchPrice * pairLeg.benchPrice);
            winner = originalLeg.swaper;
            console2.log("winner: maker");
            //TODO check update notional value, check the precious
            legs[legId].balance += int256(profit);
            legs[originalLeg.pairLegId].balance -= int256(profit);
            loserLegId = originalLeg.pairLegId;
        } else {
            profit = (
                uint256(
                    pairLegTokenLatestPrice * originalLeg.benchPrice - originalLegTokenLatestPrice * pairLeg.benchPrice
                ) * notionalAmount
            ) / uint256(originalLeg.benchPrice * pairLeg.benchPrice);

            legs[legId].balance -= int256(profit);
            legs[originalLeg.pairLegId].balance += int256(profit);
            console2.log("winner: taker");
            winner = pairLeg.swaper;
        }
        // console2.log("winner:", winner);
        // uint8 usdcDecimals = ERC20(settledStableToken).decimals();
        // console2.log("profit:", profit / 10**usdcDecimals, "USDC");

        // TODO update bench price for the two legs
        legs[legId].benchPrice = originalLegTokenLatestPrice;
        legs[originalLeg.pairLegId].benchPrice = pairLegTokenLatestPrice;

        // IERC20(settledStableToken).transfer(winner, profit);

        // TODO below logic should optimize
        address yieldAddress = YieldStrategies.getYieldStrategy(legs[loserLegId].yieldId);
        uint256 shares = convertShareToUnderlyingAmount(loserLegId, profit);
        IERC20(yieldAddress).transfer(address(YieldStrategies), shares);

        // TODO below function should check
        console2.log("expected profit", profit);
        uint256 actualProfit = YieldStrategies.withdrawYield(legs[loserLegId].yieldId, shares, winner);
        console2.log("actual profit", actualProfit);

        // IERC20(settledStableToken).transfer(winner, actualProfit);

        // when end, the status of the two legs should be settled
        legs[legId].status = Status.Settled;
        legs[originalLeg.pairLegId].status = Status.Settled;

        // TODO , endDate, just close this swap.
        emit SettleSwap(legId, winner, settledStableToken, profit);

        // TODO
        // Related test cases
        // Confirm the formula is right, especially confirm the loss of precision
    }

    /// legA.tokenAddress is ledA.feedId
    function getPerformanceForPeriod(
        Leg memory leg,
        uint256 startDate,
        uint256 endDate
    )
        public
        view
        returns (int256, int256)
    {
        int256 startPrice = priceFeeds.getHistoryPrice(leg.tokenAddress, startDate);
        int256 endPrice = priceFeeds.getHistoryPrice(leg.tokenAddress, endDate);

        return (startPrice, endPrice);
    }

    function comparePerformanceForPeriod(
        Leg memory legA,
        Leg memory legB,
        uint256 startDate,
        uint256 endDate
    )
        public
        view
        returns (uint256, address, address)
    {
        uint256 profit;
        address winner;
        address loser;
        (int256 legAStartPrice, int256 legAEndPrice) = getPerformanceForPeriod(legA, startDate, endDate);
        (int256 legBStartPrice, int256 legBEndPrice) = getPerformanceForPeriod(legB, startDate, endDate);

        if (legAEndPrice * legBStartPrice == legBEndPrice * legAStartPrice) {
            return (0, address(0), address(0));
        } else if (legAEndPrice * legBStartPrice > legBEndPrice * legAStartPrice) {
            profit = (uint256(legAEndPrice * legBStartPrice - legAStartPrice * legBEndPrice))
                / uint256(legAStartPrice * legBStartPrice);
            winner = legA.swaper;
            loser = legB.swaper;
            console2.log("winner: maker");
        } else {
            profit = (uint256(legBEndPrice * legAStartPrice - legAEndPrice * legBStartPrice))
                / uint256(legAStartPrice * legBStartPrice);
            console2.log("winner: taker");
            winner = legB.swaper;
            loser = legA.swaper;
        }
        return (profit, winner, loser);
    }

    // function _updatePosition(uint256 masterId, uint256 contractId) internal { // TODO, Keep for FrontEnd version
    function _updatePosition(Leg legA, Leg legB) internal {
        // SwapContract storage swapContract = swapContracts[masterId][contractId];
        // Period storage period = swapContract.period; // TODO, Keep for FrontEnd version
        Period storage period = legA.period;

        uint256 startDate = period.startDate;
        uint256 periodInterval = period.periodInterval;

        // 30/360 => 30 days per month / 360 days per year
        // TODO: Need to calculate the number of time to loop
        uint256 numberOfPeriods = (block.timestamp - startDate) / periodInterval;
        while (block.timestamp >= startDate + (periodInterval * period.intervalCount)) {
            uint256 intervalCount = period.intervalCount;

            (profit, winner, loser) = comparePerformanceForPeriod(legA, legB, startDate, endDate);
        }
    }

    function _createLeg(
        address legToken,
        uint256 notionalAmount,
        Period period,
        int256 balance,
        Status status,
        uint64 startDate,
        uint64 pairLegId,
        int256 benchPrice,
        uint8 yieldId
    )
        internal
        returns (uint64 legId)
    {
        Leg memory leg = Leg({
            swaper: msg.sender,
            tokenAddress: legToken,
            notionalAmount: notionalAmount,
            yieldId: yieldId,
            balance: balance,
            startDate: startDate,
            status: status,
            pairLegId: pairLegId, // Status.Open also means the pairLegId is 0
            benchPrice: benchPrice, // TODO more check(store need to compare with the deposited USDC) BenchPrice is
            period: period
        });
        // updatated on
        // the startDate

        legs[maxLegId] = leg;
        return maxLegId++;
    }

    function queryLeg(uint64 legId) external view returns (Leg memory) {
        return legs[legId];
    }

    ///////////////////////////////////////////////////////
    //              HELPER FUNCTIONS                    ///
    ///////////////////////////////////////////////////////

    function _handlePeriod(
        uint64 _startDate,
        uint8 _periodType,
        uint8 _totalIntervals
    )
        internal
        returns (Period memory period)
    {
        period = Period({ startDate: _startDate, periodInterval: 0, totalIntervals: _totalIntervals, intervalCount: 0 });

        if (_periodType == 0) {
            period.periodInterval = 7 days;
        } else if (_periodType == 1) {
            period.periodInterval = 30 days;
        } else if (_periodType == 2) {
            period.periodInterval = 90 days;
        } else {
            period.periodInterval = 365 days;
        }
    }

    // TODO ,temp function should consider move to YieldStrategies contract. Are there problems related with applying
    // notionalAmount directly?
    // convert the share to the underlying amount
    function convertShareToUnderlyingAmount(uint64 legId, uint256 profit) internal view returns (uint256) {
        uint256 shares = legIdShares[legId] * profit / legs[legId].notionalAmount;
        return shares;
    }
}
