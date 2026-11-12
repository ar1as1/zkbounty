# zkBounty

Trustless ZK exploit disclosure protocol on Ethereum. Researchers prove they found a vulnerability without revealing it — payment settles on-chain before disclosure.

Live: https://zk.egold.dev

## Deployments (Sepolia)

| Contract | Address |
|----------|---------|
| zkBounty v0.6 | `0x32F8e9Ba3b43586A34F9ba0CB2325433a23943F6` |
| ExploitVerifier | `0xb7645218565e27d599cA47D67eB89EF9285C59a2` |

## How it works

1. Company posts bounty, locks ETH in escrow
2. Researcher finds exploit, generates Groth16 proof locally
3. Commits proof hash on-chain (MEV protection)
4. Reveals proof — verified on-chain against the circuit
5. Company accepts → researcher paid, minus 2.5% protocol fee
6. Company rejects → dispute opens (see below)
7. Company ignores → researcher force-releases after timeout

## Dispute resolution

A rejection no longer resets the bounty unilaterally. Instead:

- `companyReject` opens a 7-day dispute window
- A designated arbitrator (separate address from owner) rules either way:
  researcher paid, or bounty reset to active
- If the arbitrator never acts, the researcher can force-release
  after the window closes

Default outcome favors the researcher. No single party — company,
owner, or arbitrator — can trap escrowed funds.

## Contract surface

- Commit-reveal with nonce binding (front-run resistant)
- Proof bound to bountyId + researcher address + severity (replay-proof)
- `MIN_BOUNTY` 0.001 ETH spam floor
- Pausable entry points; payout/refund paths cannot be paused
- Custom reentrancy guard, custom errors throughout

## Stack

- Circuit: Circom 2.2.3 + Groth16
- Prover: SnarkJS 0.7.6
- Contracts: Solidity 0.8.24 + Foundry
- Frontend: React + Vite + ethers.js

## Development

```bash
forge build
forge test   # 28 tests
```

## Roadmap

- Severity rubric enforced in-circuit
- Proof generation via distributed gRPC prover mesh
- Multi-party arbitration
