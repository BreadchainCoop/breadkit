// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseDistributionStrategy} from "./BaseDistributionStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title EqualDistributionStrategy
/// @notice Distributes yield equally among all recipients from registry
/// @dev Implements equal distribution logic using recipient registry
contract EqualDistributionStrategy is BaseDistributionStrategy {
    using SafeERC20 for IERC20;

    /// @dev Initializes the equal distribution strategy
    /// @param _yieldToken Address of the yield token to distribute
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _distributionManager Address of the distribution manager
    function initialize(address _yieldToken, address _recipientRegistry, address _distributionManager)
        external
        initializer
    {
        __BaseDistributionStrategy_init(_yieldToken, _recipientRegistry, _distributionManager);
    }

    /// @dev Distributes amount equally among all recipients
    /// @param amount Total amount to distribute
    /// @param recipients Array of recipients to distribute to
    function _distribute(uint256 amount, address[] memory recipients) internal override {
        uint256 amountPerRecipient = amount / recipients.length;
        uint256 distributed = 0;

        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 share;

            // Last recipient gets remainder to handle rounding
            if (i == recipients.length - 1) {
                share = amount - distributed;
            } else {
                share = amountPerRecipient;
            }

            if (share > 0) {
                yieldToken.safeTransfer(recipients[i], share);
                distributed += share;
            }
        }
    }
}
