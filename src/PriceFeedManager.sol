// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./DegenFetcher.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

contract PriceFeedManager is Ownable, DegenFetcher {
    mapping(uint16 => address) public priceFeedAddresses;

    event PriceFeedAdded(uint16 indexed feedId, address indexed feedAddress);
    event PriceFeedRemoved(uint16 indexed feedId);
    event PriceQueried(uint16 indexed feedId, int256 price);

    error FeedAlreadyExists(uint16 feedId);
    error FeedDoesNotExist(uint16 feedId);
    error Unauthorized();

    constructor() Ownable(msg.sender) {}

    function addPriceFeed(uint16 _feedId, address priceFeedAddress) external onlyOwner {
        if (priceFeedAddresses[_feedId] != address(0)) {
            revert FeedAlreadyExists(_feedId);
        }
        priceFeedAddresses[_feedId] = priceFeedAddress;
        emit PriceFeedAdded(_feedId, priceFeedAddress);
    }

    function removePriceFeed(uint16 _feedId) external onlyOwner {
        if (priceFeedAddresses[_feedId] == address(0)) {
            revert FeedDoesNotExist(_feedId);
        }
        delete priceFeedAddresses[_feedId];
        emit PriceFeedRemoved(_feedId);
    }

    function getLatestPrice(uint16 _feedId) public returns (int256) {
        if (priceFeedAddresses[_feedId] == address(0)) {
            revert FeedDoesNotExist(_feedId);
        }
        (,int256 price,,,) = AggregatorV3Interface(priceFeedAddresses[_feedId]).latestRoundData();
        emit PriceQueried(_feedId, price);
        return price;
    }

    function getHistoryPrice(uint16 _feedId, uint256 timestamp) public view returns (int256) {
        if (priceFeedAddresses[_feedId] == address(0)) {
            revert FeedDoesNotExist(_feedId);
        }
        int32[] memory prices = fetchPriceDataForFeed(priceFeedAddresses[_feedId], timestamp, uint80(1), uint256(2));
        return prices[0];
    }

    function description(uint16 _feedId) public view returns (string memory) {
        if (priceFeedAddresses[_feedId] == address(0)) {
            revert FeedDoesNotExist(_feedId);
        }
        return AggregatorV3Interface(priceFeedAddresses[_feedId]).description();
    }

    function priceFeedDecimals(uint16 _feedId) public view returns (uint8) {
        if (priceFeedAddresses[_feedId] == address(0)) {
            revert FeedDoesNotExist(_feedId);
        }
        return AggregatorV3Interface(priceFeedAddresses[_feedId]).decimals();
    }
}
