// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract YieldStrategies is Ownable {
    mapping(uint8 => address) public yieldAddresses;
    address private immutable settledToken;

    constructor(
        uint8[] memory yieldIds,
        address[] memory yieldAddress,
        address settledStableToken
    )
        Ownable(_msgSender())
    {
        settledToken = settledStableToken;
        require(yieldIds.length == yieldAddress.length, "The length of the yields and yieldAddress should be equal");
        for (uint8 i; i < yieldIds.length; i++) {
            yieldAddresses[yieldIds[i]] = yieldAddress[i];
        }
    }

    // TODO different yield strategy may have different deposit function, so should use different function depends on
    // different yield strategy
    // TODO, add bytes action, which specify the corresponding function
    // TODO, Now make the CryptoSwap contract as the recipient
    function depositYield(uint8 yieldId, uint256 amount, address recipient) external returns (uint256) {
        require(yieldId != 0, "The yieldId is invalid");
        address yieldStrategyAddress = yieldAddresses[yieldId];
        IERC20(settledToken).transferFrom(_msgSender(), address(this), amount);
        IERC20(settledToken).approve(yieldStrategyAddress, amount);
        // below function is USDC yVault (yvUSDC) in ethereum mainnet
        // yieldStrategyAddress.deposit(amount,recipient);
        (bool ok, bytes memory result) =
            yieldStrategyAddress.call(abi.encodeWithSignature("deposit(uint256,address)", amount, recipient));
        require(ok);
        return abi.decode(result, (uint256));
    }

    // TODO  when dealing with withdraw yields,transfer to the CryptoSwap or directly to the user?
    // TODO, same questions as deposit function
    function withdrawYield(uint8 yieldId, uint256 amount, address recipient) external returns (uint256) {
        // approve the yieldStrategy to transfer the amount of yvUSDC token

        require(yieldId != 0, "The yieldId is invalid");
        // approve the yieldStrategy to transfer the amount of yvUSDC token
        address yieldStrategyAddress = yieldAddresses[yieldId];
        IERC20(yieldStrategyAddress).approve(address(this), amount);
        // below function is USDC yVault (yvUSDC) in ethereum mainnet
        // yieldStrategyAddress.withdraw(amount,recipient);
        (bool ok, bytes memory result) = yieldStrategyAddress.call(
            abi.encodeWithSignature("withdraw(uint256,address,uint256)", amount, recipient, 1)
        );
        require(ok);
        return abi.decode(result, (uint256));
    }

    //  only contract can manage the yieldStrategs
    function addYieldStrategy(uint8 yieldId, address yieldAddress) external onlyOwner {
        require(yieldAddresses[yieldId] != address(0), "The yieldId already exists");
        yieldAddresses[yieldId] = yieldAddress;
    }

    function removeYieldStrategy(uint8 yieldId) external onlyOwner {
        require(yieldAddresses[yieldId] != address(0), "The yieldId not exists");
        delete yieldAddresses[yieldId];
    }

    function getYieldStrategy(uint8 _strategyId) external view returns (address) {
        return yieldAddresses[_strategyId];
    }
}
