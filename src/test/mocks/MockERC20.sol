// SPDX-License-Identifier: UNLICENSED
 pragma solidity 0.8.25;

 import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
 import "@openzeppelin/contracts/access/Ownable.sol";
 import { console2 } from "forge-std/src/console2.sol";
 
 /**
  * @title A Mock ERC20 contract used for testing
  */
 contract MockERC20 is ERC20,Ownable {
     uint8 private _decimals;
 
     constructor(
         string memory name,
         string memory symbol,
         uint8 decimals_
     ) ERC20(name, symbol) Ownable(_msgSender()) {
         _decimals = decimals_;
     }
 
     function decimals() public view override returns (uint8) {
         return _decimals;
     }

     function mint(address account, uint256 amount) external onlyOwner{
         _mint(account, amount);
     }
 }