// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICycleManager} from "../interfaces/ICycleManager.sol";
import {ICycleModule} from "../interfaces/ICycleModule.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

contract CycleManager is ICycleManager, Ownable {
    ICycleModule public cycleModule;
    
    modifier onlyAuthorized() {
        require(msg.sender == owner() || _isAuthorized(msg.sender), "Not authorized");
        _;
    }

    constructor() {
        _initializeOwner(msg.sender);
    }

    function getCurrentCycle() external view override returns (uint256) {
        require(address(cycleModule) != address(0), "Cycle module not set");
        return cycleModule.getCurrentCycle();
    }

    function isDistributionReady(
        uint256 votesCast,
        uint256 availableYield,
        uint256 minimumYield
    ) external view override returns (bool) {
        require(address(cycleModule) != address(0), "Cycle module not set");
        
        if (!cycleModule.isDistributionReady()) {
            return false;
        }
        
        if (votesCast == 0) {
            return false;
        }
        
        if (availableYield < minimumYield) {
            return false;
        }
        
        return true;
    }

    function startNewCycle() external override onlyAuthorized {
        require(address(cycleModule) != address(0), "Cycle module not set");
        require(validateCycleTransition(), "Cycle transition invalid");
        
        cycleModule.startNewCycle();
        
        emit CycleTransitionValidated(cycleModule.getCurrentCycle());
    }

    function getCycleInfo() external view override returns (CycleInfo memory) {
        require(address(cycleModule) != address(0), "Cycle module not set");
        return cycleModule.getCycleInfo();
    }

    function setCycleModule(address _cycleModule) external override onlyOwner {
        require(_cycleModule != address(0), "Invalid cycle module address");
        cycleModule = ICycleModule(_cycleModule);
        emit CycleModuleSet(_cycleModule);
    }

    function validateCycleTransition() public view returns (bool) {
        return cycleModule.isDistributionReady();
    }

    function getCycleProgress() external view returns (uint256) {
        require(address(cycleModule) != address(0), "Cycle module not set");
        return cycleModule.getCycleProgress();
    }

    function getBlocksUntilNextCycle() external view returns (uint256) {
        require(address(cycleModule) != address(0), "Cycle module not set");
        return cycleModule.getBlocksUntilNextCycle();
    }

    function _isAuthorized(address account) internal view virtual returns (bool) {
        return false;
    }

    function setAuthorized(address account, bool authorized) external onlyOwner {
    }
}