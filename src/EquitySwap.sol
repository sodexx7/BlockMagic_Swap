// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.25;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import { console2 } from "forge-std/src/console2.sol";
// import "./PriceFeeds.sol";

// contract EquitySwap is Ownable, PriceFeeds {
//     using SafeERC20 for IERC20;

//     // TODO: Period should be set by the user
//     uint8 public period; // as the global period time or can be set per swap by user?
//     uint64 public maxLegId = 1; // maxLegId's init value is 1
//     address private immutable settledStableToken; // users should deposit the stable coin to the contract when
// openSwap
//         // or pairSwap TODO  only support one stableCoin?

//     /// @notice Address of the yield strategy
//     /// @return yieldAddress the address of the yield strategy
//     struct YieldStrategy {
//         address yieldAddress;
//     }
//     // TODO: More yield strategy info, or as ta separate contract?
//     // TODO: when user deposit token; how to deal with yield?

//     mapping(uint8 => YieldStrategy) public YieldStrategies; // 1: Aave, 2: Compound, 3: Yearn

//     enum Status {
//         Open,
//         Active,
//         Settled,
//         Cancelled // User cancelled the order or no taker

//     }

//     /**
//      * @notice The Leg struct
//      * @param swaper The address of the swaper
//      * @param tokenAddress The address of the token
//      * @param notional The notional amount of the swap
//      * @param settledStableTokenAmount The amount of the stable token
//      * @param benchPrice The price of the token when open the swap
//      * @param startDate The start date of the swap
//      * @param pairLegId The pair leg id
//      * @param status The status of the swap
//      */
//     struct Leg {
//         address swaper;
//         address tokenAddress;
//         uint256 notional;
//         uint256 settledStableTokenAmount;
//         int256 benchPrice;
//         uint64 startDate;
//         /// @dev 0: not taken (open status), pairLegId>1: taken (active status)
//         uint64 pairLegId;
//         Status status;
//     }

//     /// @notice The leg owned by each account //TODO  check
//     /// @dev legId,
//     /// @notice get legInfo by querying the legId, get all legs info by combing maxLegId
//     /// @notice if want to used by external service,like chainlink, can use the legId
//     mapping(uint256 => Leg) public legs;

//     event OpenSwap(address indexed swaper, address indexed tokenAddress, uint256 notional, uint256 startDate);
//     event PairSwap(
//         uint256 indexed originalLegId, uint256 indexed pairlegId, address pairer, address pairToekn, uint256 notional
//     );
//     // TODO more PairSwap event cases
//     event SettleSwap(uint256 indexed legId, address indexed winner, address payToken, uint256 profit);
//     event NoProfitWhileSettle(uint256 indexed legId, address indexed swaper, address indexed pairer);

//     // event, who win the swap, how much profit
//     // event, the latest notional of the swaper and pairer after the settleSwap

//     // init the contract with the period and the yield strategy
//     // TODO memory changed to calldata
//     // TODO check Ownable(msg.sender)
//     constructor(
//         uint8 _period, /*uint8[] memory yields, address[] memory yieldAddress,*/
//         address _settledStableToken,
//         address _tokenAddress,
//         address _priceFeed
//     )
//         Ownable(msg.sender)
//         PriceFeeds(_tokenAddress, _priceFeed)
//     {
//         period = _period;
//         settledStableToken = _settledStableToken;
//         // require(yields.length == yieldAddress.length, "The length of the yields and yieldAddress should be
// equal");
//         // for(uint8 i; i < yields.length; i++) {
//         //     YieldStrategies[yields[i]] = YieldStrategy({
//         //         yieldAddress: yieldAddress[i]
//         //     });
//         // }
//     }

//     // TODO: When open the swap, should grant the contract can use the legToken along with the notional
//     // TODO: more conditions check, such as user should have enough token to open the swap
//     // TODO: For the legToken, should supply options for user's selection. (NOW, BTC, ETH, USDC)
//     // TODO: TYPE? Deposited stable coin or directly apply legToken.(Now only support Deposited stable coin)
//     function openSwap(
//         uint256 settledStableTokenAmount,
//         address legToken,
//         uint256 notional,
//         uint64 startDate
//     )
//         external
//     {
//         require(startDate > block.timestamp, "startDate should be greater than now"); // TODO change to custom error
//             // message

//         // check stable coin balance
//         require(
//             IERC20(settledStableToken).balanceOf(msg.sender) >= settledStableTokenAmount,
//             "The user should have enough token to open the swap"
//         );

//         int256 legTokenLatestPrice = getLatestPrice(legToken);
//         uint8 legTokenDecimals = ERC20(legToken).decimals();
//         uint8 priceDecimials = priceFeedDecimals(legToken);
//         // console2.log("legTokenLatestPrice",uint256(legTokenLatestPrice) / 10**priceDecimials ,"USDC");
//         // console2.log("opener settledStableTokenAmount",settledStableTokenAmount /
//         // 10**ERC20(settledStableToken).decimals(),"USDC");
//         // console2.log("legToken Market Value(USDC)",((notional / 10**legTokenDecimals) *
// uint256(legTokenLatestPrice)
//         // / (10**(priceDecimials)  )),"USDC");

//         // Now compare the value based on USDC verse USD. such as 1500USDC > 1000USD, elimate the fraction part
//         // (10_000.23  USDC > 30000.49 USD)
//         /**
//          * For example: opener deposited 1500USDC, the legToken's latest value is 1000 ETH/USD, the notional is 1
// ETH,
//          * below comparing 1500USDC verse 1000USD
//          * emiliating the fraction part, though the USD's decimals is 8, the USDC's decimals is 6
//          */
//         require(
//             settledStableTokenAmount / 10 ** ERC20(settledStableToken).decimals()
//                 >= (notional * uint256(legTokenLatestPrice) / 10 ** (legTokenDecimals + priceDecimials)),
//             "The settledStableTokenAmount shouldn't be less than legToken's market value"
//         );

//         // When transfer USDC to the contract, immediatly or when pairSwap?
//         IERC20(settledStableToken).transferFrom(msg.sender, address(this), settledStableTokenAmount);

//         Leg memory leg = Leg({
//             swaper: msg.sender,
//             tokenAddress: legToken,
//             notional: notional,
//             settledStableTokenAmount: settledStableTokenAmount,
//             startDate: startDate,
//             status: Status.Open,
//             pairLegId: 0, // Status.Open also means the pairLegId is 0
//             benchPrice: legTokenLatestPrice // TODO more check(store need to compare with the deposited USDC)
// BenchPrice
//                 // is updatated on the startDate
//          });

//         legs[maxLegId] = leg;
//         maxLegId++;
//         emit OpenSwap(msg.sender, legToken, notional, startDate);
//     }

//     function pairSwap(
//         uint256 settledStableTokenAmount,
//         uint64 originalLegId,
//         address pairToken,
//         uint256 notional
//     )
//         external
//     {
//         // TODO: in this stage, get all token price when pairing the swap?

//         Leg memory originalLeg = legs[originalLegId];
//         require(originalLeg.status == Status.Open, "The leg is not open");
//         require(originalLeg.startDate > block.timestamp, "The leg is expired");
//         // TODO: More rules check: the amount of the pairToken should be enough to pair the original leg?
//         // check stable coin balance
//         require(
//             IERC20(settledStableToken).balanceOf(msg.sender) >= settledStableTokenAmount,
//             "The user should have enough token to pair the swap"
//         );

//         uint256 pairTokenLatestPrice = uint256(getLatestPrice(pairToken));
//         uint8 priceDecimials = priceFeedDecimals(pairToken);
//         uint8 pairTokenDecimals = ERC20(pairToken).decimals();
//         // console2.log("pairTokenLatestPrice",pairTokenLatestPrice / 10**priceDecimials ,"USDC");
//         // console2.log("pairer settledStableTokenAmount",settledStableTokenAmount /
//         // 10**ERC20(settledStableToken).decimals(),"USDC");
//         // console2.log("pairToken Market Value(USDC)",((notional / 10**pairTokenDecimals) *
//         // uint256(pairTokenLatestPrice) / (10**(priceDecimials)  )),"USDC"); // TODO CHECK
//         // Now compare the value based on USDC verse USD. such as 1500USDC > 1000USD, elimate the fraction part
//         // (10_000.23  USDC > 30000.49 USD)
//         /**
//          * for exmaple: swaper deposited 1500USDC, the legToken's latest value is 1000 ETH/USD, the notional is 1
// ETH,
//          * below comparing 1500USDC verse 1000USD
//          *      emiliating the fraction part, though the USD's decimals is 8, the USDC's decimals is 6
//          */
//         require(
//             settledStableTokenAmount / 10 ** ERC20(settledStableToken).decimals()
//                 >= (notional * uint256(pairTokenLatestPrice) / 10 ** (pairTokenDecimals + priceDecimials)),
//             "The settledStableTokenAmount shouldn't be less than legToken's market value"
//         );

//         // Transfer the stable coin of the orderMaker and orderTaker to the contract
//         IERC20(settledStableToken).transferFrom(msg.sender, address(this), settledStableTokenAmount);

//         int256 pairLegTokenLatestPrice = getLatestPrice(pairToken);
//         Leg memory pairLeg = Leg({
//             swaper: msg.sender,
//             tokenAddress: pairToken,
//             notional: notional,
//             settledStableTokenAmount: settledStableTokenAmount,
//             startDate: originalLeg.startDate,
//             status: Status.Active,
//             pairLegId: originalLegId,
//             benchPrice: pairLegTokenLatestPrice // TODO: benchPrice should be updated on the startDate
//          });

//         legs[maxLegId] = pairLeg;
//         legs[originalLegId].pairLegId = maxLegId;
//         legs[originalLegId].status = Status.Active;

//         int256 originalLegPrice = getLatestPrice(originalLeg.tokenAddress);
//         legs[originalLegId].benchPrice = originalLegPrice;
//         maxLegId++;

//         emit PairSwap(originalLegId, legs[originalLegId].pairLegId, msg.sender, pairToken, notional);

//         // inform chainlink deal with the deal when the time is arrived. or was called by users
//     }

//     // This function was called by chainlink or by the user
//     // TODO Use historical price instead
//     /**
//      * @dev The function will settle the swap, and the winner will get the profit. the profit was calculated by the
//      * increased rate mulitiply the benchMarketCap
//      *    x`: the latest price of the original leg token
//      *    x : the bench price of the original leg token
//      *    y`: the latest price of the pair leg token
//      *    y : the bench price of the pair leg token
//      *    benchMarketCap: the smaller market cap of the two legs
//      *
//      *    when x`/x > y`/y, the profit is (x`*y - x*y`)*benchMarketCap/(x*y)
//      *    when y`/y > x`/x, the profit is (y`*x - y*x`)*benchMarketCap/(y*x)
//      *    how to get the formula:
//      *    if y`/y > x`/x
//      *    (y`/y-x`/x)*benchMarketCap => (y`*x - y*x`)/y*x*benchMarketCap=>(y`*x - y*x`)*benchMarketCap/(y*x)
//      */
//     function settleSwap(uint64 legId) external {
//         // TODO more conditions check
//         // 1. time check
//         Leg memory originalLeg = legs[legId];
//         Leg memory pairLeg = legs[originalLeg.pairLegId];
//         require(originalLeg.status == Status.Active && pairLeg.status == Status.Active, "The leg is not active");

//         // TODO precious and arithmetic calculation check, security check
//         int256 originalLegTokenLatestPrice = getLatestPrice(originalLeg.tokenAddress);
//         int256 pairLegTokenLatestPrice = getLatestPrice(pairLeg.tokenAddress);

//         uint8 legTokenDecimals = ERC20(originalLeg.tokenAddress).decimals();
//         uint8 pairTokenDecimals = ERC20(pairLeg.tokenAddress).decimals();
//         // uint8 legTokenPriceDecimials = priceFeedDecimals(originalLeg.tokenAddress);
//         // uint8 pairTokenPriceDecimials = priceFeedDecimals(pairLeg.tokenAddress);
//         // uint8 usdcDecimals = ERC20(settledStableToken).decimals();

//         // below marketCap was expressed by USD
//         uint256 originalLegMarketCap = (originalLeg.notional / 10 ** legTokenDecimals) *
// uint256(originalLeg.benchPrice);
//         // console2.log("originalLegMarketCap",originalLegMarketCap / 10**usdcDecimals, "USDC");
//         uint256 pairLegMarketCap = (pairLeg.notional / 10 ** pairTokenDecimals) * uint256(pairLeg.benchPrice);
//         // console2.log("pairLegMarketCap",pairLegMarketCap / 10**usdcDecimals, "USDC");
//         uint256 benchMarketCap = originalLegMarketCap > pairLegMarketCap ? pairLegMarketCap : originalLegMarketCap;
//         // compare the price change for the two legs
//         address winner;
//         uint256 profit;
//         uint256 updateLegId = legId;
//         // TODO, It's rare that existed the equal, should limited in a range(as 0.1% -> 0.2%)
//         if (originalLegTokenLatestPrice * pairLeg.benchPrice == pairLegTokenLatestPrice * originalLeg.benchPrice) {
//             // the increased rates of  both legToken price are all equal
//             emit NoProfitWhileSettle(legId, originalLeg.swaper, pairLeg.swaper);
//             return;
//         } else if (originalLegTokenLatestPrice * pairLeg.benchPrice > pairLegTokenLatestPrice *
// originalLeg.benchPrice)
//         {
//             // console2.log("originalLeg token price change:", uint256(originalLeg.benchPrice) /
//             // 10**legTokenPriceDecimials, uint256(originalLegTokenLatestPrice) / 10**legTokenPriceDecimials);
//             // console2.log("pairLeg token price change:", uint256(pairLeg.benchPrice) / 10**pairTokenPriceDecimials,
//             // uint256(pairLegTokenLatestPrice) / 10**pairTokenPriceDecimials);
//             {
//                 profit = (
//                     uint256(
//                         originalLegTokenLatestPrice * pairLeg.benchPrice
//                             - originalLeg.benchPrice * pairLegTokenLatestPrice
//                     ) * benchMarketCap
//                 ) / uint256(originalLeg.benchPrice * pairLeg.benchPrice);
//                 winner = originalLeg.swaper;
//             }
//         } else {
//             // console2.log("originalLeg token price change:", uint256(originalLeg.benchPrice) /
//             // 10**legTokenPriceDecimials, uint256(originalLegTokenLatestPrice) / 10**legTokenPriceDecimials);
//             // console2.log("pairLeg token price change:", uint256(pairLeg.benchPrice) / 10**pairTokenPriceDecimials,
//             // uint256(pairLegTokenLatestPrice) / 10**pairTokenPriceDecimials);
//             profit = (
//                 uint256(
//                     pairLegTokenLatestPrice * originalLeg.benchPrice - originalLegTokenLatestPrice *
// pairLeg.benchPrice
//                 ) * benchMarketCap
//             ) / uint256(originalLeg.benchPrice * pairLeg.benchPrice);

//             winner = pairLeg.swaper;
//             updateLegId = originalLeg.pairLegId;
//         }
//         profit = convertedBySettleStableCoin(profit);
//         // console2.log("winner:", winner);
//         // console2.log("profit:", profit / 10**usdcDecimals, "USDC");

//         IERC20(settledStableToken).transfer(winner, profit);
//         legs[updateLegId].settledStableTokenAmount = legs[updateLegId].settledStableTokenAmount - profit; // TODO
// should
//             // consider price does not change

//         // when end, the status of the two legs should be settled
//         legs[legId].status = Status.Settled;
//         legs[originalLeg.pairLegId].status = Status.Settled;

//         emit SettleSwap(legId, winner, settledStableToken, profit);

//         // TODO
//         // Related test cases
//         // Confirm the formula is right, especially confirm the loss of precision
//     }

//     function queryLeg(uint64 legId) external view returns (Leg memory) {
//         return legs[legId];
//     }

//     //  only contract can manage the yieldStrategs
//     function addYieldStrategy(uint8 yieldStrategyId, address yieldAddress) external onlyOwner {
//         require(YieldStrategies[yieldStrategyId].yieldAddress != address(0), "The yieldStrategyId already exists");

//         YieldStrategy memory yieldStrategy = YieldStrategy({ yieldAddress: yieldAddress });
//         YieldStrategies[yieldStrategyId] = yieldStrategy;
//     }

//     function removeYieldStrategy(uint8 yieldStrategyId) external onlyOwner {
//         require(YieldStrategies[yieldStrategyId].yieldAddress != address(0), "The yieldStrategyId not exists");
//         delete YieldStrategies[yieldStrategyId];
//     }

//     // @notice the amount value was based on the priceFeedDecimals(8 decimals for ETH/USD,BTC/USD on arbitrum), but
// the
//     // settledStableToken's decimals is 6
//     // TODO if  settledStableToken's decimals > priceFeedDecimals
//     function convertedBySettleStableCoin(uint256 amount) internal returns (uint256) {
//         uint8 settledStableTokenDecimals = ERC20(settledStableToken).decimals();
//         uint8 priceFeedDecimals = 8; // Temporary set to 18 TODO

//         return amount / 10 ** (priceFeedDecimals - settledStableTokenDecimals);
//     }
// }
