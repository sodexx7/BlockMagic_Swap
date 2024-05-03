# Participants

1. opener, pairer, dealContract(EquitySwap)

# The define of Equity

1. Now take the token(BTC or USDC ) as the equity
2. the yields strategy can select when one person begin open one swap, like the Aave, Compound, Yearn, etc. TODO should
   check how to use the strategy
3. Structs of Equity(Leg)

```solidity
   1. swapwer: who ownes the equity
   2. tokenAddress: which token(Now just considet the top token BTC, USDC,ETH)
   3. Notional: the amount of the equity
   4. StartDate: the start date of the swap
   5. ExpireDate: StartDate + period(30 days)
   6. yieldStragett: based on user selecting which yieldStragety
   7. status: Open, Active,Settled,Cancelled
   8. pairLegId: if the leg doesn't pair, pairLegId=0, if paired, pairLegId = the legId of the pair leg

```

# YieldStrategy management

- owner can modify YieldStrategy

* todo
  1.  how to return the yields? when the swap end, send the yields to the user?

# Deal workFlow

1. 0ne user openSwap
2. Another user pairSwap, based on the legId, creating new pair.

   2.1 Updating the two pairs(status, pairLegId)

   2.2 Get all benchPrice for the two related legToken

   2.3 inform the chainlink, when call(startDate+period) and call who(legId)

3. SettleSwap.

   3.1 It'S time to call this function by chainlink.

   3.2 get the currentPrice for the two related legToken.

   3.3 Comparing the price of the legToken, deciding transfer profit to the winner.

   3.4 if not the end of swap, should update all leg info, if it's the ned of the swap, transfer all tokens to the
   corresponding's owner along with making the leg's status as settled.

# DealEngine(todo check my understanding is right? Based on the relative increased percent, Is it Fair?)

- Rules: How to send the profit the corresponding user?

1.  case1

    1.1. startDate: opener: 1 BTC, actual value: 10,000; pairer: 10,000 USDC BTC

    1.2. endDate: BTC increase: 0.5%. Now BTC market value: 10,500, USDC price don't change. the relative increase rates
    of the BTC comparing to the USDC: 5%.

    - 5% \* 10,000 = 500 USDC to BTC depositer.

      1.3. updating opener: 1 BTC, actual value: 10,500; pairer: 9,500 USDC

2.  case2

    2.1 startDate: opener: 1 BTC, actual value: 10,000; pairer: 5,000 USDC

    2.2 endDate: BTC increase: 0.5%. Now BTC market value: 10,500, USDC price don't change.

    - DealEngine: 5% \* 5,000 = 250 USDC to BTC depositer.

      2.3. updating opener: 1 BTC, actual value: 10,500; pairer: 4,750 USDC

# When using chainlink, which features?

1.  pairSwap

- get all token's bench price

* inform chainlink(automation) when to call settleSwap

2.  settleSwap

- was called by chainlink automation

* get all token's latest price

# TODO, or questiosn?

1. No matter the opener and the pairer, must have the same value for their equity?
2. Why not immediately begin the swap when another user pair the swap?
   - Just wait the startDate?
3. liquidation problems.

   - The reserve desgin?(disscussing) make the participant can keep on the swap avoid the liquidation before the swap
     end.

   * creation Date, TradeDate, start Date, fixDate1,fixDate2,fixDate3.... End Date (Current design, just have EndDate =
     fixDate1)

4. The market demands for the EquitySwap?

   - When user holds one asset(BTC) and want to bet another asset(ETH), but don't want to sell his token(BTC) to buy the
     ETH. Another user holds the ETH and want to bet the BTC, but don't want to sell his token(ETH) to buy the BTC.

   * questions? they maybe lost their current holding

5. consistant of the data structurre between smart contract and front-end

   - Now the leg data stucture is convenience for front-end?

6. More EquityType, maybe add more equity type in the future
   - Compitable with more Equity type, such as the swap between floating and fix rate. Stock price?
