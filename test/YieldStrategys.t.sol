// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { Test } from "forge-std/src/Test.sol";
import "forge-std/src/StdUtils.sol";
import { console2 } from "forge-std/src/console2.sol";
import { YieldStrategys } from "../src/YieldStrategys.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface YieldStrategysInterface {
    function deposit(uint256 depositUSDC, address user) external;
    function balanceOf(address) external returns (uint256);
    function withdraw(uint256 maxShares,address user,uint256 maxLoss) external returns (uint256);
}

contract YieldStrategysTest is Test {

    address usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC contract address on Ethereum Mainnet

    /// @dev A function invoked before each test case is run.
    /**
     * Initial price for ETH/USD: 1000, BTC/USD: 60_000, whose decimals are 8
     */
    function setUp() public virtual {
        

    }

   /// @dev Fork test that runs against an Ethereum Mainnet fork. For this to work, you need to set `API_KEY_ALCHEMY`
    /// in your environment You can get an API key for free at https://alchemy.com.
    function testFork_YearnYield() external {
        // Silently pass this test if there is no API key.
        string memory alchemyApiKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        if (bytes(alchemyApiKey).length == 0) {
            return;
        }
        // Otherwise, run the test against the mainnet fork.
        vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 19_865_400 });  // 19865622 16_428_000

        address user = address(0x09);
        deal(usdcAddress, user, 10e6); 

        // deposit USDC to yvUSDC yeran vault
        address yvUSDC = address(0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE); // ethereum mainnet yvUSDC
        uint256 depositUSDC= 10e6;

        vm.startPrank(user);
        IERC20(usdcAddress).approve(yvUSDC, depositUSDC);
        uint256 usdcBalanceBefore = IERC20(usdcAddress).balanceOf(user);
        console2.log("usdc balance before deposit", usdcBalanceBefore);
        // YieldStrategysInterface(yvUSDC).deposit(depositUSDC, user);

        (bool ok,bytes memory result) =
        yvUSDC.call(abi.encodeWithSignature("deposit(uint256,address)", depositUSDC, user));
        require(ok);
        uint256 shares =  abi.decode(result, (uint256));
        uint256 usdcBalanceAfter = IERC20(usdcAddress).balanceOf(user);
        console2.log("usdc balance after deposit", usdcBalanceAfter);
        // uint256 shares = YieldStrategysInterface(yvUSDC).balanceOf(user);
        console2.log("yields share",shares);
        uint256 expectedUSDCForShare = depositUSDC/shares;
        console2.log("after withdraw 1 USDC");
        // reference
        // https://docs.yearn.fi/vaults/smart-contracts/vault#withdraw-1 
        // https://github.com/yearn/yearn-vaults/blob/97ca1b2e4fcf20f4be0ff456dabd020bfeb6697b/contracts/Vault.vy#L1033
        // YieldStrategysInterface(yvUSDC).withdraw(expectedUSDCForShare*1e6, user, 1); 
        (bool ok1,bytes memory result2) =
        yvUSDC.call(abi.encodeWithSignature("withdraw(uint256,address,uint256)", expectedUSDCForShare*1e6, user,1));
        require(ok1);
        console2.log("usdc balance after withdraw  shares", IERC20(usdcAddress).balanceOf(user));
        vm.stopPrank();

    }
}
