### **1. Data structure for leg design**

old Version

```
struct Leg {
        address swaper;
        address tokenAddress;
        uint256 notionalAmount;
        // uint256 settledStableTokenAmount;
        uint8 yieldId;
        int256 balance;
        int256 benchPrice;
        uint64 startDate;
        /// @dev 0: not taken (open status), pairLegId>1: taken (active status)
        uint64 pairLegId;
        Status status;
    }
```

New Version

```
struct SwapContract {
        uint256 contractMasterId;
        uint256 contractId;
        address userA;
        address userB;
        Period period;
        Leg legA;
        Leg legB;
        uint8 settlementTokenId;
        uint8 yieldId;
        uint256 notionalAmount;
        uint256 yieldShares;
        Status status;
    }

    struct Leg {
        bool legPosition; // true for legA, false for legB
        uint16 feedId;
        int256 benchPrice;
        int256 lastPrice;
        uint256 balance;
        uint256 withdrawable;
        uint256 poolPercentage; // percentage of the pool that this Leg currently owns
    }

    struct Period{
        uint64 startDate;
        uint32 periodInterval;
        uint8 totalIntervals;
        uint8 intervalCount;
    }
```

1. For the old version, there are overlap params when the user creates a new swap deal; two pair legs include two same
   params startDate status
2. But this brings some advantages
   1. fewer operations when need to update leg
   2. The old version is more flexible, such as pairing another leg.
   3. The new version doesn't maintain the relationship; should also input the pair leg in the front end
   4. Manage the legs easily; if It's not easy to get the individual leg by the swap contract.

### 2. Main functions interfaces:

1. openSwap

   ```
       uint256 _notionalId,
       uint256 _notionalCount, (the name is related with the notional )
       address legToken, (directly input the token address  for dealing with token operations)
       uint64 _startDate,
       uint8 _periodType, (adding )
       uint8 _totalIntervals,(adding)
       uint8 _settlementTokenId, (Currently, should require user deposit the stableToken add?)
       uint8 _yieldId
   ```

   1. When user opens a swap, select a legToken. Front-end can query pariLegConfig, query the corrospending's leg
      token(Now just support one legToken)
   2. If front-end need to show the paiLeg info, smart contracts' supply the legToken's prices.
   3. User should grant Cryptoswap contract the require amount of stableToken before calling openSwap.
   4. The only difference of the input comparing the new version is discarded the pairlegInfo check
   5. Does need to add \_settlementTokenId?

2. pairSwap

   ```
       uint64 originalLegId,
       uint256 notionalAmount,
       address pairToken,
       uint8 yieldId
   ```

   1. Now we only support 50:50. the notionalAmount must match the originalLegId's notionalAmount. smart contract supply
      the function to show the notionalAmount.
   2. PairToken can be queried by the smart contract's function.

3. `settleSwap(uint64 legId)`
   1. The core logic is dealing with who wins the profit.Now shoudl add \_periodType, \_totalIntervals logic

### **Add more help functions for front-end**

1. query Allleginfo by different status, as all legs are open
2. queyr pairLegConfig, getting pairleg by input one leg
3. Others?

### **to-do confirm**

1. notionalValueOptions verse directly input \_notionalAmount.

   - `require(_notionalAmount % 10 == 0, "The notional amount must be a multiple of 10");`
   - My understanding is can supply more options, like can add 55$ in the future. but will need more logic in the
     front-end.
   - Smart contracts can supply this function, shows each value of the notionalValueOptions. But doesn't matter use
     which solution.

2. The loop logic for \_periodType, \_totalIntervals

   - As our rule is zero-sum game, unlike staking game. user sometimes wins and sometimes lose, so their balance are
     changing. That's one reason I think it's inappropriatte to use this logic
   - If apply, just conpy the version logic meanwhile add a logic when the user's balance is less than zero(bankrupt
     logic)
