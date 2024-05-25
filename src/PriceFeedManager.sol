// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./DegenFetcher.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

import { console2 } from "forge-std/src/console2.sol";

/**
 * @title The PriceFeeds contract
 * @notice A contract that returns latest price from Chainlink Price Feeds
 */
contract PriceFeedManager is Ownable, DegenFetcher {
    // TODO, Now directly get by price, can apply register in the future
    // tokenAddress=>priceFeedAddress
    mapping(uint16 => address) priceFeedAddresses;

    constructor() Ownable(_msgSender()) {
    }

    function addPriceFeed(uint16 _feedId, address priceFeedAddress) external onlyOwner {
        priceFeedAddresses[_feedId] = priceFeedAddress;
    }

    function removePriceFeed(uint16 _feedId) external onlyOwner {
        delete priceFeedAddresses[_feedId];
    }

    /**
     * @notice Returns the latest price
     *
     * @return latest price
     */

    //  TODO, should check updatTime, keep the price is the latest price
    function getLatestPrice(uint16 _feedId) public view returns (int256) {
        (
            /* uint80 roundID */
            ,
            int256 price,
            /* uint256 startedAt */
            ,
            /* uint256 timeStamp */
            ,
            /* uint80 answeredInRound */
        ) = AggregatorV3Interface(priceFeedAddresses[_feedId]).latestRoundData();

        return price;
    }

    // Through degenFetcher, get historypirce
    // TODO how to config the params?
    function getHistoryPrice(uint16 _feedId, uint256 timestamp) public view returns (int256) {
        int32[] memory prices =
            fetchPriceDataForFeed(priceFeedAddresses[_feedId], timestamp, uint80(1), uint256(2));
        return prices[0];
    }

    /**
     * @notice Returns the Price Feed address
     *
     * @return Price Feed address
     */
    function getPriceFeed(uint16 _feedId) public view returns (address) {
        return priceFeedAddresses[_feedId];
    }

    // TODO for test
    function description(uint16 _feedId) public view returns (string memory) {
        return AggregatorV3Interface(priceFeedAddresses[_feedId]).description();
    }

    function priceFeedDecimals(uint16 _feedId) public view returns (uint8) {
        return AggregatorV3Interface(priceFeedAddresses[_feedId]).decimals();
    }
}
