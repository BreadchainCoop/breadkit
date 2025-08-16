// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IYieldModule} from "../interfaces/IYieldModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title YieldCollector
/// @notice Utility contract for collecting yield from various sources
/// @dev Handles token minting, multi-source yield aggregation, and validation
contract YieldCollector is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidSource();
    error YieldCollectionFailed();
    error UnauthorizedCaller();
    error InsufficientYield();
    error SourceAlreadyRegistered();
    error SourceNotRegistered();
    error NoSources();

    struct YieldSource {
        address sourceAddress;
        bool isActive;
        uint256 lastCollectedBlock;
        uint256 totalCollected;
        string sourceName;
    }

    event YieldCollected(address indexed source, uint256 amount, uint256 blockNumber);
    event YieldSourceAdded(address indexed source, string name);
    event YieldSourceRemoved(address indexed source);
    event YieldSourceToggled(address indexed source, bool isActive);
    event TokensMinted(address indexed token, uint256 amount);
    event YieldValidated(uint256 totalYield, uint256 sourceCount);

    address public distributionManager;
    address public yieldToken;
    
    mapping(address => YieldSource) public yieldSources;
    address[] public sourceAddresses;
    
    uint256 public totalYieldCollected;
    uint256 public lastCollectionBlock;

    modifier onlyDistributionManager() {
        if (msg.sender != distributionManager) revert UnauthorizedCaller();
        _;
    }

    constructor(address _yieldToken) {
        if (_yieldToken == address(0)) revert ZeroAddress();
        yieldToken = _yieldToken;
        _initializeOwner(msg.sender);
    }

    /// @notice Sets the distribution manager address
    /// @param _distributionManager Address of the distribution manager
    function setDistributionManager(address _distributionManager) external onlyOwner {
        if (_distributionManager == address(0)) revert ZeroAddress();
        distributionManager = _distributionManager;
    }

    /// @notice Adds a new yield source
    /// @param source Address of the yield source
    /// @param name Name identifier for the source
    function addYieldSource(address source, string memory name) external onlyOwner {
        if (source == address(0)) revert ZeroAddress();
        if (yieldSources[source].sourceAddress != address(0)) revert SourceAlreadyRegistered();
        
        yieldSources[source] = YieldSource({
            sourceAddress: source,
            isActive: true,
            lastCollectedBlock: block.number,
            totalCollected: 0,
            sourceName: name
        });
        
        sourceAddresses.push(source);
        emit YieldSourceAdded(source, name);
    }

    /// @notice Removes a yield source
    /// @param source Address of the yield source to remove
    function removeYieldSource(address source) external onlyOwner {
        if (yieldSources[source].sourceAddress == address(0)) revert SourceNotRegistered();
        
        delete yieldSources[source];
        
        for (uint256 i = 0; i < sourceAddresses.length; i++) {
            if (sourceAddresses[i] == source) {
                sourceAddresses[i] = sourceAddresses[sourceAddresses.length - 1];
                sourceAddresses.pop();
                break;
            }
        }
        
        emit YieldSourceRemoved(source);
    }

    /// @notice Toggles a yield source active status
    /// @param source Address of the yield source
    /// @param isActive New active status
    function toggleYieldSource(address source, bool isActive) external onlyOwner {
        if (yieldSources[source].sourceAddress == address(0)) revert SourceNotRegistered();
        
        yieldSources[source].isActive = isActive;
        emit YieldSourceToggled(source, isActive);
    }

    /// @notice Mints tokens before collecting yield
    /// @return Amount of tokens minted
    function mintTokensBeforeCollection() external onlyDistributionManager returns (uint256) {
        uint256 requiredTokens = calculateRequiredTokensForDistribution();
        
        if (requiredTokens > 0) {
            IYieldModule(yieldToken).mint(requiredTokens, address(this));
            emit TokensMinted(yieldToken, requiredTokens);
        }
        
        return requiredTokens;
    }

    /// @notice Collects yield from all active sources
    /// @return totalYield Total yield collected from all sources
    function collectYield() external onlyDistributionManager nonReentrant returns (uint256 totalYield) {
        if (sourceAddresses.length == 0) revert NoSources();
        
        uint256[] memory amounts = new uint256[](sourceAddresses.length);
        uint256 activeSourceCount = 0;
        
        for (uint256 i = 0; i < sourceAddresses.length; i++) {
            address source = sourceAddresses[i];
            YieldSource storage yieldSource = yieldSources[source];
            
            if (!yieldSource.isActive) continue;
            
            uint256 collected = _collectFromSource(source);
            if (collected > 0) {
                amounts[i] = collected;
                totalYield += collected;
                yieldSource.lastCollectedBlock = block.number;
                yieldSource.totalCollected += collected;
                activeSourceCount++;
                
                emit YieldCollected(source, collected, block.number);
            }
        }
        
        if (totalYield == 0) revert InsufficientYield();
        
        totalYieldCollected += totalYield;
        lastCollectionBlock = block.number;
        
        emit YieldValidated(totalYield, activeSourceCount);
        
        return totalYield;
    }

    /// @notice Gets the total available yield from all sources
    /// @return availableYield Total available yield
    function getAvailableYield() external view returns (uint256 availableYield) {
        for (uint256 i = 0; i < sourceAddresses.length; i++) {
            address source = sourceAddresses[i];
            if (yieldSources[source].isActive) {
                availableYield += _getSourceYield(source);
            }
        }
        return availableYield;
    }

    /// @notice Validates all yield sources
    /// @return isValid Whether all sources are valid
    /// @return invalidSources Array of invalid source addresses
    function validateYieldSources() external view returns (bool isValid, address[] memory invalidSources) {
        uint256 invalidCount = 0;
        address[] memory tempInvalid = new address[](sourceAddresses.length);
        
        for (uint256 i = 0; i < sourceAddresses.length; i++) {
            address source = sourceAddresses[i];
            if (yieldSources[source].isActive && !_isSourceValid(source)) {
                tempInvalid[invalidCount] = source;
                invalidCount++;
            }
        }
        
        if (invalidCount == 0) {
            return (true, new address[](0));
        }
        
        invalidSources = new address[](invalidCount);
        for (uint256 i = 0; i < invalidCount; i++) {
            invalidSources[i] = tempInvalid[i];
        }
        
        return (false, invalidSources);
    }

    /// @notice Claims yield from specific sources
    /// @param sources Array of source addresses to claim from
    /// @return totalClaimed Total amount claimed
    function claimFromSources(address[] memory sources) external onlyDistributionManager returns (uint256 totalClaimed) {
        for (uint256 i = 0; i < sources.length; i++) {
            address source = sources[i];
            if (yieldSources[source].sourceAddress == address(0)) revert SourceNotRegistered();
            if (!yieldSources[source].isActive) continue;
            
            uint256 claimed = _collectFromSource(source);
            if (claimed > 0) {
                totalClaimed += claimed;
                yieldSources[source].lastCollectedBlock = block.number;
                yieldSources[source].totalCollected += claimed;
                
                emit YieldCollected(source, claimed, block.number);
            }
        }
        
        return totalClaimed;
    }

    /// @notice Calculates required tokens for distribution
    /// @return Required token amount
    function calculateRequiredTokensForDistribution() public view returns (uint256) {
        uint256 currentBalance = IERC20(yieldToken).balanceOf(distributionManager);
        uint256 availableYield = this.getAvailableYield();
        
        if (availableYield > currentBalance) {
            return availableYield - currentBalance;
        }
        
        return 0;
    }

    /// @notice Gets information about a specific yield source
    /// @param source Address of the yield source
    /// @return sourceInfo The yield source information
    function getYieldSourceInfo(address source) external view returns (YieldSource memory sourceInfo) {
        return yieldSources[source];
    }

    /// @notice Gets all active yield sources
    /// @return Array of active source addresses
    function getActiveSources() external view returns (address[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < sourceAddresses.length; i++) {
            if (yieldSources[sourceAddresses[i]].isActive) {
                activeCount++;
            }
        }
        
        address[] memory activeSources = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < sourceAddresses.length; i++) {
            if (yieldSources[sourceAddresses[i]].isActive) {
                activeSources[index] = sourceAddresses[i];
                index++;
            }
        }
        
        return activeSources;
    }

    /// @notice Internal function to collect yield from a specific source
    /// @param source Address of the yield source
    /// @return Amount collected
    function _collectFromSource(address source) internal returns (uint256) {
        try IYieldModule(source).yieldAccrued() returns (uint256 accrued) {
            if (accrued > 0) {
                try IYieldModule(source).claimYield(accrued, distributionManager) {
                    return accrued;
                } catch {
                    return 0;
                }
            }
            return 0;
        } catch {
            uint256 balance = IERC20(source).balanceOf(address(this));
            if (balance > 0) {
                IERC20(source).safeTransfer(distributionManager, balance);
                return balance;
            }
            return 0;
        }
    }

    /// @notice Internal function to get available yield from a source
    /// @param source Address of the yield source
    /// @return Available yield amount
    function _getSourceYield(address source) internal view returns (uint256) {
        try IYieldModule(source).yieldAccrued() returns (uint256 accrued) {
            return accrued;
        } catch {
            return IERC20(source).balanceOf(address(this));
        }
    }

    /// @notice Internal function to validate a yield source
    /// @param source Address of the yield source
    /// @return Whether the source is valid
    function _isSourceValid(address source) internal view returns (bool) {
        if (source.code.length == 0) return false;
        
        try IYieldModule(source).yieldAccrued() returns (uint256) {
            return true;
        } catch {
            try IERC20(source).totalSupply() returns (uint256) {
                return true;
            } catch {
                return false;
            }
        }
    }

    /// @notice Emergency withdrawal function
    /// @param token Token to withdraw
    /// @param to Recipient address
    /// @param amount Amount to withdraw
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
    }
}