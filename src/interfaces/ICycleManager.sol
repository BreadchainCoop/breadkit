// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICycleManager {
    struct CycleInfo {
        uint256 cycleNumber;
        uint256 startBlock;
        uint256 endBlock;
        uint256 blocksRemaining;
        bool isActive;
    }

    event CycleStarted(uint256 indexed cycleNumber, uint256 startBlock, uint256 endBlock);
    event CycleTransitionValidated(uint256 indexed cycleNumber);
    event CycleModuleSet(address indexed cycleModule);

    function getCurrentCycle() external view returns (uint256);

    function isDistributionReady(
        uint256 votesCast,
        uint256 availableYield,
        uint256 minimumYield
    ) external view returns (bool);

    function startNewCycle() external;

    function getCycleInfo() external view returns (CycleInfo memory);

    function setCycleModule(address cycleModule) external;
}