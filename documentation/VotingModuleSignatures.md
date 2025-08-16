# Voting Module Signature Generation Guide

## Overview

The BreadKit Voting Module uses EIP-712 typed data signatures to enable gasless voting. This guide explains how to generate valid signatures for casting votes.

## EIP-712 Domain

The voting module uses the following EIP-712 domain:

```solidity
{
    name: "BreadKit Voting",
    version: "1",
    chainId: <current_chain_id>,
    verifyingContract: <voting_module_address>
}
```

## Vote Type Definition

The vote structure for EIP-712 signing:

```solidity
struct Vote {
    address voter;
    bytes32 pointsHash;
    uint256 nonce;
}
```

Type hash:
```solidity
bytes32 VOTE_TYPEHASH = keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)");
```

## Signature Generation Examples

### JavaScript/TypeScript (using ethers.js v6)

```typescript
import { ethers } from 'ethers';

async function generateVoteSignature(
    signer: ethers.Signer,
    votingModuleAddress: string,
    points: number[],
    nonce: number
): Promise<string> {
    const voter = await signer.getAddress();
    const chainId = (await signer.provider!.getNetwork()).chainId;
    
    // EIP-712 Domain
    const domain = {
        name: "BreadKit Voting",
        version: "1",
        chainId: chainId,
        verifyingContract: votingModuleAddress
    };
    
    // Type definitions
    const types = {
        Vote: [
            { name: "voter", type: "address" },
            { name: "pointsHash", type: "bytes32" },
            { name: "nonce", type: "uint256" }
        ]
    };
    
    // Calculate points hash
    const pointsHash = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
            ["uint256[]"],
            [points]
        )
    );
    
    // Vote data
    const value = {
        voter: voter,
        pointsHash: pointsHash,
        nonce: nonce
    };
    
    // Generate signature
    const signature = await signer.signTypedData(domain, types, value);
    return signature;
}

// Usage example
async function castVoteWithSignature() {
    const provider = new ethers.JsonRpcProvider("YOUR_RPC_URL");
    const signer = new ethers.Wallet("YOUR_PRIVATE_KEY", provider);
    
    const votingModule = new ethers.Contract(
        VOTING_MODULE_ADDRESS,
        VOTING_MODULE_ABI,
        provider
    );
    
    // Vote distribution: 50 points to project 0, 30 to project 1, 20 to project 2
    const points = [50, 30, 20];
    const nonce = 1; // Can be any unused nonce
    
    // Generate signature
    const signature = await generateVoteSignature(
        signer,
        VOTING_MODULE_ADDRESS,
        points,
        nonce
    );
    
    // Submit vote with signature
    const tx = await votingModule.castVoteWithSignature(
        await signer.getAddress(),
        points,
        nonce,
        signature
    );
    
    await tx.wait();
    console.log("Vote cast successfully!");
}
```

### JavaScript/TypeScript (using viem)

```typescript
import { 
    createWalletClient, 
    createPublicClient, 
    http, 
    keccak256, 
    encodeAbiParameters 
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

async function generateVoteSignatureViem(
    account: any,
    votingModuleAddress: `0x${string}`,
    chainId: number,
    points: bigint[],
    nonce: bigint
): Promise<`0x${string}`> {
    // Calculate points hash
    const pointsHash = keccak256(
        encodeAbiParameters(
            [{ type: 'uint256[]' }],
            [points]
        )
    );
    
    // EIP-712 Domain and types
    const domain = {
        name: 'BreadKit Voting',
        version: '1',
        chainId,
        verifyingContract: votingModuleAddress,
    };
    
    const types = {
        Vote: [
            { name: 'voter', type: 'address' },
            { name: 'pointsHash', type: 'bytes32' },
            { name: 'nonce', type: 'uint256' },
        ],
    };
    
    const message = {
        voter: account.address,
        pointsHash,
        nonce,
    };
    
    const signature = await account.signTypedData({
        domain,
        types,
        primaryType: 'Vote',
        message,
    });
    
    return signature;
}

// Usage example
async function castVoteWithSignatureViem() {
    const account = privateKeyToAccount('0x...');
    const walletClient = createWalletClient({
        account,
        chain: mainnet,
        transport: http(),
    });
    
    const points = [50n, 30n, 20n];
    const nonce = 1n;
    
    const signature = await generateVoteSignatureViem(
        account,
        VOTING_MODULE_ADDRESS,
        1, // chainId
        points,
        nonce
    );
    
    // Submit to contract
    const hash = await walletClient.writeContract({
        address: VOTING_MODULE_ADDRESS,
        abi: votingModuleAbi,
        functionName: 'castVoteWithSignature',
        args: [account.address, points, nonce, signature],
    });
}
```

### Python (using web3.py)

```python
from web3 import Web3
from eth_account import Account
from eth_account.messages import encode_structured_data
import json

def generate_vote_signature(
    private_key: str,
    voting_module_address: str,
    chain_id: int,
    points: list[int],
    nonce: int
) -> str:
    """Generate EIP-712 signature for voting"""
    
    # Create account from private key
    account = Account.from_key(private_key)
    voter = account.address
    
    # Calculate points hash
    w3 = Web3()
    points_encoded = w3.codec.encode(['uint256[]'], [points])
    points_hash = w3.keccak(points_encoded)
    
    # EIP-712 structured data
    structured_data = {
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "version", "type": "string"},
                {"name": "chainId", "type": "uint256"},
                {"name": "verifyingContract", "type": "address"}
            ],
            "Vote": [
                {"name": "voter", "type": "address"},
                {"name": "pointsHash", "type": "bytes32"},
                {"name": "nonce", "type": "uint256"}
            ]
        },
        "primaryType": "Vote",
        "domain": {
            "name": "BreadKit Voting",
            "version": "1",
            "chainId": chain_id,
            "verifyingContract": voting_module_address
        },
        "message": {
            "voter": voter,
            "pointsHash": points_hash.hex(),
            "nonce": nonce
        }
    }
    
    # Sign the structured data
    encoded_data = encode_structured_data(structured_data)
    signed_message = account.sign_message(encoded_data)
    
    return signed_message.signature.hex()

# Usage example
def cast_vote():
    w3 = Web3(Web3.HTTPProvider('YOUR_RPC_URL'))
    
    private_key = 'YOUR_PRIVATE_KEY'
    voting_module_address = '0x...'
    chain_id = 1
    
    # Vote distribution
    points = [50, 30, 20]
    nonce = 1
    
    # Generate signature
    signature = generate_vote_signature(
        private_key,
        voting_module_address,
        chain_id,
        points,
        nonce
    )
    
    # Prepare contract call
    voting_module = w3.eth.contract(
        address=voting_module_address,
        abi=VOTING_MODULE_ABI
    )
    
    account = Account.from_key(private_key)
    
    # Build transaction
    tx = voting_module.functions.castVoteWithSignature(
        account.address,
        points,
        nonce,
        signature
    ).build_transaction({
        'from': account.address,
        'nonce': w3.eth.get_transaction_count(account.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })
    
    # Sign and send transaction
    signed_tx = account.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
    
    print(f"Vote cast! Transaction: {tx_hash.hex()}")
```

## Batch Voting

For batch voting, you need to generate multiple signatures:

```typescript
async function generateBatchVoteSignatures(
    signers: ethers.Signer[],
    votingModuleAddress: string,
    pointsArrays: number[][],
    nonces: number[]
): Promise<string[]> {
    const signatures: string[] = [];
    
    for (let i = 0; i < signers.length; i++) {
        const signature = await generateVoteSignature(
            signers[i],
            votingModuleAddress,
            pointsArrays[i],
            nonces[i]
        );
        signatures.push(signature);
    }
    
    return signatures;
}

// Submit batch
async function castBatchVotes() {
    const voters = [address1, address2, address3];
    const pointsArrays = [[50, 30, 20], [60, 25, 15], [40, 40, 20]];
    const nonces = [1, 1, 1];
    const signatures = await generateBatchVoteSignatures(
        signers,
        VOTING_MODULE_ADDRESS,
        pointsArrays,
        nonces
    );
    
    const tx = await votingModule.castBatchVotesWithSignature(
        voters,
        pointsArrays,
        nonces,
        signatures
    );
    
    await tx.wait();
}
```

## Important Notes

### Nonce Management
- Nonces don't need to be sequential
- Each nonce can only be used once per voter
- Check if a nonce is used: `votingModule.isNonceUsed(voter, nonce)`

### Points Validation
- Total points must be greater than 0
- Each individual point allocation must not exceed `maxPoints`
- Points array length should match the number of projects

### Gas Optimization
- Use batch voting when submitting multiple votes
- Signatures can be generated off-chain to save gas
- Consider using a relayer for true gasless transactions

### Security Considerations
- Never share or expose private keys
- Validate all inputs before signing
- Verify the voting module address before signing
- Check the chain ID matches your intended network

## Troubleshooting

### Common Errors

1. **InvalidSignature**: Ensure domain parameters match exactly
2. **NonceAlreadyUsed**: Use a different nonce
3. **InsufficientVotingPower**: Voter needs minimum voting power
4. **InvalidPointsDistribution**: Check points validation rules

### Verification

To verify a signature off-chain before submission:

```typescript
function verifySignature(
    voter: string,
    points: number[],
    nonce: number,
    signature: string,
    votingModuleAddress: string,
    chainId: number
): boolean {
    const domain = {
        name: "BreadKit Voting",
        version: "1",
        chainId,
        verifyingContract: votingModuleAddress
    };
    
    const types = {
        Vote: [
            { name: "voter", type: "address" },
            { name: "pointsHash", type: "bytes32" },
            { name: "nonce", type: "uint256" }
        ]
    };
    
    const pointsHash = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(["uint256[]"], [points])
    );
    
    const value = {
        voter,
        pointsHash,
        nonce
    };
    
    const recoveredAddress = ethers.verifyTypedData(
        domain,
        types,
        value,
        signature
    );
    
    return recoveredAddress.toLowerCase() === voter.toLowerCase();
}
```

## Contract Integration

### Reading Domain Separator

```typescript
const domainSeparator = await votingModule.DOMAIN_SEPARATOR();
console.log("Domain Separator:", domainSeparator);
```

### Checking Voting Power

```typescript
const votingPower = await votingModule.getTotalVotingPower(voterAddress);
console.log("Voting Power:", votingPower.toString());
```

### Getting Vote Distribution

```typescript
const distribution = await votingModule.getVoterDistribution(voterAddress, cycleNumber);
console.log("Vote Distribution:", distribution);
```