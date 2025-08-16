# Automation Module

## Overview
The Automation Module provides an abstract base contract for creating provider-specific automation implementations. Following the Breadchain pattern, all distribution logic resides in the CycleManager, while automation contracts simply provide compatible interfaces for different automation providers.

## Architecture

### Abstract Base Design
- **AutomationBase.sol**: Abstract contract that provider implementations inherit from
- **ChainlinkAutomation.sol**: Chainlink Keeper compatible implementation
- **GelatoAutomation.sol**: Gelato Network compatible implementation
- **ICycleManager**: Contains all distribution logic and conditions

### Key Components

1. **AutomationBase**
   - Abstract contract defining core automation functionality
   - Delegates all logic to CycleManager
   - Provider implementations inherit and add their specific interfaces

2. **CycleManager Integration**
   - `resolveDistribution()`: Determines if distribution should occur
   - Contains yield calculations, voting checks, and timing logic
   - Distribution execution logic is handled by provider implementations

3. **Provider Implementations**
   - Minimal contracts that inherit from AutomationBase
   - Add provider-specific method signatures
   - No duplicate logic between providers

## Usage

### Deployment
```solidity
// Deploy CycleManager with distribution logic
ICycleManager cycleManager = new CycleManager(distributionModule);

// Deploy Chainlink automation
ChainlinkAutomation chainlink = new ChainlinkAutomation(address(cycleManager));

// Deploy Gelato automation
GelatoAutomation gelato = new GelatoAutomation(address(cycleManager));
```

### Chainlink Integration
```solidity
// Chainlink Keeper checks if execution is needed
(bool upkeepNeeded, bytes memory performData) = chainlink.checkUpkeep("");

// If needed, Chainlink calls performUpkeep
if (upkeepNeeded) {
    chainlink.performUpkeep(performData);
}
```

### Gelato Integration
```solidity
// Gelato checks if execution is needed
(bool canExec, bytes memory execPayload) = gelato.checker();

// If needed, Gelato calls execute
if (canExec) {
    gelato.execute(execPayload);
}
```

### Creating New Provider Implementations
```solidity
contract NewProviderAutomation is AutomationBase {
    constructor(address _cycleManager) AutomationBase(_cycleManager) {}
    
    // Add provider-specific methods
    function providerSpecificCheck() external view returns (bool, bytes memory) {
        return resolveDistribution();
    }
    
    function providerSpecificExecute() external {
        executeDistribution();
    }
}
```

## CycleManager Responsibilities

The CycleManager contains all distribution logic:
- Cycle timing and block counting
- Voting tallies and thresholds
- Yield availability checks
- Distribution execution
- State management and resets

## Benefits of This Design

1. **Single Source of Truth**: All logic in CycleManager, no duplication
2. **Easy to Add Providers**: Just inherit AutomationBase and add interface methods
3. **Following Breadchain Pattern**: Mirrors the proven architecture
4. **Minimal Gas Overhead**: Thin automation contracts reduce costs
5. **Clean Separation**: Automation interface separate from business logic

## Testing

Run the test suite:
```bash
forge test --match-path test/automation/AutomationBase.t.sol
```

All tests passing (11/11):
- Chainlink automation flow
- Gelato automation flow
- Distribution conditions
- Cycle management
- State transitions

## File Structure

```
src/
├── interfaces/
│   └── ICycleManager.sol       # Enhanced with distribution logic
├── modules/
│   └── automation/
│       ├── AutomationBase.sol      # Abstract base contract
│       ├── ChainlinkAutomation.sol # Chainlink implementation
│       └── GelatoAutomation.sol    # Gelato implementation
└── mocks/
    └── MockCycleManager.sol    # Example CycleManager with all logic

test/
└── automation/
    └── AutomationBase.t.sol    # Comprehensive test suite
```

## Integration Requirements

- **ICycleManager**: Must implement `resolveDistribution()` and `executeDistribution()`
- **IDistributionModule**: Called by CycleManager to handle transfers

## Security Considerations

- All authorization logic should be in CycleManager
- Automation contracts are permissionless (anyone can call)
- CycleManager validates all conditions before execution
- No state in automation contracts, only in CycleManager