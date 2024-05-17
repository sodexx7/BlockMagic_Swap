## HowToGetHistoryPrice

1. The main logic showd in this,https://docs.chain.link/data-feeds/historical-data.

   - User get the priceInfo through poxy, which called the Aggregator. The priceInfo maybe was stored in the different
     Aggregator. The algorithm was find the corresponding roundId with the timestamp while check all Aggregators

2. Two ways getting the history priceFeed based on above algorithm.

   2.1 front-end
   https://github.com/smartcontractkit/quickstarts-historical-prices-api/tree/85180c5a1d06eba6e32417bfbf19fcbb53e140be

   2.2 smart-contract https://github.com/andyszy/DegenFetcher

- **My opinion is just used the point 2 no matter in smart contract or front-end**

# Question for this solution

- https://blog.chain.link/historical-cryptocurrency-price-data/

  1.  Have past two years, maybe not fit current situation

  2.  Solution workflow:

  - Consumer Contract(such as EquitySwap) => chainlink anyAPI => external adapter.

  * for my understanding, external adapter have done the above point 1 and 2's work meanwhile solving other problems
    like capability limitations or efficiency considerations.

    **But the problems are: First don't find the external adapter**

    **Second is should used anyapi in smartcontracts which maybe will consumed the link as gas**
