// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./DegenFetcher.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title PriceFeedManager
/// @notice Manages multiple Chainlink price feeds and provides the latest and historical price data.
/// @dev Inherits from Ownable for access control and DegenFetcher for fetching historical data.
contract PriceFeedManager is Ownable, DegenFetcher {
    /// @notice Maps feed IDs to their corresponding Chainlink price feed addresses.
    mapping(uint16 => address) public priceFeedAddresses;

    /// @notice Emitted when a new price feed is added.
    /// @param feedId The identifier of the feed.
    /// @param feedAddress The address of the Chainlink price feed.
    event PriceFeedAdded(uint16 indexed feedId, address indexed feedAddress);

    /// @notice Emitted when a price feed is removed.
    /// @param feedId The identifier of the feed.
    event PriceFeedRemoved(uint16 indexed feedId);

    /// @notice Emitted when a price is queried from a feed.
    /// @param feedId The identifier of the feed.
    /// @param price The latest price retrieved.
    event PriceQueried(uint16 indexed feedId, int256 price);

    /// @notice Indicates an attempt to interact with a feed that already exists.
    error FeedAlreadyExists(uint16 feedId);

    /// @notice Indicates an attempt to interact with a feed that does not exist.
    error FeedDoesNotExist(uint16 feedId);

    /// @notice Indicates an unauthorized attempt to perform an operation.
    error Unauthorized();

    /// @notice Initializes the contract setting the owner.
    constructor() Ownable(msg.sender) {}

    /// @notice Adds a new price feed to the manager.
    /// @param _feedId The identifier for the new price feed.
    /// @param priceFeedAddress The address of the Chainlink price feed contract.
    /// @dev Reverts if the feed already exists.
    function addPriceFeed(uint16 _feedId, address priceFeedAddress) external onlyOwner {
        if (priceFeedAddresses[_feedId] != address(0)) {
            revert FeedAlreadyExists(_feedId);
        }
        priceFeedAddresses[_feedId] = priceFeedAddress;
        emit PriceFeedAdded(_feedId, priceFeedAddress);
    }

    /// @notice Removes an existing price feed from the manager.
    /// @param _feedId The identifier of the price feed to remove.
    /// @dev Reverts if the feed does not exist.
    function removePriceFeed(uint16 _feedId) external onlyOwner {
        if (priceFeedAddresses[_feedId] == address(0)) {
            revert FeedDoesNotExist(_feedId);
        }
        delete priceFeedAddresses[_feedId];
        emit PriceFeedRemoved(_feedId);
    }

    /// @notice Retrieves the latest price from a specified feed.
    /// @param _feedId The identifier of the feed.
    /// @return price The latest price from the feed.
    /// @dev Reverts if the feed does not exist.
    function getLatestPrice(uint16 _feedId) public returns (int256) {
        if (priceFeedAddresses[_feedId] == address(0)) {
            revert FeedDoesNotExist(_feedId);
        }
        (,int256 price,,,) = AggregatorV3Interface(priceFeedAddresses[_feedId]).latestRoundData();
        emit PriceQueried(_feedId, price);
        return price;
    }

    /// @notice Retrieves historical price data for a specified feed and averages it.
    /// @param _feedId The identifier of the feed.
    /// @param timestamp The timestamp for historical data retrieval.
    /// @return average The average price calculated from the historical data.
    /// @dev Uses DegenFetcher to fetch the data.
    function getHistoryPrice(uint16 _feedId, uint256 timestamp) public view returns (int256) {
        if (priceFeedAddresses[_feedId] == address(0)) {
            revert FeedDoesNotExist(_feedId);
        }
        int32[] memory prices = fetchPriceDataForFeed(priceFeedAddresses[_feedId], timestamp, uint80(1), uint256(48));
        int256 average = int256(calculatePriceAverage(prices));
        return average;
    }

    /// @notice Returns the description of the specified feed.
    /// @param _feedId The identifier of the feed.
    /// @return The description of the feed.
    function description(uint16 _feedId) public view returns (string memory) {
        if (priceFeedAddresses[_feedId] == address(0)) {
            revert FeedDoesNotExist(_feedId);
        }
        return AggregatorV3Interface(priceFeedAddresses[_feedId]).description();
    }

    /// @notice Returns the number of decimals used in the specified feed.
    /// @param _feedId The identifier of the feed.
    /// @return The number of decimals used by the feed.
    function priceFeedDecimals(uint16 _feedId) public view returns (uint8) {
        if (priceFeedAddresses[_feedId] == address(0)) {
            revert FeedDoesNotExist(_feedId);
        }
        return AggregatorV3Interface(priceFeedAddresses[_feedId]).decimals();
    }

    /// @notice Calculates the average of an array of prices.
    /// @param data The array of prices to average.
    /// @return The calculated average price.
    function calculatePriceAverage(int32[] memory data) public pure returns (int32) {
        int256 sum = 0;
        uint256 count = 0;

        for(uint i = 0; i < data.length; i++) {
            if(data[i] != 0) {
                sum += int256(data[i]);
                count++;
            }
        }

        if (count == 0) {
            return 0;
        } else {
            return int32(sum / int256(count));
        }
    }
}
