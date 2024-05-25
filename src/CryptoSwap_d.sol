// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { console2 } from "forge-std/src/console2.sol";
import "./interfaces/IPriceFeedManager.sol";
import "./interfaces/IYieldStrategyManager.sol";

contract CryptoSwap is Ownable {
    using SafeERC20 for IERC20;

    IPriceFeedManager private immutable priceFeedManager;
    IYieldStrategyManager private immutable yieldStrategyManager;
    mapping(uint8 => address) public settlementTokenAddresses;

    uint256 contractMasterId = 0; // The master id of each swapContract
    mapping(uint256 => uint256) public contractCreationCount; // How many of each contractMasterId have been created

    // Status of each contract at masterId => contractId
    // masterId => contractId => SwapContract
    mapping(uint256 => mapping(uint256 => SwapContract)) public swapContracts;

    // Balances of each leg in each contractId at masterId
    // masterId => contractId => leg => balance
    mapping(uint256 => mapping(uint256 => mapping(bool => uint256))) public balances;

    enum Status {
        OPEN,
        ACTIVE,
        SETTLED,
        CANCELLED // User cancelled the order or no taker

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
        uint8 settlementTokenId;
        uint8 yieldId;
        uint256 notionalAmount;
        uint256 yieldShares;
        Status status;
    }

    struct Leg {
        bool legPosition; // true for legA, false for legB
        uint16 feedId;
        int256 benchPrice;
        // TODO: Update the _updatePosition function to not use the lastPrice
        int256 lastPrice; // TODO: Remove this part
        uint256 balance;
        // TODO: Update functions to not use the withdrawable
        // TODO: Make a view function to return the withdrawable amount, with the Leg as a parameter
        uint256 withdrawable; // TODO: Remove this part
        // TODO: Maybe not use the poolPercentage for the moment
        uint256 poolPercentage; // percentage of the pool that this Leg currently owns // TODO: To remove
    }

    struct Period {
        uint64 startDate;
        uint32 periodInterval;
        uint8 totalIntervals;
        uint8 intervalCount;
    }

    constructor(address _priceFeedManager, address _yieldStrategyManager) Ownable(msg.sender) {
        priceFeedManager = IPriceFeedManager(priceFeedManager);
        yieldStrategyManager = IYieldStrategyManager(yieldStrategyManager);
    }

    function openSwap(
        uint256 _contractCreationCount,
        uint256 _notionalAmount,
        uint64 _startDate,
        uint16 _feedIdA,
        uint16 _feedIdB,
        uint8 _periodType,
        uint8 _totalIntervals,
        uint8 _settlementTokenId,
        uint8 _yieldId
    )
        external
    {
        require(_startDate >= block.timestamp, "startDate >= block.timestamp");
        require(_periodType <= 3, "Invalid period type");
        // TODO: 1500 = 1 * 1000 + 5 * 100 + 1 * 10 Directly when user input
        // 500 = 5 * 100
        // 1000 = 2 * 500 <- Cannot
        require(_notionalAmount % 10 == 0, "The notional amount must be a multiple of 10");

        IERC20(settlementTokenAddresses[_settlementTokenId]).transferFrom(
            msg.sender, address(this), (_contractCreationCount * _notionalAmount) / 2
        );

        uint256 shares;
        if (_yieldId != 0) {
            shares = yieldStrategyManager.depositYield(
                _yieldId, (_contractCreationCount * _notionalAmount) / 2, address(this)
            );
        }

        (Leg memory legA, Leg memory legB) = _handleLegs(_notionalAmount, _feedIdA, _feedIdB);
        Period memory period = _handlePeriod(_startDate, _periodType, _totalIntervals);

        for (uint256 i = 0; i < _contractCreationCount; i++) {
            SwapContract memory swapContract = SwapContract({
                contractMasterId: contractMasterId,
                contractId: i,
                userA: msg.sender,
                userB: address(0),
                period: period,
                legA: legA,
                legB: legB,
                settlementTokenId: _settlementTokenId,
                yieldId: _yieldId,
                notionalAmount: _notionalAmount,
                yieldShares: shares,
                status: Status.OPEN
            });

            swapContracts[contractMasterId][i] = swapContract;
        }

        contractCreationCount[contractMasterId] = _contractCreationCount;
        contractMasterId++;
    }

    function pairSwap(uint256 _swapContractMasterId, uint256 _swapContractId) external {
        SwapContract storage swapContract = swapContracts[_swapContractMasterId][_swapContractId];
        require(swapContract.status == Status.OPEN, "The swapContract is not open");

        swapContract.userB = msg.sender;
        swapContract.status = Status.ACTIVE;

        int256 legALatestPrice = priceFeedManager.getLatestPrice(swapContract.legA.feedId);
        int256 legBLatestPrice = priceFeedManager.getLatestPrice(swapContract.legB.feedId);

        swapContract.legA.benchPrice = legALatestPrice;
        swapContract.legA.lastPrice = legALatestPrice;
        swapContract.legB.benchPrice = legBLatestPrice;
        swapContract.legB.lastPrice = legBLatestPrice;

        uint256 halfNotionalAmount = swapContract.notionalAmount / 2;
        IERC20(settlementTokenAddresses[swapContract.settlementTokenId]).transferFrom(
            msg.sender, address(this), halfNotionalAmount
        );

        // Handle yield shares
        if (swapContract.yieldId != 0) {
            uint256 shares = yieldStrategyManager.depositYield(swapContract.yieldId, halfNotionalAmount, address(this));
            swapContract.yieldShares += shares;
        }
    }

    function settleSwap(uint256 _swapContractMasterId, uint256 _swapContractId) external {
        SwapContract memory swapContract = swapContracts[_swapContractMasterId][_swapContractId];

        require(msg.sender == swapContract.userA || msg.sender == swapContract.userB, "Unauthorized!");

        require(swapContract.status == Status.ACTIVE, "The swapContract is not active");

        if (
            block.timestamp
                < swapContract.period.startDate + (swapContract.period.periodInterval * swapContract.period.totalIntervals)
        ) {
            _updatePosition(_swapContractMasterId, _swapContractId);
        } else {
            swapContracts[_swapContractMasterId][_swapContractId].status = Status.SETTLED;
        }
    }

    function withdrawWinnings(uint256 masterId, uint256 contractId) public {
        SwapContract memory swapContract = swapContracts[masterId][contractId];
        require(msg.sender == swapContract.userA || msg.sender == swapContract.userB, "Unauthorized!");
        require(swapContract.status != Status.OPEN, "The swapContract is not active, settled, cancelled");

        bool user = msg.sender == swapContract.userA ? true : false;

        if (swapContract.status == Status.ACTIVE) {
            if (user == true) {
                require(swapContract.legA.withdrawable > 0, "No winnings available to withdraw!");

                swapContract.legA.withdrawable = 0;

                uint256 amount = swapContract.legA.withdrawable;
                IERC20(settlementTokenAddresses[swapContract.settlementTokenId]).safeTransfer(
                    swapContract.userA, amount
                );
            } else {
                require(swapContract.legB.withdrawable > 0, "No winnings available to withdraw!");

                swapContract.legB.withdrawable = 0;

                uint256 amount = swapContract.legB.withdrawable;
                IERC20(settlementTokenAddresses[swapContract.settlementTokenId]).safeTransfer(
                    swapContract.userB, amount
                );
            }
        } else {
            if (user == true) {
                swapContract.legA.balance = 0;

                uint256 amount = swapContract.legA.balance;
                IERC20(settlementTokenAddresses[swapContract.settlementTokenId]).safeTransfer(
                    swapContract.userA, amount
                );
            } else {
                swapContract.legB.balance = 0;

                uint256 amount = swapContract.legB.balance;
                IERC20(settlementTokenAddresses[swapContract.settlementTokenId]).safeTransfer(
                    swapContract.userB, amount
                );
            }
        }
    }

    function getPerformanceForPeriod(
        Leg memory legA,
        Leg memory legB,
        uint256 startDate,
        uint256 endDate
    )
        public
        view
        returns (int256)
    {
        int256 startPrice = priceFeedManager.getHistoryPrice(legA.feedId, startDate);
        int256 endPrice = priceFeedManager.getHistoryPrice(legA.feedId, endDate);

        return performance;
    }

    // If the user does not check their position for many intervals gas will become very expensive
    // Max possible intervals before breaking due to block gas limits is roughly 300
    // It is important for users to stay current with their position
    function _updatePosition(uint256 masterId, uint256 contractId) internal {
        SwapContract storage swapContract = swapContracts[masterId][contractId];
        Period storage period = swapContract.period;

        uint256 startDate = period.startDate;
        uint256 periodInterval = period.periodInterval;

        while (block.timestamp >= startDate + (periodInterval * period.intervalCount)) {
            uint256 intervalCount = period.intervalCount;
            int256 currentPriceA =
                priceFeedManager.getHistoryPrice(swapContract.legA.feedId, startDate + (periodInterval * intervalCount));
            int256 currentPriceB =
                priceFeedManager.getHistoryPrice(swapContract.legB.feedId, startDate + (periodInterval * intervalCount));

            int256 legALastPrice = swapContract.legA.lastPrice;
            int256 legBLastPrice = swapContract.legB.lastPrice;
            int256 performanceA = ((currentPriceA - legALastPrice) * 10_000) / legALastPrice;
            int256 performanceB = ((currentPriceB - legBLastPrice) * 10_000) / legBLastPrice;

            uint256 legABalance = swapContract.legA.balance;
            uint256 legBBalance = swapContract.legB.balance;

            uint256 totalValue = legABalance + legBBalance;
            uint256 performanceDiff;
            uint256 valueChange;

            if (performanceA > performanceB) {
                performanceDiff = uint256(performanceA - performanceB);
                // Apply the poolPercentage to calculate the value change
                valueChange = (performanceDiff * totalValue * swapContract.legA.poolPercentage) / 1_000_000; // Adjusted
                    // for basis points and percentage
                swapContract.legA.withdrawable += valueChange;
                legBBalance -= valueChange;
            } else if (performanceB > performanceA) {
                performanceDiff = uint256(performanceB - performanceA);
                valueChange = (performanceDiff * totalValue * swapContract.legB.poolPercentage) / 1_000_000; // Adjusted
                    // for basis points and percentage
                legABalance -= valueChange;
                swapContract.legB.withdrawable += valueChange;
            }

            // Update the pool percentages based on new balances
            uint256 newLegABalance = swapContract.legA.balance;
            uint256 newLegBBalance = swapContract.legB.balance;
            uint256 newTotal = swapContract.legA.balance + swapContract.legB.balance;
            swapContract.legA.poolPercentage = (newLegABalance * 10_000) / newTotal;
            swapContract.legB.poolPercentage = (newLegBBalance * 10_000) / newTotal;

            // Update last prices for next interval
            swapContract.legA.lastPrice = currentPriceA;
            swapContract.legB.lastPrice = currentPriceB;

            period.intervalCount++;
        }
    }

    ///////////////////////////////////////////////////////
    //              HELPER FUNCTIONS                    ///
    ///////////////////////////////////////////////////////

    function _handleLegs(
        uint256 _notionalAmount,
        uint16 _feedIdA,
        uint16 _feedIdB
    )
        internal
        returns (Leg memory legA, Leg memory legB)
    {
        legA = Leg({
            legPosition: true,
            feedId: _feedIdA,
            benchPrice: 0,
            lastPrice: 0,
            withdrawable: 0,
            balance: _notionalAmount / 2,
            poolPercentage: 50e18
        });

        legB = Leg({
            legPosition: false,
            feedId: _feedIdB,
            benchPrice: 0,
            lastPrice: 0,
            withdrawable: 0,
            balance: _notionalAmount / 2,
            poolPercentage: 50e18
        });
    }

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

    ///////////////////////////////////////////////////////
    //              SETUP FUNCTIONS                    ///
    ///////////////////////////////////////////////////////

    function addSettlementToken(uint8 _tokenId, address _tokenAddress) external onlyOwner {
        require(settlementTokenAddresses[_tokenId] == address(0), "The token already exists");
        settlementTokenAddresses[_tokenId] = _tokenAddress;
    }

    function removeSettlementToken(uint8 _tokenId) external onlyOwner {
        require(settlementTokenAddresses[_tokenId] != address(0), "The token does not exist");
        delete settlementTokenAddresses[_tokenId];
    }

    // function convertShareToUnderlyingAmount(uint64 legId, uint256 profit) internal view returns (uint256) {
    //     uint256 shares = legIdShares[legId] * profit / legs[legId].notionalAmount;
    //     return shares;
    // }
}
