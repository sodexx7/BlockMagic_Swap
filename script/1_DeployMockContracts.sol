// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/src/Script.sol";
import "src/CryptoSwap.sol";

import "../src/test/mocks/MockERC20.sol";
import "../src/test/mocks/MockyvUSDC.sol";

contract DeployMockContracts is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockERC20 ethToken = new MockERC20("ETH", "ETH", 18);
        MockERC20 btcToken = new MockERC20("WBTC", "WBTC", 8);
        MockERC20 usdcContract = new MockERC20("USDC", "USDC", 6); // USDC default value on arb is 6
        MockyvUSDC yvUSDCContract = new MockyvUSDC("YvUSDC", "YvUSDC", 6, address(usdcContract)); // mock yearn yvUSDC

        vm.stopBroadcast();

        console.log("ethToken deployed to:", address(ethToken));
        console.log("btcToken deployed to:", address(btcToken));
        console.log("usdcContract deployed to:", address(usdcContract));
        console.log("yvUSDCContract deployed to:", address(yvUSDCContract));
    }
}
