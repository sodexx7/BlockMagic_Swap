// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

contract DegenFetcher {
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
        uint256 fromTime,
        uint80 daysToFetch
    )
        public
        view
        returns (uint80 firstRoundToSearch, uint80 numRoundsToSearch)
    {
        uint256 toTime = fromTime + SECONDS_PER_DAY * daysToFetch;

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

        uint80 fromRound = binarySearchForTimestamp(feed, fromTime, lhRound, lhTime, rhRound, rhTime);
        uint80 toRound = binarySearchForTimestamp(feed, toTime, fromRound, fromTime, rhRound, rhTime);
        return (fromRound, toRound - fromRound);
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
        returns (uint80 targetRound)
    {
        if (lhTime > targetTime) return 0;

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
        return guessRound;
    }

    function roundIdsToSearch(
        AggregatorV2V3Interface feed,
        uint256 fromTimestamp,
        uint80 daysToFetch,
        uint256 dataPointsToFetchPerDay
    )
        public
        view
        returns (uint80[] memory)
    {
        (uint80 startingId, uint80 numRoundsToSearch) = guessSearchRoundsForTimestamp(feed, fromTimestamp, daysToFetch);

        uint80 fetchFilter = uint80(numRoundsToSearch / (daysToFetch * dataPointsToFetchPerDay));
        if (fetchFilter < 1) {
            fetchFilter = 1;
        }
        uint80[] memory roundIds = new uint80[](numRoundsToSearch / fetchFilter);

        // Snap startingId to a round that is a multiple of fetchFilter. This prevents the perpetual jam from changing
        // more often than
        // necessary, and keeps it aligned with the daily prints.
        startingId -= startingId % fetchFilter;

        for (uint80 i = 0; i < roundIds.length; i++) {
            roundIds[i] = startingId + i * fetchFilter;
        }
        return roundIds;
    }

    function fetchPriceData(
        AggregatorV2V3Interface feed,
        uint256 fromTimestamp,
        uint80 daysToFetch,
        uint256 dataPointsToFetchPerDay
    )
        public
        view
        returns (int32[] memory)
    {
        uint80[] memory roundIds = roundIdsToSearch(feed, fromTimestamp, daysToFetch, dataPointsToFetchPerDay);
        uint256 dataPointsToReturn;
        if (roundIds.length == 0) {
            dataPointsToReturn = 0;
        } else {
            dataPointsToReturn = dataPointsToFetchPerDay * daysToFetch; // Number of data points to return
        }
        uint256 secondsBetweenDataPoints = SECONDS_PER_DAY / dataPointsToFetchPerDay;

        int32[] memory prices = new int32[](dataPointsToReturn);

        uint80 latestRoundId = uint80(feed.latestRound());
        for (uint80 i = 0; i < roundIds.length; i++) {
            if (roundIds[i] != 0 && roundIds[i] < latestRoundId) {
                (, int256 price, uint256 timestamp,,) = feed.getRoundData(roundIds[i]);

                if (timestamp >= fromTimestamp) {
                    uint256 segmentsSinceStart = (timestamp - fromTimestamp) / secondsBetweenDataPoints;
                    if (segmentsSinceStart < prices.length) {
                        prices[segmentsSinceStart] = int32(price / 10 ** 8);
                    }
                }
            }
        }

        return prices;
    }

    function fetchPriceDataForFeed(
        address feedAddress,
        uint256 fromTimestamp,
        uint80 daysToFetch,
        uint256 dataPointsToFetchPerDay
    )
        public
        view
        returns (int32[] memory)
    {
        AggregatorV2V3Interface feed = AggregatorV2V3Interface(feedAddress);

        require(fromTimestamp > 0);

        int32[] memory prices = fetchPriceData(feed, fromTimestamp, daysToFetch, dataPointsToFetchPerDay);
        return prices;
    }
}
