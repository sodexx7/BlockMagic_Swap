// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import { console2 } from "forge-std/src/console2.sol";

abstract contract YieldStrategys is Ownable {
    mapping(uint8 => address) public yieldStrategies;
    mapping(uint64 => uint256) public legIdShares;

    constructor(uint8[] memory yieldIds, address[] memory yieldAddress) {
        require(yieldIds.length == yieldAddress.length, "The length of the yields and yieldAddress should be equal");
        for (uint8 i; i < yieldIds.length; i++) {
            yieldStrategies[yieldIds[i]] = yieldAddress[i];
        }
    }

    // TODO different yield strategy may have different deposit function, so should use different function depends on
    // different yield strategy
    // TODO, add bytes action, which specify the corresponding function
    // TODO, Now make the CryptoSwap contract as the recipient
    function depositYield(uint8 yieldStrategyId, uint256 amount, address recipient) internal returns (uint256) {
        require(yieldStrategyId != 0, "The yieldStrategyId is invalid");
        address yieldStrategyAddress = yieldStrategies[yieldStrategyId];
        // below function is USDC yVault (yvUSDC) in ethereum mainnet
        // yieldStrategyAddress.deposit(amount,recipient);
        (bool ok, bytes memory result) =
            yieldStrategyAddress.call(abi.encodeWithSignature("deposit(uint256,address)", amount, recipient));
        require(ok);
        return abi.decode(result, (uint256));
    }

    // TODO  when dealing with withdraw yields,transfer to the CryptoSwap or directly to the user?
    // TODO, same questions as deposit function
    function withdrawYield(uint8 yieldStrategyId, uint256 amount, address recipient) internal returns (uint256) {
        require(yieldStrategyId != 0, "The yieldStrategyId is invalid");
        address yieldStrategyAddress = yieldStrategies[yieldStrategyId];
        // below function is USDC yVault (yvUSDC) in ethereum mainnet
        // yieldStrategyAddress.withdraw(amount,recipient);
        (bool ok, bytes memory result) = yieldStrategyAddress.call(
            abi.encodeWithSignature("withdraw(uint256,address,uint256)", amount, recipient, 1)
        );
        require(ok);
        console2.log("withdrawYield", abi.decode(result, (uint256)));
    }

    //  only contract can manage the yieldStrategs
    function addYieldStrategy(uint8 yieldStrategyId, address yieldAddress) external onlyOwner {
        require(yieldStrategies[yieldStrategyId] != address(0), "The yieldStrategyId already exists");
        yieldStrategies[yieldStrategyId] = yieldAddress;
    }

    function removeYieldStrategy(uint8 yieldStrategyId) external onlyOwner {
        require(yieldStrategies[yieldStrategyId] != address(0), "The yieldStrategyId not exists");
        delete yieldStrategies[yieldStrategyId];
    }

    function getYieldStrategy(uint8 _strategyId) external view returns (address) {
        return yieldStrategies[_strategyId];
    }
}
