Here are the commands to deploy and verify the following contracts

1. Arbitrum
   1. YieldStrategies
      1. This will deploy and verify YieldStrategies for USDC set for yUSDC on Arbitrum
         1. Constructor args = uint8[] memory yieldIds, address[] memory yieldAddress, address settledStableToken
         2. forge create YieldStrategies --constructor-args "[1]" "[0x6FAF8b7fFeE3306EfcFc2BA9Fec912b4d49834C1]" "0xaf88d065e77c8cC2239327C5EDb3A432268e5831" --rpc-url https://arb-mainnet.g.alchemy.com/v2/{API_KEY} --private-key PRIVATE_KEY --verify
         3. Dummies: 0x89b0b02407EE20232d39AED5Fa44c17499a2b0E7
   2. PriceFeeds
      1. This will deploy and verify PriceFeeds for USDC on Arbitrum
         1. Constructor args = address _tokenAddress, address _priceFeed
         2. forge create PriceFeeds --constructor-args "0xaf88d065e77c8cC2239327C5EDb3A432268e5831" "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3" --rpc-url https://arb-mainnet.g.alchemy.com/v2/{API_KEY} --private-key PRIVATE_KEY --verify
         3. Dummies: 0xc5681E5B2cC5E520393641824C408e536558Dd21
   3. CryptoSwap
      1. This will deploy and verify CryptoSwap on Arbitrum
         1. Constructor args = address _settledStableToken, address priceFeedsAddress, address YieldStrategiesAddress, uint8[] memory notionalIds, uint256[] memory notionalValues
         2. forge create CryptoSwap --constructor-args "0xaf88d065e77c8cC2239327C5EDb3A432268e5831" "0xc5681E5B2cC5E520393641824C408e536558Dd21" "0xB0bDD147b8f86B438747CF58DA4BBfAfE17c9519" "[1,2,3]" "[10,100,1000]" --rpc-url https://arb-mainnet.g.alchemy.com/v2/{API_KEY} --private-key PRIVATE_KEY --verify
         3. Dummies: 0x1d1fD1d8E3FBc644c28B97aFD7f9a7aC71AACf55