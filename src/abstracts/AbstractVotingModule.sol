// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";
import {IMockRecipientRegistry} from "../interfaces/IMockRecipientRegistry.sol";
import {IDistributionModule} from "../interfaces/IDistributionModule.sol";
import {ICycleModule} from "../interfaces/ICycleModule.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title AbstractVotingModule
/// @author BreadKit
/// @notice Abstract base contract for voting modules with signature-based voting
/// @dev Provides core voting functionality including vote processing, signature verification,
///      and integration with voting power strategies, cycle management, and recipient registries.
///      Inheriting contracts must implement specific voting logic.
abstract contract AbstractVotingModule is Initializable, EIP712Upgradeable, OwnableUpgradeable {
    using ECDSA for bytes32;

    // ============ Constants ============

    /// @notice Precision factor for calculations to avoid rounding errors
    /// @dev Used in vote weight calculations to maintain precision
    uint256 public constant PRECISION = 1e18;

    /// @notice Maximum number of votes that can be cast in a single batch transaction
    /// @dev Prevents gas limit issues and potential DOS attacks
    uint256 public constant MAX_BATCH_SIZE = 50;

    /// @notice EIP-712 typehash for vote signature verification
    /// @dev Keccak256 hash of the Vote type structure for EIP-712 signing
    bytes32 public constant VOTE_TYPEHASH = keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)");

    // ============ Storage Variables ============

    /// @notice Maximum points that can be allocated to a single recipient
    /// @dev Configurable per implementation to control vote distribution
    uint256 public maxPoints;

    /// @notice Array of voting power calculation strategies
    /// @dev Multiple strategies can be used to calculate combined voting power
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
    /// @dev Handles the actual distribution of rewards based on voting results
    IDistributionModule public distributionModule;

    /// @notice Reference to the recipient registry for validation
    /// @dev Maintains the list of valid recipients that can receive votes
    IMockRecipientRegistry public recipientRegistry;

    /// @notice Reference to the cycle module for cycle management
    /// @dev Manages voting cycles and transitions between periods
    ICycleModule public cycleModule;

    // ============ Events ============

    /// @notice Emitted when a vote is cast with a signature
    /// @param voter The address of the voter
    /// @param points Array of points allocated to each recipient
    /// @param votingPower The total voting power used
    /// @param nonce The nonce used for replay protection
    /// @param signature The EIP-712 signature
    event VoteCast(address indexed voter, uint256[] points, uint256 votingPower, uint256 nonce, bytes signature);

    /// @notice Emitted when multiple votes are cast in a batch
    /// @param voters Array of voter addresses
    /// @param nonces Array of nonces used
    event BatchVotesCast(address[] voters, uint256[] nonces);

    /// @notice Emitted when the voting module is initialized
    /// @param strategies Array of voting power strategies
    event VotingModuleInitialized(IVotingPowerStrategy[] strategies);

    /// @notice Emitted when the distribution module is set
    /// @param distributionModule Address of the distribution module
    event DistributionModuleSet(address distributionModule);

    /// @notice Emitted when the recipient registry is set
    /// @param recipientRegistry Address of the recipient registry
    event RecipientRegistrySet(address recipientRegistry);

    /// @notice Emitted when the cycle module is set
    /// @param cycleModule Address of the cycle module
    event CycleModuleSet(address cycleModule);

    /// @notice Emitted when max points is updated
    /// @param maxPoints New maximum points value
    event MaxPointsSet(uint256 maxPoints);

    // ============ Errors ============

    /// @notice Thrown when an invalid signature is provided
    error InvalidSignature();

    /// @notice Thrown when a nonce has already been used
    error NonceAlreadyUsed();

    /// @notice Thrown when points distribution is invalid
    error InvalidPointsDistribution();

    /// @notice Thrown when points exceed the maximum allowed
    error ExceedsMaxPoints();

    /// @notice Thrown when zero vote points are submitted
    error ZeroVotePoints();

    /// @notice Thrown when array lengths don't match in batch operations
    error ArrayLengthMismatch();

    /// @notice Thrown when batch size exceeds maximum allowed
    error BatchTooLarge();

    /// @notice Thrown when no strategies are provided during initialization
    error NoStrategiesProvided();

    /// @notice Thrown when an invalid strategy address is provided
    error InvalidStrategy();

    /// @notice Thrown when the number of recipients doesn't match expected
    error IncorrectNumberOfRecipients();

    /// @notice Thrown when recipient registry is not set
    error RecipientRegistryNotSet();

    // ============ Initialization ============

    /// @notice Initializes the abstract voting module
    /// @dev Sets up EIP-712 domain, ownership, and core parameters.
    ///      Must be called by inheriting contract's initializer.
    /// @param _maxPoints Maximum points that can be allocated per recipient
    /// @param _strategies Array of voting power strategy contracts
    /// @param _distributionModule Address of the distribution module
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _cycleModule Address of the cycle module
    function __AbstractVotingModule_init(
        uint256 _maxPoints,
        IVotingPowerStrategy[] calldata _strategies,
        address _distributionModule,
        address _recipientRegistry,
        address _cycleModule
    ) internal onlyInitializing {
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

    // ============ External Functions ============

    /// @notice Gets the voting power of an account across all strategies
    /// @dev Aggregates voting power from all configured strategies
    /// @param account The address to check voting power for
    /// @return The total voting power of the account
    function getVotingPower(address account) external view virtual returns (uint256) {
        return _calculateTotalVotingPower(account);
    }

    /// @notice Gets the current voting distribution for the active cycle
    /// @dev Returns the array of weighted votes for each project in the current cycle
    /// @return Array of vote weights for each project
    function getCurrentVotingDistribution() external view virtual returns (uint256[] memory) {
        uint256 currentCycle = cycleModule.getCurrentCycle();
        return projectDistributions[currentCycle];
    }

    /// @notice Returns the EIP-712 domain separator for signature verification
    /// @dev Used by external contracts to verify signatures
    /// @return The domain separator hash
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Checks if a nonce has been used for a voter
    /// @dev Used to prevent replay attacks
    /// @param voter The voter's address
    /// @param nonce The nonce to check
    /// @return True if the nonce has been used, false otherwise
    function isNonceUsed(address voter, uint256 nonce) external view virtual returns (bool) {
        return usedNonces[voter][nonce];
    }

    /// @notice Gets all configured voting power strategies
    /// @dev Returns the array of strategy contracts
    /// @return Array of voting power strategy contracts
    function getVotingPowerStrategies() external view virtual returns (IVotingPowerStrategy[] memory) {
        return votingPowerStrategies;
    }

    /// @notice Sets the maximum points that can be allocated per recipient
    /// @dev Only callable by owner
    /// @param _maxPoints The new maximum points value
    function setMaxPoints(uint256 _maxPoints) external virtual onlyOwner {
        maxPoints = _maxPoints;
        emit MaxPointsSet(_maxPoints);
    }

    /// @notice Gets the expected number of vote points based on active recipients
    /// @dev Used to validate vote arrays have correct length
    /// @return The number of active recipients
    function getExpectedPointsLength() external view returns (uint256) {
        if (address(recipientRegistry) == address(0)) revert RecipientRegistryNotSet();
        return recipientRegistry.getActiveRecipientsCount();
    }

    // ============ Internal Functions ============

    /// @notice Processes a single vote with signature verification
    /// @dev Validates signature, nonce, and voting power before processing
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
        if (!_validateVotePoints(points)) revert InvalidPointsDistribution();

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
    /// @dev Updates project distributions and cycle voting power. Handles vote recasting.
    /// @param voter Address of the voter
    /// @param points Array of points allocated to each recipient
    /// @param votingPower Total voting power of the voter
    function _processVote(address voter, uint256[] calldata points, uint256 votingPower) internal virtual {
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

    /// @notice Validates vote points distribution
    /// @dev Checks if points array is valid according to module rules
    /// @param points Array of points to validate
    /// @return True if points are valid, false otherwise
    function _validateVotePoints(uint256[] calldata points) internal view virtual returns (bool) {
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

    /// @notice Validates a vote signature
    /// @dev Verifies that a signature is valid for the given vote parameters
    /// @param voter The address of the voter
    /// @param points Array of points allocated to each project
    /// @param nonce The nonce for replay protection
    /// @param signature The signature to validate
    /// @return True if signature is valid, false otherwise
    function validateSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        public
        view
        virtual
        returns (bool)
    {
        bytes32 structHash = keccak256(abi.encode(VOTE_TYPEHASH, voter, keccak256(abi.encodePacked(points)), nonce));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);
        return signer == voter && !usedNonces[voter][nonce];
    }

    /// @notice Validates vote points distribution externally
    /// @dev Public wrapper for internal validation logic
    /// @param points Array of points to validate
    /// @return True if points are valid, false otherwise
    function validateVotePoints(uint256[] calldata points) public view virtual returns (bool) {
        return _validateVotePoints(points);
    }

    // ============ Gap for Upgradeable Contracts ============

    /// @dev Gap for future storage variables in upgradeable contracts
    uint256[40] private __gap;
}
