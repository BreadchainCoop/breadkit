// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/Test.sol";
import {TestWrapper} from "./TestWrapper.sol";
import {DefaultYieldClaimer} from "../src/DefaultYieldClaimer.sol";
import {SexyDaiYield} from "../src/token-types/SexyDaiYield.sol";
import {IBreadKitToken} from "../src/interfaces/IBreadKitToken.sol";
import {BreadKitFactory} from "../src/BreadKitFactory.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DefaultYieldClaimerTest is TestWrapper {
    address constant wxDAI = 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d;
    address constant sxDAI = 0xaf204776c7245bF4147c2612BF6e5972Ee483701;
    
    BreadKitFactory public factory;
    IBreadKitToken public token;
    DefaultYieldClaimer public claimer;
    
    address public recipient1 = address(0x1111);
    address public recipient2 = address(0x2222);
    address public recipient3 = address(0x3333);
    address public voter1 = address(0x4444);
    address public voter2 = address(0x5555);

    function setUp() public {
        factory = new BreadKitFactory(address(this));
        
        address impl = address(new SexyDaiYield(wxDAI, sxDAI));
        address beacon = address(new UpgradeableBeacon(impl, address(this)));
        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);
        
        bytes memory payload = abi.encodeWithSelector(SexyDaiYield.initialize.selector, "YIELD", "YLD", address(this));
        token = IBreadKitToken(factory.createToken(beacon, payload, keccak256("salt")));
        
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        
        claimer = new DefaultYieldClaimer(address(token), recipients, 50, address(this));
        
        token.setYieldClaimer(address(claimer));
        
        token.mint{value: 10 ether}(voter1);
        token.mint{value: 5 ether}(voter2);
    }

    function test_constructor() public {
        assertEq(claimer.votingToken(), address(token));
        assertEq(claimer.percentVoted(), 50);
        assertEq(claimer.owner(), address(this));
        
        address[] memory recipients = claimer.getRecipients();
        assertEq(recipients.length, 2);
        assertEq(recipients[0], recipient1);
        assertEq(recipients[1], recipient2);
    }

    function test_addRemoveRecipient() public {
        claimer.addRecipient(recipient3);
        
        address[] memory recipients = claimer.getRecipients();
        assertEq(recipients.length, 3);
        assertTrue(claimer.isRecipient(recipient3));
        
        claimer.removeRecipient(recipient1);
        recipients = claimer.getRecipients();
        assertEq(recipients.length, 2);
        assertFalse(claimer.isRecipient(recipient1));
    }

    function test_votingRound() public {
        claimer.startVoting();
        
        vm.prank(voter1);
        claimer.vote(recipient1);
        
        vm.prank(voter2);
        claimer.vote(recipient2);
        
        uint256 votes1 = claimer.getVotes(1, recipient1);
        uint256 votes2 = claimer.getVotes(1, recipient2);
        
        assertEq(votes1, 10 ether);
        assertEq(votes2, 5 ether);
        
        vm.warp(block.timestamp + 7 days + 1);
        
        claimer.finalizeVoting();
    }

    function test_claimAndDistribute() public {
        vm.warp(block.timestamp + 365 days);
        
        uint256 yield = token.yieldAccrued();
        assertGt(yield, 0);
        
        claimer.startVoting();
        
        vm.prank(voter1);
        claimer.vote(recipient1);
        
        vm.prank(voter2);
        claimer.vote(recipient2);
        
        vm.warp(block.timestamp + 7 days + 1);
        claimer.finalizeVoting();
        
        uint256 balBefore1 = token.balanceOf(recipient1);
        uint256 balBefore2 = token.balanceOf(recipient2);
        
        claimer.claimAndDistribute();
        
        uint256 balAfter1 = token.balanceOf(recipient1);
        uint256 balAfter2 = token.balanceOf(recipient2);
        
        assertGt(balAfter1, balBefore1);
        assertGt(balAfter2, balBefore2);
        
        assertGt(balAfter1 - balBefore1, balAfter2 - balBefore2);
    }

    function test_setPercentVoted() public {
        claimer.setPercentVoted(75);
        assertEq(claimer.percentVoted(), 75);
        
        vm.expectRevert();
        claimer.setPercentVoted(101);
    }

    function test_distributionInterval() public {
        vm.warp(block.timestamp + 365 days);
        
        claimer.claimAndDistribute();
        
        vm.expectRevert();
        claimer.claimAndDistribute();
        
        vm.warp(block.timestamp + 1 days);
        
        claimer.claimAndDistribute();
    }

    function test_votingRevertConditions() public {
        vm.expectRevert();
        vm.prank(voter1);
        claimer.vote(recipient1);
        
        claimer.startVoting();
        
        vm.expectRevert();
        vm.prank(voter1);
        claimer.vote(address(0x9999));
        
        vm.prank(voter1);
        claimer.vote(recipient1);
        
        vm.expectRevert();
        vm.prank(voter1);
        claimer.vote(recipient2);
        
        vm.warp(block.timestamp + 8 days);
        
        vm.expectRevert();
        vm.prank(voter2);
        claimer.vote(recipient1);
        
        vm.expectRevert();
        claimer.finalizeVoting();
    }

    function test_onlyOwnerFunctions() public {
        vm.prank(voter1);
        vm.expectRevert();
        claimer.startVoting();
        
        vm.prank(voter1);
        vm.expectRevert();
        claimer.addRecipient(recipient3);
        
        vm.prank(voter1);
        vm.expectRevert();
        claimer.removeRecipient(recipient1);
        
        vm.prank(voter1);
        vm.expectRevert();
        claimer.setPercentVoted(25);
    }

    receive() external payable {}
}