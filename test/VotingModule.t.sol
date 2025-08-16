// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VotingModule} from "../src/modules/VotingModule.sol";
import {TokenBasedVotingPower} from "../src/modules/strategies/TokenBasedVotingPower.sol";
import {TimeWeightedVotingPower} from "../src/modules/strategies/TimeWeightedVotingPower.sol";
import {SignatureVerifier} from "../src/modules/utils/SignatureVerifier.sol";
import {VoteValidator} from "../src/modules/utils/VoteValidator.sol";
import {IVotingPowerStrategy} from "../src/interfaces/IVotingPowerStrategy.sol";
import {IBreadKitToken} from "../src/interfaces/IBreadKitToken.sol";
import {SexyDaiYield} from "../src/token-types/SexyDaiYield.sol";
import {BreadKitFactory} from "../src/BreadKitFactory.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VotingModuleTest is Test {
    // Constants
    uint256 constant MAX_POINTS = 100;
    uint256 constant MIN_VOTING_POWER = 1e18;

    // Test addresses
    address constant wxDAI = 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d;
    address constant sxDAI = 0xaf204776c7245bF4147c2612BF6e5972Ee483701;

    // Contracts
    VotingModule public votingModule;
    TokenBasedVotingPower public tokenStrategy;
    TimeWeightedVotingPower public timeWeightedStrategy;
    SignatureVerifier public signatureVerifier;
    VoteValidator public voteValidator;
    BreadKitFactory public factory;
    IBreadKitToken public token;

    // Test accounts
    address public owner;
    address public voter1;
    address public voter2;
    address public voter3;
    uint256 public voter1PrivateKey;
    uint256 public voter2PrivateKey;
    uint256 public voter3PrivateKey;

    // Events
    event VoteCastWithSignature(address indexed voter, uint256[] points, uint256 votingPower, uint256 nonce);
    event BatchVotesCast(address[] voters, uint256[] nonces);
    event VotingModuleInitialized(IVotingPowerStrategy[] strategies);

    function setUp() public {
        // Setup test accounts
        owner = address(this);
        voter1PrivateKey = 0x1;
        voter2PrivateKey = 0x2;
        voter3PrivateKey = 0x3;
        voter1 = vm.addr(voter1PrivateKey);
        voter2 = vm.addr(voter2PrivateKey);
        voter3 = vm.addr(voter3PrivateKey);

        // Deploy factory and token
        factory = new BreadKitFactory(owner);

        // Deploy and whitelist token implementation
        address impl = address(new SexyDaiYield(wxDAI, sxDAI));
        address beacon = address(new UpgradeableBeacon(impl, owner));
        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        // Deploy token
        bytes memory payload = abi.encodeWithSelector(SexyDaiYield.initialize.selector, "Test Token", "TEST", owner);
        token = IBreadKitToken(factory.createToken(beacon, payload, keccak256("test salt")));

        // Mint tokens to test accounts
        deal(voter1, 10 ether);
        deal(voter2, 10 ether);
        deal(voter3, 10 ether);

        vm.prank(voter1);
        token.mint{value: 5 ether}(voter1);

        vm.prank(voter2);
        token.mint{value: 3 ether}(voter2);

        vm.prank(voter3);
        token.mint{value: 2 ether}(voter3);

        // Deploy voting power strategies
        tokenStrategy = new TokenBasedVotingPower(token);
        timeWeightedStrategy = new TimeWeightedVotingPower(token, block.number - 1000, block.number - 100);

        // Deploy utility contracts
        signatureVerifier = new SignatureVerifier();
        voteValidator = new VoteValidator();

        // Deploy and initialize voting module
        votingModule = new VotingModule();
        IVotingPowerStrategy[] memory strategies = new IVotingPowerStrategy[](2);
        strategies[0] = IVotingPowerStrategy(address(tokenStrategy));
        strategies[1] = IVotingPowerStrategy(address(timeWeightedStrategy));

        votingModule.initialize(MAX_POINTS, strategies);
        votingModule.setMinRequiredVotingPower(MIN_VOTING_POWER);
    }

    function testInitialization() public view {
        assertEq(votingModule.maxPoints(), MAX_POINTS);
        assertEq(votingModule.minRequiredVotingPower(), MIN_VOTING_POWER);
        assertEq(votingModule.currentCycle(), 1);

        IVotingPowerStrategy[] memory strategies = votingModule.getVotingPowerStrategies();
        assertEq(strategies.length, 2);
        assertEq(address(strategies[0]), address(tokenStrategy));
        assertEq(address(strategies[1]), address(timeWeightedStrategy));
    }

    function testDirectVoting() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        vm.prank(voter1);
        votingModule.vote(points);

        // Verify vote was recorded by checking that the voter has voted
        assertTrue(votingModule.accountLastVoted(voter1) > 0);

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

        // Verify vote was recorded
        assertTrue(votingModule.accountLastVoted(voter1) > 0);

        // Verify nonce was used
        assertTrue(votingModule.isNonceUsed(voter1, nonce));
    }

    function testBatchVoting() public {
        address[] memory voters = new address[](2);
        voters[0] = voter1;
        voters[1] = voter2;

        uint256[][] memory pointsArray = new uint256[][](2);
        pointsArray[0] = new uint256[](3);
        pointsArray[0][0] = 50;
        pointsArray[0][1] = 30;
        pointsArray[0][2] = 20;

        pointsArray[1] = new uint256[](3);
        pointsArray[1][0] = 60;
        pointsArray[1][1] = 25;
        pointsArray[1][2] = 15;

        uint256[] memory nonces = new uint256[](2);
        nonces[0] = 1;
        nonces[1] = 1;

        bytes[] memory signatures = new bytes[](2);

        // Create signatures
        bytes32 digest1 = _createVoteDigest(voter1, pointsArray[0], nonces[0]);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(voter1PrivateKey, digest1);
        signatures[0] = abi.encodePacked(r1, s1, v1);

        bytes32 digest2 = _createVoteDigest(voter2, pointsArray[1], nonces[1]);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(voter2PrivateKey, digest2);
        signatures[1] = abi.encodePacked(r2, s2, v2);

        // Cast batch votes
        vm.expectEmit(false, false, false, true);
        emit BatchVotesCast(voters, nonces);

        votingModule.castBatchVotesWithSignature(voters, pointsArray, nonces, signatures);

        // Verify both votes were recorded
        assertTrue(votingModule.accountLastVoted(voter1) > 0);
        assertTrue(votingModule.accountLastVoted(voter2) > 0);
    }

    function testNoVoteRecasting() public {
        uint256[] memory points1 = new uint256[](3);
        points1[0] = 50;
        points1[1] = 30;
        points1[2] = 20;

        // First vote
        vm.prank(voter1);
        votingModule.vote(points1);

        // Verify vote was recorded
        assertTrue(votingModule.accountLastVoted(voter1) > 0);

        // Try to recast vote with different distribution - should fail
        uint256[] memory points2 = new uint256[](3);
        points2[0] = 60;
        points2[1] = 25;
        points2[2] = 15;

        vm.prank(voter1);
        vm.expectRevert(VotingModule.AlreadyVotedInCycle.selector);
        votingModule.vote(points2);
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

    function testInsufficientVotingPower() public {
        // Create account with no tokens
        address noTokensVoter = address(0x999);

        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        // Direct vote should fail
        vm.prank(noTokensVoter);
        vm.expectRevert(VotingModule.InsufficientVotingPower.selector);
        votingModule.vote(points);
    }

    function testExceedsMaxPoints() public {
        uint256[] memory points = new uint256[](2);
        points[0] = MAX_POINTS + 1; // Exceeds max
        points[1] = 50;

        vm.prank(voter1);
        vm.expectRevert(VotingModule.InvalidPointsDistribution.selector);
        votingModule.vote(points);
    }

    function testZeroVotePoints() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 0;
        points[1] = 0;
        points[2] = 0;

        vm.prank(voter1);
        vm.expectRevert(VotingModule.InvalidPointsDistribution.selector);
        votingModule.vote(points);
    }

    function testValidateSignature() public view {
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        uint256 nonce = 1;

        // Create valid signature
        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Should return true for valid signature
        assertTrue(votingModule.validateSignature(voter1, points, nonce, signature));

        // Should return false for wrong voter
        assertFalse(votingModule.validateSignature(voter2, points, nonce, signature));
    }

    function testGetTotalVotingPower() public view {
        uint256 power = votingModule.getTotalVotingPower(voter1);
        assertGt(power, 0);

        // Voter1 should have more power than voter2
        uint256 power2 = votingModule.getTotalVotingPower(voter2);
        assertGt(power, power2);
    }

    function testNewCycle() public {
        // Vote in cycle 1
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        vm.prank(voter1);
        votingModule.vote(points);

        // Start new cycle
        votingModule.startNewCycle();
        assertEq(votingModule.currentCycle(), 2);

        // Vote in cycle 2
        vm.prank(voter2);
        votingModule.vote(points);

        // Check that votes are recorded in different cycles
        assertTrue(votingModule.accountLastVoted(voter1) > 0);
        assertTrue(votingModule.accountLastVoted(voter2) > 0);
        assertEq(votingModule.currentCycle(), 2);
    }

    function testNonceSkipping() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        // Use nonce 5 (skipping 1-4)
        uint256 nonce = 5;

        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Should succeed even though nonces 1-4 weren't used
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);
        assertTrue(votingModule.isNonceUsed(voter1, nonce));

        // Nonces 1-4 should still be available
        assertFalse(votingModule.isNonceUsed(voter1, 1));
        assertFalse(votingModule.isNonceUsed(voter1, 2));
        assertFalse(votingModule.isNonceUsed(voter1, 3));
        assertFalse(votingModule.isNonceUsed(voter1, 4));
    }

    // Helper functions

    function _createVoteDigest(address voter, uint256[] memory points, uint256 nonce) internal view returns (bytes32) {
        bytes32 VOTE_TYPEHASH = keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)");

        bytes32 structHash = keccak256(abi.encode(VOTE_TYPEHASH, voter, keccak256(abi.encodePacked(points)), nonce));

        return keccak256(abi.encodePacked("\x19\x01", votingModule.DOMAIN_SEPARATOR(), structHash));
    }
}
