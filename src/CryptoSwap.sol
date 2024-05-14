// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { console2 } from "forge-std/src/console2.sol";
import "./PriceFeeds.sol";
import "./YieldStrategys.sol";

contract CryptoSwap is Ownable, PriceFeeds, YieldStrategys {
    using SafeERC20 for IERC20;

    /// @notice The balances of the users
    /// @return balances the balances of the users
    mapping(address => uint256) public balances;

    // // uint8 public period; // as the global period time or can be set per swap by user?
    uint64 public maxLegId = 1; // maxLegId's init value is 1
    address private immutable settledStableToken; // users should deposit the stable coin to the contract when openSwap
        // or pairSwap TODO  only support one stableCoin?
    mapping(uint8 => uint256) public notionalValueOptions; // notion value options, 1: 100, 2: 1000, 3: 3000 owner can
        // modified

    /// @notice Address of the yield strategy
    /// @return yieldAddress the address of the yield strategy
    struct YieldStrategy {
        address yieldAddress;
    }
    // TODO: More yield strategy info, or as ta separate contract?
    // TODO: when user deposit token; how to deal with yield?

    mapping(uint8 => YieldStrategy) public yieldStrategys; // 1: Aave, 2: Compound, 3: Yearn

    enum Status {
        Open,
        Active,
        Settled,
        Cancelled // User cancelled the order or no taker

    }

    // TODO: Period should be set by the user
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
        address _tokenAddress,
        address _priceFeed,
        uint8[] memory notionalIds,
        uint256[] memory notionalValues,
        uint8[] memory yieldIds,
        address[] memory yieldAddress
    )
        Ownable(msg.sender)
        PriceFeeds(_tokenAddress, _priceFeed)
        YieldStrategys(yieldIds, yieldAddress)
    {
        // // period = _period;
        settledStableToken = _settledStableToken;
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

        // When transfer USDC to the contract, immediatly or when pairSwap?
        // TODO below logic should optimize
        IERC20(settledStableToken).transferFrom(msg.sender, address(this), balance);
        IERC20(settledStableToken).approve(yieldStrategies[yieldId], balance);
        uint256 shares = depositYield(yieldId, balance, address(this));
        legIdShares[maxLegId] = shares;

        uint64 legId = maxLegId;
        for (uint256 i; i < notionalCount; i++) {
            _createLeg(
                legToken, notionalValueOptions[notionalId], int256(notionalValueOptions[notionalId]), startDate, yieldId
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

        // Transfer the settledStableToken to the contract
        require(
            IERC20(settledStableToken).balanceOf(msg.sender) >= notionalAmount,
            "The user should have enough token to pair the swap"
        );

        // TODO below logic should optimize
        IERC20(settledStableToken).transferFrom(msg.sender, address(this), notionalAmount);
        IERC20(settledStableToken).approve(yieldStrategies[yieldId], notionalAmount);
        uint256 shares = depositYield(yieldId, notionalAmount, address(this));
        legIdShares[maxLegId] = shares;

        // TODO: benchPrice should be 0 and updated on the startDate
        int256 pairLegTokenLatestPrice = getLatestPrice(pairToken);
        Leg memory pairLeg = Leg({
            swaper: msg.sender,
            tokenAddress: pairToken,
            notionalAmount: notionalAmount,
            yieldId: yieldId,
            balance: int256(notionalAmount),
            startDate: originalLeg.startDate,
            status: Status.Active,
            pairLegId: originalLegId,
            benchPrice: pairLegTokenLatestPrice
        });

        legs[maxLegId] = pairLeg;
        legs[originalLegId].pairLegId = maxLegId;
        legs[originalLegId].status = Status.Active;

        int256 originalLegPrice = getLatestPrice(originalLeg.tokenAddress);
        legs[originalLegId].benchPrice = originalLegPrice;
        maxLegId++;

        emit PairSwap(originalLegId, legs[originalLegId].pairLegId, msg.sender);
    }

    // This function was called by chainlink or by the user
    // TODO Use historical price instead
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

        // // uint256 originaSettledStableTokenAmount = originalLeg.notionalAmount;
        // // uint256 pairSettledStableTokenAmount = originalLeg.notionalAmount;
        // // uint256 benchSettlerAmount = originaSettledStableTokenAmount >= pairSettledStableTokenAmount
        // //     ? originaSettledStableTokenAmount
        // //     : pairSettledStableTokenAmount;

        uint256 notionalAmount = originalLeg.notionalAmount;

        // TODO precious and arithmetic calculation check, security check
        int256 originalLegTokenLatestPrice = getLatestPrice(originalLeg.tokenAddress);
        int256 pairLegTokenLatestPrice = getLatestPrice(pairLeg.tokenAddress);

        console2.log("originalLegTokenLatestPrice", originalLegTokenLatestPrice);
        console2.log("originalLeg.benchPrice", originalLeg.benchPrice);
        console2.log("pairLegTokenLatestPrice", pairLegTokenLatestPrice);
        console2.log("originalLeg.benchPrice", pairLeg.benchPrice);

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

            winner = pairLeg.swaper;
        }
        // console2.log("winner:", winner);
        // uint8 usdcDecimals = ERC20(settledStableToken).decimals();
        // console2.log("profit:", profit / 10**usdcDecimals, "USDC");

        // TODO update bench price for the two legs

        // IERC20(settledStableToken).transfer(winner, profit);
        // TODO below function should check
        console2.log("profit", profit);
        uint256 profit2 = withdrawYield(legs[loserLegId].yieldId, 1, address(this));
        // IERC20(settledStableToken).transfer(winner, profit2);

        // when end, the status of the two legs should be settled
        legs[legId].status = Status.Settled;
        legs[originalLeg.pairLegId].status = Status.Settled;

        // TODO , endDate, just close this swap.

        emit SettleSwap(legId, winner, settledStableToken, profit);

        // TODO
        // Related test cases
        // Confirm the formula is right, especially confirm the loss of precision
    }

    function _createLeg(
        address legToken,
        uint256 notionalAmount,
        int256 balance,
        uint64 startDate,
        uint8 yieldId
    )
        internal
    {
        Leg memory leg = Leg({
            swaper: msg.sender,
            tokenAddress: legToken,
            notionalAmount: notionalAmount,
            yieldId: yieldId,
            balance: balance,
            startDate: startDate,
            status: Status.Open,
            pairLegId: 0, // Status.Open also means the pairLegId is 0
            benchPrice: 0 // TODO more check(store need to compare with the deposited USDC) BenchPrice is updatated on
                // the startDate
         });

        legs[maxLegId] = leg;
        maxLegId++;
    }

    function queryLeg(uint64 legId) external view returns (Leg memory) {
        return legs[legId];
    }

    // TODO ,temp function should consider move to YieldStrategys contract. Are there problems related with applying
    // notionalAmount directly?
    // convert the share to the underlying amount
    function convertShareToUnderlyingAmount(uint64 legId, uint256 profit) internal view returns (uint256) {
        console2.log("legIdShares[legId]", legIdShares[legId]);
        return legs[legId].notionalAmount * profit / legIdShares[legId];
    }
}
