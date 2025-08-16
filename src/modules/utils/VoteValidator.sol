// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title VoteValidator
/// @notice Utility contract for validating vote parameters
/// @dev Provides validation logic for vote points and cycle states
contract VoteValidator {
    // Errors
    error InvalidPointsDistribution();
    error ExceedsMaxPoints();
    error ZeroVotePoints();
    error InvalidCycleState();
    error VotingNotActive();
    error InvalidNonce();
    error NonceAlreadyUsed();

    /// @notice Validates that points distribution is valid
    /// @param points Array of points to validate
    /// @param maxPoints Maximum allowed points per project
    /// @return True if the distribution is valid
    function validatePointsDistribution(uint256[] calldata points, uint256 maxPoints) external pure returns (bool) {
        if (points.length == 0) return false;

        uint256 totalPoints = 0;

        for (uint256 i = 0; i < points.length; i++) {
            if (points[i] > maxPoints) return false;
            totalPoints += points[i];
        }

        // At least some points must be allocated
        return totalPoints > 0;
    }

    /// @notice Validates the current cycle state
    /// @param currentCycle The current cycle number
    /// @param cycleStart The start block of the current cycle
    /// @param cycleLength The length of a cycle in blocks
    /// @return True if the cycle state is valid for voting
    function validateCycleState(uint256 currentCycle, uint256 cycleStart, uint256 cycleLength)
        external
        view
        returns (bool)
    {
        if (currentCycle == 0) return false;
        if (cycleStart == 0) return false;

        // Check if we're within the voting period of the cycle
        uint256 blocksElapsed = block.number - cycleStart;

        // Voting should be active if we're within the cycle length
        return blocksElapsed < cycleLength;
    }

    /// @notice Validates a signature for vote integrity
    /// @param voter The voter address
    /// @param points The points being voted
    /// @param nonce The nonce for replay protection
    /// @param signature The signature to validate
    /// @param domainSeparator The EIP-712 domain separator
    /// @return True if the signature is valid
    function validateSignature(
        address voter,
        uint256[] calldata points,
        uint256 nonce,
        bytes calldata signature,
        bytes32 domainSeparator
    ) external pure returns (bool) {
        // Create the vote type hash
        bytes32 VOTE_TYPEHASH = keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)");

        // Create the struct hash
        bytes32 structHash = keccak256(abi.encode(VOTE_TYPEHASH, voter, keccak256(abi.encodePacked(points)), nonce));

        // Create the digest
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Recover the signer
        address signer = _recoverSigner(digest, signature);

        return signer == voter;
    }

    // Note: validateNonce is removed as storage mappings cannot be passed as parameters
    // This validation should be done within the contract that owns the mapping

    /// @notice Validates batch vote parameters
    /// @param voters Array of voter addresses
    /// @param pointsArray Array of points arrays
    /// @param nonces Array of nonces
    /// @param signatures Array of signatures
    /// @param maxBatchSize Maximum allowed batch size
    /// @return True if batch parameters are valid
    function validateBatchVoteParameters(
        address[] calldata voters,
        uint256[][] calldata pointsArray,
        uint256[] calldata nonces,
        bytes[] calldata signatures,
        uint256 maxBatchSize
    ) external pure returns (bool) {
        // Check array lengths match
        if (voters.length != pointsArray.length) return false;
        if (voters.length != nonces.length) return false;
        if (voters.length != signatures.length) return false;

        // Check batch size limit
        if (voters.length > maxBatchSize) return false;

        // Check for duplicate voters in batch
        for (uint256 i = 0; i < voters.length; i++) {
            for (uint256 j = i + 1; j < voters.length; j++) {
                if (voters[i] == voters[j]) return false;
            }
        }

        return true;
    }

    /// @notice Validates voting power requirements
    /// @param votingPower The voter's voting power
    /// @param minRequiredPower The minimum required voting power
    /// @return True if voting power meets requirements
    function validateVotingPower(uint256 votingPower, uint256 minRequiredPower) external pure returns (bool) {
        return votingPower >= minRequiredPower;
    }

    // Internal helper functions

    /// @dev Recovers signer address from signature
    function _recoverSigner(bytes32 digest, bytes calldata signature) private pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }

        if (v < 27) {
            v += 27;
        }

        require(v == 27 || v == 28, "Invalid signature v value");

        return ecrecover(digest, v, r, s);
    }
}
