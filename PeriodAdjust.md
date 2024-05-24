## PeriodAdjust

1. interface:

   1. openSwap input add uint8 \_periodType, uint8 \_totalIntervals,
   1. pairSwap, settleswap interface keep same

2. Data structure for leg

   2.1 add new struct:SwapDealInfo,can add more info if needed. Now period and stats was moved to SwapDealInfo

   ```
       struct SwapDealInfo {
       uint64 startDate;
       uint64 updateDate;
       uint32 periodInterval;
       uint8 totalIntervals;
       Status status;
   }
   ```

   2.2 Leg add LegType(opener,parier), remove startDate, status to SwapDealInfo

   ```
        struct Leg {
       address swaper;
       address tokenAddress;
       uint256 notionalAmount;
       // uint256 settledStableTokenAmount;
       uint8 yieldId;
       int256 balance;
       int256 benchPrice;
       /// @dev 0: not taken (open status), pairLegId>1: taken (active status)
       uint64 pairLegId;
       LegType legType;
   }
   ```

   2.3 `// legId => SwapDealInfo  mapping(uint64 => SwapDealInfo) public swapDealInfos;` swapDealInfos keep the
   relationships between OPENER leg and the SwapDealInfo

3. Functions rebuild

   1. ` function getPricesForPeriod(     uint64 legId,     uint256 startDate,     uint256 endDate )` , return token's
      prices in different time. view function
   2. ` function calculatePerformanceForPeriod(     uint64 legAId,     uint64 legBId,     uint256 startDate,     uint256 endDate )`
      calculating the profit by view function
   3. `function queryHistoryPerformance(uint64 legId) public view returns (bool, uint64, uint64, int256, uint256)` query
      a deal's all accumulate profit, it one pair was bankrupt, also show the info
   4. `function withdraw(uint64 legId)`, if one user have profit, can withdraw all history profit meanwhile update the
      lastFixDate

4. Some logic explain

   1. (settleSwap) From the traditonal finance perspective, the swap should be settled at the end of the period,
      meanwhile this function can be called by the chianlink automation. so settleSwap can be settled in one period.
   2. For the accumulate profit, user can directly call withdraw

5. plus

   1. `calculatePerformanceForPeriod` can specify any two leg in any time, even the two legs are not paired.

6. todo which functions should added for show more info in front-end?

   1. add user's legs balance like below

   ```
      uint256 balance = cryptoSwap.legBalance(swaper);
      for (uint8 i = 0; i < balance; i++) {
         uint64 legId = cryptoSwap.legOfOwnerByIndex(swaper, i);
         CryptoSwap.Leg memory leg = cryptoSwap.queryLeg(legId);
      }
   ```

7. Test cases doing

```
 /**
     * Test cases:
     *     1. typicail call withdrawRouter, settleSwap,withdraw in first period
     *     2. First period not called, then will call withdraw
     *     3. check in different periods, the results is right
     */
```
