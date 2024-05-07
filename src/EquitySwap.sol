// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { console2 } from "forge-std/src/console2.sol";
import "./PriceFeeds.sol";

contract EquitySwap is Ownable, PriceFeeds {
    using SafeERC20 for IERC20;

    // TODO: Period should be set by the user
    uint8 public period; // as the global period time or can be set per swap by user?
    uint64 public maxLegId = 1; // maxLegId's init value is 1
    address private immutable settledStableToken; // users should deposit the stable coin to the contract when openSwap
        // or pairSwap TODO  only support one stableCoin?

    /// @notice Address of the yield strategy
    /// @return yieldAddress the address of the yield strategy
    struct YieldStrategy {
        address yieldAddress;
    }
    // TODO: More yield strategy info, or as ta separate contract?
    // TODO: when user deposit token; how to deal with yield?

    mapping(uint8 => YieldStrategy) public yieldStrategys; // 1: Aave, 2: Compound, 3: Yearn

    enum Status {
        Open,
        Active,
        Settled,
        Cancelled // User cancelled the order or no taker

    }

    /**
     * @notice The Leg struct
     * @param swaper The address of the swaper
     * @param tokenAddress The address of the token
     * @param notional The notional amount of the swap
     * @param settledStableTokenAmount The amount of the stable token
     * @param benchPrice The price of the token when open the swap
     * @param startDate The start date of the swap
     * @param pairLegId The pair leg id
     * @param status The status of the swap
     */
    struct Leg {
        address swaper;
        address tokenAddress;
        uint256 notional;
        uint256 settledStableTokenAmount; //
        uint256 benchPrice;
        uint64 startDate;
        /// @dev 0: not taken (open status), pairLegId>1: taken (active status)
        uint64 pairLegId;
        Status status;
    }

    /// @notice The leg owned by each account
    /// @return leg the leg owned by the account
    /// @dev legId, used by chainlink and check the pair leg // TODO: Explain this part
    mapping(uint256 => Leg) public legs;

    event OpenSwap(address indexed swaper, address indexed tokenAddress, uint256 notional, uint256 startDate);
    event PairSwap(
        uint256 indexed originalLegId, uint256 indexed pairlegId, address pairer, address pairToekn, uint256 notional
    );
    // TODO more PairSwap event cases
    event SettleSwap(uint256 indexed legId, address indexed winner, address payToken, uint256 profit);

    // event, who win the swap, how much profit
    // event, the latest notional of the swaper and pairer after the settleSwap

    // init the contract with the period and the yield strategy
    // TODO memory changed to calldata
    // TODO check Ownable(msg.sender)
    constructor(
        uint8 _period, /*uint8[] memory yields, address[] memory yieldAddress,*/
        address _settledStableToken,
        address _tokenAddress,
        address _priceFeed
    )
        Ownable(msg.sender)
        PriceFeeds(_tokenAddress, _priceFeed)
    {
        period = _period;
        settledStableToken = _settledStableToken;
        // require(yields.length == yieldAddress.length, "The length of the yields and yieldAddress should be equal");
        // for(uint8 i; i < yields.length; i++) {
        //     yieldStrategys[yields[i]] = YieldStrategy({
        //         yieldAddress: yieldAddress[i]
        //     });
        // }
    }

    // TODO: When open the swap, should grant the contract can use the legToken along with the notional
    // TODO: more conditions check, such as user should have enough token to open the swap
    // TODO: For the legToken, should supply options for user's selection. (NOW, BTC, ETH, USDC)
    // TODO: TYPE? Deposited stable coin or directly apply legToken.(Now only support Deposited stable coin)
    function openSwap(
        uint256 settledStableTokenAmount,
        address legToken,
        uint256 notional,
        uint64 startDate
    )
        external
    {
        require(startDate > block.timestamp, "startDate should be greater than now"); // TODO change to custom error
            // message

        // check stable coin balance
        require(
            IERC20(settledStableToken).balanceOf(msg.sender) >= settledStableTokenAmount,
            "The user should have enough token to open the swap"
        );

        uint256 legTokenLatestPrice = uint256(getLatestPrice(legToken));
        // console2.log("opner settledStableTokenAmount",settledStableTokenAmount);
        // console2.log("notional*legTokenLatestPrice",notional*legTokenLatestPrice);

        // TODO: Need to change this requirement
        // User transfer USDC to the contract
        // check USDC's market value equal legTokenPrice*notional
        require(
            settledStableTokenAmount >= notional * legTokenLatestPrice,
            "The settledStableTokenAmount shouldn't be less than legToken's market value"
        );

        // When transfer USDC to the contract, immediatly or when pairSwap?
        IERC20(settledStableToken).transferFrom(msg.sender, address(this), settledStableTokenAmount);

        Leg memory leg = Leg({
            swaper: msg.sender,
            tokenAddress: legToken,
            notional: notional,
            settledStableTokenAmount: settledStableTokenAmount,
            startDate: startDate,
            status: Status.Open,
            pairLegId: 0, // Status.Open also means the pairLegId is 0
            benchPrice: 0 // BenchPrice is updatated on the startDate
         });

        legs[maxLegId] = leg;
        maxLegId++;
        emit OpenSwap(msg.sender, legToken, notional, startDate);
    }

    function pairSwap(
        uint256 settledStableTokenAmount,
        uint64 originalLegId,
        address pairToken,
        uint256 notional
    )
        external
    {
        // TODO: in this stage, get all token price when pairing the swap?

        Leg memory originalLeg = legs[originalLegId];
        require(originalLeg.status == Status.Open, "The leg is not open");
        require(originalLeg.startDate > block.timestamp, "The leg is expired");
        // TODO: More rules check: the amount of the pairToken should be enough to pair the original leg?
        // check stable coin balance
        require(
            IERC20(settledStableToken).balanceOf(msg.sender) >= settledStableTokenAmount,
            "The user should have enough token to pair the swap"
        );

        uint256 pairTokenLatestPrice = uint256(getLatestPrice(pairToken));
        // console2.log("pairer settledStableTokenAmount",settledStableTokenAmount);
        // console2.log("notional*pairTokenLatestPrice",notional*pairTokenLatestPrice);
        require(
            settledStableTokenAmount >= notional * pairTokenLatestPrice,
            "The settledStableTokenAmount shouldn't less than legToken's market value"
        );

        // Transfer the stable coin of the orderMaker and orderTaker to the contract
        IERC20(settledStableToken).transferFrom(msg.sender, address(this), settledStableTokenAmount);

        uint256 pairLegTokenLatestPrice = uint256(getLatestPrice(pairToken));
        Leg memory pairLeg = Leg({
            swaper: msg.sender,
            tokenAddress: pairToken,
            notional: notional,
            settledStableTokenAmount: settledStableTokenAmount,
            startDate: originalLeg.startDate,
            status: Status.Active,
            pairLegId: originalLegId,
            benchPrice: pairLegTokenLatestPrice // TODO: benchPrice should be updated on the startDate
         });

        legs[maxLegId] = pairLeg;
        legs[originalLegId].pairLegId = maxLegId;
        legs[originalLegId].status = Status.Active;

        uint256 originalLegPrice = uint256(getLatestPrice(originalLeg.tokenAddress));
        legs[originalLegId].benchPrice = originalLegPrice;
        maxLegId++;

        emit PairSwap(originalLegId, legs[originalLegId].pairLegId, msg.sender, pairToken, notional);

        // inform chainlink deal with the deal when the time is arrived.
    }

    // This function was called by chainlink or by the user
    // TODO Use historical price instead
    function settleSwap(uint64 legId) external {
        // TODO more conditions check
        // 1. time check
        Leg memory originalLeg = legs[legId];
        Leg memory pairLeg = legs[originalLeg.pairLegId];
        require(originalLeg.status == Status.Active && pairLeg.status == Status.Active, "The leg is not active");

        // TODO precious and arithmetic calculation check, security check
        uint256 originalLegTokenLatestPrice = uint256(getLatestPrice(originalLeg.tokenAddress));
        uint256 pairLegTokenLatestPrice = uint256(getLatestPrice(pairLeg.tokenAddress));

        uint256 originalLegMarketCap = originalLeg.benchPrice * originalLeg.notional;
        uint256 pairLegMarketCap = pairLeg.benchPrice * pairLeg.notional;
        uint256 benchMarketCap = originalLegMarketCap > pairLegMarketCap ? pairLegMarketCap : originalLegMarketCap;
        // compare the price change for the two legs
        address winner;
        uint256 profit;
        uint256 updateLegId = legId;
        // TODO, It's rare that existed the equal, should limited in a range(as 0.1% -> 0.2%)
        // x`/x = y`/y => x`*y = x*y` => x`*y - x*y` = 0
        if (originalLegTokenLatestPrice * pairLeg.benchPrice == pairLegTokenLatestPrice * originalLeg.benchPrice) {
            // the increased rates of  both legToken price are all equal
            // skip emit equal
            // x`/x > y`/y => x`*y > x*y` => x`*y - x*y` > 0
        } else if (originalLegTokenLatestPrice * pairLeg.benchPrice > pairLegTokenLatestPrice * originalLeg.benchPrice)
        {
            console2.log("originalLeg token price change:", originalLeg.benchPrice, originalLegTokenLatestPrice);
            console2.log("pairLeg token price change:", pairLeg.benchPrice, pairLegTokenLatestPrice);
            console2.log("benchMarketCap", benchMarketCap, "USDC");
            // how to calculate the profit: (x`/x-y`/y)*benchMarketCap => (x`*y - x*y`)/x*y*benchMarketCap=>(x`*y -
            // x*y`)*benchMarketCap/(x*y)
            profit = (
                (originalLegTokenLatestPrice * pairLeg.benchPrice - pairLegTokenLatestPrice * originalLeg.benchPrice)
                    * benchMarketCap
            ) / (originalLeg.benchPrice * pairLeg.benchPrice);
            winner = originalLeg.swaper;
        } else {
            console2.log("originalLeg token price change:", originalLeg.benchPrice, originalLegTokenLatestPrice);
            console2.log("pairLeg token price change:", pairLeg.benchPrice, pairLegTokenLatestPrice);
            console2.log("benchMarketCap", benchMarketCap, "USDC");
            profit = (
                (pairLegTokenLatestPrice * originalLeg.benchPrice - originalLegTokenLatestPrice * pairLeg.benchPrice)
                    * benchMarketCap
            ) / (originalLeg.benchPrice * pairLeg.benchPrice);
            // pairLeg win
            winner = pairLeg.swaper;
            updateLegId = originalLeg.pairLegId;
        }
        console2.log("winner:", winner);
        console2.log("profit:", profit);

        IERC20(settledStableToken).transfer(winner, profit);
        legs[updateLegId].settledStableTokenAmount = legs[updateLegId].settledStableTokenAmount - profit;

        // when end, the status of the two legs should be settled
        legs[legId].status = Status.Settled;
        legs[originalLeg.pairLegId].status = Status.Settled;

        emit SettleSwap(legId, winner, settledStableToken, profit);

        // TODO
        // Related test cases
        // Confirm the formula is right, especially confirm the loss of precision
    }

    function queryLeg(uint64 legId) external view returns (Leg memory) {
        return legs[legId];
    }

    //  only contract can manage the yieldStrategs
    function addYieldStrategy(uint8 yieldStrategyId, address yieldAddress) external onlyOwner {
        require(yieldStrategys[yieldStrategyId].yieldAddress != address(0), "The yieldStrategyId already exists");

        YieldStrategy memory yieldStrategy = YieldStrategy({ yieldAddress: yieldAddress });
        yieldStrategys[yieldStrategyId] = yieldStrategy;
    }

    function removeYieldStrategy(uint8 yieldStrategyId) external onlyOwner {
        require(yieldStrategys[yieldStrategyId].yieldAddress != address(0), "The yieldStrategyId not exists");
        delete yieldStrategys[yieldStrategyId];
    }
}
