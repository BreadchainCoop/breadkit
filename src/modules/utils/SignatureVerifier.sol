// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @title SignatureVerifier
/// @author BreadKit
/// @notice Utility contract for verifying EIP-712 signatures for votes
/// @dev Implements EIP-712 structured data hashing and ECDSA signature verification.
///      Used for gasless voting where votes are prepared off-chain and submitted with signatures.
contract SignatureVerifier is EIP712 {
    using ECDSA for bytes32;

    // ============ Constants ============

    /// @notice EIP-712 type hash for single vote data structure
    /// @dev Used to create structured hash of vote parameters
    bytes32 public constant VOTE_TYPEHASH = keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)");

    /// @notice EIP-712 type hash for batch vote data structure
    /// @dev Used for batch vote operations (currently unused but available for future use)
    bytes32 public constant BATCH_VOTE_TYPEHASH =
        keccak256("BatchVote(address[] voters,bytes32 pointsHashArray,uint256[] nonces)");

    /// @notice Constructs the signature verifier with EIP-712 domain
    /// @dev Initializes with domain name "BreadKit Voting" and version "1"
    constructor() EIP712("BreadKit Voting", "1") {}

    /// @notice Verifies a vote signature
    /// @param voter The address of the voter
    /// @param points Array of points allocated to projects
    /// @param nonce The nonce for replay protection
    /// @param signature The signature to verify
    /// @return True if the signature is valid
    function verifyVoteSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        external
        view
        returns (bool)
    {
        bytes32 hash = hashVoteData(voter, points, nonce);
        address signer = recoverSigner(hash, signature);
        return signer == voter;
    }

    /// @notice Verifies multiple vote signatures
    /// @param voters Array of voter addresses
    /// @param pointsArray Array of points arrays for each voter
    /// @param nonces Array of nonces for each voter
    /// @param signatures Array of signatures to verify
    /// @return results Array of booleans indicating validity of each signature
    function verifyBatchVoteSignatures(
        address[] calldata voters,
        uint256[][] calldata pointsArray,
        uint256[] calldata nonces,
        bytes[] calldata signatures
    ) external view returns (bool[] memory results) {
        require(
            voters.length == pointsArray.length && voters.length == nonces.length && voters.length == signatures.length,
            "Array length mismatch"
        );

        results = new bool[](voters.length);

        for (uint256 i = 0; i < voters.length; i++) {
            bytes32 hash = hashVoteData(voters[i], pointsArray[i], nonces[i]);
            address signer = recoverSigner(hash, signatures[i]);
            results[i] = (signer == voters[i]);
        }
    }

    /// @notice Hashes vote data according to EIP-712
    /// @param voter The voter address
    /// @param points The points array
    /// @param nonce The nonce
    /// @return The EIP-712 hash of the vote data
    function hashVoteData(address voter, uint256[] calldata points, uint256 nonce) public view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(VOTE_TYPEHASH, voter, keccak256(abi.encodePacked(points)), nonce));
        return _hashTypedDataV4(structHash);
    }

    /// @notice Recovers the signer address from a signature
    /// @param hash The hash that was signed
    /// @param signature The signature
    /// @return The recovered signer address
    function recoverSigner(bytes32 hash, bytes calldata signature) public pure returns (address) {
        return hash.recover(signature);
    }

    /// @notice Returns the domain separator
    /// @return The EIP-712 domain separator
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
