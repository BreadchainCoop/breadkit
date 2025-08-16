// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICycleManager} from "./ICycleManager.sol";

interface ICycleModule {
    event CycleLengthUpdated(uint256 newLength);
    event CycleInitialized(uint256 cycleLength, uint256 startBlock);

    function getCurrentCycle() external view returns (uint256);

    function isDistributionReady() external view returns (bool);

    function startNewCycle() external;

    function getCycleInfo() external view returns (ICycleManager.CycleInfo memory);

    function getBlocksUntilNextCycle() external view returns (uint256);

    function getCycleProgress() external view returns (uint256);

    function initialize(uint256 cycleLength, uint256 startBlock) external;

    function updateCycleLength(uint256 newCycleLength) external;
}