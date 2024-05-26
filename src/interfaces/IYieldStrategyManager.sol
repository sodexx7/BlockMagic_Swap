pragma solidity 0.8.25;

interface IYieldStrategyManager {
    function depositYield(uint8 yieldStrategyId, uint256 amount, address recipient) external returns (uint256);

    function withdrawYield(uint8 yieldStrategyId, uint256 amount, address recipient) external returns (uint256);
    
    function addYieldStrategy(uint8 yieldStrategyId, address yieldAddress) external;

    function removeYieldStrategy(uint8 yieldStrategyId) external;

    function getYieldStrategy(uint8 _strategyId) external view returns (address);
}
