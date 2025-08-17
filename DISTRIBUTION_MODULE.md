# Distribution Module Implementation

## Overview

The Distribution Module is the central orchestrating component that handles yield distribution and collection. It consolidates all distribution and yield collection logic in a single abstract contract that can be extended and integrated with voting and recipient management modules.

## Architecture

### Core Components

1. **IDistributionModule** (`src/interfaces/IDistributionModule.sol`)
   - Interface defining distribution operations
   - State management and emergency functions
   - Event definitions for transparency

2. **DistributionManager** (`src/modules/DistributionManager.sol`)
   - Abstract contract with ALL distribution and yield collection logic
   - Calculation and execution algorithms
   - Built-in yield collection from single source
   - Token minting coordination
   - Virtual hooks for voting and recipient management
   - Emergency mechanisms

## Key Features

### Distribution Process
1. **Validation** - Cycle completion, yield availability, votes
2. **Token Minting** - Built-in minting before collection  
3. **Yield Collection** - Built-in collection from single source
4. **Split Calculation** - Fixed and voted portions
5. **Distribution Execution** - Transfer to recipients
6. **Cycle Transition** - State updates for next cycle

### Abstract Hooks
The DistributionManager provides hooks that implementations must override:
- `_mintTokensBeforeDistribution()` - Optional: Custom token minting logic (has default implementation)
- `_getVotingResults()` - Voting data retrieval
- `_getActiveRecipients()` - Recipient list retrieval
- `_processQueuedChanges()` - Queue processing logic

### Built-in Functionality
The DistributionManager includes concrete implementations for:
- Yield collection from single source
- Token minting before distribution
- Available yield calculation
- Yield source validation

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
        address _yieldSource,
        uint256 _cycleLength,
        uint256 _yieldFixedSplitDivisor
    ) external {
        __DistributionManager_init(_yieldToken, _yieldSource, _cycleLength, _yieldFixedSplitDivisor);
    }

    // Implement required hooks
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

    // Optional: Override for custom token minting
    function _mintTokensBeforeDistribution() internal override {
        // Custom minting logic if needed
        // Default implementation handles most cases
        super._mintTokensBeforeDistribution();
    }
}
```

### Managing Yield Source

```solidity
// Yield source is set during initialization
MyDistribution distribution = new MyDistribution();
distribution.initialize(yieldToken, yieldSource, cycleLength, divisor);

// Change yield source if needed
distribution.setYieldSource(newYieldSource);

// Check yield source validity
bool isValid = distribution.validateYieldSource();

// Get current yield source
address currentSource = distribution.getYieldSource();
```

## Testing

Test suite in `test/DistributionModule.t.sol` covers:
- Distribution execution with integrated yield collection
- Fixed/voted split calculations
- Emergency mechanisms
- Multi-cycle operations
- Yield source validation
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