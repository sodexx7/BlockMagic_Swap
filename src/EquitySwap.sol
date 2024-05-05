// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

contract EquitySwap is ownable {

    uint8 public period; // as the global period time or can be set per swap by user?
    uint64 public legIds = 1; // legIds's init value is 1
    Struct YieldStrategy {
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
        uint64 benchPrice;
        uint64 startDate;
        Status status;
        uint64 pairLegId; // 0 means not paired (open status), paired >1 means matched
    }

    // legId, used by chainlink and check the pair leg
    // how to get all legs? legIds: max legId. fron 1=>legIds
    mapping(uint => Leg) public legs;


    event OpenSwap(address indexed swaper, address indexed tokenAddress, uint notional,uint startDate);
    event PairSwap(uint indexed legId,address indexed pairer, address indexed pairToekn, uint notional);
    // todo more PairSwap event cases
    event SettelSwap(uint indexed legId, address indexed winner, address payToken, uint profit);
    

    // init the contract with the period and the yield strategy
    constructor(uint8 _period,uint8[] yields, address[] yieldAddress) public {
        period = _period;
        require(yields.length == yieldAddress.length, "The length of the yields and yieldAddress should be equal")
        for(uint8 i; i < yields.length; i++) {
            yieldStrategys[yields[i]] = YieldStrategy({
                yieldAddress: yieldAddress[i]
            });
        }
        
    }
  
    // TODO: when open the swap, should grant the contract can use the legToken along with the notional
    // TODO: more conditions check, such as user should have enough token to open the swap
    // TODO: For the legToken, should supply options for user's selection. (NOW, BTC,ETH,USDC)
    function openSwap(address legToken,uint notional,uint64 startDate) external {

        require(startDate > block.timestamp, "startDate should be greater than now"); // todo change to custom error message

        Leg memory leg = Leg({
            swaper: msg.sender,
            tokenAddress: legToken,
            notional: notional,
            benchPrice: 0 //todo, necessary get the token price when open the swap?
            startDate: startDate,
            status: Status.Open,
            pairLegId:0, //todo Status.Open also means the pairLegId is 0
            
        });

        emit OpenSwap(msg.sender, legToken, notional, startDate);

        legs[legIds] = leg;
        legIds++;
        
    }

    function pairSwap(uint64 originalLegId,address pairToken,uint notional) external {
        // todo, in this stage, get all token price when pair the swap?
        // get  openToken price by chainlink   ************************
        uint64 openTokenPrice = 11; // todo temporary set
        uint64 pairTokenPrice = 22; // todo temporary set
        // get  openToken price by chainlink   ************************

        Leg memory originalLeg =  legs[originalLegId];
        require(originalLeg.status == Status.Open, "The leg is not open");
        require(originalLeg.startDate > block.timestamp, "The leg is expired");
        // todo, mroe rules check: the amount of the pairToken should be enough to pair the original leg?
        Leg memory pairLeg = Leg({
            swaper: msg.sender,
            tokenAddress: pairToken,
            notional: notional,
            startDate: originalLeg.startDate,
            status: Status.Active,
            pairLegId: legId,
            benchPrice:pairTokenPrice 
        });

        legs[legIds] = pairLeg;
        legIds++;
        legs[legId].status = Status.Active;
        legs[legId].benchPrice = openTokenPrice;

        emit PairSwap(legId, msg.sender, pairToken, notional);

        // inform chainlink deal with the deal when the time is arrived.
        
    }


    // This function was called by chainlink
    function settleSwap(uint64 legId) external {

        // TODO more conditions check
        Leg memory leg1 =  legs[legId];
        require(leg1.status == Status.Active, "The leg is not active");

        Leg memory leg2 = legs[leg1.pairLegId];

        uint64 openTokenPrice = leg1.benchPrice; 
        uint64 pairTokenPrice = leg2.benchPrice; 

        uint64 openTokenPriceCur = 33; // get the price by chianlink  
        uint64 pairTokenPriceCur = 44; // get the price by chianlink  

        // openTokenPriceCur > openTokenPrice ? 
        // Deal engine

        // emit SettelSwap(legId, xxx, leg1.tokenAddress, profit);
          // DealEngine
        // 1. send which token to the user? the loser's token?

        
    }


    //  only contract can manage the yieldStrategs
    function addYieldStrategy(uint8 yieldStrategyId,address yieldAddress) external onlyOwner {
        require(yieldStrategys[yieldStrategyId] != 0, "The yieldStrategyId already exists");
        
        YieldStrategy memory yieldStrategy = YieldStrategy({
            yieldAddress: yieldAddress
        });
        yieldStrategys[yieldStrategyId] = yieldStrategy;
    }

    function removeYieldStrategy(uint8 yieldStrategy) external onlyOwner {
        require(yieldStrategys[yieldStrategyId] > 0, "The yieldStrategyId not exists");
        delete yieldStrategys[yieldStrategy];
    }