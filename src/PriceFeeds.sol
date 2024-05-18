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
contract PriceFeeds is Ownable, DegenFetcher {
    // TODO, Now directly get by price, can apply register in the future
    // tokenAddress=>priceFeedAddress
    mapping(address => address) priceFeedAddresses;

    constructor(address _tokenAddress, address _priceFeed) Ownable(_msgSender()) {
        priceFeedAddresses[_tokenAddress] = _priceFeed;
    }

    /**
     * @notice Returns the latest price
     *
     * @return latest price
     */

    //  TODO, should check updatTime, keep the price is the latest price
    function getLatestPrice(address tokenAddress) public view returns (int256) {
        (
            /* uint80 roundID */
            ,
            int256 price,
            /* uint256 startedAt */
            ,
            /* uint256 timeStamp */
            ,
            /* uint80 answeredInRound */
        ) = AggregatorV3Interface(priceFeedAddresses[tokenAddress]).latestRoundData();

        return price;
    }

    // Through degenFetcher, get historypirce
    // TODO how to config the params?
    function getHistoryPrice(address tokenAddress, uint256 timestamp) public view returns (int256) {
        int32[] memory prices =
            fetchPriceDataForFeed(priceFeedAddresses[tokenAddress], timestamp, uint80(1), uint256(2));
        return prices[0];
    }

    /**
     * @notice Returns the Price Feed address
     *
     * @return Price Feed address
     */
    function getPriceFeed(address tokenAddress) public view returns (address) {
        return priceFeedAddresses[tokenAddress];
    }

    // TODO for test
    function description(address tokenAddress) public view returns (string memory) {
        return AggregatorV3Interface(priceFeedAddresses[tokenAddress]).description();
    }

    // TODO, below function should optimize
    function addPriceFeed(address tokenAddress, address priceFeedAddress) external onlyOwner {
        priceFeedAddresses[tokenAddress] = priceFeedAddress;
    }

    function priceFeedDecimals(address tokenAddress) public view returns (uint8) {
        return AggregatorV3Interface(priceFeedAddresses[tokenAddress]).decimals();
    }
}
