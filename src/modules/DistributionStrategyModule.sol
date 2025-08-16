// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionStrategyModule} from "../interfaces/IDistributionStrategyModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title DistributionStrategyModule
/// @notice Manages configurable yield distribution strategies
/// @dev Implements flexible split between fixed and voted distribution portions
contract DistributionStrategyModule is IDistributionStrategyModule, Ownable {
    using SafeERC20 for IERC20;

    error InvalidDivisor();
    error DivisorTooSmall();
    error LengthMismatch();
    error EmptyRecipients();
    error InvalidPercentageTotal();
    error ZeroAddress();
    error ZeroFixedAmount();
    error NoStrategyRecipients();
    error InsufficientStrategyYield();

    uint256 public constant PERCENTAGE_BASE = 10000; // 100% = 10000 basis points
    uint256 public constant MIN_STRATEGY_DIVISOR = 1;

    uint256 public strategyDivisor;
    address[] public strategyRecipients;
    uint256[] public strategyPercentages;
    IERC20 public yieldToken;
    address public authorized;

    modifier onlyAuthorized() {
        if (msg.sender != authorized && msg.sender != owner()) revert Ownable.Unauthorized();
        _;
    }

    /// @notice Initializes the distribution strategy module
    /// @param _yieldToken Address of the yield token to distribute
    /// @param _initialDivisor Initial divisor for distribution split
    constructor(address _yieldToken, uint256 _initialDivisor) {
        if (_yieldToken == address(0)) revert ZeroAddress();
        if (_initialDivisor == 0) revert InvalidDivisor();

        yieldToken = IERC20(_yieldToken);
        strategyDivisor = _initialDivisor;
        _initializeOwner(msg.sender);
    }

    /// @notice Sets the authorized address that can trigger distributions
    /// @param _authorized Address to authorize
    function setAuthorized(address _authorized) external onlyOwner {
        if (_authorized == address(0)) revert ZeroAddress();
        authorized = _authorized;
    }

    /// @inheritdoc IDistributionStrategyModule
    function calculateDistribution(uint256 totalYield)
        external
        view
        returns (uint256 fixedAmount, uint256 votedAmount)
    {
        if (totalYield == 0) return (0, 0);

        fixedAmount = totalYield / strategyDivisor;
        votedAmount = totalYield - fixedAmount;

        if (strategyRecipients.length > 0 && fixedAmount < strategyRecipients.length) {
            revert InsufficientStrategyYield();
        }
    }

    /// @inheritdoc IDistributionStrategyModule
    function updateDistributionStrategy(uint256 newDivisor) external onlyOwner {
        if (newDivisor == 0) revert InvalidDivisor();
        if (newDivisor < MIN_STRATEGY_DIVISOR) revert DivisorTooSmall();

        uint256 oldDivisor = strategyDivisor;
        strategyDivisor = newDivisor;

        emit DistributionStrategyUpdated(oldDivisor, newDivisor);
    }

    /// @inheritdoc IDistributionStrategyModule
    function setStrategyRecipients(address[] calldata recipients, uint256[] calldata percentages) external onlyOwner {
        if (recipients.length != percentages.length) revert LengthMismatch();
        if (recipients.length == 0) revert EmptyRecipients();

        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < percentages.length; i++) {
            totalPercentage += percentages[i];
        }
        if (totalPercentage != PERCENTAGE_BASE) revert InvalidPercentageTotal();

        delete strategyRecipients;
        delete strategyPercentages;

        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert ZeroAddress();
            strategyRecipients.push(recipients[i]);
            strategyPercentages.push(percentages[i]);
        }

        emit StrategyRecipientsUpdated(recipients, percentages);
    }

    /// @inheritdoc IDistributionStrategyModule
    function getStrategyRecipients()
        external
        view
        returns (address[] memory recipients, uint256[] memory percentages)
    {
        recipients = strategyRecipients;
        percentages = strategyPercentages;
    }

    /// @inheritdoc IDistributionStrategyModule
    function getStrategyAmount(uint256 totalYield) external view returns (uint256) {
        if (totalYield == 0) return 0;
        return totalYield / strategyDivisor;
    }

    /// @inheritdoc IDistributionStrategyModule
    function distributeFixed(uint256 fixedAmount) external onlyAuthorized {
        if (fixedAmount == 0) revert ZeroFixedAmount();
        if (strategyRecipients.length == 0) revert NoStrategyRecipients();

        uint256 totalDistributed = 0;

        for (uint256 i = 0; i < strategyRecipients.length; i++) {
            uint256 recipientShare = (fixedAmount * strategyPercentages[i]) / PERCENTAGE_BASE;

            if (recipientShare > 0) {
                yieldToken.safeTransfer(strategyRecipients[i], recipientShare);
                totalDistributed += recipientShare;

                emit StrategyDistribution(strategyRecipients[i], recipientShare);
            }
        }

        emit StrategyDistributionComplete(fixedAmount, totalDistributed);
    }

    /// @inheritdoc IDistributionStrategyModule
    function validateStrategyConfiguration() external view returns (bool isValid) {
        if (strategyDivisor == 0) return false;

        if (strategyRecipients.length > 0) {
            if (strategyRecipients.length != strategyPercentages.length) return false;

            uint256 totalPercentage = 0;
            for (uint256 i = 0; i < strategyPercentages.length; i++) {
                totalPercentage += strategyPercentages[i];
                if (strategyRecipients[i] == address(0)) return false;
            }

            if (totalPercentage != PERCENTAGE_BASE) return false;
        }

        return true;
    }
}
