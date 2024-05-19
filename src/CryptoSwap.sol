// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { console2 } from "forge-std/src/console2.sol";
import "./interfaces/IPriceFeedManager.sol";
import "./interfaces/IYieldStrategies.sol";

contract CryptoSwap is Ownable {
    using SafeERC20 for IERC20;

    IPriceFeedManager private immutable priceFeedManager;
    IYieldStrategyManager private immutable yieldStrategyManager;
    mapping(uint8 => address) public settlementTokenAddresses;
    
    uint256 contractMasterId = 0;   // The master id of each swapContract
    mapping(uint256 => uint256) public contractCreationCount;   // How many of each contractMasterId have been created

    // Status of each contract at masterId => contractId
    // masterId => contractId => SwapContract
    mapping(uint256 => mapping(uint256 => SwapContract)) public swapContracts;

    // Balances of each leg in each contractId at masterId
    // masterId => contractId => leg => balance
    mapping(uint256 => mapping(uint256 => mapping(bool => uint256))) public balances; 

    enum Status {
        Open,
        Active,
        Settled,
        Cancelled // User cancelled the order or no taker
    }

    enum PeriodType {
        Daily,
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

    struct SwapContract {
        uint256 contractMasterId;
        uint256 contractId;
        address userA;
        address userB;
        Period period;
        Leg legA;
        Leg legB;
        uint16 periodIntervals;
        uint8 settlementTokenId
        uint8 yieldId;
        uint256 notionalAmount;
        uint256 yieldShares;
        Status status;
    }

    struct Leg {
        bool legPosition; // true for legA, false for legB
        uint64 feedId;
        int256 balance;
        int256 benchPrice;
    }

    struct Period{
        uint64 startDate;
        uint16 periodIntervals;
        PeriodType periodType;
    }

    constructor(
        address _priceFeedManager,
        address _yieldStrategyManager
    )
        Ownable(msg.sender)
    {
        priceFeedManager = IPriceFeedManager(priceFeedsManager);
        yieldStrategyManager = IYieldStrategyManager(yieldStrategyManager);
    }

    function openSwap(
        uint256 _contractCreationCount,
        uint256 _notionalAmount,
        Period _period,
        uint8 _settlementTokenId,
        uint8 _feedIdA,
        uint8 _feedIdB,
        uint8 _yieldId
    )
        external
    {
        require(_period.startDate >= block.timestamp, "startDate >= block.timestamp");
        require(_notionalAmount % 10 == 0, "The notional amount must be a multiple of 10");

        IERC20(settlementTokenAddresses[_settlementTokenId]).transferFrom(msg.sender, address(this), (_contractCreationCount * _notionalAmount) / 2);

        uint256 shares;
        if (_yieldId != 0) {
            address yieldAddress = yieldStrategyManager.getYieldStrategy(_yieldId);
            shares = yieldAddress.depositYield(_yieldId, (_contractCreationCount * _notionalAmount) / 2, address(this));
        }

        (Leg memory legA, Leg memory legB) = handleLegs(_feedIdA, _feedIdB);

        for(uint256 i = 0; i < _contractCreationCount; i++) {
            SwapContract memory swapContract = SwapContract({
                contractMasterId: contractMasterId,
                contractId: i,
                period: _period,
                userA: msg.sender,
                userB: address(0),
                legA: legA,
                legB: legB,
                settlementTokenId: _settlementTokenId,
                yieldId: _yieldId,
                notionalAmount: _notionalAmount,
                yieldShares: shares,
                status: Status.Open,

            });

            swapContracts[contractMasterId][i][true] = swapContract;
        }

        contractCreationCount[contractMasterId] = _contractCreationCount;
        contractMasterId++;
    }

    function pairSwap(uint256 _swapContractMasterId, uint256 _swapContractId) external {
        SwapContract storage swapContract = swapContracts[_swapContractMasterId][_swapContractId];
        require(swapContract.status == Status.Open, "The swapContract is not open");

        swapContract.userB = msg.sender;

        int256 legALatestPrice = priceFeeds.getLatestPrice(swapContract.legA.feedId);
        int256 legBLatestPrice = priceFeeds.getLatestPrice(swapContract.legB.feedId);

        swapContract.legA.benchPrice = legALatestPrice;
        swapContract.legB.benchPrice = legBLatestPrice;

        swapContract.status = Status.Active;

        IERC20(settledStableToken).transferFrom(msg.sender, address(this), swapContract.notionalAmount / 2);

        uint256 shares;
        if (swapContract.yieldId != 0) {
            address yieldAddress = yieldStrategyManager.getYieldStrategy(swapContract.yieldId);
            shares = yieldAddress.depositYield(swapContract.yieldId, swapContract.notionalAmount / 2, address(this));
        }
        
        swapContract.yieldShares += shares;
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
            console2.log("winner: opener");
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
            console2.log("winner: parier");
            winner = pairLeg.swaper;
        }
        // console2.log("winner:", winner);
        uint8 usdcDecimals = ERC20(settledStableToken).decimals();
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

    function handleLegs(uint8 _feedIdA, uint8 _feedIdB) internal returns (Leg memory legA, Leg memory legB) {
        legA = Leg({
            legPosition: true,
            feedId: _feedIdA,
            balance: 0,
            benchPrice: 0
        });
    
        legB = Leg({
            legPosition: false,
            feedId: _feedIdB,
            balance: 0,
            benchPrice: 0
        });
    }

    function queryLeg(uint64 legId) external view returns (Leg memory) {
        return legs[legId];
    }

    // TODO ,temp function should consider move to YieldStrategies contract. Are there problems related with applying
    // notionalAmount directly?
    // convert the share to the underlying amount
    function convertShareToUnderlyingAmount(uint64 legId, uint256 profit) internal view returns (uint256) {
        uint256 shares = legIdShares[legId] * profit / legs[legId].notionalAmount;
        return shares;
    }
}
