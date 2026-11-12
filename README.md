# zkBounty

Trustless ZK exploit disclosure protocol on Ethereum. Researchers prove they found a vulnerability without revealing it — payment settles on-chain, affirmed by the company or an independent arbitrator, before disclosure.

Live: https://zk.egold.dev

## Deployments (Sepolia)

| Contract | Address |
|----------|---------|
| zkBountyV7 (current) | `0x47931cfB7E5d29a20f76941E6F180AA4cBa119eF` |
| ExploitVerifier | `0xb7645218565e27d599cA47D67eB89EF9285C59a2` |
| zkBounty v0.6 (superseded) | `0x32F8e9Ba3b43586A34F9ba0CB2325433a23943F6` |

## How it works

1. Company posts a bounty, locks ETH in escrow.
2. Researcher finds an exploit, generates a Groth16 proof locally.
3. Commits the proof hash on-chain (front-run / MEV protection).
4. Reveals the proof, locking a refundable bond — verified on-chain against the circuit.
5. Company accepts → researcher is paid the reward minus a 2.5% protocol fee, plus the bond back.
6. Company ignores the claim → after the claim timeout the researcher escalates to the arbitrator.
7. Company rejects → a dispute opens (see below).

Payment only ever settles when **affirmed** — there is no unilateral timeout payout.

## Dispute resolution

The ZK proof attests knowledge of a commitment, not that an exploit is real or in-scope — that judgement is made off-chain. Payment is therefore gated on affirmation, not a timer:

- `companyReject`, or researcher `escalate` after the claim timeout, opens an arbitration window.
- An independent arbitrator — immutable, set at deploy, a separate address from the owner — rules either way: researcher paid, or the claim is reset / the reward refunded.
- A losing claim forfeits the researcher's bond to the treasury (never to the company), so the company gains nothing from a rejection.
- If the arbitrator never acts, `disputeTimeout` refunds the company — a safe default, never a payout to an unadjudicated claim.

No single party — company, owner, or arbitrator — can seize escrowed funds, and no claim is ever paid without an affirmative accept or arbitrator ruling.

## Contract surface

- Commit-reveal with nonce binding (front-run resistant).
- Proof bound to bountyId + researcher address + severity (replay- and reveal-snipe-proof).
- Affirmation-only payment — `companyAccept` or `resolveDispute(true)`; no unadjudicated auto-payout.
- Researcher bond at reveal = max(10% of reward, 0.005 ETH); refunded on payout, forfeited to the treasury on an invalid ruling.
- Immutable `arbitrator` and `treasury`; `MIN_BOUNTY` 0.001 ETH spam floor.
- Pausable entry points; payout/refund paths cannot be paused.
- Custom reentrancy guard (checks-effects-interactions), custom errors throughout.

See [`docs/CE-5_WRITEUP.md`](docs/CE-5_WRITEUP.md) for the audit that motivated v0.7.

## Stack

- Circuit: Circom 2.2.3 + Groth16
- Prover: SnarkJS 0.7.6
- Contracts: Solidity 0.8.24 + Foundry
- Frontend: React + Vite + ethers.js

## Development

```bash
forge build
forge test                      # 35 tests (v0.7) + v0.6 regression suite
slither src/zkBountyV7.sol      # static analysis
```

## Roadmap

- Severity rubric enforced in-circuit
- Proof generation via distributed gRPC prover mesh
- Independent multi-party arbitration (Safe 2-of-3 / Kleros) for mainnet

---

Built by mrZk @ka eGold — ZK security research. BlackArch Linux + ZK proofs + Web3.
