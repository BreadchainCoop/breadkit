// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/Test.sol";
import {TestWrapper} from "./TestWrapper.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BreadKitFactory} from "../src/BreadKitFactory.sol";
import {SexyDaiYield} from "../src/token-types/SexyDaiYield.sol";
import {IBreadKitToken} from "../src/interfaces/IBreadKitToken.sol";
import {IWXDAI} from "../src/interfaces/IWXDAI.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BreadKitTest is TestWrapper {
    address constant wxDAI = 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d;
    address constant sxDAI = 0xaf204776c7245bF4147c2612BF6e5972Ee483701;
    BreadKitFactory public factory;
    IBreadKitToken public token;
    address public constant randomHolder = 0x23b4f73FB31e89B27De17f9c5DE2660cc1FB0CdF; // random multisig
    address public constant randomEOA = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        factory = new BreadKitFactory(address(this));

        /// @dev this is how we deploy and whitelist a new token type
        address impl = address(new SexyDaiYield(wxDAI, sxDAI));
        address beacon = address(new UpgradeableBeacon(impl, address(this)));
        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        /// @dev this is how we deploy a new token

        // encode initialization payload for given token type
        bytes memory payload = abi.encodeWithSelector(SexyDaiYield.initialize.selector, "TOKEN", "T", address(this));

        // deploy token
        token = IBreadKitToken(factory.createToken(address(beacon), payload, keccak256("random salt")));

        // deploy yield claimer
        address[] memory recipients = new address[](1);
        address claimer =
            factory.createDefaultYieldClaimer(address(token), recipients, 0, address(this), keccak256("random salt"));

        // set yield claimer
        token.setYieldClaimer(claimer);

        // burn 1 wei
        token.mint{value: 1}(0x0000000000000000000000000000000000000009);
    }

    function test_mint() public {
        uint256 supplyBefore = token.totalSupply();
        uint256 balBefore = token.balanceOf(address(this));
        uint256 contractBalBefore = IERC20(sxDAI).balanceOf(address(token));

        assertEq(supplyBefore, 1);
        assertEq(balBefore, 0);
        assertEq(contractBalBefore, 0);

        token.mint{value: 1 ether}(address(this));

        uint256 supplyAfter = token.totalSupply();
        uint256 balAfter = token.balanceOf(address(this));
        uint256 contractBalAfter = IERC20(sxDAI).balanceOf(address(token));

        assertEq(supplyAfter, supplyBefore + 1 ether);
        assertEq(balAfter, balBefore + 1 ether);
        assertGt(contractBalAfter, contractBalBefore);
        assertLt(contractBalAfter, supplyBefore + 1 ether);

        uint256 yieldBefore = token.yieldAccrued();
        assertEq(yieldBefore, 0);

        token.transfer(randomEOA, 0.5 ether);
        assertEq(token.balanceOf(address(this)), 0.5 ether);
        assertEq(token.balanceOf(randomEOA), 0.5 ether);

        IWXDAI(wxDAI).deposit{value: 1 ether}();

        IERC20(wxDAI).approve(address(token), 1 ether);
        token.mint(address(this), 1 ether);

        assertEq(token.balanceOf(address(this)), 1.5 ether);
    }

    function test_burn() public {
        token.mint{value: 1 ether}(address(this));
        uint256 balBefore = token.balanceOf(address(this));
        assertEq(balBefore, 1 ether);

        uint256 ethBalBefore = address(this).balance;
        token.burn(0.5 ether, address(this));
        uint256 ethBalAfter = address(this).balance;

        assertEq(token.balanceOf(address(this)), 0.5 ether);
        assertEq(ethBalAfter - ethBalBefore, 0.5 ether);
    }

    function test_yieldClaimer() public {
        address newClaimer = address(0x123);
        
        vm.expectRevert();
        token.setYieldClaimer(newClaimer);

        token.prepareNewYieldClaimer(newClaimer);
        
        vm.warp(block.timestamp + 14 days);
        
        token.finalizeNewYieldClaimer();
    }

    function test_claimYield() public {
        token.mint{value: 10 ether}(address(this));
        
        vm.warp(block.timestamp + 365 days);
        
        uint256 yield = token.yieldAccrued();
        assertGt(yield, 0);
        
        address claimer = factory.createDefaultYieldClaimer(
            address(token),
            new address[](1),
            0,
            address(this),
            keccak256("test")
        );
        
        token.prepareNewYieldClaimer(claimer);
        vm.warp(block.timestamp + 14 days);
        token.finalizeNewYieldClaimer();
        
        vm.prank(claimer);
        token.claimYield(yield / 2, claimer);
        
        assertGt(token.balanceOf(claimer), 0);
    }

    function test_factoryWhitelistBlacklist() public {
        address newBeacon = address(new UpgradeableBeacon(address(new SexyDaiYield(wxDAI, sxDAI)), address(this)));
        
        address[] memory beacons = new address[](1);
        beacons[0] = newBeacon;
        
        factory.whitelistBeacons(beacons);
        assertTrue(factory.beaconsContains(newBeacon));
        
        factory.blacklistBeacons(beacons);
        assertFalse(factory.beaconsContains(newBeacon));
    }

    function test_computeAddress() public {
        address beacon = factory.beacons()[0];
        bytes memory payload = abi.encodeWithSelector(SexyDaiYield.initialize.selector, "TEST", "T", address(this));
        bytes32 salt = keccak256("test");
        
        address computed = factory.computeTokenAddress(beacon, payload, salt);
        address actual = factory.createToken(beacon, payload, salt);
        
        assertEq(computed, actual);
    }

    function test_delegation() public {
        token.mint{value: 1 ether}(address(this));
        
        // Cast to SexyDaiYield to access delegates function
        SexyDaiYield sexyToken = SexyDaiYield(address(token));
        assertEq(sexyToken.delegates(address(this)), address(this));
        
        address newDelegate = address(0x456);
        sexyToken.delegate(newDelegate);
        
        assertEq(sexyToken.delegates(address(this)), newDelegate);
    }

    function test_votingPower() public {
        token.mint{value: 1 ether}(address(this));
        
        // Cast to SexyDaiYield to access getVotes function
        SexyDaiYield sexyToken = SexyDaiYield(address(token));
        uint256 votes = sexyToken.getVotes(address(this));
        assertEq(votes, 1 ether);
        
        token.transfer(randomEOA, 0.5 ether);
        
        votes = sexyToken.getVotes(address(this));
        assertEq(votes, 0.5 ether);
        
        votes = sexyToken.getVotes(randomEOA);
        assertEq(votes, 0.5 ether);
    }

    function test_revertConditions() public {
        vm.expectRevert();
        token.mint{value: 0}(address(this));
        
        vm.expectRevert();
        token.burn(0, address(this));
        
        vm.expectRevert();
        token.claimYield(1, address(this));
        
        vm.expectRevert();
        token.setYieldClaimer(address(0));
    }

    receive() external payable {}
}
