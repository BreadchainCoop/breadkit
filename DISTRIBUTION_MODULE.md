# Distribution Module Implementation

## Overview

The Distribution Module is the central orchestrating component that handles yield distribution. It consolidates all distribution logic in an abstract contract that can be extended and integrated with other modules.

## Architecture

### Core Components

1. **IDistributionModule** (`src/interfaces/IDistributionModule.sol`)
   - Interface defining distribution operations
   - State management and emergency functions
   - Event definitions for transparency

2. **DistributionManager** (`src/modules/DistributionManager.sol`)
   - Abstract contract with ALL distribution logic consolidated
   - Calculation and execution algorithms
   - Virtual hooks for module integration
   - Emergency mechanisms

3. **YieldCollector** (`src/modules/YieldCollector.sol`)
   - Multi-source yield collection utility
   - Token minting coordination
   - Source validation and monitoring

## Key Features

### Distribution Process
1. **Validation** - Cycle completion, yield availability, votes
2. **Token Minting** - Hook for minting before collection  
3. **Yield Collection** - Hook for collecting from sources
4. **Split Calculation** - Fixed and voted portions
5. **Distribution Execution** - Transfer to recipients
6. **Cycle Transition** - State updates for next cycle

### Abstract Hooks
The DistributionManager provides hooks that implementations must override:
- `_mintTokensBeforeDistribution()` - Token minting logic
- `_collectYield()` - Yield collection logic
- `_getAvailableYield()` - Available yield calculation
- `_getVotingResults()` - Voting data retrieval
- `_getActiveRecipients()` - Recipient list retrieval
- `_processQueuedChanges()` - Queue processing logic

### Security Features
- Reentrancy protection
- Emergency pause/resume
- Emergency withdrawal
- Input validation
- Separate emergency admin role

## Integration Guide

### Extending DistributionManager

```solidity
contract MyDistribution is DistributionManager {
    
    function initialize(
        address _yieldToken,
        uint256 _cycleLength,
        uint256 _yieldFixedSplitDivisor
    ) external {
        __DistributionManager_init(_yieldToken, _cycleLength, _yieldFixedSplitDivisor);
    }

    // Implement required hooks
    function _mintTokensBeforeDistribution() internal override {
        // Your minting logic
    }

    function _collectYield() internal override returns (uint256) {
        // Your yield collection logic
        return collectedAmount;
    }

    function _getAvailableYield() internal view override returns (uint256) {
        // Your available yield logic
        return availableAmount;
    }

    function _getVotingResults() internal view override returns (uint256[] memory) {
        // Your voting integration
        return votes;
    }

    function _getActiveRecipients() internal view override returns (address[] memory) {
        // Your recipient logic
        return recipients;
    }

    function _processQueuedChanges() internal override {
        // Your queue processing logic
    }
}
```

### Using YieldCollector

```solidity
YieldCollector collector = new YieldCollector(yieldTokenAddress);
collector.setDistributionManager(distributionAddress);

// Add yield sources
collector.addYieldSource(source1, "Source 1");
collector.addYieldSource(source2, "Source 2");

// Collect yield (called by distribution manager)
uint256 collected = collector.collectYield();
```

## Testing

Test suite in `test/DistributionModule.t.sol` covers:
- Distribution execution
- Fixed/voted split calculations
- Emergency mechanisms
- Multi-cycle operations
- Edge cases

Run tests:
```bash
forge test --match-contract DistributionModuleTest
```

## Events

- `YieldDistributed` - Successful distribution
- `TokensMintedForDistribution` - Token minting
- `EmergencyPause` - System paused
- `EmergencyWithdraw` - Emergency withdrawal
- `CycleCompleted` - Cycle completed
- `DistributionValidated` - Distribution validated

## Errors

- `ZeroAddress` - Invalid zero address
- `InvalidCycleLength` - Invalid cycle length
- `InvalidDivisor` - Invalid divisor
- `DistributionNotResolved` - Conditions not met
- `InsufficientYield` - Not enough yield
- `NoRecipients` - No recipients found
- `CycleNotComplete` - Cycle not elapsed
- `OnlyEmergencyAdmin` - Unauthorized

## Gas Estimates

- Distribution: ~150k-300k gas (depends on recipients)
- Yield collection: ~50k-100k per source
- Emergency pause: ~30k gas
- Parameter updates: ~25k gas each