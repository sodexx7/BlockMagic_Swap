# Equity Swap Intro

The application will act like an Escrow for market participants willing to enter into a Swap contract. We are firstly
focusing on Price Return Swap.

## Participants

- opener/orderMaker: A user making an offer for a Swap contract.
  - Can make an offer for a Swap contract on the website.
- pairer/orderTaker: A user joining an offer for a Swap Contract.
  - Can take an offer for a Swap contract on the website.
- dealContract(EquitySwap): The contract acting as third party

## Definition of Equity Swap

1. orderMaker select:

- Notional ($10, $100, $1,000)
  - $100 X 5 ==> creates 5 swap deals of $100 Notional
  - If someone else wants to take only $100, he will "take" one of the swap deal
- Leg A (AAPL, AMZN, NVDA, etc...)
- Leg B (AAPL, AMZN, NVDA, etc...) **Can choose more than one**
- Start Date
- End Date
- Frequency (Weekly/Monthly/Quaterly/Annualy)
- Currency (BTC, ETH, USDC, etc...)
- Yield (Aave, Compound, Yearn, etc...) **Check how to use the strategy**

```solidity
   1. swaper: The address of the user
   2. tokenAddress: The token address of the currency
   3. Notional: The notional amount of the swap
   4. StartDate: The start date of the swap
   5. ExpireDate: StartDate + period(30 days)
   6. yieldStrategy: The yield selected by the user
   7. status: Open, Active, Settled, Cancelled
   8. pairLegId: if the leg isn't paired, pairLegId=0, if paired, pairLegId = the legId of the pair leg
```

## YieldStrategy management

- Owner can modify YieldStrategy

### Todo

- How to return the yields?  
  When the swap end, send the yields to the user?

## Deal workFlow

1. 0ne user openSwap
2. Another user pairSwap, based on the legId, creating new pair.

   2.1 Updating the two pairs(status, pairLegId)

   2.2 Get all benchPrice for the two related legToken at the startDate

   2.3 Inform the chainlink, when call(startDate+period) and call who(legId)

3. SettleSwap.

   3.1 It'S time to call this function by chainlink.

   3.2 get the currentPrice for the two related legToken.

   3.3 Comparing the price of the legToken, deciding transfer profit to the winner.

   3.4 if not the end of swap, should update all leg info, if it's the ned of the swap, transfer all tokens to the
   corresponding's owner along with making the leg's status as settled.

## [DealEngine](DealEngine.md)

## When using chainlink, which features?

1.  pairSwap

- get all token's bench price

* inform chainlink(automation) when to call settleSwap

2.  settleSwap X

- was called by chainlink automation

* get all token's latest price

## TODO, or questiosn?

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

## FAQ Trader

- Should allow Notional (10/100/1000) with multiplier
  - This will allow matching of position
- We should introduce a Margin call mechanism (version 2):
  - Reserve
  - Dipslay margin call satus from contract
  - Give 24h to 36h (1 to 1.5 days) to repay
  - For the minimum margin
    - We can use the volatily 1 week of the underlying
- We should only give yield only for short leg
  - To avoid arbitrage !!!
- Problem if we use ratio to sanction people with less money
  - Need to check for arbitrage opportunity (Opening a lot of contract)
- We should do Long GOOGLE VS Short Google i/o GOOGLE VS AMAZON
V2 - V3
- Fix rate VS Google => Aave/Defi Rate Vs Google perfomance
