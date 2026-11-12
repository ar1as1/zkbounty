# zkBounty v0.7 — CHANGE SPEC (apply atas src/zkBounty.sol v0.6 sebenar kau)

> AXIOM-CORE R1: patch minimal, anchor unik, edit bawah→atas (line number tak gerak).
> Aku TAK nampak 100% source v0.6 kau (createBounty/commitProof body penuh, _safeTransfer,
> modifier onlyCompany/onlyOwner, senarai error). Jadi ini CHANGE SPEC — kau reconcile dgn
> source sebenar. JANGAN whole-rewrite (Pengajaran #9). Setiap fungsi di bawah = ganti/tambah
> yang DINYATAKAN sahaja.
> BELUM compile dari sisi aku (takde forge+bridge). CARA UJI (fail test) yang sahkan.

---

## 0. Pemalar + state var baru (bahagian atas kontrak)

```solidity
// --- BARU ---
uint16  public constant RESEARCHER_BOND_BPS = 1000;        // 10% reward
uint256 public constant MIN_BOND            = 0.005 ether; // floor spam-deterrent
uint256 public constant ARB_WINDOW          = 14 days;     // tingkap arbitrator rule
address public immutable arbitrator;                       // GANTI `address public arbitrator;`
address public immutable treasury;                         // sink forfeit bon
// MAX_DISPUTE_COUNT, DISPUTE_WINDOW, disputeCount, disputeDeadlines, commitEpoch — KEKAL dari v0.6
```

Tambah ke `struct Bounty { ... }`:
```solidity
    uint256 researcherBond;   // bon yang di-escrow oleh researcher masa reveal
```

Tambah error (kalau belum ada):
```solidity
error InsufficientBond();
error DisputeWindowNotClosed();
error NotDisputed();
```
Tambah event:
```solidity
event DisputeTimedOut(uint256 indexed bountyId, address indexed researcher, uint256 rewardToCompany);
event BondForfeited(uint256 indexed bountyId, uint256 amount);
```

---

## 1. constructor — tambah arbitrator + treasury immutable, validasi ≠0 (R3: throw, bukan teka)

GANTI constructor v0.6:
```solidity
constructor(
    address _verifier,
    address _feeRecipient,
    address _arbitrator,
    address _treasury
) {
    if (_verifier == address(0))     revert ZeroAddress();
    if (_feeRecipient == address(0)) revert ZeroAddress();
    if (_arbitrator == address(0))   revert ZeroAddress();   // arbitrator=0 mustahil (tutup brick live v0.6)
    if (_treasury == address(0))     revert ZeroAddress();
    owner             = msg.sender;
    verifier          = _verifier;
    feeRecipient      = _feeRecipient;
    arbitrator        = _arbitrator;     // immutable — tiada swap (H5-1 tutup struktur)
    treasury          = _treasury;       // immutable — sink forfeit
    _reentrancyStatus = 1;
}
```

## 2. BUANG setArbitrator SEPENUHNYA

Padam fungsi `setArbitrator(address) external onlyOwner { ... }` (v0.6 line ~307-311) + event `ArbitratorUpdated` kalau tiada guna lain. Tiada setter = tiada swap-mid-dispute.

## 3. BUANG forceRelease SEPENUHNYA

Padam fungsi `forceRelease(uint256) external nonReentrant ... { ... }` (v0.6 line ~313-32x).
Ini kunci mati CE-5/CE-4: tiada lagi auto-bayar-claimant atas timeout.

## 4. revealProof — jadikan `payable`, escrow bon (CEI: refund excess di hujung)

Pada signature tambah `payable`. SELEPAS semua check sedia ada LULUS dan SEBELUM set state,
tambah (R3: kesan sampingan selepas validasi):
```solidity
    // --- BARU: escrow bon ---
    uint256 need = _requiredBond(b.reward);
    if (msg.value < need) revert InsufficientBond();
    b.researcherBond = need;
```
Dan di HUJUNG fungsi (selepas `b.state = PendingCompany;` dan emit), refund lebihan:
```solidity
    uint256 excess = msg.value - need;
    if (excess > 0) _safeTransfer(msg.sender, excess);   // CEI: state dah set sebelum transfer
```
Tambah helper:
```solidity
function _requiredBond(uint256 reward) internal pure returns (uint256) {
    uint256 pct = (reward * RESEARCHER_BOND_BPS) / BPS_DENOMINATOR;
    return pct < MIN_BOND ? MIN_BOND : pct;
}
```

## 5. companyAccept — pulang bon + reward (R1: tambah 2 baris pada body sedia ada)

Dalam companyAccept, GANTI blok bayar supaya pulang bon:
```solidity
    b.state = BountyState.Claimed;
    uint256 fee    = (b.reward * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
    uint256 payout = b.reward - fee;
    uint256 bond   = b.researcherBond; b.researcherBond = 0;   // BARU
    emit BountyClaimed(bountyId, b.researcher, payout);
    _safeTransfer(b.researcher, payout + bond);                // BARU: + bond
    _safeTransfer(feeRecipient, fee);
```

## 6. escalate() — BARU (company ghost → researcher paksa arbitrasi; ganti J1 tanpa drain)

```solidity
function escalate(uint256 bountyId) external nonReentrant bountyExists(bountyId) {
    Bounty storage b = bounties[bountyId];
    if (msg.sender != b.researcher) revert Unauthorized();
    if (b.state != BountyState.PendingCompany) revert BountyNotActive();
    if (block.timestamp <= b.deadline + b.claimTimeout) revert ClaimTimeoutNotReached();
    b.state = BountyState.Disputed;
    disputeDeadlines[bountyId] = block.timestamp + ARB_WINDOW;
    emit DisputeOpened(bountyId, msg.sender, disputeDeadlines[bountyId]);
}
```
(Tidak increment disputeCount — ini escalation researcher, bukan dispute company.)

## 7. companyReject — set tingkap arbitrator = ARB_WINDOW (kekal MAX cap)

Pastikan `disputeDeadlines[bountyId] = block.timestamp + ARB_WINDOW;` (ganti DISPUTE_WINDOW
kalau kau mahu satu tingkap konsisten; atau kekal DISPUTE_WINDOW — pilih satu dan selaraskan
dgn disputeTimeout). Guard `disputeCount >= MAX_DISPUTE_COUNT` KEKAL.

## 8. resolveDispute — bon handling + BUANG DisputeWindowClosed-favouring-claimant

GANTI body v0.6:
```solidity
function resolveDispute(uint256 bountyId, bool researcherWins)
    external nonReentrant bountyExists(bountyId)
{
    if (msg.sender != arbitrator) revert NotArbitrator();
    Bounty storage b = bounties[bountyId];
    if (b.state != BountyState.Disputed) revert NotDisputed();
    // NOTA: TIADA lagi `if (now > disputeDeadlines) revert DisputeWindowClosed` —
    // lepas tingkap, disputeTimeout() yang flip state (fail-safe company), bukan auto-claimant.
    delete disputeDeadlines[bountyId];
    uint256 bond = b.researcherBond; b.researcherBond = 0;

    if (researcherWins) {
        b.state = BountyState.Claimed;
        uint256 fee    = (b.reward * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 payout = b.reward - fee;
        emit DisputeResolved(bountyId, true, msg.sender);
        emit BountyClaimed(bountyId, b.researcher, payout);
        _safeTransfer(b.researcher, payout + bond);   // reward + bon balik
        _safeTransfer(feeRecipient, fee);
    } else {
        emit DisputeResolved(bountyId, false, msg.sender);
        if (bond > 0) { emit BondForfeited(bountyId, bond); _safeTransfer(treasury, bond); } // forfeit→TREASURY
        if (block.timestamp < b.deadline && disputeCount[bountyId] < MAX_DISPUTE_COUNT) {
            // reopen — researcher lain boleh cuba (hanya kalau masih boleh re-commit sebelum deadline)
            commitEpoch[bountyId] += 1;
            b.state      = BountyState.Active;
            b.researcher = address(0);
            b.commitment = 0;
        } else {
            // tak boleh reopen (deadline lepas / max dispute) → refund company, tiada clawback-theft
            uint256 r = b.reward; b.reward = 0;
            b.state = BountyState.Expired;
            emit BountyRefunded(bountyId, b.company, r);
            _safeTransfer(b.company, r);
        }
    }
}
```

## 9. disputeTimeout() — BARU (fail-safe liveness; sesiapa boleh panggil lepas ARB_WINDOW)

```solidity
function disputeTimeout(uint256 bountyId) external nonReentrant bountyExists(bountyId) {
    Bounty storage b = bounties[bountyId];
    if (b.state != BountyState.Disputed) revert NotDisputed();
    if (block.timestamp <= disputeDeadlines[bountyId]) revert DisputeWindowNotClosed();
    // arbitrator gagal rule dalam ARB_WINDOW → FAIL-SAFE ke company (tiada drain ke claimant)
    delete disputeDeadlines[bountyId];
    uint256 bond = b.researcherBond; b.researcherBond = 0;
    uint256 r    = b.reward;         b.reward = 0;
    b.state = BountyState.Expired;
    emit DisputeTimedOut(bountyId, b.researcher, r);
    if (bond > 0) _safeTransfer(b.researcher, bond);   // bon researcher balik (tak di-adjudicate false)
    _safeTransfer(b.company, r);                        // reward balik company (fail-safe)
}
```

## 10. refundExpired — KEKAL (Active + >deadline → refund company). Selamat sebab tiada reveal
boleh force-bayar lagi. Tiada perubahan diperlukan.

---

## INVARIANT yang test MESTI buktikan (lihat zkBountyV7.t.sol)
1. Tiada laluan `_safeTransfer(researcher, reward)` selain companyAccept / resolveDispute(true).
2. arbitrator immutable — tiada setter; getter kekal 0x…multisig.
3. resolveDispute(false) → bon ke treasury, BUKAN company/researcher.
4. disputeTimeout → reward ke company, bon balik researcher, tiada ke pihak ke-3.
5. escalate hanya oleh researcher, hanya lepas claimTimeout, dari PendingCompany.
6. reveal tolak kalau msg.value < requiredBond.
