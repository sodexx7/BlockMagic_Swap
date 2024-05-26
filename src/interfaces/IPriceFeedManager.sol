pragma solidity 0.8.25;

interface IPriceFeedManager {
    function getLatestPrice(uint16 feedId) external view returns (int256);

    function getHistoryPrice(uint16 feedId, uint256 timestamp) external view returns (int256);

    function getPriceFeed(uint16 feedId) external view returns (address);

    function description(uint16 feedId) external view returns (string memory);

    function addPriceFeed(uint16 feedId, address priceFeedAddress) external;

    function priceFeedDecimals(uint16 feedId) external view returns (uint8);
}
