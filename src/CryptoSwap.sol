// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { console2 } from "forge-std/src/console2.sol";
import "./interfaces/IPriceFeedManager.sol";
import "./interfaces/IYieldStrategyManager.sol";

/// @title CryptoSwap - A contract for managing decentralized swaps between assets
contract CryptoSwap is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Price feed manager for managing external price feeds
    IPriceFeedManager public immutable priceFeedManager;
    /// @notice Yield strategy manager for handling yield-generating strategies
    IYieldStrategyManager public immutable yieldStrategyManager;
    /// @notice Mapping from numeric token IDs to their corresponding ERC20 addresses
    mapping(uint8 => address) public settlementTokenAddresses;
    
    /// @notice Unique identifier for each swap contract
    uint256 contractMasterId = 0;
    /// @notice Count of contracts created under each master ID
    mapping(uint256 => uint256) public contractCreationCount;

    /// @notice Nested mapping to store swap contract details by master and individual contract IDs
    mapping(uint256 => mapping(uint256 => SwapContract)) public swapContracts;

    /// @notice Enumerations for swap contract statuses
    enum Status {
        OPEN,
        ACTIVE,
        SETTLED,
        CANCELLED
    }

    /// @notice Enumerations for defining interval durations
    enum PeriodInterval {
        DAILY,
        WEEKLY,
        MONTHLY,
        QUARTERLY,
        YEARLY
    }

    /// @dev Struct to store details about each swap contract
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

    /// @dev Struct to describe each leg of a swap
    struct Leg {
        bool legPosition; // true for legA, false for legB
        uint16 feedId;
        int256 originalPrice;
        int256 lastPrice;
        uint256 balance;
        uint256 withdrawable;
    }

    /// @dev Struct to manage the timing details of a swap
    struct Period{
        uint64 startDate;
        uint32 periodInterval;
        uint16 totalIntervals;
        uint16 intervalCount;
    }

    /// @notice Constructor to set up the contract with necessary managers
    constructor(
        address _priceFeedManager,
        address _yieldStrategyManager
    )
        Ownable(msg.sender)
    {
        priceFeedManager = IPriceFeedManager(_priceFeedManager);
        yieldStrategyManager = IYieldStrategyManager(_yieldStrategyManager);
    }

    ///////////////////////////////////////////////////////
    ///                  EVENTS                         ///
    ///////////////////////////////////////////////////////

    /// @notice Event emitted when a new swap is opened
    event SwapOpened(
        uint256 indexed contractMasterId,
        uint256 indexed contractCreationCount,
        address indexed userA,
        uint256 notionalAmount,
        uint8 settlementTokenId,
        uint8 yieldId,
        Status status
    );
    
    /// @notice Event emitted when a swap is paired with another user
    event SwapPaired(
        uint256 indexed contractMasterId,
        uint256 indexed contractId,
        address indexed userB,
        Status status
    );
    
    /// @notice Event emitted when a swap is settled
    event SwapSettled(
        uint256 indexed contractMasterId,
        uint256 indexed contractId,
        Status status
    );
    
    /// @notice Event emitted when a swap is updated
    event SwapUpdated(
        uint256 indexed contractMasterId,
        uint256 indexed contractId,
        uint256 newBalanceA,
        uint256 newBalanceB,
        uint256 intervalCount
    );
    
    /// @notice Event emitted when winnings are withdrawn by a user
    event WinningsWithdrawn(
        uint256 indexed contractMasterId,
        uint256 indexed contractId,
        address indexed user,
        uint256 amount
    );
    
    /// @notice Event emitted when a new settlement token is added
    event SettlementTokenAdded(uint8 indexed tokenId, address tokenAddress);
    /// @notice Event emitted when a settlement token is removed
    event SettlementTokenRemoved(uint8 indexed tokenId);

    ///////////////////////////////////////////////////////
    ///                  ERRORS                         ///
    ///////////////////////////////////////////////////////

    /// @notice Error for when the start date of a swap is invalid
    error InvalidStartDate(uint256 startDate);
    /// @notice Error for when the notional amount is not properly quantized
    error InvalidNotionalAmount(uint256 notionalAmount);
    /// @notice Error for unauthorized access attempts
    error UnauthorizedAccess();
    /// @notice Error for when the status of a swap must be OPEN to proceed
    error StatusMustBeOpen(Status status);
    /// @notice Error for when the status of a swap must be ACTIVE to proceed
    error StatusMustBeActive(Status status);
    /// @notice Error for when a swap contract is not active
    error InactiveSwapContract();
    /// @notice Error for when a swap cannot be settled until a certain timestamp
    error CannotSettleUntil(uint256 timestamp);
    /// @notice Error for when there are no winnings available for withdrawal
    error NoWinningsAvailable();
    /// @notice Error for when a token already exists in the mapping
    error TokenAlreadyExists();
    /// @notice Error for when a token does not exist in the mapping
    error TokenDoesNotExist();

    ///////////////////////////////////////////////////////
    ///                MUTATIVE FUNCTIONS               ///
    ///////////////////////////////////////////////////////

    /// @notice Opens a new swap with specified parameters
    /// @param _contractCreationCount The number of contracts to create under the master ID
    /// @param _notionalAmount The notional amount for each contract
    /// @param _startDate The start date of the swap
    /// @param _feedIdA The feed ID for leg A
    /// @param _feedIdB The feed ID for leg B
    /// @param _periodType The period interval type
    /// @param _totalIntervals The total number of intervals in the period
    /// @param _settlementTokenId The ID of the settlement token
    /// @param _yieldId The ID of the yield strategy to be used
    function openSwap(
        uint256 _contractCreationCount,
        uint256 _notionalAmount,
        uint64 _startDate,
        uint16 _feedIdA,
        uint16 _feedIdB,
        PeriodInterval _periodType,
        uint8 _totalIntervals,
        uint8 _settlementTokenId,
        uint8 _yieldId
    )
        external
    {
        if (_startDate < block.timestamp) revert InvalidStartDate(_startDate);
        if (_notionalAmount % 10 != 0) revert InvalidNotionalAmount(_notionalAmount);

        IERC20(settlementTokenAddresses[_settlementTokenId]).transferFrom(msg.sender, address(this), (_contractCreationCount * _notionalAmount) / 2);

        uint256 shares;
        if (_yieldId != 0) {
            shares = yieldStrategyManager.depositYield(_yieldId, (_contractCreationCount * _notionalAmount) / 2, address(this));
        }

        (Leg memory legA, Leg memory legB) = _handleLegs(_notionalAmount, _feedIdA, _feedIdB);
        Period memory period = _handlePeriod(_startDate, _periodType, _totalIntervals);

        for(uint256 i = 0; i < _contractCreationCount; i++) {
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
        emit SwapOpened(contractMasterId, _contractCreationCount, msg.sender, _notionalAmount, _settlementTokenId, _yieldId, Status.OPEN);
    }

    /// @notice Pairs a second user with an open swap, changing its status to ACTIVE
    /// @param _swapContractMasterId The master ID of the contract
    /// @param _swapContractId The individual ID of the contract within the master grouping
    function pairSwap(uint256 _swapContractMasterId, uint256 _swapContractId) external {
        SwapContract storage swapContract = swapContracts[_swapContractMasterId][_swapContractId];

        if (msg.sender == swapContract.userA) revert UnauthorizedAccess();
        if (swapContract.status != Status.OPEN) revert StatusMustBeOpen(swapContract.status);
    
        swapContract.userB = msg.sender;
        swapContract.status = Status.ACTIVE;
    
        int256 legALatestPrice = priceFeedManager.getLatestPrice(swapContract.legA.feedId);
        int256 legBLatestPrice = priceFeedManager.getLatestPrice(swapContract.legB.feedId);
    
        swapContract.legA.originalPrice = legALatestPrice;
        swapContract.legA.lastPrice = legALatestPrice;
        swapContract.legB.originalPrice = legBLatestPrice;
        swapContract.legB.lastPrice = legBLatestPrice;
    
        uint256 halfNotionalAmount = swapContract.notionalAmount / 2;
        IERC20(settlementTokenAddresses[swapContract.settlementTokenId]).transferFrom(msg.sender, address(this), halfNotionalAmount);
    
        // Handle yield shares
        if (swapContract.yieldId != 0) {
            uint256 shares = yieldStrategyManager.depositYield(swapContract.yieldId, halfNotionalAmount, address(this));
            swapContract.yieldShares += shares;
        }

        emit SwapPaired(_swapContractMasterId, _swapContractId, msg.sender, Status.ACTIVE);
    }
    

    /// @notice Settles an active swap, potentially updating its status to SETTLED if conditions are met
    /// @param _swapContractMasterId The master ID of the contract
    /// @param _swapContractId The individual ID of the contract within the master grouping
    function settleSwap(uint256 _swapContractMasterId, uint256 _swapContractId) external {
        SwapContract memory swapContract = swapContracts[_swapContractMasterId][_swapContractId];

        if (!(msg.sender == swapContract.userA || msg.sender == swapContract.userB)) revert UnauthorizedAccess();
        if (swapContract.status != Status.ACTIVE) revert StatusMustBeActive(swapContract.status);

        uint256 startDate = swapContract.period.startDate;
        uint256 periodInterval = swapContract.period.periodInterval;
        uint256 totalIntervals = swapContract.period.totalIntervals;
        uint256 intervalCount = swapContract.period.intervalCount;

        if (block.timestamp < startDate + (periodInterval * intervalCount)) {
            revert CannotSettleUntil(startDate + (periodInterval * intervalCount));
        }

        if (block.timestamp < startDate + (periodInterval * totalIntervals)) {
            _updatePosition(_swapContractMasterId, _swapContractId);
        } else {
            swapContracts[_swapContractMasterId][_swapContractId].status = Status.SETTLED;

            emit SwapSettled(_swapContractMasterId, _swapContractId, Status.SETTLED);
        }
    }

    /// @notice Allows users to withdraw their winnings if any are available
    /// @param _swapContractMasterId The master ID of the contract
    /// @param _swapContractId The individual ID of the contract within the master grouping
    function withdrawWinnings(uint256 _swapContractMasterId, uint256 _swapContractId) public {
        SwapContract memory swapContract = swapContracts[_swapContractMasterId][_swapContractId];

        if (!(msg.sender == swapContract.userA || msg.sender == swapContract.userB)) revert UnauthorizedAccess();
        if (swapContract.status == Status.OPEN) revert InactiveSwapContract();
    
        bool user = msg.sender == swapContract.userA ? true : false;
        uint8 yieldId = swapContract.yieldId;
        uint256 amount;

        if (swapContract.status == Status.ACTIVE) {
            if (user == true) {
                if (swapContract.legA.withdrawable > 0) revert NoWinningsAvailable();

                swapContract.legA.withdrawable = 0;
    
                amount = swapContract.legA.withdrawable;

                if (yieldId != 0) {
                    yieldStrategyManager.withdrawYield(yieldId, amount, swapContract.userA);
                }
                IERC20(settlementTokenAddresses[swapContract.settlementTokenId]).safeTransfer(swapContract.userA, amount);
                } else {
                if (swapContract.legB.withdrawable > 0) revert NoWinningsAvailable();

                swapContract.legB.withdrawable = 0;
    
                amount = swapContract.legB.withdrawable;

                if (yieldId != 0) {
                    yieldStrategyManager.withdrawYield(swapContract.yieldId, amount, swapContract.userB);
                }
                IERC20(settlementTokenAddresses[swapContract.settlementTokenId]).safeTransfer(swapContract.userB, amount);
                }
        } else {
            if (user == true) {

                swapContract.legA.balance = 0;

                amount = swapContract.legA.balance;

                if(yieldId != 0) {
                    yieldStrategyManager.withdrawYield(swapContract.yieldId, amount, swapContract.userA);
                }
                IERC20(settlementTokenAddresses[swapContract.settlementTokenId]).safeTransfer(swapContract.userA, amount);
            } else {

                swapContract.legB.balance = 0;

                amount = swapContract.legB.balance;

                if (yieldId != 0) {
                    yieldStrategyManager.withdrawYield(swapContract.yieldId, amount, swapContract.userB);
                }
                IERC20(settlementTokenAddresses[swapContract.settlementTokenId]).safeTransfer(swapContract.userB, amount);
            }
        }
        emit WinningsWithdrawn(
            _swapContractMasterId,
            _swapContractId,
            msg.sender,
            amount
        );
    }

    /// @dev Internal function to update positions within a contract over time, adjusting balances and intervals
    /// @param _swapContractMasterId The master ID of the contract
    /// @param _swapContractId The individual ID of the contract within the master grouping
    function _updatePosition(uint256 _swapContractMasterId, uint256 _swapContractId) internal {
        SwapContract storage swapContract = swapContracts[_swapContractMasterId][_swapContractId];

        uint256 startDate = swapContract.period.startDate;
        uint256 periodInterval = swapContract.period.periodInterval;
        uint256 notionalAmount = swapContract.notionalAmount;

        uint256 updatedLegABalance = swapContract.legA.balance;
        uint256 updatedLegBWithdrawable = swapContract.legB.withdrawable;
        uint256 updatedLegAWithdrawable = swapContract.legA.withdrawable;
        uint256 updatedLegBBalance = swapContract.legB.balance;
        uint16 intervalCount = swapContract.period.intervalCount;

        while (block.timestamp >= startDate + (periodInterval * intervalCount)) {
            uint256 currentInterval = startDate + (periodInterval * intervalCount);
            uint256 nextInterval = startDate + (periodInterval * (intervalCount + 1));

            (int256 legAStartPrice, int256 legAEndPrice) = getPricesForPeriod(swapContract.legA.feedId, currentInterval, nextInterval);
            (int256 legBStartPrice, int256 legBEndPrice) = getPricesForPeriod(swapContract.legB.feedId, currentInterval, nextInterval);

            swapContract.legA.lastPrice = legAEndPrice;
            swapContract.legB.lastPrice = legBEndPrice;

            uint256 netValueChange;

            if (legAEndPrice * legBStartPrice > legBEndPrice * legAStartPrice) {
                netValueChange = (uint256(legAEndPrice * legBStartPrice - legAStartPrice * legBEndPrice) * notionalAmount)
                    / uint256(legAStartPrice * legBStartPrice);
                if (updatedLegBBalance < netValueChange) {
                    updatedLegBBalance = 0;
                    break;
                }
                updatedLegBBalance -= netValueChange;
                updatedLegAWithdrawable += netValueChange;
            } else {
                netValueChange = (uint256(legBEndPrice * legAStartPrice - legAEndPrice * legBStartPrice) * notionalAmount)
                    / uint256(legAStartPrice * legBStartPrice);
                if (updatedLegABalance < netValueChange) {
                    updatedLegABalance = 0;
                    break;
                }
                updatedLegABalance -= netValueChange;
                updatedLegBWithdrawable += netValueChange;
            }

            intervalCount++;
        }

        // Set status to SETTLED if loop was broken due to bankruptcy
        if (updatedLegABalance == 0 || updatedLegBBalance == 0) {
            swapContract.status = Status.SETTLED;
        }

        if (updatedLegABalance != swapContract.legA.balance) swapContract.legA.balance = updatedLegABalance;
        if (updatedLegBWithdrawable != swapContract.legB.withdrawable) swapContract.legB.withdrawable = updatedLegBWithdrawable;
        if (updatedLegAWithdrawable != swapContract.legA.withdrawable) swapContract.legA.withdrawable = updatedLegAWithdrawable;
        if (updatedLegBBalance != swapContract.legB.balance) swapContract.legB.balance = updatedLegBBalance;
        if (intervalCount != swapContract.period.intervalCount) swapContract.period.intervalCount = intervalCount;

        emit SwapUpdated(
            _swapContractMasterId, 
            _swapContractId, 
            swapContract.legA.balance, 
            swapContract.legB.balance, 
            swapContract.period.intervalCount
        );
    }
    


    ///////////////////////////////////////////////////////
    ///                SETUP FUNCTIONS                  ///
    ///////////////////////////////////////////////////////

        /// @notice Adds a new token to the settlement token registry
    /// @param _tokenId The ID to assign to the new token
    /// @param _tokenAddress The address of the ERC20 token to add
    function addSettlementToken(uint8 _tokenId, address _tokenAddress) external onlyOwner {
        if (settlementTokenAddresses[_tokenId] != address(0)) revert TokenAlreadyExists();
        settlementTokenAddresses[_tokenId] = _tokenAddress;

        emit SettlementTokenAdded(_tokenId, _tokenAddress);
    }

    /// @notice Removes a token from the settlement token registry
    /// @param _tokenId The ID of the token to remove
    function removeSettlementToken(uint8 _tokenId) external onlyOwner {
        if (settlementTokenAddresses[_tokenId] == address(0)) revert TokenDoesNotExist();
        delete settlementTokenAddresses[_tokenId];

        emit SettlementTokenRemoved(_tokenId);
    }

    ///////////////////////////////////////////////////////
    ///                HELPER FUNCTIONS                 ///
    ///////////////////////////////////////////////////////

    /// @dev Helper function to initialize legs of a swap based on provided parameters
    /// @param _notionalAmount The notional amount for each leg
    /// @param _feedIdA Feed ID for leg A
    /// @param _feedIdB Feed ID for leg B
    /// @return legA Initialized leg structure for leg A
    /// @return legB Initialized leg structure for leg B
    function _handleLegs(uint256 _notionalAmount, uint16 _feedIdA, uint16 _feedIdB) internal pure returns (Leg memory legA, Leg memory legB) {
        legA = Leg({
            legPosition: true,
            feedId: _feedIdA,
            originalPrice: 0,
            lastPrice: 0,
            withdrawable: 0,
            balance: _notionalAmount / 2
        });
    
        legB = Leg({
            legPosition: false,
            feedId: _feedIdB,
            originalPrice: 0,
            lastPrice: 0,
            withdrawable: 0,
            balance: _notionalAmount / 2
        });
    }

    /// @dev Helper function to configure the period parameters of a swap
    /// @param _startDate The start date for the period
    /// @param _periodType The type of period interval
    /// @param _totalIntervals The total number of intervals within the period
    /// @return period Configured period structure
    function _handlePeriod(uint64 _startDate, PeriodInterval _periodType, uint8 _totalIntervals) internal pure returns (Period memory period) {
        uint32 periodInterval;
        
        if (_periodType == PeriodInterval.DAILY) {
            periodInterval = 1 days;
        }   else if (_periodType == PeriodInterval.WEEKLY) {
            periodInterval = 7 days;
        } else if (_periodType == PeriodInterval.MONTHLY) {
            periodInterval = 30 days;
        } else if (_periodType == PeriodInterval.QUARTERLY) {
            periodInterval = 90 days;
        } else {
            periodInterval = 365 days;
        }
    
        period = Period({
            startDate: _startDate,
            periodInterval: periodInterval,
            totalIntervals: _totalIntervals,
            intervalCount: 0
        });
    
        return period;
    }

    ///////////////////////////////////////////////////////
    ///                VIEW FUNCTIONS                  ///
    ///////////////////////////////////////////////////////

    /// @notice Provides historical prices for a specific feed ID between two timestamps
    /// @param _feedId The feed ID to query
    /// @param _startDate The start timestamp for price retrieval
    /// @param _endDate The end timestamp for price retrieval
    /// @return startPrice Price at the start timestamp
    /// @return endPrice Price at the end timestamp
    function getPricesForPeriod(
        uint16 _feedId,
        uint256 _startDate,
        uint256 _endDate
    )
        public
        view
        returns (int256 startPrice, int256 endPrice)
    {
        startPrice = priceFeedManager.getHistoryPrice(_feedId, _startDate);
        endPrice = priceFeedManager.getHistoryPrice(_feedId, _endDate);

        return (startPrice, endPrice);
    }

    function getSwapContract(uint256 masterId, uint256 contractId) public view returns (SwapContract memory) {
        return swapContracts[masterId][contractId];
    }

    // function convertShareToUnderlyingAmount(uint64 legId, uint256 profit) internal view returns (uint256) {
    //     uint256 shares = legIdShares[legId] * profit / legs[legId].notionalAmount;
    //     return shares;
    // }
}
