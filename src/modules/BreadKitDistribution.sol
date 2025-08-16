// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DistributionManager} from "./DistributionManager.sol";
import {IVotingModule} from "../interfaces/IVotingModule.sol";
import {IFixedSplitModule} from "../interfaces/IFixedSplitModule.sol";
import {IRecipientRegistry} from "../interfaces/IRecipientRegistry.sol";
import {IYieldModule} from "../interfaces/IYieldModule.sol";
import {YieldCollector} from "./YieldCollector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BreadKitDistribution
/// @notice Concrete implementation of the DistributionManager for BreadKit
/// @dev Integrates with all BreadKit modules to orchestrate distributions
contract BreadKitDistribution is DistributionManager {
    
    event VotingStateReset(uint256 cycleNumber);
    event RecipientChangesProcessed(uint256 addedCount, uint256 removedCount);
    
    /// @notice Initializes the BreadKit distribution system
    /// @param _yieldToken Address of the yield token
    /// @param _cycleLength Initial cycle length in blocks
    /// @param _yieldFixedSplitDivisor Initial fixed split divisor
    function initialize(
        address _yieldToken,
        uint256 _cycleLength,
        uint256 _yieldFixedSplitDivisor
    ) external {
        __DistributionManager_init(_yieldToken, _cycleLength, _yieldFixedSplitDivisor);
    }

    /// @inheritdoc DistributionManager
    function _mintTokensBeforeDistribution() internal override {
        if (yieldCollector != address(0)) {
            YieldCollector(yieldCollector).mintTokensBeforeCollection();
        } else if (fixedSplitModule != address(0)) {
            uint256 requiredTokens = IFixedSplitModule(fixedSplitModule).calculateRequiredTokensForDistribution();
            if (requiredTokens > 0) {
                IYieldModule(yieldToken).mint(requiredTokens, address(this));
                emit TokensMintedForDistribution(requiredTokens);
            }
            IFixedSplitModule(fixedSplitModule).prepareTokensForDistribution();
        }
    }

    /// @inheritdoc DistributionManager
    function _collectYield() internal override returns (uint256) {
        if (yieldCollector != address(0)) {
            return YieldCollector(yieldCollector).collectYield();
        } else {
            uint256 yieldAccrued = IYieldModule(yieldToken).yieldAccrued();
            if (yieldAccrued > 0) {
                IYieldModule(yieldToken).claimYield(yieldAccrued, address(this));
            }
            return IERC20(yieldToken).balanceOf(address(this));
        }
    }

    /// @inheritdoc DistributionManager
    function _getAvailableYield() internal view override returns (uint256) {
        if (yieldCollector != address(0)) {
            return YieldCollector(yieldCollector).getAvailableYield();
        } else {
            uint256 balance = IERC20(yieldToken).balanceOf(address(this));
            uint256 yieldAccrued = IYieldModule(yieldToken).yieldAccrued();
            return balance + yieldAccrued;
        }
    }

    /// @inheritdoc DistributionManager
    function _getVotingResults() internal view override returns (uint256[] memory votes, uint256 totalVotes) {
        if (votingModule == address(0)) {
            return (new uint256[](0), 0);
        }
        
        votes = IVotingModule(votingModule).getCurrentVotingDistribution();
        
        for (uint256 i = 0; i < votes.length; i++) {
            totalVotes += votes[i];
        }
        
        return (votes, totalVotes);
    }

    /// @inheritdoc DistributionManager
    function _getActiveRecipients() internal view override returns (address[] memory) {
        if (recipientRegistry != address(0)) {
            return IRecipientRegistry(recipientRegistry).getActiveRecipients();
        } else if (fixedSplitModule != address(0)) {
            return IFixedSplitModule(fixedSplitModule).getFixedSplitRecipients();
        } else {
            return recipients;
        }
    }

    /// @inheritdoc DistributionManager
    function _resetVotingState() internal override {
        emit VotingStateReset(cycleNumber);
    }

    /// @inheritdoc DistributionManager
    function _processQueuedRecipientChanges() internal override {
        if (recipientRegistry != address(0)) {
            address[] memory beforeAdditions = IRecipientRegistry(recipientRegistry).getQueuedAdditions();
            address[] memory beforeRemovals = IRecipientRegistry(recipientRegistry).getQueuedRemovals();
            
            IRecipientRegistry(recipientRegistry).processQueuedChanges();
            
            emit RecipientChangesProcessed(beforeAdditions.length, beforeRemovals.length);
        }
    }

    /// @notice Adds a new recipient immediately (emergency function)
    /// @param recipient Address to add
    function emergencyAddRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        
        if (recipientRegistry != address(0)) {
            IRecipientRegistry(recipientRegistry).emergencyAddRecipient(recipient);
        } else {
            bool exists = false;
            for (uint256 i = 0; i < recipients.length; i++) {
                if (recipients[i] == recipient) {
                    exists = true;
                    break;
                }
            }
            
            if (!exists) {
                recipients.push(recipient);
                recipientVotedDistributions.push(0);
                recipientFixedDistributions.push(0);
            }
        }
    }

    /// @notice Removes a recipient immediately (emergency function)
    /// @param recipient Address to remove
    function emergencyRemoveRecipient(address recipient) external onlyOwner {
        if (recipientRegistry != address(0)) {
            IRecipientRegistry(recipientRegistry).emergencyRemoveRecipient(recipient);
        } else {
            for (uint256 i = 0; i < recipients.length; i++) {
                if (recipients[i] == recipient) {
                    recipients[i] = recipients[recipients.length - 1];
                    recipients.pop();
                    
                    recipientVotedDistributions[i] = recipientVotedDistributions[recipientVotedDistributions.length - 1];
                    recipientVotedDistributions.pop();
                    
                    recipientFixedDistributions[i] = recipientFixedDistributions[recipientFixedDistributions.length - 1];
                    recipientFixedDistributions.pop();
                    
                    break;
                }
            }
        }
    }

    /// @notice Gets distribution history for a specific cycle
    /// @param _cycleNumber The cycle number to query
    /// @return The distribution state for that cycle
    function getDistributionHistory(uint256 _cycleNumber) external view returns (DistributionState memory) {
        return distributionHistory[_cycleNumber];
    }

    /// @notice Checks if the system is ready for distribution
    /// @return ready Whether the system is ready
    /// @return details Detailed status information
    function getReadinessStatus() external view returns (bool ready, string memory details) {
        (bool canDistribute, string memory reason) = validateDistribution();
        
        if (!canDistribute) {
            return (false, reason);
        }
        
        uint256 availableYield = _getAvailableYield();
        address[] memory activeRecipients = _getActiveRecipients();
        (, uint256 totalVotes) = _getVotingResults();
        
        if (availableYield == 0) {
            return (false, "No yield available");
        }
        
        if (activeRecipients.length == 0) {
            return (false, "No active recipients");
        }
        
        if (totalVotes == 0) {
            return (false, "No votes cast");
        }
        
        return (true, "Ready for distribution");
    }

    /// @notice Forces a distribution (owner only, emergency use)
    /// @dev Bypasses some validation checks - use with caution
    function forceDistribution() external onlyOwner {
        lastDistributionBlock = 0;
        this.distributeYield();
    }
}