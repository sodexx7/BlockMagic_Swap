// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { console2 } from "forge-std/src/console2.sol";

contract DegenFetcherV2 {
    uint80 constant SECONDS_PER_DAY = 3600 * 24;

    function getPhaseForTimestamp(
        AggregatorV2V3Interface feed,
        uint256 targetTime
    )
        public
        view
        returns (uint80, uint256, uint80)
    {
        uint16 currentPhase = uint16(feed.latestRound() >> 64);
        uint80 firstRoundOfCurrentPhase = (uint80(currentPhase) << 64) + 1;

        for (uint16 phase = currentPhase; phase >= 1; phase--) {
            uint80 firstRoundOfPhase = (uint80(phase) << 64) + 1;
            uint256 firstTimeOfPhase = feed.getTimestamp(firstRoundOfPhase);

            if (targetTime > firstTimeOfPhase) {
                return (firstRoundOfPhase, firstTimeOfPhase, firstRoundOfCurrentPhase);
            }
        }
        return (0, 0, firstRoundOfCurrentPhase);
    }

    function guessSearchRoundsForTimestamp(
        AggregatorV2V3Interface feed,
        uint256 fromTime
    )
        public
        view
        returns (uint80 firstRoundToSearch, uint80 numRoundsToSearch)
    {
        (uint80 lhRound, uint256 lhTime, uint80 firstRoundOfCurrentPhase) = getPhaseForTimestamp(feed, fromTime);

        uint80 rhRound;
        uint256 rhTime;
        if (lhRound == 0) {
            // Date is too far in the past, no data available
            return (0, 0);
        } else if (lhRound == firstRoundOfCurrentPhase) {
            // Data is in the current phase
            (rhRound,, rhTime,,) = feed.latestRoundData();
        } else {
            // No good way to get last round of phase from Chainlink feed, so our binary search function will have to
            // use trial & error.
            // Use 2**16 == 65536 as a upper bound on the number of rounds to search in a single Chainlink phase.

            rhRound = lhRound + 2 ** 16;
            rhTime = 0;
        }

        (uint80 fromRound, uint80 toRound) = binarySearchForTimestamp(feed, fromTime, lhRound, lhTime, rhRound, rhTime);
        return (fromRound, toRound);
    }

    function binarySearchForTimestamp(
        AggregatorV2V3Interface feed,
        uint256 targetTime,
        uint80 lhRound,
        uint256 lhTime,
        uint80 rhRound,
        uint256 rhTime
    )
        public
        view
        returns (uint80 targetRoundL, uint80 targetRoundR)
    {
        if (lhTime > targetTime) return (0, 0);

        uint80 guessRound = rhRound;
        while (rhRound - lhRound > 1) {
            guessRound = uint80(int80(lhRound) + int80(rhRound - lhRound) / 2);
            uint256 guessTime = feed.getTimestamp(uint256(guessRound));
            if (guessTime == 0 || guessTime > targetTime) {
                (rhRound, rhTime) = (guessRound, guessTime);
            } else if (guessTime < targetTime) {
                (lhRound, lhTime) = (guessRound, guessTime);
            }
        }
        console2.log("lhRound: ", lhRound, "rhRound: ", rhRound);
        console2.log("guessRound: ", guessRound);
        return (lhRound, rhRound);
    }

    function getClosestPrice(
        AggregatorV2V3Interface feed,
        uint256 targetTimestamp,
        uint80 roundId1,
        uint80 roundId2
    )
        public
        view
        returns (int256 price)
    {
        (, int256 price1, uint256 timestamp1,,) = feed.getRoundData(roundId1);
        (, int256 price2, uint256 timestamp2,,) = feed.getRoundData(roundId2);
        uint256 diff1 = targetTimestamp > timestamp1 ? targetTimestamp - timestamp1 : timestamp1 - targetTimestamp;
        uint256 diff2 = targetTimestamp > timestamp2 ? targetTimestamp - timestamp2 : timestamp2 - targetTimestamp;

        if (diff1 < diff2) {
            console2.log("Round picked: ", roundId1);
            console2.log("Timestamp: ", timestamp1);
            return price1;
        } else {
            console2.log("Round picked: ", roundId2);
            console2.log("Timestamp: ", timestamp2);
            return price2;
        }
    }

    function fetchPriceDataForFeed(address feedAddress, uint256 targetTimestamp) public view returns (int32) {
        AggregatorV2V3Interface feed = AggregatorV2V3Interface(feedAddress);

        require(targetTimestamp > 0);

        (uint80 roundId1, uint80 roundId2) = guessSearchRoundsForTimestamp(feed, targetTimestamp);
        int256 price = getClosestPrice(feed, targetTimestamp, roundId1, roundId2);

        // return price;
        return int32(price / 10 ** 8);
    }
}
