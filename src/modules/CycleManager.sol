// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/ICycleManager.sol";
import "../interfaces/ICycleModule.sol";

/// @title CycleManager
/// @notice Main contract that orchestrates cycle timing and transitions
/// @dev Manages distribution cycles and ensures predictable, deterministic execution
contract CycleManager is ICycleManager {
    /// @notice The cycle module implementation
    ICycleModule public cycleModule;

    /// @notice Addresses authorized to trigger cycle transitions
    mapping(address => bool) public authorized;

    /// @notice Historical record of cycle transitions
    mapping(uint256 => CycleInfo) public cycleHistory;

    /// @notice Error thrown when caller is not authorized
    error NotAuthorized();

    /// @notice Error thrown when cycle module is not set
    error CycleModuleNotSet();

    /// @notice Error thrown when cycle transition is invalid
    error InvalidCycleTransition();
    /// @notice Emitted when an address authorization status changes
    /// @param account The address whose authorization was updated
    /// @param isAuthorized The new authorization status
    event AuthorizationUpdated(address indexed account, bool isAuthorized);

    /// @notice Initializes the contract and authorizes the deployer
    constructor() {
        authorized[msg.sender] = true;
        emit AuthorizationUpdated(msg.sender, true);
    }


    /// @notice Modifier to restrict access to authorized addresses
    modifier onlyAuthorized() {
        if (!authorized[msg.sender]) {
            revert NotAuthorized();
        }
        _;
    }

    /// @notice Modifier to ensure cycle module is set
    modifier cycleModuleSet() {
        if (address(cycleModule) == address(0)) {
            revert CycleModuleNotSet();
        }
        _;
    }

    /// @notice Adds or removes an authorized address
    /// @param account The address to update
    /// @param isAuthorized The authorization status to set
    function setAuthorization(address account, bool isAuthorized) external onlyAuthorized {
        authorized[account] = isAuthorized;
        emit AuthorizationUpdated(account, isAuthorized);
    }

    /// @inheritdoc ICycleManager
    function getCurrentCycle() external view cycleModuleSet returns (uint256) {
        return cycleModule.getCurrentCycle();
    }

    /// @inheritdoc ICycleManager
    function isDistributionReady(uint256 votesCast, uint256 availableYield, uint256 minimumYield)
        external
        view
        cycleModuleSet
        returns (bool)
    {
        // Check cycle timing via cycle module
        if (!cycleModule.isDistributionReady()) {
            return false;
        }

        // Check voting activity
        if (votesCast == 0) {
            return false;
        }

        // Check sufficient yield
        if (availableYield < minimumYield) {
            return false;
        }

        return true;
    }

    /// @inheritdoc ICycleManager
    function startNewCycle() external onlyAuthorized cycleModuleSet {
        if (!validateCycleTransition()) {
            revert InvalidCycleTransition();
        }

        // Store cycle history before transition
        uint256 currentCycleNumber = cycleModule.getCurrentCycle();
        cycleHistory[currentCycleNumber] = cycleModule.getCycleInfo();

        // Delegate cycle management to the cycle module
        cycleModule.startNewCycle();

        // Get new cycle info
        CycleInfo memory newCycleInfo = cycleModule.getCycleInfo();

        emit CycleStarted(newCycleInfo.cycleNumber, newCycleInfo.startBlock, newCycleInfo.endBlock);
        emit CycleTransitionValidated(newCycleInfo.cycleNumber);
    }

    /// @inheritdoc ICycleManager
    function getCycleInfo() external view cycleModuleSet returns (CycleInfo memory) {
        return cycleModule.getCycleInfo();
    }

    /// @inheritdoc ICycleManager
    function setCycleModule(address _cycleModule) external onlyAuthorized {
        require(_cycleModule != address(0), "Invalid cycle module address");

        address oldModule = address(cycleModule);
        cycleModule = ICycleModule(_cycleModule);

        emit CycleModuleUpdated(oldModule, _cycleModule);
    }

    /// @inheritdoc ICycleManager
    function validateCycleTransition() public view cycleModuleSet returns (bool) {
        // Basic validation that the cycle module is ready for transition
        return cycleModule.isDistributionReady();
    }
}
