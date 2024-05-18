// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { console2 } from "forge-std/src/console2.sol";

/**
 * @title A Mock ERC20 contract used for testing
 */
contract MockyvUSDC is ERC20, Ownable {
    uint8 private _decimals;
    IERC20 private usdc;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        address usdcAddress
    )
        ERC20(name, symbol)
        Ownable(_msgSender())
    {
        _decimals = decimals_;
        usdc = IERC20(usdcAddress);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    // mock deposit, real case should refer fork test mode
    function deposit(uint256 amount, address recipient) external returns (uint256) {
        // usdc transfer to MockyvUSDC address, mint MockyvUSDC token to recipient
        usdc.transferFrom(_msgSender(), address(this), amount);
        _mint(recipient, amount);
        return amount;
    }
    // mock withdraw, real case should refer fork test mode

    function withdraw(uint256 amount, address recipient, uint256 share) external returns (uint256) {
        // usdc transfer to recipient while should receive share MockyvUSDC token then burn.
        transferFrom(_msgSender(), address(this), share);
        _burn(address(this), share);
        usdc.transfer(recipient, amount);
        return amount;
    }
}
