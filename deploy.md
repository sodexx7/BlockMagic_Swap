Here are the commands to deploy and verify the following contracts

1. Arbitrum
   1. YieldStrategies
      1. This will deploy and verify YieldStrategies for USDC set for yUSDC on Arbitrum
         1. forge create YieldStrategyManager --rpc-url https://arb-mainnet.g.alchemy.com/v2/{API} --private-key PRIVATE_KEY --verify
         2. Dummies: 0x6f376c17Cc423194205Fe74633A746526A53A4Df
   2. PriceFeeds
      1. This will deploy and verify PriceFeedsManager on Arbitrum
         1. forge create PriceFeedManager --rpc-url https://arb-mainnet.g.alchemy.com/v2/{API} --private-key PRIVATE_KEY --verify
         2. Dummies: 0x08751fAC1dA7D063daF6a2a6B5D6770F2f5517f7
   3. CryptoSwap
      1. This will deploy and verify CryptoSwap on Arbitrum
         1. Constructor args = address _priceFeedManager, address _yieldStrategyManager
         2. forge create CryptoSwap --constructor-args "0x08751fAC1dA7D063daF6a2a6B5D6770F2f5517f7" "0x6f376c17Cc423194205Fe74633A746526A53A4Df" --rpc-url https://arb-mainnet.g.alchemy.com/v2/{API} --private-key PRIVATE_KEY --verify
         3. Dummies: 0x06CE6359f93a9a12E415FffB65ACeb6BC3dAA161