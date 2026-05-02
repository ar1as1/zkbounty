# zkBounty

Zero-knowledge exploit disclosure protocol on Ethereum.

Prove you found a bug. Get paid. Reveal after.

## The Problem

Bug bounty has a trust problem — researchers must reveal exploits before getting paid. Companies can take the exploit without paying. zkBounty fixes this with ZK proofs.

## How It Works

1. Company posts bounty + locks ETH in escrow
2. Researcher finds exploit, generates ZK proof
3. Proof submitted on-chain — exploit stays hidden
4. Contract verifies proof, ETH locked for researcher
5. Company releases payment
6. Researcher reveals full exploit

No middleman. No trust needed.

## Stack

- Circom + Groth16 — ZK circuit
- SnarkJS — proof generation
- Solidity + Foundry — smart contracts
- React + ethers.js — frontend

## Contracts (Sepolia)

- ExploitVerifier: `0x77C2d9d22193cB8099153fE8C7b8c33317186978`
- BountyEscrow: `0x1E1668c1E53C108607734283C6be83348063B8E5`

## Usage

```bash
# Generate proof
node prover-cli/prove.js --bounty 0 --target 42 --severity 4

# Claim bounty
node prover-cli/claim.js --bounty 0 --proof proof_bounty_0.json
```

## Built by

eGold — BlackArch Linux · ZK Proofs · Web3
