// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import { console2 } from "forge-std/src/console2.sol";
import "./PriceFeeds.sol";

contract EquitySwap is Ownable,PriceFeeds {

    uint8 public period; // as the global period time or can be set per swap by user?
    uint64 public maxLegId = 1; // maxLegId's init value is 1
    struct YieldStrategy{
        address yieldAddress;
        // todo, more yield strategy info, or as ta sepatate contract
    }
    // todo: when user deposit tokem; how to deal with yield??
    mapping(uint8 => YieldStrategy) public yieldStrategys; // 1: Aave, 2: Compound, 3: Yearn

    enum Status {
        Open,
        Active,
        Settled,
        Cancelled // No one pair or user cancled the swap
    }
    struct Leg{
        address swaper;
        address tokenAddress;
        uint notional;
        uint256 benchPrice;
        uint64 startDate;
        uint64 pairLegId; // 0 means not paired (open status), paired >1 means matched
        Status status;
    }

    // legId, used by chainlink and check the pair leg
    // how to get all legs? maxLegId: max legId. front 1=>maxLegId
    mapping(uint => Leg) public legs;

    event OpenSwap(address indexed swaper, address indexed tokenAddress, uint notional,uint startDate);
    event PairSwap(uint indexed originalLegId,uint indexed pairlegId,address pairer, address pairToekn, uint notional);
    // todo more PairSwap event cases
    event SettelSwap(uint indexed legId, address indexed winner, address payToken, uint profit);

    // event, who win the swap, how much profit
    // event, the latest notional of the swaper and pairer after the settleSwap
    
    // init the contract with the period and the yield strategy
    // TODO memory changed to calldata
    // TODO check Ownable(msg.sender)
    constructor(uint8 _period,/*uint8[] memory yields, address[] memory yieldAddress,*/ address _tokenAddress,address _priceFeed) Ownable(msg.sender) PriceFeeds(_tokenAddress,_priceFeed)  public {
        period = _period;
        // require(yields.length == yieldAddress.length, "The length of the yields and yieldAddress should be equal");
        // for(uint8 i; i < yields.length; i++) {
        //     yieldStrategys[yields[i]] = YieldStrategy({
        //         yieldAddress: yieldAddress[i]
        //     });
        // }
    }
  
    // TODO: when open the swap, should grant the contract can use the legToken along with the notional
    // TODO: more conditions check, such as user should have enough token to open the swap
    // TODO: For the legToken, should supply options for user's selection. (NOW, BTC,ETH,USDC)
    // TODO: TYPE? Deposited stable coin or directly apply legToken.(Now only support Deposited stable coin)
    function openSwap(address legToken,uint notional,uint64 startDate) external {

        require(startDate > block.timestamp, "startDate should be greater than now"); // todo change to custom error message

        //  user transfer usdc to the contract and make sure the usdc's market value equal legTokenPrice* notional TODO, when transfer usdc to the contract,now or when pairSwap?

        uint256 legTokenPrice = uint256(getLatestPrice(legToken));
        Leg memory leg = Leg({
            swaper: msg.sender,
            tokenAddress: legToken,
            notional: notional,
            benchPrice: legTokenPrice, 
            startDate: startDate,
            status: Status.Open,
            pairLegId:0 //todo Status.Open also means the pairLegId is 0
        });

        legs[maxLegId] = leg;
        maxLegId++;
        emit OpenSwap(msg.sender, legToken, notional, startDate);
        
    }

    function pairSwap(uint64 originalLegId,address pairToken,uint notional) external {
        // todo, in this stage, get all token price when pair the swap?
  
        Leg memory originalLeg = legs[originalLegId];
        require(originalLeg.status == Status.Open, "The leg is not open");
        require(originalLeg.startDate > block.timestamp, "The leg is expired");
        // todo, mroe rules check: the amount of the pairToken should be enough to pair the original leg?

        uint256 pairLegTokenLatestPrice = uint256(getLatestPrice(pairToken));
        Leg memory pairLeg = Leg({
            swaper: msg.sender,
            tokenAddress: pairToken,
            notional: notional,
            startDate: originalLeg.startDate,
            status: Status.Active,
            pairLegId: originalLegId,
            benchPrice: pairLegTokenLatestPrice
        });

        legs[maxLegId] = pairLeg;
        legs[originalLegId].pairLegId = maxLegId;
        legs[originalLegId].status = Status.Active;

        uint256 originalLegPrice = uint256(getLatestPrice(originalLeg.tokenAddress));
        legs[originalLegId].benchPrice = originalLegPrice;
        maxLegId++;

        emit PairSwap(originalLegId,legs[originalLegId].pairLegId, msg.sender, pairToken, notional);

        // inform chainlink deal with the deal when the time is arrived.
    }

    // This function was called by chainlink or by the user
    function settleSwap(uint64 legId) external {

        // TODO more conditions check
        // 1. time check
        Leg memory originalLeg = legs[legId];
        Leg memory pairLeg = legs[originalLeg.pairLegId];
        require(originalLeg.status == Status.Active && pairLeg.status == Status.Active, "The leg is not active");
        
        // TODO precious and arithmetic calculation check, securty check
        uint256 originalLegTokenLatestPrice = uint256(getLatestPrice(originalLeg.tokenAddress));
        uint256 pairLegTokenLatestPrice = uint256(getLatestPrice(pairLeg.tokenAddress));

        uint256 originalLegMarketCap = originalLeg.benchPrice*originalLeg.notional;
        uint256 pairLegMarketCap = pairLeg.benchPrice*pairLeg.notional;
        uint256 benchMarketCap = originalLegMarketCap > pairLegMarketCap ? pairLegMarketCap:originalLegMarketCap;
        // compare the price change for the two legs
        address winner;
        uint256 profit;
        // TODO, It's rare that existed the equal, should limited in a range(as 0.1% = 0.2%)
        // x`/x = y`/y => x`*y = x*y` => x`*y - x*y` = 0
        if(originalLegTokenLatestPrice*pairLeg.benchPrice == pairLegTokenLatestPrice*originalLeg.benchPrice){ // the increased rates of  both legToken price are all equal
            // skip emit equal
            // x`/x > y`/y => x`*y > x*y` => x`*y - x*y` > 0
        } else if (originalLegTokenLatestPrice*pairLeg.benchPrice > pairLegTokenLatestPrice*originalLeg.benchPrice){
            console2.log("originalLeg token price change:",originalLeg.benchPrice,originalLegTokenLatestPrice);
            console2.log("pairLeg token price change:",pairLeg.benchPrice,pairLegTokenLatestPrice);
            console2.log("benchMarketCap<USDC>",benchMarketCap);
            // how to calculate the profit: (x`/x-y`/y)*benchMarketCap => (x`*y - x*y`)/x*y*benchMarketCap=>(x`*y - x*y`)*benchMarketCap/(x*y)
            profit = ((originalLegTokenLatestPrice*pairLeg.benchPrice - pairLegTokenLatestPrice*originalLeg.benchPrice) * benchMarketCap) / (originalLeg.benchPrice*pairLeg.benchPrice);
            winner = originalLeg.swaper;
        } else {
            console2.log("originalLeg token price change:",originalLeg.benchPrice,originalLegTokenLatestPrice);
            console2.log("pairLeg token price change:",pairLeg.benchPrice,pairLegTokenLatestPrice);
            console2.log("benchMarketCap<USDC>",benchMarketCap);
            profit = ((pairLegTokenLatestPrice*originalLeg.benchPrice - originalLegTokenLatestPrice*pairLeg.benchPrice) * benchMarketCap) / (originalLeg.benchPrice*pairLeg.benchPrice);
            // originalLeg win
            winner = pairLeg.swaper;
        }
        console2.log("winner:",winner);
        console2.log("profit:",profit);
        // TOOD
        // 1. transfer the profit to the winner
        // 2. update the status of the originalLeg and pairLeg
        // 3. emit the event
        // 4. update the notional of the originalLeg and pairLeg
        
    }

    function queryLeg(uint64 legId) external view returns(Leg memory) {
        return legs[legId];
    }


    //  only contract can manage the yieldStrategs
    function addYieldStrategy(uint8 yieldStrategyId,address yieldAddress) external onlyOwner {
        require(yieldStrategys[yieldStrategyId].yieldAddress != address(0), "The yieldStrategyId already exists");
        
        YieldStrategy memory yieldStrategy = YieldStrategy({
            yieldAddress: yieldAddress
        });
        yieldStrategys[yieldStrategyId] = yieldStrategy;
    }

    function removeYieldStrategy(uint8 yieldStrategyId) external onlyOwner {
        require(yieldStrategys[yieldStrategyId].yieldAddress != address(0), "The yieldStrategyId not exists");
        delete yieldStrategys[yieldStrategyId];
    }
}