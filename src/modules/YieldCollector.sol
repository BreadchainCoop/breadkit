// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IYieldModule} from "../interfaces/IYieldModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title YieldCollector
/// @notice Utility contract for collecting yield from a single source
/// @dev Handles token minting, single-source yield collection, and validation
contract YieldCollector is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidSource();
    error YieldCollectionFailed();
    error UnauthorizedCaller();
    error InsufficientYield();
    error NoYieldSource();



    event YieldCollected(address indexed source, uint256 amount, uint256 blockNumber);
    event TokensMinted(address indexed token, uint256 amount);
    event YieldValidated(uint256 totalYield);

    address public distributionManager;
    address public yieldToken;
    address public yieldSource;

    uint256 public totalYieldCollected;
    uint256 public lastCollectionBlock;

    modifier onlyDistributionManager() {
        if (msg.sender != distributionManager) revert UnauthorizedCaller();
        _;
    }

    constructor(address _yieldToken, address _yieldSource) {
        if (_yieldToken == address(0)) revert ZeroAddress();
        if (_yieldSource == address(0)) revert ZeroAddress();
        yieldToken = _yieldToken;
        yieldSource = _yieldSource;
        _initializeOwner(msg.sender);
    }

    /// @notice Sets the distribution manager address
    /// @param _distributionManager Address of the distribution manager
    function setDistributionManager(address _distributionManager) external onlyOwner {
        if (_distributionManager == address(0)) revert ZeroAddress();
        distributionManager = _distributionManager;
    }

    /// @notice Sets the yield source address
    /// @param _yieldSource Address of the new yield source
    function setYieldSource(address _yieldSource) external onlyOwner {
        if (_yieldSource == address(0)) revert ZeroAddress();
        yieldSource = _yieldSource;
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

    /// @notice Collects yield from the yield source
    /// @return totalYield Total yield collected
    function collectYield() external onlyDistributionManager nonReentrant returns (uint256 totalYield) {
        if (yieldSource == address(0)) revert NoYieldSource();

        totalYield = _collectFromSource(yieldSource);
        if (totalYield == 0) revert InsufficientYield();

        totalYieldCollected += totalYield;
        lastCollectionBlock = block.number;

        emit YieldCollected(yieldSource, totalYield, block.number);
        emit YieldValidated(totalYield);

        return totalYield;
    }

    /// @notice Gets the total available yield from the yield source
    /// @return availableYield Total available yield
    function getAvailableYield() external view returns (uint256 availableYield) {
        if (yieldSource == address(0)) return 0;
        return _getSourceYield(yieldSource);
    }

    /// @notice Validates the yield source
    /// @return isValid Whether the source is valid
    function validateYieldSource() external view returns (bool isValid) {
        if (yieldSource == address(0)) return false;
        return _isSourceValid(yieldSource);
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

    /// @notice Gets the current yield source address
    /// @return The current yield source address
    function getYieldSource() external view returns (address) {
        return yieldSource;
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
