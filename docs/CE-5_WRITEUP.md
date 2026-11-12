# CE-5 — Permissionless Bounty Drain (zkBounty v0.6) + v0.7 Fix

**Severity:** CRITICAL (fund loss, permissionless, no exploit required)
**Status:** v0.6 rentan (live `0x32F8e9Ba3b43586A34F9ba0CB2325433a23943F6`, tiada dana sebenar);
v0.7 TUTUP (35/35 test + slither 0-reentrancy, belum deploy).
**Disahkan:** 12 Nov 2026, fork bytecode v0.6 sebenar (anvil --fork-url Sepolia).

---

## 1. Ringkasan

zkBounty escrow membayar researcher bila mereka reveal ZK-proof "pengetahuan exploit". Masalah
teras: **circuit `exploit_knowledge.circom` cuma buktikan pengetahuan PREIMAGE, bukan exploit sebenar.**
Digabung dengan `forceRelease` (bayar-claimant-atas-timeout tanpa adjudikasi), **sesiapa boleh kuras
mana-mana bounty berdana tanpa memiliki apa-apa exploit** — kos = gas sahaja.

## 2. Punca akar — proof tak attest apa-apa

```
template ExploitKnowledge():
  private: secret, salt          ← prover pilih BEBAS (prove.js: default randField())
  public:  commitment, severity, bounty_id, claimer_addr
  C1: commitment === Poseidon(secret, salt, severity, bounty_id, claimer_addr)
  C2: 1 ≤ severity ≤ 10
  C3: bounty_id ≠ 0, claimer_addr ≠ 0
```

Proof attest: *"aku tahu (secret,salt) yang hash ke commitment ni."* Tiada ikatan ke exploit,
scope, atau apa-apa fakta luar. Prover set `secret=1, salt=1, severity=10, bounty_id=sasaran,
claimer=diri`, kira commitment, jana proof sah. **Kesahihan exploit 100% off-chain** — chain tak
boleh bezakan exploit betul vs preimage sampah. (Ini sebenarnya reka bentuk betul; masalahnya
kontrak v0.6 _auto-bayar_ atas proof sahaja.)

## 3. CE-5 — drain (v0.6)

`forceRelease` (v0.6) membayar `b.researcher` selepas timeout, tanpa companyAccept atau arbitrator:

```solidity
function forceRelease(uint256 bountyId) external nonReentrant bountyExists(bountyId) {
    if (msg.sender != b.researcher) revert Unauthorized();
    bool timeoutPath = (state==PendingCompany) && (now > deadline + claimTimeout);
    bool disputePath = (state==Disputed)       && (now > disputeDeadlines[bountyId]);
    ...
    _safeTransfer(b.researcher, payout);   // ← bayar tanpa afirmasi sesiapa
}
```

Serangan (tiada exploit, tiada kolusi):
```
attacker jana preimage proof → commit → reveal → PendingCompany (b.researcher=attacker)
company diam → now > deadline+claimTimeout → attacker forceRelease → DIKURAS
   (atau company reject → Disputed; arbitrator=0x0 brick resolveDispute; 7 hari → forceRelease disputePath → DIKURAS)
```

Company **takde pertahanan berkesan** pada v0.6 live: `arbitrator()=0x0` (tak pernah di-set),
jadi `resolveDispute` revert `NotArbitrator` — satu-satunya kill-switch mati. companyReject cuma
tambah 7 hari, lepas tu claimant forceRelease.

## 4. Bukti empirik (fork bytecode sebenar)

`ce5_fork.sh` (repeatable): fork Sepolia head terkini → warp lepas unlock → `forceRelease(#4)`
dari wallet test-researcher (yang cuma run prove.js nilai rawak, tiada exploit):

```
baki SEBELUM : 7999999882418504 wei
baki SELEPAS : 8974999881411968 wei
DELTA        : +974999999111880 wei (≈ +0.000975 ETH = reward 0.001 − 2.5% fee), status 1
```

Claimant tanpa exploit sedut dana company yang **tak pernah companyAccept**. Gate satu-satunya =
masa (3× `ClaimTimeoutNotReached` sebelum unlock). CE-5 CONFIRMED.

## 5. Vektor berkaitan

- **CE-3** (arbitrator korup): `resolveDispute(false)` post-deadline → reopen→Active → company
  `refundExpired` claw-back bounty terbukti. Memerlukan arbitrator korup; = kerosakan sebenar H5-1.
- **CE-4** (budget-exhaustion): bakar 2 dispute (MAX_DISPUTE_COUNT=2) → claim ke-3 tak boleh reject →
  forceRelease. Subset CE-5 (sama punca: claim percuma kalahkan pertahanan terhad).

## 6. v0.7 — fix (jalan 1: afirmasi, bukan auto-bayar)

Insight: forceRelease auto-bayar ialah teras drain. **Buang sepenuhnya.** Bayaran HANYA melalui
afirmasi — `companyAccept` atau `resolveDispute(true)` (arbitrator bebas). J1 (company tak boleh
nafi) dilindungi oleh `escalate()` (company ghost → researcher paksa arbitrasi), bukan timeout-drain.

| v0.6 | v0.7 |
|---|---|
| `forceRelease` auto-bayar atas timeout | **DIBUANG** — tiada auto-bayar |
| `arbitrator` settable (`setArbitrator onlyOwner`), live=0x0 | **immutable** constructor, `setArbitrator` DIBUANG |
| claim percuma, tiada kos | **bon** flat (10% reward, min 0.005 ETH) masa reveal |
| dispute ghost → claimant forceRelease | `escalate()` + `disputeTimeout()` fail-safe → **company** |
| forfeit (resolveDispute false) reopen sahaja | forfeit bon → **treasury** (bukan company, elak motif kolusi) |

Kerana forceRelease dibuang, budget-exhaustion (CE-4) + timeout-drain (CE-5) **mati secara struktur**
— bukan sebab bon mahal, tapi sebab **tiada laluan bayar yang tak di-afirmasi**. Bon jadi flat
anti-spam sahaja (bukan escalation kompleks).

## 7. Bukti v0.7 tutup

- `forge test`: **35/35 PASS** (7 v0.7 + 28 v0.6 kekal hijau).
  - `test_CE5_attacker_cannot_drain_via_timeout` PASS → attacker escalate→disputeTimeout dapat **bon
    sendiri sahaja**, reward ke company. Drain GAGAL.
  - `test_honest_paid_via_escalate` PASS → J1 dilindungi.
  - `test_false_forfeits_to_treasury`, `test_dispute_timeout_failsafe_to_company`,
    `test_reveal_requires_bond`, `test_arbitrator_immutable`, `test_CE5_no_self_resolve` PASS.
- `slither src/zkBountyV7.sol`: **0 reentrancy** (CEI fix resolveDispute else). 17 baki
  false-positive/kosmetik (sama fire atas v0.6).

## 8. Residual (BELUM tutup — gate mainnet)

- **Trust arbitrator bebas:** proof tak attest exploit sebenar → kesahihan dihakim off-chain oleh
  arbitrator. v0.7 jadikan arbitrator immutable multisig, TAPI deploy **WAJIB** guna Safe 2-of-3
  **custody berasingan sebenar**. Jika arbitrator = deployer = company (satu entiti), CE-3 masih
  terbuka (arbitrator korup rompak honest + rampas bon). Testnet OK (arbitrator jujur); mainnet
  wajib bebas.
- Arbitrator gagal total → bounty fail-safe refund ke company (hilang availability, BUKAN drain).

## 9. Nota metodologi

Gate correctness v0.7 = **gabungan**: triple-cycle adversarial (tutup yang dilupa) + 35/35 test
(tutup yang ditulis) + compile 0-warning + slither 0-reentrancy. Bukan satu alat.
Pengajaran: v0.6 ada 28/28 test hijau termasuk `test_CRITICAL02_ForceReleaseAfterTimeout` — yang
menguji forceRelease sebagai "betul", sedangkan forceRelease ITULAH CE-5. Test hijau menguji apa
yang ditulis, bukan apa yang dilupa.

---
*Dijana dalam sesi audit AXIOM-CORE. PoC: ce5_fork.sh. Kod: src/zkBountyV7.sol. Test: test/zkBountyV7.t.sol.*
