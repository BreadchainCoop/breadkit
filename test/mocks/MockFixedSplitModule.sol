// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFixedSplitModule} from "../../src/interfaces/IFixedSplitModule.sol";

contract MockFixedSplitModule is IFixedSplitModule {
    uint256 public fixedSplitDivisor = 4;
    address[] public fixedRecipients;
    
    constructor() {
        fixedRecipients.push(address(0x1));
        fixedRecipients.push(address(0x2));
        fixedRecipients.push(address(0x3));
    }
    
    function calculateFixedDistribution(uint256 totalYield) 
        external 
        view 
        override 
        returns (uint256 fixedAmount, uint256 votedAmount) 
    {
        fixedAmount = totalYield / fixedSplitDivisor;
        votedAmount = totalYield - fixedAmount;
    }
    
    function calculateRequiredTokensForDistribution() external pure override returns (uint256) {
        return 0;
    }
    
    function prepareTokensForDistribution() external override {}
    
    function getFixedSplitDivisor() external view override returns (uint256) {
        return fixedSplitDivisor;
    }
    
    function setFixedSplitDivisor(uint256 divisor) external override {
        fixedSplitDivisor = divisor;
    }
    
    function getFixedSplitRecipients() external view override returns (address[] memory) {
        return fixedRecipients;
    }
    
    function setFixedRecipients(address[] memory recipients) external {
        fixedRecipients = recipients;
    }
}