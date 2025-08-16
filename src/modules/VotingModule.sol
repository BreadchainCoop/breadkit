// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingModule} from "../interfaces/IVotingModule.sol";
import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";
import {IDistributionModule} from "../interfaces/IDistributionModule.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title VotingModule
/// @notice Main voting module implementation with signature-based voting and multiple strategies
/// @dev Implements EIP-712 compliant signature verification for gasless voting
/// @dev See documentation/VotingModuleSignatures.md for detailed signature generation examples
contract VotingModule is IVotingModule, Initializable, EIP712Upgradeable, OwnableUpgradeable {
    using ECDSA for bytes32;

    // Constants
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_BATCH_SIZE = 100;

    // EIP-712 type hash for vote data
    bytes32 public constant VOTE_TYPEHASH = keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)");

    // Storage
    uint256 public maxPoints;
    uint256 public minRequiredVotingPower;
    uint256 public currentCycle;
    uint256 public lastCycleStart;

    // Voting power strategies
    IVotingPowerStrategy[] public votingPowerStrategies;

    // Vote tracking
    mapping(address => mapping(uint256 => bool)) public usedNonces;
    mapping(address => uint256) public accountLastVoted;
    mapping(address => mapping(uint256 => uint256[])) public voterDistributions;
    mapping(uint256 => uint256[]) public projectDistributions;
    mapping(uint256 => uint256) public cycleVotingPower;
    mapping(uint256 => uint256) public currentVotes;

    // Distribution module reference
    IDistributionModule public distributionModule;

    // Events
    event VoteCastWithSignature(address indexed voter, uint256[] points, uint256 votingPower, uint256 nonce);
    event BatchVotesCast(address[] voters, uint256[] nonces);
    event VotingModuleInitialized(IVotingPowerStrategy[] strategies);
    event CycleStarted(uint256 indexed cycle, uint256 startBlock);
    event DistributionModuleSet(address distributionModule);
    event MinRequiredVotingPowerSet(uint256 minPower);
    event MaxPointsSet(uint256 maxPoints);

    // Errors
    error InvalidSignature();
    error NonceAlreadyUsed();
    error InsufficientVotingPower();
    error InvalidPointsDistribution();
    error ExceedsMaxPoints();
    error ZeroVotePoints();
    error ArrayLengthMismatch();
    error BatchTooLarge();
    error NoStrategiesProvided();
    error InvalidStrategy();
    error NotInVotingPeriod();
    error StartMustBeBeforeEnd();
    error EndAfterCurrentBlock();
    error IncorrectNumberOfProjects();

    /// @notice Initializes the voting module with strategies
    /// @param _maxPoints Maximum points that can be allocated per recipient
    /// @param _strategies Array of voting power strategy contracts
    function initialize(uint256 _maxPoints, IVotingPowerStrategy[] calldata _strategies) external initializer {
        if (_strategies.length == 0) revert NoStrategiesProvided();

        __EIP712_init("BreadKit Voting", "1");
        __Ownable_init(msg.sender);

        maxPoints = _maxPoints;

        for (uint256 i = 0; i < _strategies.length; i++) {
            if (address(_strategies[i]) == address(0)) revert InvalidStrategy();
            votingPowerStrategies.push(_strategies[i]);
        }

        currentCycle = 1;
        lastCycleStart = block.number;

        emit VotingModuleInitialized(_strategies);
    }

    /// @inheritdoc IVotingModule
    /// @dev See documentation/VotingModuleSignatures.md for signature generation examples
    function castVoteWithSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        external
        override
    {
        _castSingleVote(voter, points, nonce, signature);
    }

    /// @inheritdoc IVotingModule
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

    /// @inheritdoc IVotingModule
    function vote(uint256[] calldata points) public override {
        uint256 votingPower = getTotalVotingPower(msg.sender);
        if (votingPower < minRequiredVotingPower) revert InsufficientVotingPower();

        if (!validateVotePoints(points)) revert InvalidPointsDistribution();

        bool hasVotedInCycle = accountLastVoted[msg.sender] > lastCycleStart;
        _processVote(msg.sender, points, votingPower, hasVotedInCycle);
    }

    /// @inheritdoc IVotingModule
    function voteWithMultipliers(uint256[] calldata points, uint256[] calldata multiplierIndices) public override {
        // Implementation for multipliers can be added later
        vote(points);
    }

    /// @inheritdoc IVotingModule
    function castVote(uint256[] calldata points) external override {
        vote(points);
    }

    /// @inheritdoc IVotingModule
    function castVoteWithMultipliers(uint256[] calldata points, uint256[] calldata multiplierIndices)
        external
        override
    {
        voteWithMultipliers(points, multiplierIndices);
    }

    /// @inheritdoc IVotingModule
    function delegate(address delegatee) external override {
        // Delegation is handled at the token level (ERC20Votes)
        // This is a no-op but kept for interface compatibility
    }

    /// @inheritdoc IVotingModule
    function validateVotePoints(uint256[] calldata points) public view override returns (bool) {
        if (points.length == 0) return false;

        uint256 totalPoints;
        for (uint256 i = 0; i < points.length; i++) {
            if (points[i] > maxPoints) return false;
            totalPoints += points[i];
        }

        return totalPoints > 0;
    }

    /// @inheritdoc IVotingModule
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

    /// @inheritdoc IVotingModule
    function getTotalVotingPower(address voter) public view override returns (uint256) {
        uint256 totalPower = 0;

        for (uint256 i = 0; i < votingPowerStrategies.length; i++) {
            totalPower += votingPowerStrategies[i].getCurrentVotingPower(voter);
        }

        return totalPower;
    }

    /// @inheritdoc IVotingModule
    function getVotingPower(address account) external view override returns (uint256) {
        return getTotalVotingPower(account);
    }

    /// @inheritdoc IVotingModule
    function getVotingPowerForPeriod(address account, uint256 start, uint256 end)
        external
        view
        override
        returns (uint256)
    {
        // This would need to be implemented based on specific strategy requirements
        // For now, return current voting power
        return getTotalVotingPower(account);
    }

    /// @inheritdoc IVotingModule
    function getCurrentAccumulatedVotingPower(address account) external view override returns (uint256) {
        uint256 totalPower = 0;

        for (uint256 i = 0; i < votingPowerStrategies.length; i++) {
            totalPower += votingPowerStrategies[i].getAccumulatedVotingPower(account);
        }

        return totalPower;
    }

    /// @inheritdoc IVotingModule
    function getVoterDistribution(address account, uint256 cycle) external view override returns (uint256[] memory) {
        return voterDistributions[account][cycle];
    }

    /// @inheritdoc IVotingModule
    function getTotalVotingPowerForCycle(uint256 cycle) external view override returns (uint256) {
        return cycleVotingPower[cycle];
    }

    /// @inheritdoc IVotingModule
    function getCurrentVotingDistribution() external view override returns (uint256[] memory) {
        return projectDistributions[currentCycle];
    }

    /// @inheritdoc IVotingModule
    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc IVotingModule
    function isNonceUsed(address voter, uint256 nonce) external view override returns (bool) {
        return usedNonces[voter][nonce];
    }

    /// @inheritdoc IVotingModule
    function getVotingPowerStrategies() external view override returns (IVotingPowerStrategy[] memory) {
        return votingPowerStrategies;
    }

    /// @inheritdoc IVotingModule
    function setMinRequiredVotingPower(uint256 _minRequiredVotingPower) external override onlyOwner {
        minRequiredVotingPower = _minRequiredVotingPower;
        emit MinRequiredVotingPowerSet(_minRequiredVotingPower);
    }

    /// @inheritdoc IVotingModule
    function setMaxPoints(uint256 _maxPoints) external override onlyOwner {
        maxPoints = _maxPoints;
        emit MaxPointsSet(_maxPoints);
    }

    /// @notice Sets the distribution module address
    /// @param _distributionModule Address of the distribution module
    function setDistributionModule(address _distributionModule) external onlyOwner {
        distributionModule = IDistributionModule(_distributionModule);
        emit DistributionModuleSet(_distributionModule);
    }

    /// @notice Starts a new voting cycle
    function startNewCycle() external onlyOwner {
        currentCycle++;
        lastCycleStart = block.number;
        emit CycleStarted(currentCycle, block.number);
    }

    // Internal functions

    function _castSingleVote(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        internal
    {
        // Validate and consume nonce
        if (usedNonces[voter][nonce]) revert NonceAlreadyUsed();
        usedNonces[voter][nonce] = true;

        // Verify signature
        if (!validateSignature(voter, points, nonce, signature)) {
            revert InvalidSignature();
        }

        // Get total voting power and validate
        uint256 votingPower = getTotalVotingPower(voter);
        if (votingPower < minRequiredVotingPower) revert InsufficientVotingPower();

        // Validate points
        if (!validateVotePoints(points)) revert InvalidPointsDistribution();

        // Process vote
        bool hasVotedInCycle = accountLastVoted[voter] > lastCycleStart;
        _processVote(voter, points, votingPower, hasVotedInCycle);

        emit VoteCastWithSignature(voter, points, votingPower, nonce);
    }

    function _processVote(address voter, uint256[] calldata points, uint256 votingPower, bool hasVotedInCycle)
        internal
    {
        // Store voter distributions for this cycle
        uint256[] storage distributions = voterDistributions[voter][currentCycle];

        if (!hasVotedInCycle) {
            // First vote in cycle - clear old distributions
            delete voterDistributions[voter][currentCycle];
            currentVotes[currentCycle] += votingPower;
            cycleVotingPower[currentCycle] += votingPower;
        } else {
            // Recasting vote - subtract old distributions
            uint256[] memory oldDistributions = distributions;
            for (uint256 i = 0; i < oldDistributions.length && i < projectDistributions[currentCycle].length; i++) {
                projectDistributions[currentCycle][i] -= oldDistributions[i];
            }
            delete voterDistributions[voter][currentCycle];
        }

        // Calculate and store new distributions
        for (uint256 i = 0; i < points.length; i++) {
            uint256 allocation = (votingPower * points[i]) / PRECISION;
            distributions.push(allocation);

            // Update project distributions
            if (i >= projectDistributions[currentCycle].length) {
                projectDistributions[currentCycle].push(allocation);
            } else {
                projectDistributions[currentCycle][i] += allocation;
            }
        }

        // Update last voted block
        accountLastVoted[voter] = block.number;

        // Update distribution module if set
        if (address(distributionModule) != address(0)) {
            // distributionModule would handle the actual distribution logic
        }
    }
}
