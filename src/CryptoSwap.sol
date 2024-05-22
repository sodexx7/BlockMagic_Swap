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

    address private immutable settledStableToken; // users should deposit the stable coin to the contract when openSwap
    // TODO  only support one stableCoin?
    mapping(uint8 => uint256) public notionalValueOptions; // notion value options, 1: 100, 2: 1000, 3: 3000 owner can
        // modified

    enum Status {
        OPEN,
        ACTIVE,
        SETTLED,
        CANCELLED // User cancelled the order or no taker

    }

    enum LegType {
        OPENER,
        PAIRER
    }

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
     *
     */
    // struct Leg {
    //     address swaper;
    //     address tokenAddress;
    //     uint256 notionalAmount;
    //     // uint256 settledStableTokenAmount;
    //     uint8 yieldId;
    //     int256 balance;
    //     int256 benchPrice;
    //     uint64 startDate;
    //     /// @dev 0: not taken (open status), pairLegId>1: taken (active status)
    //     uint64 pairLegId;
    //     Status status;
    // }

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
        LegType legType;
    }

    /**
     * @notice SwapDealInfo, when open the swap, should record the swap info, such as periodTime
     * @param status     The status of the swap
     * @param updateDate  When trigger the swap execute, should record the dealDate as updateDate
     */
    struct SwapDealInfo {
        uint64 updateDate;
        uint32 periodInterval;
        uint8 totalIntervals;
        Status status;
    }
    //info  based on needs, can add more info about one swap Deal. Maybe can configed into another contract like AAVE

    uint64 public maxLegId = 1; // maxLegId's init value is 1

    /// @notice The legs
    /// @dev legId,
    /// @notice get legInfo by querying the legId, get all legs info by combing maxLegId
    /// @notice if want to used by external service, like chainlink, can use the legId
    mapping(uint256 => Leg) public legs;

    // TODO: when user deposit token; how to deal with yield?
    // TODO: maintian the yield info for each leg
    mapping(uint64 => uint256) public legIdShares;

    // legId => SwapDealInfo
    mapping(uint64 => SwapDealInfo) public swapDealInfos;

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

    // TODO check Ownable(msg.sender)
    constructor(
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
        require(_periodType <= 3, "Invalid period type");

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

        for (uint256 i; i < notionalCount; i++) {
            uint64 legId = _createLeg({
                legToken: legToken,
                notionalAmount: notionalValueOptions[notionalId],
                balance: int256(notionalValueOptions[notionalId]),
                status: Status.Open,
                startDate: _startDate,
                pairLegId: 0,
                benchPrice: 0,
                yieldId: yieldId,
                LegType: LegType.OPENER
            });

            SwapDealInfo[legId] = SwapDealInfo({
                updateDate: _startDate,
                periodInterval: _periodType,
                totalIntervals: _totalIntervals,
                status: Status.OPEN
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

        uint64 pairLegId = _createLeg({
            legToken: pairToken,
            notionalAmount: notionalAmount,
            balance: int256(notionalAmount),
            pairLegId: originalLegId,
            benchPrice: pairLegTokenLatestPrice,
            yieldId: yieldId,
            LegType: LegType.OPENER
        });

        legs[originalLegId].pairLegId = pairLegId;
        legs[originalLegId].status = Status.Active;

        SwapDealInfo[legId].status = Status.Active;

        int256 originalLegPrice = priceFeeds.getLatestPrice(originalLeg.tokenAddress);
        legs[originalLegId].benchPrice = originalLegPrice;

        emit PairSwap(originalLegId, pairLegId, msg.sender);
    }

    // This function was called by chainlink or by the user
    // TODO Use historical price instead
    // From the traditonal finance perspective, the swap should be settled at the end of the period, meanwhile this
    // function can be called by the chianlink automation
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

        // only can be called in one period
        SwapDealInfo memory swapDealInfo = SwapDealInfo[legId];
        require(
            block.timestamp >= swapDealInfo.updateDate
                && block.timestamp <= swapDealInfo.updateDate + swapDealInfo.periodInterval,
            "The swap can only be settled in one period"
        );

        // compare the price change for the two legs
        uint256 profit;
        uint64 loserLegId = legId;
        (profit, roundWinner, loserLegId) = calculatePerformanceForPeriod(
            originalLeg, pairLeg, swapDealInfo.updateDate, swapDealInfo.updateDate + swapDealInfo.periodInterval
        );
        address winner = legs[loserLegId].swaper;

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

        SwapDealInfo[legId].updateDate += swapDealInfo.periodInterval;
        if (swapDealInfo.updateDate == _getEndDate(legId)) {
            SwapDealInfo[legId].status = Status.Settled;
        }

        // TODO , endDate, just close this swap.
        emit SettleSwap(legId, winner, settledStableToken, profit);

        // TODO
        // Related test cases
        // Confirm the formula is right, especially confirm the loss of precision
    }

    // TODO the bankrupt logic, if user lose all, just retunr0
    // return winner, the total profit, if trigger
    // winner,loser,profit, states(whether or not is backrupt for loser)
    // TODO, when updating the leg Data Strucute, should updating this function

    /**
     * @notice Query the history performance of the leg
     *         if no profit, just return 0
     * @param legId The legId
     * @return isBankrupt Whether or not the loser is bankrupt
     * @return winnerLegId The winner of the swap
     * @return loserLegId The loser of the swap
     * @return totalProfit The total profit of the winner
     * @return latestDate The latest dealing date of the swap
     */
    function queryHistoryPerformance(uint64 legId) public view returns (bool, uint64, uint64, int256, uint256) {
        Leg memory leg = legs[legId];
        Leg memory pairLeg = legs[leg.pairLegId];

        // get the OPERNER TYPE leg
        uint64 openLeg = leg.legType == LegType.OPENER ? legId : leg.pairLegId;
        swapDealInfo memory swapDealInfo = swapDealInfos[openLeg];
        uint256 startDate = swapDealInfo.startDate;
        uint32 periodInterval = swapDealInfo.periodInterval;
        uint256 numberOfPeriods = (block.timestamp - startDate) / periodInterval;
        bool isBankrupt = false;
        if (numberOfPeriods == 1) {
            return (false, 0, 0, 0, 0);
        }

        mapping(uint256 => uint256) predictBalances;
        uint256 legStartBalance = legs[legId].balance;
        uint256 pairlegStartBalance = legs[leg.pairLegId].balance;

        predictBalances[legId] = legs[legId].balance;
        predictBalances[leg.pairLegId] = legs[leg.pairLegId].balance;

        for (uint256 i; i < numberOfPeriods; i++) {
            (profit, roundWinner, roundLoser) = calculatePerformanceForPeriod(
                legA, pairLeg, updateDate + periodInterval * (i), updateDate + periodInterval * (1 + i)
            );
            // if trigger the bankrupt, just return 0
            predictBalances[roundWinner] += profit;
            predictBalances[roundLoser] -= profit;
            if (legsBalances[roundWinner] < 0) {
                loserlgId = roundWinner;
                isBankrupt = true;
                break;
            }
            if (legsBalances[roundLoser] < 0) {
                loserlgId = roundLoser;
                isBankrupt = true;
                break;
            }
        }
        uint64 winnerLegId = predictBalances[legId] > legStartBalance ? legId : leg.pairLegId;
        uint256 totalProfit = predictBalances[winnerLegId] - legStartBalance;
        return
            (isBankrupt, winnerLegId, legs[winnerLegId].pairLegId, totalProfit, updateDate + periodInterval * (1 + i));
    }

    // todo reentrance check
    function withdraw(uint64 legId) external {
        uint64 pairLegId = legs[legId].pairLegId;
        require(
            legs[legId].swaper == msg.sender || legs[pairLegId].swaper == msg.sender,
            "Only the swaper can withdraw the leg"
        );

        (bool isBankrupt, uint64 winnerLegId, uint64 loserlegId, int256 profit, uint256 latestDate) =
            getHistoryPerformance(legId);
        if (isBankrupt && legs[loserlegId].swaper == msg.sender) {
            // add emit the user have been bankrupt
            return 0;
        }

        IERC20(settledStableToken).transfer(legs[winnerLegId].swaper, profit);

        uint64 openerleg = legs[legId].legType == LegType.OPENER ? legId : pairLegId;
        swapDealInfos[legId].updateDate = latestDate;
        if (latestDate == _getEndDate(legId)) {
            SwapDealInfo[legId].status = Status.Settled;
        }

        // emit the withdraw event
    }

    /**
     * @notice Compare the performance of the two legs for the period
     *     This funtion don't limit the legAId and legBId are paired.
     * @param legAId The legAId
     * @param legBId The legBId
     * @param startDate The start date of the period
     * @param endDate The end date of the period
     * @return profit The profit of the winner
     * @return winner The winner of the swap
     * @return loser The loser of the swap
     */
    function calculatePerformanceForPeriod(
        uint64 legAId,
        uint64 legBId,
        uint256 startDate,
        uint256 endDate
    )
        internal
        view
        returns (uint256, uint64, uint64)
    {
        Leg memory legA = legs[legAId];
        Leg memory legB = legs[legBId];
        uint256 profit;
        uint64 winnerLegId;
        uint64 loserLegId;
        (int256 legAStartPrice, int256 legAEndPrice) = getPricesForPeriod(legA, startDate, endDate);
        (int256 legBStartPrice, int256 legBEndPrice) = getPricesForPeriod(legB, startDate, endDate);

        uint256 notionalAmount = originalLeg.notionalAmount;

        if (legAEndPrice * legBStartPrice == legBEndPrice * legAStartPrice) {
            return (0, address(0), address(0));
        } else if (legAEndPrice * legBStartPrice > legBEndPrice * legAStartPrice) {
            // Notice: For keep the precision, should multiply the notionalAmount at the end. if not, the profit will be
            // less than 0 when all leg prices are decreased
            // TODO, can apply the limit? as x1/x - y1/y+x2/x1-y2/y1+…, move the division into the last operation
            profit = (
                uint256(
                    originalLegTokenLatestPrice * pairLeg.benchPrice - originalLeg.benchPrice * pairLegTokenLatestPrice
                ) * notionalAmount
            ) / uint256(originalLeg.benchPrice * pairLeg.benchPrice);
            winner = legA.swaper;
            loser = legB.swaper;
            winnerLegId = legA.legId;
            loserLegId = legB.legId;
            console2.log("winner: maker");
        } else {
            profit = (
                uint256(
                    pairLegTokenLatestPrice * originalLeg.benchPrice - originalLegTokenLatestPrice * pairLeg.benchPrice
                ) * notionalAmount
            ) / uint256(originalLeg.benchPrice * pairLeg.benchPrice);
            console2.log("winner: taker");
            winner = legB.swaper;
            loser = legA.swaper;
            winnerLegId = legB.legId;
            loserLegId = legA.legId;
        }
        return (profit, winnerLegId, loserLegId);
    }

    function _createLeg(
        address legToken,
        uint256 notionalAmount,
        int256 balance,
        uint64 pairLegId,
        int256 benchPrice,
        uint8 yieldId,
        LegType legType
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
            pairLegId: pairLegId, // Status.Open also means the pairLegId is 0
            benchPrice: benchPrice, // TODO more check(store need to compare with the deposited USDC) BenchPrice is
            LegType: legType
        });
        // updatated on
        // the startDate

        legs[maxLegId] = leg;
        return maxLegId++;
    }

    /// legA.tokenAddress is ledA.feedId
    function getPricesForPeriod(
        uint64 legId,
        uint256 startDate,
        uint256 endDate
    )
        public
        view
        returns (int256, int256)
    {
        address legToken = legs[legId].tokenAddress;
        int256 startPrice = priceFeeds.getHistoryPrice(legToken, startDate);
        int256 endPrice = priceFeeds.getHistoryPrice(legToken, endDate);

        return (startPrice, endPrice);
    }

    function queryLeg(uint64 legId) external view returns (Leg memory) {
        return legs[legId];
    }

    ///////////////////////////////////////////////////////
    //              HELPER FUNCTIONS                    ///
    ///////////////////////////////////////////////////////

    // TODO use another way to implement this
    function _handlePeriod(periodInterval) internal returns (uint32 periodInterval) {
        if (_periodType == 0) {
            periodInterval = 7 days;
        } else if (_periodType == 1) {
            periodInterval = 30 days;
        } else if (_periodType == 2) {
            periodInterval = 90 days;
        } else {
            periodInterval = 365 days;
        }
    }

    function _getEndDate(uint64 legId) internal view returns (uint64) {
        SwapDealInfo memory swapDealInfo = swapDealInfos[legId];
        return swapDealInfo.startDate + _handlePeriod(swapDealInfo.periodInterval) * swapDealInfo.totalIntervals;
    }

    // TODO ,temp function should consider move to YieldStrategies contract. Are there problems related with applying
    // notionalAmount directly?
    // convert the share to the underlying amount
    function convertShareToUnderlyingAmount(uint64 legId, uint256 profit) internal view returns (uint256) {
        uint256 shares = legIdShares[legId] * profit / legs[legId].notionalAmount;
        return shares;
    }
}
