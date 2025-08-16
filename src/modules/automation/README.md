# Automation Module

## Overview
The Automation Module provides a simple, unified interface for automation providers (Chainlink, Gelato, etc.) to trigger protocol operations. It eliminates the need for on-chain provider management while ensuring secure and controlled execution.

## Architecture

### Single Contract Design
The `AutomationModule.sol` contract provides:
- Compatible endpoints for multiple automation providers
- Authorization control for callers
- Timing controls to prevent excessive executions
- Emergency manual execution capability

### Key Features

1. **Provider Compatibility**
   - Chainlink: `checkUpkeep()` and `performUpkeep()`
   - Gelato: `checker()` and `execute()`
   - Generic: `executeAutomation()`

2. **Security Controls**
   - Authorized caller whitelist
   - Minimum blocks between executions
   - Owner-only emergency execution
   - Enable/disable automation

3. **Integration**
   - Works with `ICycleManager` for timing
   - Triggers `IDistributionModule` for yield distribution
   - No on-chain provider coordination needed

## Usage

### Deployment
```solidity
// Deploy AutomationModule
AutomationModule automation = new AutomationModule();
automation.initialize(owner);

// Configure modules
automation.setCycleManager(cycleManager);
automation.setDistributionModule(distributionModule);

// Authorize automation providers
automation.setCallerAuthorization(chainlinkKeeper, true);
automation.setCallerAuthorization(gelatoExecutor, true);
```

### Chainlink Integration
```solidity
// Chainlink Keeper checks if execution is needed
(bool upkeepNeeded, bytes memory performData) = automation.checkUpkeep("");

// If needed, Chainlink calls performUpkeep
if (upkeepNeeded) {
    automation.performUpkeep(performData);
}
```

### Gelato Integration
```solidity
// Gelato checks if execution is needed
(bool canExec, bytes memory execPayload) = automation.checker();

// If needed, Gelato calls execute
if (canExec) {
    automation.execute(execPayload);
}
```

### Configuration
```solidity
// Set minimum blocks between executions
automation.setMinBlocksBetweenExecutions(100);

// Enable/disable automation
automation.setAutomationEnabled(false);

// Manage authorized callers
automation.setCallerAuthorization(address, true);
```

### Emergency Controls
```solidity
// Owner can always execute manually
automation.emergencyExecute();
```

## Benefits of Simplified Design

1. **No On-chain Coordination**: Providers operate independently without needing to coordinate
2. **Lower Gas Costs**: No provider registration or management overhead
3. **Simpler Code**: Easier to audit and maintain
4. **Flexible**: Any automation provider can integrate by calling the appropriate endpoint
5. **Secure**: Authorization controls prevent unauthorized execution

## Testing

Run the test suite:
```bash
forge test --match-path test/automation/AutomationModule.t.sol
```

## Security Considerations

- Only authorized addresses can trigger automation
- Minimum block intervals prevent excessive executions
- Owner retains emergency control
- Automation can be disabled if needed

## Integration Requirements

The module requires:
- `ICycleManager`: To determine when distributions are ready
- `IDistributionModule`: To execute the actual distribution

## Gas Optimization

- Simple authorization check (mapping lookup)
- Minimal state updates per execution
- No complex provider management logic
- Early revert conditions to save gas