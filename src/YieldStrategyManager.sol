// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YieldStrategyManager is Ownable {
    // Mapping of yield strategy IDs to their contract addresses and deposit tokens
    mapping(uint8 => address[2]) public yieldAddresses; 

    /// @notice Constructor to set the owner
    constructor() Ownable(msg.sender) {}

    /// @notice Deposits tokens into a yield strategy
    /// @param _yieldId The ID of the yield strategy
    /// @param _amount The amount of tokens to deposit
    /// @param _recipient The address to receive the yield shares
    /// @return shares The amount of shares received from the deposit
    function depositYield(uint8 _yieldId, uint256 _amount, address _recipient) external returns (uint256 shares) {
        require(_yieldId != 0, "Invalid yield ID");
        require(yieldAddresses[_yieldId][0] != address(0), "Yield strategy not found");

        address yieldStrategyAddress = yieldAddresses[_yieldId][0];
        address depositToken = yieldAddresses[_yieldId][1];

        IERC20(depositToken).transferFrom(_msgSender(), address(this), _amount);
        IERC20(depositToken).approve(yieldStrategyAddress, _amount);

        // Calling the deposit function of the yield strategy
        (bool ok, bytes memory result) = yieldStrategyAddress.call(
            abi.encodeWithSignature("deposit(uint256,address)", _amount, _recipient)
        );
        require(ok, "Deposit failed");

        return abi.decode(result, (uint256));
    }

    /// @notice Withdraws tokens from a yield strategy
    /// @param _yieldId The ID of the yield strategy
    /// @param _amount The amount of shares to withdraw
    /// @param _recipient The address to receive the withdrawn tokens
    /// @return withdrawnAmount The amount of tokens withdrawn
    function withdrawYield(uint8 _yieldId, uint256 _amount, address _recipient) external returns (uint256 withdrawnAmount) {
        require(_yieldId != 0, "Invalid yield ID");
        require(yieldAddresses[_yieldId][0] != address(0), "Yield strategy not found");

        address yieldStrategyAddress = yieldAddresses[_yieldId][0];

        IERC20(yieldStrategyAddress).approve(address(this), _amount);

        // Calling the withdraw function of the yield strategy
        (bool ok, bytes memory result) = yieldStrategyAddress.call(
            abi.encodeWithSignature("withdraw(uint256,address,uint256)", _amount, _recipient, 1)
        );
        require(ok, "Withdrawal failed");

        return abi.decode(result, (uint256));
    }

    /// @notice Adds a new yield strategy
    /// @param _yieldId The ID to assign to the new yield strategy
    /// @param _yieldAddress The contract address of the yield strategy
    /// @param _depositToken The address of the deposit token
    function addYieldStrategy(uint8 _yieldId, address _yieldAddress, address _depositToken) external onlyOwner {
        require(yieldAddresses[_yieldId][0] == address(0), "Yield ID already in use");
        require(_yieldAddress != address(0) && _depositToken != address(0), "Invalid addresses");

        yieldAddresses[_yieldId] = [_yieldAddress, _depositToken];
    }

    /// @notice Removes a yield strategy
    /// @param _yieldId The ID of the yield strategy to remove
    function removeYieldStrategy(uint8 _yieldId) external onlyOwner {
        require(yieldAddresses[_yieldId][0] != address(0), "Yield ID does not exist");
        delete yieldAddresses[_yieldId];
    }

    /// @notice Gets the address of a yield strategy
    /// @param _yieldId The ID of the yield strategy
    /// @return The address of the specified yield strategy and deposit token
    function getYieldStrategy(uint8 _yieldId) external view returns (address[2] memory) {
        return yieldAddresses[_yieldId];
    }
}
