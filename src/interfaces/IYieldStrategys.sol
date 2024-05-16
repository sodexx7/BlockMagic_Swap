pragma solidity 0.8.25;

interface IYieldStrategys {
    function depositYield(uint8 yieldStrategyId, uint256 amount, address recipient) external returns (uint256);

    // TODO  when dealing with withdraw yields,transfer to the CryptoSwap or directly to the user?
    // TODO, same questions as deposit function
    function withdrawYield(uint8 yieldStrategyId, uint256 amount, address recipient) external returns (uint256);

    //  only contract can manage the yieldStrategs
    function addYieldStrategy(uint8 yieldStrategyId, address yieldAddress) external;

    function removeYieldStrategy(uint8 yieldStrategyId) external;

    function getYieldStrategy(uint8 _strategyId) external view returns (address);
}
