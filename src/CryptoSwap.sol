// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IPriceFeeds.sol";
import "./interfaces/IYieldStrategies.sol";

contract CryptoSwap is Ownable {
    using SafeERC20 for IERC20;

    IPriceFeeds private immutable priceFeeds;
    IYieldStrategies private immutable YieldStrategies;

    uint64 public maxLegId = 1;
    address private immutable settledStableToken;
    mapping(uint8 => uint256) public notionalValueOptions;

    mapping(uint64 => uint256) public legIdShares;

    enum Status {
        Open,
        Active,
        Settled,
        Cancelled
    }

    enum periodType {
        Weekly,
        Monthly,
        Quarterly,
        Yearly
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
    event PairSwap(uint256 indexed originalLegId, uint256 indexed pairlegId, address pairer);
    event SettleSwap(uint256 indexed legId, address indexed winner, address payToken, uint256 profit);
    event NoProfitWhileSettle(uint256 indexed legId, address indexed swaper, address indexed pairer);

    constructor(
        address _settledStableToken,
        address priceFeedsAddress,
        address YieldStrategiesAddress,
        uint8[] memory notionalIds,
        uint256[] memory notionalValues
    )
        Ownable(msg.sender)
    {
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

    function openSwap(
        uint8 notionalId,
        uint8 notionalCount,
        address legToken,
        uint64 startDate,
        uint8 yieldId
    )
        external
    {
        require(notionalId >= 1, "The notionalId should be greater than 0");
        require(startDate > block.timestamp, "startDate should be greater than now"); // TODO change to custom error

        uint256 balance = notionalValueOptions[notionalId] * notionalCount;
        require(
            IERC20(settledStableToken).allowance(msg.sender, address(this)) >= balance,
            "The user should have grant enough settleStable token to open the swap"
        );

        address yieldAddress = YieldStrategies.getYieldStrategy(yieldId);
        IERC20(settledStableToken).transferFrom(msg.sender, address(this), balance);
        IERC20(settledStableToken).approve(address(YieldStrategies), balance);
        uint256 shares = YieldStrategies.depositYield(yieldId, balance, address(this));
        legIdShares[maxLegId] = shares;

        uint64 legId = maxLegId;
        for (uint256 i; i < notionalCount; i++) {
            _createLeg(
                legToken,
                notionalValueOptions[notionalId],
                int256(notionalValueOptions[notionalId]),
                Status.Open,
                startDate,
                0,
                0,
                yieldId
            );
        }
        if (notionalCount == 1) {
            emit OpenSwap(legId, msg.sender, legToken, balance, startDate);
        } else {
            uint64[] memory legIds = new uint64[](notionalCount);
            for (uint256 i; i < notionalCount; i++) {
                legIds[i] = uint64(legId++);
            }
            emit BatchOpenSwap(msg.sender, legToken, legIds, balance, notionalCount, startDate);
        }
    }

    function pairSwap(uint64 originalLegId, uint256 notionalAmount, address pairToken, uint8 yieldId) external {
        require(notionalAmount == legs[originalLegId].notionalAmount, "Notional amount should pair the leg Value");

        Leg memory originalLeg = legs[originalLegId];
        require(originalLeg.status == Status.Open, "The leg is not open");
        require(originalLeg.startDate > block.timestamp, "The leg is expired");

        require(
            IERC20(settledStableToken).balanceOf(msg.sender) >= notionalAmount,
            "The user should have enough token to pair the swap"
        );

        address yieldAddress = YieldStrategies.getYieldStrategy(yieldId);
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

    /**
     * @dev The function will settle the swap, and the winner will get the profit. the profit was calculated by the
     * increased rate mulitiply the benchSettlerAmount
     *    x`: the price of the original leg's underlying at fixingDate
     *    x : the price of the original leg's underlying at startDate
     *    y`: the price of the pair leg's underlying at fixingDate
     *    y : the price of the pair leg's underlying at startDate
     *    notionalAmount: the notional value of the two legs
     *  // // *    benchSettlerAmount: the smaller settledStableTokenAmount of the two legs
     *
     *    when x`/x > y`/y, the profit is (x`*y - x*y`) * notionalAmount / (x*y)
     *    when y`/y > x`/x, the profit is (y`*x - y*x`) * notionalAmount / (y*x)
     *    How to get the formula:
     *    if y`/y > x`/x
     *    (y`/y - x`/x) * notionalAmount => (y`*x - y*x`) / y*x*notionalAmount => (y`*x - y*x`) * notionalAmount / (y*x)
     */
    function settleSwap(uint64 legId) external {
        // TODO more conditions check
        // 1. time check
        Leg memory originalLeg = legs[legId];
        Leg memory pairLeg = legs[originalLeg.pairLegId];
        require(originalLeg.status == Status.Active && pairLeg.status == Status.Active, "The leg is not active");

        uint256 notionalAmount = originalLeg.notionalAmount;
        int256 originalLegTokenLatestPrice = priceFeeds.getLatestPrice(originalLeg.tokenAddress);
        int256 pairLegTokenLatestPrice = priceFeeds.getLatestPrice(pairLeg.tokenAddress);

        // compare the price change for the two legs
        address winner;
        uint256 profit;
        uint64 loserLegId = legId;
        if (originalLegTokenLatestPrice * pairLeg.benchPrice == pairLegTokenLatestPrice * originalLeg.benchPrice) {
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
            winner = pairLeg.swaper;
        }
        uint8 usdcDecimals = ERC20(settledStableToken).decimals();

        legs[legId].benchPrice = originalLegTokenLatestPrice;
        legs[originalLeg.pairLegId].benchPrice = pairLegTokenLatestPrice;

        address yieldAddress = YieldStrategies.getYieldStrategy(legs[loserLegId].yieldId);
        uint256 shares = convertShareToUnderlyingAmount(loserLegId, profit);
        IERC20(yieldAddress).transfer(address(YieldStrategies), shares);

        uint256 actualProfit = YieldStrategies.withdrawYield(legs[loserLegId].yieldId, shares, winner);
        legs[legId].status = Status.Settled;
        legs[originalLeg.pairLegId].status = Status.Settled;

        emit SettleSwap(legId, winner, settledStableToken, profit);
    }

    function _createLeg(
        address legToken,
        uint256 notionalAmount,
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
            pairLegId: pairLegId,
            benchPrice: benchPrice
        });

        legs[maxLegId] = leg;
        return maxLegId++;
    }

    function queryLeg(uint64 legId) external view returns (Leg memory) {
        return legs[legId];
    }

    function convertShareToUnderlyingAmount(uint64 legId, uint256 profit) internal view returns (uint256) {
        uint256 shares = legIdShares[legId] * profit / legs[legId].notionalAmount;
        return shares;
    }

    // temp function, for test only in arb
    function withDrawUSDC(uint256 amount) external onlyOwner {
        IERC20(settledStableToken).transfer(msg.sender, amount);
    }
}
