// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingModule} from "../interfaces/IVotingModule.sol";
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
abstract contract AbstractVotingModule is IVotingModule, Initializable, EIP712Upgradeable, OwnableUpgradeable {
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

    // Events and Errors are inherited from IVotingModule

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

    /// @notice Gets the voting power of an account from the voting strategies
    /// @dev Queries the configured voting strategies for the account's power
    /// @param account The address to check voting power for
    /// @return The total voting power from all strategies
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

    // ============ Getter Functions ============

    /// @notice Gets the precision factor used in calculations
    /// @dev Returns the constant PRECISION value for external contracts
    /// @return The precision factor (1e18)
    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    /// @notice Gets the maximum batch size for batch voting
    /// @dev Returns the constant MAX_BATCH_SIZE value
    /// @return The maximum number of votes in a batch (50)
    function getMaxBatchSize() external pure returns (uint256) {
        return MAX_BATCH_SIZE;
    }

    /// @notice Gets the EIP-712 typehash for vote signatures
    /// @dev Returns the constant VOTE_TYPEHASH for external verification
    /// @return The keccak256 hash of the Vote type structure
    function getVoteTypehash() external pure returns (bytes32) {
        return VOTE_TYPEHASH;
    }

    // ============ View Functions ============

    /// @notice Checks if a voter has already voted in the current cycle
    /// @dev Used to determine if a vote would be a recast
    /// @param voter The address to check
    /// @return True if the voter has voted in the current cycle
    function hasVotedInCurrentCycle(address voter) external view returns (bool) {
        uint256 currentCycle = cycleModule.getCurrentCycle();
        return voterCyclePower[currentCycle][voter] > 0;
    }

    /// @notice Gets the voting power a voter used in a specific cycle
    /// @dev Returns 0 if the voter hasn't voted in that cycle
    /// @param cycle The cycle number to check
    /// @param voter The voter's address
    /// @return The voting power used by the voter in that cycle
    function getVoterCyclePower(uint256 cycle, address voter) external view returns (uint256) {
        return voterCyclePower[cycle][voter];
    }

    /// @notice Gets the points distribution a voter submitted in a specific cycle
    /// @dev Returns empty array if the voter hasn't voted in that cycle
    /// @param cycle The cycle number to check
    /// @param voter The voter's address
    /// @return Array of points the voter allocated in that cycle
    function getVoterCyclePoints(uint256 cycle, address voter) external view returns (uint256[] memory) {
        return voterCyclePoints[cycle][voter];
    }

    /// @notice Gets the total voting power used in a specific cycle
    /// @dev Useful for calculating voting participation and weight
    /// @param cycle The cycle number to check
    /// @return The total voting power used in that cycle
    function getTotalCycleVotingPower(uint256 cycle) external view returns (uint256) {
        return totalCycleVotingPower[cycle];
    }

    /// @notice Gets the vote distribution for a specific cycle
    /// @dev Returns the weighted vote totals for each recipient
    /// @param cycle The cycle number to check
    /// @return Array of weighted vote totals for each recipient
    function getProjectDistributions(uint256 cycle) external view returns (uint256[] memory) {
        return projectDistributions[cycle];
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

        // Get voting power from the voting strategy
        uint256 votingPower = _calculateTotalVotingPower(voter);

        // Validate points
        if (!_validateVotePoints(points)) revert InvalidPointsDistribution();

        // Process vote
        _processVote(voter, points, votingPower);

        emit VoteCast(voter, points, votingPower, nonce, signature);
    }

    /// @notice Gets voting power directly from the voting strategies
    /// @dev Queries each configured voting strategy for the account's power
    /// @param account Address to get voting power for
    /// @return totalPower Total voting power from all strategies
    function _calculateTotalVotingPower(address account) internal view returns (uint256) {
        uint256 totalPower = 0;

        // Get voting power directly from each voting strategy
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

            // Revert previous vote's impact on project distributions
            uint256[] storage previousPoints = voterCyclePoints[currentCycle][voter];
            for (uint256 i = 0; i < previousPoints.length; i++) {
                uint256 previousAllocation = (previousVotingPower * previousPoints[i]) / PRECISION;
                projectDistributions[currentCycle][i] -= previousAllocation;
            }
        }

        // Apply new vote
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
