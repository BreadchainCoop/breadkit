// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/modules/automation/MockDistributionManager.sol";
import "../src/modules/automation/ChainlinkAutomation.sol";

/// @title DeployMockAutomation
/// @notice Deploy script for mock distribution manager with Chainlink automation
contract DeployMockAutomation is Script {
    function run() external returns (address mockDistributionManager, address chainlinkAuto) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockDistributionManager
        MockDistributionManager mockDM = new MockDistributionManager();
        console.log("MockDistributionManager deployed at:", address(mockDM));
        console.log("Will trigger every 200 blocks");

        // Deploy ChainlinkAutomation with MockDistributionManager
        ChainlinkAutomation chainlink = new ChainlinkAutomation(address(mockDM));
        console.log("ChainlinkAutomation deployed at:", address(chainlink));

        // Log initial state
        console.log("Current block:", block.number);
        console.log("Last distribution block:", mockDM.getLastDistributionBlock());
        console.log("Blocks until next distribution:", mockDM.blocksUntilDistribution());
        console.log("Is distribution ready:", mockDM.isDistributionReady());

        vm.stopBroadcast();

        return (address(mockDM), address(chainlink));
    }

    /// @notice Deploy only the mock distribution manager
    function deployMockDistributionManager() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockDistributionManager mockDM = new MockDistributionManager();
        console.log("MockDistributionManager deployed at:", address(mockDM));

        vm.stopBroadcast();

        return address(mockDM);
    }

    /// @notice Deploy chainlink automation with existing distribution manager
    function deployChainlinkAutomation(address distributionManager) external returns (address) {
        require(distributionManager != address(0), "Invalid distribution manager");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ChainlinkAutomation chainlink = new ChainlinkAutomation(distributionManager);
        console.log("ChainlinkAutomation deployed at:", address(chainlink));
        console.log("Using DistributionManager at:", distributionManager);

        vm.stopBroadcast();

        return address(chainlink);
    }
}
