// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VotingModule} from "../src/modules/VotingModule.sol";
import {TokenBasedVotingPower} from "../src/modules/strategies/TokenBasedVotingPower.sol";
import {IVotingPowerStrategy} from "../src/interfaces/IVotingPowerStrategy.sol";
import {IBreadKitToken} from "../src/interfaces/IBreadKitToken.sol";
import {IRecipientRegistry} from "../src/interfaces/IRecipientRegistry.sol";
import {MockRecipientRegistry} from "./mocks/MockRecipientRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

// Simple mock token for testing
contract MockToken is IBreadKitToken, ERC20VotesUpgradeable {
    constructor() {
        _disableInitializers();
    }
    
    function initialize() external initializer {
        __ERC20_init("Mock Token", "MOCK");
        __ERC20Votes_init();
    }
    
    function mint(address receiver) external payable override {
        _mint(receiver, msg.value);
        if (delegates(receiver) == address(0)) _delegate(receiver, receiver);
    }
    
    function mint(address receiver, uint256 amount) external override {
        _mint(receiver, amount);
        if (delegates(receiver) == address(0)) _delegate(receiver, receiver);
    }
    
    function burn(uint256, address) external override {}
    function claimYield(uint256, address) external override {}
    function prepareNewYieldClaimer(address) external override {}
    function finalizeNewYieldClaimer() external override {}
    function setYieldClaimer(address) external override {}
    function yieldAccrued() external view override returns (uint256) { return 0; }
}

contract VotingModuleSimpleTest is Test {
    // Constants
    uint256 constant MAX_POINTS = 100;
    uint256 constant MIN_VOTING_POWER = 1e18;
    
    // Contracts
    VotingModule public votingModule;
    TokenBasedVotingPower public tokenStrategy;
    MockToken public token;
    MockRecipientRegistry public recipientRegistry;
    
    // Test accounts
    address public owner;
    address public voter1;
    address public voter2;
    uint256 public voter1PrivateKey;
    uint256 public voter2PrivateKey;
    
    // Events
    event VoteCastWithSignature(
        address indexed voter,
        uint256[] points,
        uint256 votingPower,
        uint256 nonce
    );

    function setUp() public {
        // Setup test accounts
        owner = address(this);
        voter1PrivateKey = 0x1;
        voter2PrivateKey = 0x2;
        voter1 = vm.addr(voter1PrivateKey);
        voter2 = vm.addr(voter2PrivateKey);
        
        // Deploy and initialize mock token
        token = new MockToken();
        token.initialize();
        
        // Mint tokens to test accounts
        token.mint(voter1, 5 ether);
        token.mint(voter2, 3 ether);
        
        // Deploy voting power strategy
        tokenStrategy = new TokenBasedVotingPower(IBreadKitToken(address(token)));
        
        // Deploy mock recipient registry with 3 recipients
        address[] memory recipients = new address[](3);
        recipients[0] = address(0x1111);
        recipients[1] = address(0x2222);
        recipients[2] = address(0x3333);
        recipientRegistry = new MockRecipientRegistry(recipients);
        
        // Deploy and initialize voting module
        votingModule = new VotingModule();
        IVotingPowerStrategy[] memory strategies = new IVotingPowerStrategy[](1);
        strategies[0] = IVotingPowerStrategy(address(tokenStrategy));
        
        votingModule.initialize(MAX_POINTS, strategies);
        votingModule.setMinRequiredVotingPower(MIN_VOTING_POWER);
        votingModule.setRecipientRegistry(address(recipientRegistry));
    }

    function testInitialization() public view {
        assertEq(votingModule.maxPoints(), MAX_POINTS);
        assertEq(votingModule.minRequiredVotingPower(), MIN_VOTING_POWER);
        assertEq(votingModule.currentCycle(), 1);
        
        IVotingPowerStrategy[] memory strategies = votingModule.getVotingPowerStrategies();
        assertEq(strategies.length, 1);
        assertEq(address(strategies[0]), address(tokenStrategy));
    }

    function testDirectVoting() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;
        
        vm.prank(voter1);
        votingModule.vote(points);
        
        // Verify vote was recorded by checking project distributions
        uint256[] memory projectDist = votingModule.getCurrentVotingDistribution();
        assertEq(projectDist.length, 3);
    }

    function testSignatureVoting() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 40;
        points[1] = 35;
        points[2] = 25;
        
        uint256 nonce = 1;
        
        // Create signature
        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Cast vote with signature
        vm.expectEmit(true, false, false, true);
        emit VoteCastWithSignature(voter1, points, votingModule.getTotalVotingPower(voter1), nonce);
        
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);
        
        // Verify vote was recorded by checking project distributions
        uint256[] memory projectDist = votingModule.getCurrentVotingDistribution();
        assertEq(projectDist.length, 3);
        
        // Verify nonce was used
        assertTrue(votingModule.isNonceUsed(voter1, nonce));
    }

    function testNonceReplayProtection() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;
        
        uint256 nonce = 1;
        
        // Create signature
        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // First vote should succeed
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);
        
        // Second vote with same nonce should fail
        vm.expectRevert(VotingModule.NonceAlreadyUsed.selector);
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);
    }

    function testIncorrectRecipientCount() public {
        // Try to vote with wrong number of points (2 instead of 3)
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;
        
        vm.prank(voter1);
        vm.expectRevert(VotingModule.InvalidPointsDistribution.selector);
        votingModule.vote(points);
        
        // Try with 4 points (too many)
        uint256[] memory points2 = new uint256[](4);
        points2[0] = 25;
        points2[1] = 25;
        points2[2] = 25;
        points2[3] = 25;
        
        vm.prank(voter1);
        vm.expectRevert(VotingModule.InvalidPointsDistribution.selector);
        votingModule.vote(points2);
    }
    
    function testValidRecipientCount() public {
        // Vote with correct number of points (3 recipients)
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;
        
        vm.prank(voter1);
        votingModule.vote(points);
        
        // Check vote was recorded by checking project distributions
        uint256[] memory projectDist = votingModule.getCurrentVotingDistribution();
        assertEq(projectDist.length, 3);
        
        // Verify expected points length
        assertEq(votingModule.getExpectedPointsLength(), 3);
    }
    
    function testRecipientRegistryUpdate() public {
        // Add a new recipient
        address[] memory newRecipients = new address[](4);
        newRecipients[0] = address(0x1111);
        newRecipients[1] = address(0x2222);
        newRecipients[2] = address(0x3333);
        newRecipients[3] = address(0x4444);
        recipientRegistry.setActiveRecipients(newRecipients);
        
        // Now need 4 points
        uint256[] memory points = new uint256[](4);
        points[0] = 25;
        points[1] = 25;
        points[2] = 25;
        points[3] = 25;
        
        vm.prank(voter1);
        votingModule.vote(points);
        
        // Check vote was recorded with 4 points in project distributions
        uint256[] memory projectDist = votingModule.getCurrentVotingDistribution();
        assertEq(projectDist.length, 4);
    }
    
    function testInvalidSignature() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;
        
        uint256 nonce = 1;
        
        // Create signature with wrong private key
        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter2PrivateKey, digest); // Wrong key
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Vote should fail
        vm.expectRevert(VotingModule.InvalidSignature.selector);
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);
    }

    // Helper function
    function _createVoteDigest(
        address voter,
        uint256[] memory points,
        uint256 nonce
    ) internal view returns (bytes32) {
        bytes32 VOTE_TYPEHASH = keccak256(
            "Vote(address voter,bytes32 pointsHash,uint256 nonce)"
        );
        
        bytes32 structHash = keccak256(abi.encode(
            VOTE_TYPEHASH,
            voter,
            keccak256(abi.encodePacked(points)),
            nonce
        ));
        
        return keccak256(abi.encodePacked(
            "\x19\x01",
            votingModule.DOMAIN_SEPARATOR(),
            structHash
        ));
    }
}