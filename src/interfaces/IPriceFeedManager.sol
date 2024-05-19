pragma solidity 0.8.25;

interface IPriceFeedManager {
    function getLatestPrice(address tokenAddress) external view returns (int256);

    function getHistoryPrice(address tokenAddress, uint256 timestamp) external view returns (int256);

    function getPriceFeed(address tokenAddress) external view returns (address);

    // TODO for test
    function description(address tokenAddress) external view returns (string memory);

    function addPriceFeed(address tokenAddress, address priceFeedAddress) external;

    function priceFeedDecimals(address tokenAddress) external view returns (uint8);
}
