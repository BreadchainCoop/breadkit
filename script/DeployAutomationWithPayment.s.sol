// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/modules/EnhancedDistributionManager.sol";
import "../src/modules/automation/ChainlinkAutomationWithPayment.sol";
import "../src/modules/automation/GelatoAutomationWithPayment.sol";

contract DeployAutomationWithPayment is Script {
    // Configuration parameters
    uint256 constant CYCLE_LENGTH = 7200; // ~1 day on Ethereum (12s blocks)
    uint256 constant MIN_YIELD_REQUIRED = 100 * 10**18; // 100 tokens minimum
    
    // Chainlink configuration
    uint256 constant CHAINLINK_FIXED_FEE = 5 * 10**18; // 5 tokens
    uint256 constant CHAINLINK_PERCENTAGE_FEE = 200; // 2%
    
    // Gelato configuration
    uint256 constant GELATO_FIXED_FEE = 3 * 10**18; // 3 tokens
    uint256 constant GELATO_PERCENTAGE_FEE = 300; // 3%

    function run() external {
        // Load deployment parameters from environment
        address distributionModule = vm.envAddress("DISTRIBUTION_MODULE");
        address yieldModule = vm.envAddress("YIELD_MODULE");
        address yieldToken = vm.envAddress("YIELD_TOKEN");
        address chainlinkTreasury = vm.envAddress("CHAINLINK_TREASURY");
        address gelatoTreasury = vm.envAddress("GELATO_TREASURY");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Enhanced Distribution Manager
        EnhancedDistributionManager distributionManager = new EnhancedDistributionManager(
            distributionModule,
            yieldModule,
            yieldToken,
            CYCLE_LENGTH,
            MIN_YIELD_REQUIRED
        );

        console.log("Enhanced Distribution Manager deployed at:", address(distributionManager));

        // Deploy Chainlink Automation with Payment
        ChainlinkAutomationWithPayment chainlinkAutomation = new ChainlinkAutomationWithPayment(
            address(distributionManager),
            yieldToken,
            chainlinkTreasury,
            CHAINLINK_FIXED_FEE,
            CHAINLINK_PERCENTAGE_FEE,
            MIN_YIELD_REQUIRED + CHAINLINK_FIXED_FEE
        );

        console.log("Chainlink Automation deployed at:", address(chainlinkAutomation));

        // Deploy Gelato Automation with Payment
        GelatoAutomationWithPayment gelatoAutomation = new GelatoAutomationWithPayment(
            address(distributionManager),
            yieldToken,
            gelatoTreasury,
            GELATO_FIXED_FEE,
            GELATO_PERCENTAGE_FEE,
            MIN_YIELD_REQUIRED + GELATO_FIXED_FEE
        );

        console.log("Gelato Automation deployed at:", address(gelatoAutomation));

        // Set default automation provider (can be changed later)
        distributionManager.setAutomationProvider(address(chainlinkAutomation));
        console.log("Chainlink set as default automation provider");

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Distribution Manager:", address(distributionManager));
        console.log("Chainlink Automation:", address(chainlinkAutomation));
        console.log("Gelato Automation:", address(gelatoAutomation));
        console.log("\n=== Configuration ===");
        console.log("Cycle Length (blocks):", CYCLE_LENGTH);
        console.log("Min Yield Required (tokens):", MIN_YIELD_REQUIRED / 10**18);
        console.log("Chainlink Fixed Fee (tokens):", CHAINLINK_FIXED_FEE / 10**18);
        console.log("Chainlink Percentage Fee (%):", CHAINLINK_PERCENTAGE_FEE / 100);
        console.log("Gelato Fixed Fee (tokens):", GELATO_FIXED_FEE / 10**18);
        console.log("Gelato Percentage Fee (%):", GELATO_PERCENTAGE_FEE / 100);
    }

    function setAutomationProvider(address distributionManager, address provider) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        EnhancedDistributionManager(distributionManager).setAutomationProvider(provider);
        console.log("Automation provider updated to:", provider);

        vm.stopBroadcast();
    }

    function updatePaymentConfig(
        address automation,
        bool requiresPayment,
        uint256 fixedFee,
        uint256 percentageFee,
        uint256 minYieldThreshold,
        address paymentReceiver,
        uint256 maxFeeCap
    ) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        IAutomationPaymentProvider.PaymentConfig memory config = IAutomationPaymentProvider.PaymentConfig({
            requiresPayment: requiresPayment,
            fixedFee: fixedFee,
            percentageFee: percentageFee,
            minYieldThreshold: minYieldThreshold,
            paymentReceiver: paymentReceiver,
            maxFeeCap: maxFeeCap
        });

        IAutomationPaymentProvider(automation).updatePaymentConfig(config);
        console.log("Payment configuration updated for:", automation);

        vm.stopBroadcast();
    }
}