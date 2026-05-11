# zkBounty — ZK-Proof Bug Bounty Protocol

> Trustless bug bounty escrow with ZK-proof verification on Ethereum.

## Live Deployments (Sepolia)

| Contract | Address |
|----------|---------|
| ExploitVerifier | `0x9bd36F8170728a3b0d98a75e6F379Ce79F3b671A` |
| zkBounty | `0xc2C9aD8ebC619B405Ddb4a75748b93CF7aba1b60` |

## How It Works
1. Company posts bounty + locks ETH
2. Researcher finds exploit, generates ZK proof
3. Commit proof hash on-chain (MEV protection)
4. Reveal proof — contract verifies on-chain
5. Company accepts → researcher gets paid
6. Company ignores → researcher force-releases after timeout

No trust needed. Fully on-chain.

## Stack

- Circuit: Circom 2.2.3 + Groth16
- Prover: SnarkJS 0.7.6
- Contracts: Solidity 0.8.24 + Foundry
- Network: Ethereum Sepolia Testnet
- Frontend: React + Vite + ethers.js + TailwindCSS

## Security

- MEV protection via commit-reveal scheme
- Replay attack prevention via bounty_id + claimer binding
- Force release after claimTimeout (no fund lock)
- abi.encode (no hash collision)
- Reentrancy guard on all state-changing functions

## Quick Start

```bash
git clone https://github.com/ar1as1/zkbounty
cd zkbounty
cp .env.example .env

# Generate proof
node prover-cli/prove.js --bounty 1 --target 42 --severity 4 --min 3

# Claim bounty
node prover-cli/claim.js --bounty 1 --proof proof_bounty_1.json
```

## Tests

```bash
forge test -vvv
# 8/8 passing
```

## Roadmap

- [x] ZK Circuit (Circom + Groth16)
- [x] On-chain Verifier (Sepolia)
- [x] zkBounty Contract (audit fixed)
- [x] Prover CLI
- [x] Frontend React
- [x] Security audit fixes
- [ ] ETHGlobal Prague submission
- [ ] Mainnet deployment
- [ ] ESP Grant application

## Built By

eGold — ZK Security Researcher
BlackArch Linux + ZK Proofs + Web3

---

*Built in the garage. Zero trust. Powered by Groth16.*
