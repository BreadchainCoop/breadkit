// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionModule} from "../interfaces/IDistributionModule.sol";
import {IYieldModule} from "../interfaces/IYieldModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title DistributionManager
/// @notice Abstract contract that orchestrates the entire distribution process
/// @dev Consolidates all distribution logic and provides hooks for module integration
abstract contract DistributionManager is IDistributionModule, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidCycleLength();
    error InvalidDivisor();
    error DistributionNotResolved();
    error InsufficientYield();
    error NoRecipients();
    error CycleNotComplete();
    error OnlyEmergencyAdmin();
    error NoYieldSource();

    uint256 private constant PRECISION = 1e18;

    address public emergencyAdmin;
    address public yieldToken;
    address public yieldSource;

    uint256 public cycleLength;
    uint256 public yieldFixedSplitDivisor;
    uint256 public lastDistributionBlock;
    uint256 public cycleNumber;
    uint256 public totalYieldCollected;
    uint256 public lastCollectionBlock;

    address[] public recipients;
    uint256[] public currentVotes;
    uint256 public totalVotes;

    mapping(uint256 => DistributionState) public distributionHistory;

    event YieldCollected(address indexed source, uint256 amount, uint256 blockNumber);
    event YieldValidated(uint256 totalYield);

    modifier onlyEmergencyAdmin() {
        if (msg.sender != emergencyAdmin && msg.sender != owner()) {
            revert OnlyEmergencyAdmin();
        }
        _;
    }

    /// @notice Initializes the distribution manager
    /// @param _yieldToken Address of the yield token
    /// @param _yieldSource Address of the yield source
    /// @param _cycleLength Initial cycle length in blocks
    /// @param _yieldFixedSplitDivisor Initial fixed split divisor
    function __DistributionManager_init(
        address _yieldToken,
        address _yieldSource,
        uint256 _cycleLength,
        uint256 _yieldFixedSplitDivisor
    ) internal {
        if (_yieldToken == address(0)) revert ZeroAddress();
        if (_yieldSource == address(0)) revert ZeroAddress();
        if (_cycleLength == 0) revert InvalidCycleLength();
        if (_yieldFixedSplitDivisor == 0) revert InvalidDivisor();

        yieldToken = _yieldToken;
        yieldSource = _yieldSource;
        cycleLength = _cycleLength;
        yieldFixedSplitDivisor = _yieldFixedSplitDivisor;
        lastDistributionBlock = block.number;

        _initializeOwner(msg.sender);
    }

    /// @inheritdoc IDistributionModule
    function distributeYield() external override nonReentrant whenNotPaused {
        (bool canDistribute,) = validateDistribution();
        if (!canDistribute) revert DistributionNotResolved();

        // Hook for token minting before distribution
        _mintTokensBeforeDistribution();

        // Collect yield
        uint256 totalYield = _collectYield();
        if (totalYield == 0) revert InsufficientYield();

        // Calculate splits
        (uint256 fixedAmount, uint256 votedAmount) = _calculateSplits(totalYield);

        // Get distribution data
        address[] memory activeRecipients = _getActiveRecipients();
        if (activeRecipients.length == 0) revert NoRecipients();

        uint256[] memory votes = _getVotingResults();

        // Calculate distributions
        uint256[] memory votedDistributions = _calculateVotedDistributions(votes, totalVotes, votedAmount);
        uint256[] memory fixedDistributions = _calculateFixedDistributions(activeRecipients, fixedAmount);

        // Execute distributions
        _executeDistributions(activeRecipients, votedDistributions, fixedDistributions);

        // Complete cycle
        _completeCycleTransition();

        // Record distribution
        _recordDistribution(totalYield, totalVotes, activeRecipients, votedDistributions, fixedDistributions);

        emit YieldDistributed(totalYield, totalVotes, activeRecipients, votedDistributions, fixedDistributions);
    }

    /// @inheritdoc IDistributionModule
    function getCurrentDistributionState() external view override returns (DistributionState memory state) {
        state.totalYield = _getAvailableYield();
        (state.fixedAmount, state.votedAmount) = _calculateSplits(state.totalYield);
        state.totalVotes = totalVotes;
        state.lastDistributionBlock = lastDistributionBlock;
        state.cycleNumber = cycleNumber;
        state.recipients = recipients;
        state.votedDistributions = new uint256[](recipients.length);
        state.fixedDistributions = new uint256[](recipients.length);
    }

    /// @inheritdoc IDistributionModule
    function validateDistribution() public view override returns (bool canDistribute, string memory reason) {
        if (paused()) {
            return (false, "System is paused");
        }

        if (block.number < lastDistributionBlock + cycleLength) {
            return (false, "Cycle not complete");
        }

        uint256 availableYield = _getAvailableYield();
        if (availableYield == 0) {
            return (false, "No yield available");
        }

        address[] memory activeRecipients = _getActiveRecipients();
        if (activeRecipients.length == 0) {
            return (false, "No active recipients");
        }

        if (totalVotes == 0) {
            return (false, "No votes cast");
        }

        // Validate yield amount precision and sufficiency
        uint256[] memory votes = _getVotingResults();
        if (!_validateYieldDistributionPrecision(availableYield, activeRecipients, votes, totalVotes)) {
            return (false, "Insufficient yield precision for accurate distribution");
        }

        return (true, "");
    }

    /// @inheritdoc IDistributionModule
    function emergencyPause() external override onlyEmergencyAdmin {
        _pause();
        emit EmergencyPause(msg.sender, block.timestamp);
    }

    /// @inheritdoc IDistributionModule
    function emergencyResume() external override onlyOwner {
        _unpause();
    }

    /// @notice Emergency withdraw function
    /// @param token Token to withdraw
    /// @param to Recipient address
    /// @param amount Amount to withdraw
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner whenPaused {
        if (to == address(0)) revert ZeroAddress();

        IERC20(token).safeTransfer(to, amount);
        emit EmergencyWithdraw(token, to, amount, msg.sender);
    }

    /// @inheritdoc IDistributionModule
    function setCycleLength(uint256 _cycleLength) external override onlyOwner {
        if (_cycleLength == 0) revert InvalidCycleLength();
        cycleLength = _cycleLength;
    }

    /// @inheritdoc IDistributionModule
    function setYieldFixedSplitDivisor(uint256 _divisor) external override onlyOwner {
        if (_divisor == 0) revert InvalidDivisor();
        yieldFixedSplitDivisor = _divisor;
    }

    /// @notice Sets the emergency admin
    /// @param _emergencyAdmin Address of the emergency admin
    function setEmergencyAdmin(address _emergencyAdmin) external onlyOwner {
        if (_emergencyAdmin == address(0)) revert ZeroAddress();
        emergencyAdmin = _emergencyAdmin;
    }

    /// @notice Sets the yield source address
    /// @param _yieldSource Address of the new yield source
    function setYieldSource(address _yieldSource) external onlyOwner {
        if (_yieldSource == address(0)) revert ZeroAddress();
        yieldSource = _yieldSource;
    }

    /// @notice Gets the current yield source address
    /// @return The current yield source address
    function getYieldSource() external view returns (address) {
        return yieldSource;
    }

    /// @notice Validates the yield source
    /// @return isValid Whether the source is valid
    function validateYieldSource() external view returns (bool isValid) {
        if (yieldSource == address(0)) return false;
        return _isSourceValid(yieldSource);
    }

    /// @notice Hook for minting tokens before distribution
    /// @dev Can be overridden for custom token minting logic
    function _mintTokensBeforeDistribution() internal virtual {
        uint256 requiredTokens = calculateRequiredTokensForDistribution();

        if (requiredTokens > 0) {
            IYieldModule(yieldToken).mint(requiredTokens, address(this));
            emit TokensMintedForDistribution(requiredTokens);
        }
    }

    /// @notice Collects yield from the yield source
    /// @return Total yield collected
    function _collectYield() internal returns (uint256) {
        if (yieldSource == address(0)) revert NoYieldSource();

        uint256 totalYield = _collectFromSource(yieldSource);
        if (totalYield == 0) revert InsufficientYield();

        totalYieldCollected += totalYield;
        lastCollectionBlock = block.number;

        emit YieldCollected(yieldSource, totalYield, block.number);
        emit YieldValidated(totalYield);

        return totalYield;
    }

    /// @notice Gets the total available yield from the yield source
    /// @return Available yield
    function _getAvailableYield() internal view returns (uint256) {
        if (yieldSource == address(0)) return 0;
        return _getSourceYield(yieldSource);
    }

    /// @notice Hook for getting voting results
    /// @return votes Array of votes per recipient
    function _getVotingResults() internal view virtual returns (uint256[] memory votes);

    /// @notice Hook for getting active recipients
    /// @return Array of active recipient addresses
    function _getActiveRecipients() internal view virtual returns (address[] memory);

    /// @notice Calculates fixed and voted split amounts
    /// @param totalYield Total yield to split
    /// @return fixedAmount Amount for fixed distribution
    /// @return votedAmount Amount for voted distribution
    function _calculateSplits(uint256 totalYield) internal view returns (uint256 fixedAmount, uint256 votedAmount) {
        if (yieldFixedSplitDivisor > 0) {
            fixedAmount = totalYield / yieldFixedSplitDivisor;
            votedAmount = totalYield - fixedAmount;
        } else {
            fixedAmount = 0;
            votedAmount = totalYield;
        }
    }

    /// @notice Calculates voted distributions for recipients
    /// @param votes Array of votes per recipient
    /// @param _totalVotes Total votes cast
    /// @param totalAmount Total amount to distribute
    /// @return distributions Array of distribution amounts
    function _calculateVotedDistributions(uint256[] memory votes, uint256 _totalVotes, uint256 totalAmount)
        internal
        pure
        returns (uint256[] memory distributions)
    {
        if (votes.length == 0 || _totalVotes == 0 || totalAmount == 0) {
            return new uint256[](0);
        }

        distributions = new uint256[](votes.length);
        uint256 distributed = 0;

        for (uint256 i = 0; i < votes.length; i++) {
            if (votes[i] > 0) {
                distributions[i] = (votes[i] * totalAmount) / _totalVotes;
                distributed += distributions[i];
            }
        }

        // Handle rounding remainder
        if (distributed < totalAmount) {
            uint256 remainder = totalAmount - distributed;
            for (uint256 i = 0; i < distributions.length; i++) {
                if (distributions[i] > 0) {
                    distributions[i] += remainder;
                    break;
                }
            }
        }

        return distributions;
    }

    /// @notice Calculates fixed distributions for recipients
    /// @param activeRecipients Array of recipient addresses
    /// @param totalAmount Total amount for fixed distribution
    /// @return distributions Array of distribution amounts
    function _calculateFixedDistributions(address[] memory activeRecipients, uint256 totalAmount)
        internal
        pure
        returns (uint256[] memory distributions)
    {
        if (activeRecipients.length == 0 || totalAmount == 0) {
            return new uint256[](0);
        }

        distributions = new uint256[](activeRecipients.length);
        uint256 baseAmount = totalAmount / activeRecipients.length;
        uint256 remainder = totalAmount % activeRecipients.length;

        for (uint256 i = 0; i < activeRecipients.length; i++) {
            distributions[i] = baseAmount;
            if (i == 0 && remainder > 0) {
                distributions[i] += remainder;
            }
        }

        return distributions;
    }

    /// @notice Executes the actual distribution transfers
    /// @param activeRecipients Array of recipient addresses
    /// @param votedDistributions Array of voted distribution amounts
    /// @param fixedDistributions Array of fixed distribution amounts
    function _executeDistributions(
        address[] memory activeRecipients,
        uint256[] memory votedDistributions,
        uint256[] memory fixedDistributions
    ) internal {
        uint256 recipientCount = activeRecipients.length;

        for (uint256 i = 0; i < recipientCount; i++) {
            uint256 totalAmount = 0;

            if (votedDistributions.length > i) {
                totalAmount += votedDistributions[i];
            }

            if (fixedDistributions.length > i) {
                totalAmount += fixedDistributions[i];
            }

            if (totalAmount > 0) {
                IERC20(yieldToken).safeTransfer(activeRecipients[i], totalAmount);
            }
        }
    }

    /// @notice Completes the cycle transition
    function _completeCycleTransition() internal virtual {
        lastDistributionBlock = block.number;
        cycleNumber++;

        // Reset voting state
        currentVotes = new uint256[](0);
        totalVotes = 0;

        // Process any queued changes via hooks
        _processQueuedChanges();

        emit CycleCompleted(cycleNumber, block.number);
    }

    /// @notice Hook for processing queued changes
    function _processQueuedChanges() internal virtual;

    /// @notice Records distribution in history
    function _recordDistribution(
        uint256 totalYield,
        uint256 _totalVotes,
        address[] memory activeRecipients,
        uint256[] memory votedDistributions,
        uint256[] memory fixedDistributions
    ) internal {
        DistributionState storage state = distributionHistory[cycleNumber];
        state.totalYield = totalYield;
        state.totalVotes = _totalVotes;
        state.lastDistributionBlock = block.number;
        state.cycleNumber = cycleNumber;
        state.recipients = activeRecipients;
        state.votedDistributions = votedDistributions;
        state.fixedDistributions = fixedDistributions;

        (state.fixedAmount, state.votedAmount) = _calculateSplits(totalYield);

        emit DistributionValidated(totalYield, activeRecipients.length);
    }

    /// @notice Calculates required tokens for distribution
    /// @return Required token amount
    function calculateRequiredTokensForDistribution() public view returns (uint256) {
        uint256 currentBalance = IERC20(yieldToken).balanceOf(address(this));
        uint256 availableYield = _getAvailableYield();

        if (availableYield > currentBalance) {
            return availableYield - currentBalance;
        }

        return 0;
    }

    /// @notice Internal function to collect yield from a specific source
    /// @param source Address of the yield source
    /// @return Amount collected
    function _collectFromSource(address source) internal returns (uint256) {
        try IYieldModule(source).yieldAccrued() returns (uint256 accrued) {
            if (accrued > 0) {
                try IYieldModule(source).claimYield(accrued, address(this)) {
                    return accrued;
                } catch {
                    return 0;
                }
            }
            // If accrued yield is 0, fall back to token balance
            uint256 balance = IERC20(source).balanceOf(address(this));
            if (balance > 0) {
                // For tokens with no accrued yield, just return the balance
                // The tokens are already in this contract
                return balance;
            }
            return 0;
        } catch {
            uint256 balance = IERC20(source).balanceOf(address(this));
            if (balance > 0) {
                // For non-IYieldModule tokens, just return the balance
                // The tokens are already in this contract
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
            if (accrued > 0) {
                return accrued;
            }
            // If accrued yield is 0, check token balance as fallback
            return IERC20(source).balanceOf(address(this));
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

    /// @notice Validates that the yield amount provides sufficient precision for distribution
    /// @param availableYield Total available yield
    /// @param votes Array of votes per recipient
    /// @param _totalVotes Total votes cast
    /// @return valid Whether the yield amount provides sufficient precision
    function _validateYieldDistributionPrecision(
        uint256 availableYield,
        address[] memory, /* activeRecipients */
        uint256[] memory votes,
        uint256 _totalVotes
    ) internal view returns (bool valid) {
        // Basic requirement: must have some yield to distribute
        if (availableYield == 0) {
            return false;
        }

        // Calculate splits to validate both portions
        (, uint256 votedAmount) = _calculateSplits(availableYield);

        // Validate voted distribution precision: check for potential underflow in voted calculations
        if (votedAmount > 0 && votes.length > 0 && _totalVotes > 0) {
            // Find the smallest non-zero vote
            uint256 smallestVote = type(uint256).max;
            for (uint256 i = 0; i < votes.length; i++) {
                if (votes[i] > 0 && votes[i] < smallestVote) {
                    smallestVote = votes[i];
                }
            }

            // Check if smallest vote share results in at least 1 wei
            // This prevents underflow in the _calculateVotedDistributions function
            if (smallestVote != type(uint256).max) {
                uint256 smallestDistribution = (smallestVote * votedAmount) / _totalVotes;
                if (smallestDistribution == 0) {
                    return false;
                }
            }
        }

        // For fixed distributions, the _calculateFixedDistributions function
        // handles integer division gracefully, so no additional validation needed

        return true;
    }
}
