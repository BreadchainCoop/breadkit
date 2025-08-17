// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBasisPointsVotingModule} from "../interfaces/IBasisPointsVotingModule.sol";
import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";
import {IDistributionModule} from "../interfaces/IDistributionModule.sol";
import {IMockRecipientRegistry} from "../interfaces/IMockRecipientRegistry.sol";
import {ICycleModule} from "../interfaces/ICycleModule.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title BasisPointsVotingModule
/// @author BreadKit
/// @notice Basis points voting module implementation with signature-based voting and multiple strategies
/// @dev Implements EIP-712 compliant signature verification for gasless voting.
///      Supports multiple voting power calculation strategies and batch vote submission.
///      Prevents vote recasting within cycles and uses nonces for replay protection.
contract BasisPointsVotingModule is IBasisPointsVotingModule, Initializable, EIP712Upgradeable, OwnableUpgradeable {
    using ECDSA for bytes32;

    // ============ Constants ============

    /// @notice Precision factor for calculations to prevent rounding errors
    uint256 public constant PRECISION = 1e18;

    /// @notice Maximum number of votes that can be submitted in a single batch
    uint256 public constant MAX_BATCH_SIZE = 100;

    /// @notice EIP-712 type hash for vote data structure
    bytes32 public constant VOTE_TYPEHASH = keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)");

    // ============ State Variables ============

    /// @notice Maximum points that can be allocated to a single recipient
    uint256 public maxPoints;

    /// @notice Array of voting power calculation strategies
    IVotingPowerStrategy[] public votingPowerStrategies;

    // ============ Mappings ============

    /// @notice Tracks used nonces for each voter to prevent replay attacks
    /// @dev voter => nonce => used
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    /// @notice Tracks which cycle an account last voted in
    /// @dev voter => cycle number
    mapping(address => uint256) public accountLastVotedCycle;

    /// @notice Vote distribution across projects for each cycle
    /// @dev cycle => array of weighted votes per project
    mapping(uint256 => uint256[]) public projectDistributions;

    /// @notice Total voting power used in each cycle
    /// @dev cycle => total voting power
    mapping(uint256 => uint256) public totalCycleVotingPower;

    /// @notice Current vote count for each cycle
    /// @dev cycle => vote count
    mapping(uint256 => uint256) public currentVotes;

    /// @notice Stores the voting power used by each voter in each cycle
    /// @dev cycle => voter => voting power used
    mapping(uint256 => mapping(address => uint256)) public voterCyclePower;

    /// @notice Stores the vote points distribution for each voter in each cycle
    /// @dev cycle => voter => array of points
    mapping(uint256 => mapping(address => uint256[])) public voterCyclePoints;

    // ============ External References ============

    /// @notice Reference to the distribution module for yield allocation
    IDistributionModule public distributionModule;

    /// @notice Reference to the recipient registry for validation
    IMockRecipientRegistry public recipientRegistry;
    
    /// @notice Reference to the cycle module for cycle management
    ICycleModule public cycleModule;

    // Events
    event VoteCast(address indexed voter, uint256[] points, uint256 votingPower, uint256 nonce, bytes signature);
    event BatchVotesCast(address[] voters, uint256[] nonces);
    event VotingModuleInitialized(IVotingPowerStrategy[] strategies);
    event DistributionModuleSet(address distributionModule);
    event RecipientRegistrySet(address recipientRegistry);
    event CycleModuleSet(address cycleModule);
    event MaxPointsSet(uint256 maxPoints);

    // Errors
    error InvalidSignature();
    error NonceAlreadyUsed();
    error InvalidPointsDistribution();
    error ExceedsMaxPoints();
    error ZeroVotePoints();
    error ArrayLengthMismatch();
    error BatchTooLarge();
    error NoStrategiesProvided();
    error InvalidStrategy();
    error IncorrectNumberOfRecipients();
    error RecipientRegistryNotSet();

    /// @notice Initializes the voting module with strategies
    /// @param _maxPoints Maximum points that can be allocated per recipient
    /// @param _strategies Array of voting power strategy contracts
    /// @param _distributionModule Address of the distribution module
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _cycleModule Address of the cycle module
    function initialize(
        uint256 _maxPoints,
        IVotingPowerStrategy[] calldata _strategies,
        address _distributionModule,
        address _recipientRegistry,
        address _cycleModule
    ) external initializer {
        if (_strategies.length == 0) revert NoStrategiesProvided();

        __EIP712_init("BreadKit Voting", "1");
        __Ownable_init(msg.sender);

        maxPoints = _maxPoints;
        distributionModule = IDistributionModule(_distributionModule);
        recipientRegistry = IMockRecipientRegistry(_recipientRegistry);
        cycleModule = ICycleModule(_cycleModule);

        for (uint256 i = 0; i < _strategies.length; i++) {
            if (address(_strategies[i]) == address(0)) revert InvalidStrategy();
            votingPowerStrategies.push(_strategies[i]);
        }

        emit VotingModuleInitialized(_strategies);
        emit DistributionModuleSet(_distributionModule);
        emit RecipientRegistrySet(_recipientRegistry);
        emit CycleModuleSet(_cycleModule);
    }

    /// @inheritdoc IBasisPointsVotingModule
    function castVoteWithSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        external
        override
    {
        _castSingleVote(voter, points, nonce, signature);
    }

    /// @inheritdoc IBasisPointsVotingModule
    function castBatchVotesWithSignature(
        address[] calldata voters,
        uint256[][] calldata points,
        uint256[] calldata nonces,
        bytes[] calldata signatures
    ) external override {
        if (voters.length != points.length || voters.length != nonces.length || voters.length != signatures.length) {
            revert ArrayLengthMismatch();
        }

        if (voters.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < voters.length; i++) {
            _castSingleVote(voters[i], points[i], nonces[i], signatures[i]);
        }

        emit BatchVotesCast(voters, nonces);
    }

    /// @inheritdoc IBasisPointsVotingModule
    function validateVotePoints(uint256[] calldata points) public view override returns (bool) {
        if (points.length == 0) return false;

        // Validate array length against recipient registry
        uint256 recipientCount = recipientRegistry.getActiveRecipientsCount();
        if (points.length != recipientCount) return false;

        uint256 totalPoints;
        for (uint256 i = 0; i < points.length; i++) {
            if (points[i] > maxPoints) return false;
            totalPoints += points[i];
        }

        return totalPoints > 0;
    }

    /// @inheritdoc IBasisPointsVotingModule
    function validateSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        public
        view
        override
        returns (bool)
    {
        bytes32 structHash = keccak256(abi.encode(VOTE_TYPEHASH, voter, keccak256(abi.encodePacked(points)), nonce));
        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = hash.recover(signature);
        return signer == voter && !usedNonces[voter][nonce];
    }

    /// @inheritdoc IBasisPointsVotingModule
    function getVotingPower(address account) external view override returns (uint256) {
        return _calculateTotalVotingPower(account);
    }

    /// @inheritdoc IBasisPointsVotingModule
    function getCurrentVotingDistribution() external view override returns (uint256[] memory) {
        uint256 currentCycle = cycleModule.getCurrentCycle();
        return projectDistributions[currentCycle];
    }

    /// @inheritdoc IBasisPointsVotingModule
    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc IBasisPointsVotingModule
    function isNonceUsed(address voter, uint256 nonce) external view override returns (bool) {
        return usedNonces[voter][nonce];
    }

    /// @inheritdoc IBasisPointsVotingModule
    function getVotingPowerStrategies() external view override returns (IVotingPowerStrategy[] memory) {
        return votingPowerStrategies;
    }

    // Issue #43: Store required votes at proposal creation in VotingRecipientRegistry
    // https://github.com/BreadchainCoop/breadkit/issues/43
    // TODO: Implement when VotingRecipientRegistry is added
    // /// @inheritdoc IVotingModule
    // function getRequiredVotes(uint256 proposalId) external view override returns (uint256) {
    //     // This will be implemented when VotingRecipientRegistry is integrated
    //     // For now, return a placeholder value or revert
    //     revert("getRequiredVotes: Not yet implemented - see issue #43");
    // }

    /// @inheritdoc IBasisPointsVotingModule
    function setMaxPoints(uint256 _maxPoints) external override onlyOwner {
        maxPoints = _maxPoints;
        emit MaxPointsSet(_maxPoints);
    }


    /// @notice Gets the recipient registry address
    /// @return The address of the recipient registry
    function getRecipientRegistry() external view returns (address) {
        return address(recipientRegistry);
    }

    /// @notice Gets the expected number of vote points based on active recipients
    /// @return The number of active recipients (expected array length for votes)
    function getExpectedPointsLength() external view returns (uint256) {
        if (address(recipientRegistry) == address(0)) revert RecipientRegistryNotSet();
        return recipientRegistry.getActiveRecipientsCount();
    }


    // ============ Internal Functions ============

    /// @notice Processes a single vote with signature verification
    /// @dev Validates signature, nonce, and voting power before processing the vote
    /// @param voter Address of the voter
    /// @param points Array of points to allocate to each recipient
    /// @param nonce Unique nonce for replay protection
    /// @param signature EIP-712 signature from the voter
    function _castSingleVote(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        internal
    {
        // Check nonce hasn't been used
        if (usedNonces[voter][nonce]) revert NonceAlreadyUsed();

        // Verify signature
        bytes32 structHash = keccak256(abi.encode(VOTE_TYPEHASH, voter, keccak256(abi.encodePacked(points)), nonce));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);
        if (signer != voter) revert InvalidSignature();

        // Mark nonce as used after validation
        usedNonces[voter][nonce] = true;

        // Get total voting power
        uint256 votingPower = _calculateTotalVotingPower(voter);

        // Validate points
        if (!validateVotePoints(points)) revert InvalidPointsDistribution();

        // Process vote
        _processVote(voter, points, votingPower);

        emit VoteCast(voter, points, votingPower, nonce, signature);
    }

    /// @notice Calculates total voting power across all strategies
    /// @dev Aggregates voting power from all configured strategies
    /// @param account Address to calculate voting power for
    /// @return totalPower Combined voting power from all strategies
    function _calculateTotalVotingPower(address account) internal view returns (uint256) {
        uint256 totalPower = 0;

        for (uint256 i = 0; i < votingPowerStrategies.length; i++) {
            totalPower += votingPowerStrategies[i].getCurrentVotingPower(account);
        }

        return totalPower;
    }

    /// @notice Processes and records a vote
    /// @dev Updates project distributions and cycle voting power. Handles vote recasting by reverting previous votes.
    /// @param voter Address of the voter
    /// @param points Array of points allocated to each recipient
    /// @param votingPower Total voting power of the voter
    function _processVote(address voter, uint256[] calldata points, uint256 votingPower)
        internal
    {
        uint256 currentCycle = cycleModule.getCurrentCycle();
        
        // Check if voter has already voted in this cycle and revert their previous vote
        uint256 previousVotingPower = voterCyclePower[currentCycle][voter];
        if (previousVotingPower > 0) {
            // Revert previous vote's impact on total voting power
            totalCycleVotingPower[currentCycle] -= previousVotingPower;
            currentVotes[currentCycle] -= 1; // Decrement vote count since we're replacing
            
            // Revert previous vote's impact on project distributions
            uint256[] storage previousPoints = voterCyclePoints[currentCycle][voter];
            for (uint256 i = 0; i < previousPoints.length; i++) {
                uint256 previousAllocation = (previousVotingPower * previousPoints[i]) / PRECISION;
                projectDistributions[currentCycle][i] -= previousAllocation;
            }
        }

        // Apply new vote
        currentVotes[currentCycle] += 1;
        totalCycleVotingPower[currentCycle] += votingPower;
        
        // Store voter's current voting power and points for potential future recasting
        voterCyclePower[currentCycle][voter] = votingPower;
        delete voterCyclePoints[currentCycle][voter]; // Clear previous points array
        for (uint256 i = 0; i < points.length; i++) {
            voterCyclePoints[currentCycle][voter].push(points[i]);
        }

        // Calculate and update project distributions with new vote
        for (uint256 i = 0; i < points.length; i++) {
            uint256 allocation = (votingPower * points[i]) / PRECISION;

            // Update project distributions
            if (i >= projectDistributions[currentCycle].length) {
                projectDistributions[currentCycle].push(allocation);
            } else {
                projectDistributions[currentCycle][i] += allocation;
            }
        }

        // Update last voted cycle
        accountLastVotedCycle[voter] = currentCycle;
    }
}
