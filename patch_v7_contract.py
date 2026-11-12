#!/usr/bin/env python3
"""
patch_v7_contract.py — GENERATE src/zkBountyV7.sol (contract zkBountyV7) dari
src/zkBounty.sol (v0.6). TIDAK sentuh v0.6 — 28 test sedia ada kekal hijau (R0: v0.7
= fail BARU, additive). Anchor UNIK, THROW kalau tak jumpa/>1. Idempotent. Black run sendiri.

JALAN:  python3 patch_v7_contract.py            # dry-run (semak semua anchor padan)
        python3 patch_v7_contract.py --write     # tulis src/zkBountyV7.sol (fail BARU)
"""
import sys, os, subprocess, datetime

SRC = os.environ.get("SRC_PATH", "src/zkBounty.sol")       # v0.6 — DIBACA sahaja, tak diubah
OUT = os.environ.get("OUT_PATH", "src/zkBountyV7.sol")     # v0.7 — fail baru

def die(m): print(f"FATAL: {m}", file=sys.stderr); sys.exit(1)

def rep(s, old, new, label):
    n = s.count(old)
    if n == 0: die(f"[{label}] anchor TAK JUMPA — source beza dari jangkaan, jangan teka.")
    if n > 1:  die(f"[{label}] anchor AMBIGUOUS ({n}×) — abort.")
    return s.replace(old, new, 1)

# ---- (R1) senarai ubahan, anchor = teks SEBENAR src v0.6 ----
def transform(s):
    # 0. rename contract + interface (elak clash bila v0.6 & v0.7 wujud serentak dalam projek)
    s = rep(s, "contract zkBounty {", "contract zkBountyV7 {", "rename-contract")
    s = rep(s, "interface IExploitVerifier {", "interface IExploitVerifierV7 {", "rename-iface")
    s = rep(s, "IExploitVerifier(verifier)", "IExploitVerifierV7(verifier)", "rename-iface-use")
    # 1. error baru
    s = rep(s,
        "    error MaxDisputesReached();\n",
        "    error MaxDisputesReached();\n    error InsufficientBond();\n",
        "err")
    # 2. pemalar bon/window baru
    s = rep(s,
        "    uint8   public constant MAX_DISPUTE_COUNT  = 2;\n",
        "    uint8   public constant MAX_DISPUTE_COUNT  = 2;\n"
        "    uint16  public constant RESEARCHER_BOND_BPS = 1000;      // 10% reward\n"
        "    uint256 public constant MIN_BOND            = 0.005 ether;\n"
        "    uint256 public constant ARB_WINDOW          = 14 days;\n",
        "const")
    # 3. arbitrator immutable + treasury immutable
    s = rep(s,
        "    address public arbitrator;\n",
        "    address public immutable arbitrator;\n    address public immutable treasury;\n",
        "immutables")
    # 4. event baru (letak selepas ArbitratorUpdated)
    s = rep(s,
        "    event ArbitratorUpdated(address indexed newArbitrator);\n",
        "    event ArbitratorUpdated(address indexed newArbitrator);\n"
        "    event DisputeTimedOut(uint256 indexed bountyId, address indexed researcher, uint256 rewardToCompany);\n"
        "    event BondForfeited(uint256 indexed bountyId, uint256 amount);\n",
        "events")
    # 5. struct Bounty: tambah researcherBond
    s = rep(s,
        "        uint256 commitment;\n    }\n\n    enum BountyState {",
        "        uint256 commitment;\n        uint256 researcherBond;\n    }\n\n    enum BountyState {",
        "struct")
    # 6. constructor: + arbitrator + treasury
    s = rep(s,
        "    constructor(address _verifier, address _feeRecipient) {\n"
        "        if (_verifier == address(0)) revert ZeroAddress();\n"
        "        if (_feeRecipient == address(0)) revert ZeroAddress();\n"
        "        owner        = msg.sender;\n"
        "        verifier     = _verifier;\n"
        "        feeRecipient = _feeRecipient;\n"
        "        _reentrancyStatus = 1;\n"
        "    }\n",
        "    constructor(address _verifier, address _feeRecipient, address _arbitrator, address _treasury) {\n"
        "        if (_verifier == address(0)) revert ZeroAddress();\n"
        "        if (_feeRecipient == address(0)) revert ZeroAddress();\n"
        "        if (_arbitrator == address(0)) revert ZeroAddress();   // arbitrator=0 mustahil (tutup brick v0.6)\n"
        "        if (_treasury == address(0)) revert ZeroAddress();\n"
        "        owner        = msg.sender;\n"
        "        verifier     = _verifier;\n"
        "        feeRecipient = _feeRecipient;\n"
        "        arbitrator   = _arbitrator;   // immutable — tiada swap (H5-1 tutup)\n"
        "        treasury     = _treasury;     // immutable — sink forfeit\n"
        "        _reentrancyStatus = 1;\n"
        "    }\n",
        "constructor")
    # 7. createBounty struct literal: + researcherBond: 0
    s = rep(s,
        "            commitment  : 0\n        });",
        "            commitment  : 0,\n            researcherBond: 0\n        });",
        "createBounty-literal")
    # 8. revealProof -> payable
    s = rep(s,
        "        bytes32 nonce\n    ) external nonReentrant bountyExists(bountyId) {",
        "        bytes32 nonce\n    ) external payable nonReentrant bountyExists(bountyId) {",
        "reveal-payable")
    # 9. revealProof: escrow bon selepas proofValid
    s = rep(s,
        "        if (!proofValid) revert InvalidProof();\n\n        usedCommitment[bountyId][pubSignals[0]] = true;",
        "        if (!proofValid) revert InvalidProof();\n\n"
        "        uint256 need = _requiredBond(b.reward);\n"
        "        if (msg.value < need) revert InsufficientBond();\n"
        "        b.researcherBond = need;\n\n"
        "        usedCommitment[bountyId][pubSignals[0]] = true;",
        "reveal-bond")
    # 10. revealProof: refund excess di hujung (CEI)
    s = rep(s,
        "        emit ProofRevealed(bountyId, msg.sender, pubSignals[0]);\n    }",
        "        emit ProofRevealed(bountyId, msg.sender, pubSignals[0]);\n\n"
        "        uint256 excess = msg.value - need;\n"
        "        if (excess > 0) _safeTransfer(msg.sender, excess);\n    }",
        "reveal-excess")
    # 11. companyAccept: pulang bon
    s = rep(s,
        "        b.state = BountyState.Claimed;\n"
        "        uint256 fee    = (b.reward * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;\n"
        "        uint256 payout = b.reward - fee;\n\n"
        "        emit BountyClaimed(bountyId, b.researcher, payout);\n"
        "        emit CompanyAccepted(bountyId, msg.sender);\n\n"
        "        _safeTransfer(b.researcher, payout);\n"
        "        _safeTransfer(feeRecipient, fee);",
        "        b.state = BountyState.Claimed;\n"
        "        uint256 fee    = (b.reward * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;\n"
        "        uint256 payout = b.reward - fee;\n"
        "        uint256 bond   = b.researcherBond; b.researcherBond = 0;\n\n"
        "        emit BountyClaimed(bountyId, b.researcher, payout);\n"
        "        emit CompanyAccepted(bountyId, msg.sender);\n\n"
        "        _safeTransfer(b.researcher, payout + bond);\n"
        "        _safeTransfer(feeRecipient, fee);",
        "companyAccept-bond")
    # 12. companyReject: DISPUTE_WINDOW -> ARB_WINDOW
    s = rep(s,
        "        disputeDeadlines[bountyId] = block.timestamp + DISPUTE_WINDOW;",
        "        disputeDeadlines[bountyId] = block.timestamp + ARB_WINDOW;",
        "reject-window")
    # 13. resolveDispute: ganti penuh (bon→treasury, buang DisputeWindowClosed, reopen/expire)
    s = rep(s,
        "    function resolveDispute(uint256 bountyId, bool researcherWins) external nonReentrant bountyExists(bountyId) {\n"
        "        if (msg.sender != arbitrator) revert NotArbitrator();\n"
        "        Bounty storage b = bounties[bountyId];\n"
        "        if (b.state != BountyState.Disputed) revert NoActiveDispute();\n"
        "        if (block.timestamp > disputeDeadlines[bountyId]) revert DisputeWindowClosed();\n\n"
        "        delete disputeDeadlines[bountyId];\n\n"
        "        if (researcherWins) {\n"
        "            b.state = BountyState.Claimed;\n"
        "            uint256 fee    = (b.reward * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;\n"
        "            uint256 payout = b.reward - fee;\n\n"
        "            emit DisputeResolved(bountyId, true, msg.sender);\n"
        "            emit BountyClaimed(bountyId, b.researcher, payout);\n\n"
        "            _safeTransfer(b.researcher, payout);\n"
        "            _safeTransfer(feeRecipient, fee);\n"
        "        } else {\n"
        "            // PATCH J1-FR: commitments is now per-(bountyId,epoch,address); a single\n"
        "            // mapping key can't be wiped in Solidity. Bump epoch instead so every old\n"
        "            // commit slot (incl. the losing researcher's own, revealed=true) becomes\n"
        "            // unreachable and the reopened round starts with fresh slots. Old slots\n"
        "            // are orphaned storage, not a fund-safety issue.\n"
        "            commitEpoch[bountyId] += 1;\n"
        "            b.state      = BountyState.Active;\n"
        "            b.researcher = address(0);\n"
        "            b.commitment = 0;\n\n"
        "            emit DisputeResolved(bountyId, false, msg.sender);\n"
        "        }\n"
        "    }\n",
        "    function resolveDispute(uint256 bountyId, bool researcherWins) external nonReentrant bountyExists(bountyId) {\n"
        "        if (msg.sender != arbitrator) revert NotArbitrator();\n"
        "        Bounty storage b = bounties[bountyId];\n"
        "        if (b.state != BountyState.Disputed) revert NoActiveDispute();\n"
        "        // tiada DisputeWindowClosed revert: lepas tingkap, disputeTimeout() yang flip (fail-safe company)\n"
        "        delete disputeDeadlines[bountyId];\n"
        "        uint256 bond = b.researcherBond; b.researcherBond = 0;\n\n"
        "        if (researcherWins) {\n"
        "            b.state = BountyState.Claimed;\n"
        "            uint256 fee    = (b.reward * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;\n"
        "            uint256 payout = b.reward - fee;\n\n"
        "            emit DisputeResolved(bountyId, true, msg.sender);\n"
        "            emit BountyClaimed(bountyId, b.researcher, payout);\n\n"
        "            _safeTransfer(b.researcher, payout + bond);   // reward + bon balik\n"
        "            _safeTransfer(feeRecipient, fee);\n"
        "        } else {\n"
        "            emit DisputeResolved(bountyId, false, msg.sender);\n"
        "            // CEI: SEMUA state write dulu, baru external transfer (elak reentrancy-eth)\n"
        "            if (block.timestamp < b.deadline) {\n"
        "                commitEpoch[bountyId] += 1;\n"
        "                b.state      = BountyState.Active;\n"
        "                b.researcher = address(0);\n"
        "                b.commitment = 0;\n"
        "                if (bond > 0) { emit BondForfeited(bountyId, bond); _safeTransfer(treasury, bond); }\n"
        "            } else {\n"
        "                uint256 r = b.reward; b.reward = 0;\n"
        "                b.state = BountyState.Expired;\n"
        "                if (bond > 0) { emit BondForfeited(bountyId, bond); _safeTransfer(treasury, bond); }\n"
        "                emit BountyRefunded(bountyId, b.company, r);\n"
        "                _safeTransfer(b.company, r);\n"
        "            }\n"
        "        }\n"
        "    }\n",
        "resolveDispute")
    # 14. setArbitrator -> ganti dgn escalate() + disputeTimeout()
    s = rep(s,
        "    function setArbitrator(address newArbitrator) external onlyOwner {\n"
        "        if (newArbitrator == address(0)) revert ZeroAddress();\n"
        "        arbitrator = newArbitrator;\n"
        "        emit ArbitratorUpdated(newArbitrator);\n"
        "    }\n",
        "    function escalate(uint256 bountyId) external nonReentrant bountyExists(bountyId) {\n"
        "        Bounty storage b = bounties[bountyId];\n"
        "        if (msg.sender != b.researcher) revert Unauthorized();\n"
        "        if (b.state != BountyState.PendingCompany) revert BountyNotActive();\n"
        "        if (block.timestamp <= b.deadline + b.claimTimeout) revert ClaimTimeoutNotReached();\n"
        "        b.state = BountyState.Disputed;\n"
        "        disputeDeadlines[bountyId] = block.timestamp + ARB_WINDOW;\n"
        "        emit DisputeOpened(bountyId, msg.sender, disputeDeadlines[bountyId]);\n"
        "    }\n\n"
        "    function disputeTimeout(uint256 bountyId) external nonReentrant bountyExists(bountyId) {\n"
        "        Bounty storage b = bounties[bountyId];\n"
        "        if (b.state != BountyState.Disputed) revert NoActiveDispute();\n"
        "        if (block.timestamp <= disputeDeadlines[bountyId]) revert DisputeNotExpired();\n"
        "        delete disputeDeadlines[bountyId];\n"
        "        uint256 bond = b.researcherBond; b.researcherBond = 0;\n"
        "        uint256 r    = b.reward;         b.reward = 0;\n"
        "        b.state = BountyState.Expired;\n"
        "        emit DisputeTimedOut(bountyId, b.researcher, r);\n"
        "        if (bond > 0) _safeTransfer(b.researcher, bond);   // bon balik (tak di-adjudicate false)\n"
        "        _safeTransfer(b.company, r);                       // reward balik company (fail-safe)\n"
        "    }\n",
        "escalate+disputeTimeout")
    # 15. forceRelease -> ganti dgn _requiredBond helper (buang forceRelease sepenuhnya)
    s = rep(s,
        "    function forceRelease(uint256 bountyId) external nonReentrant bountyExists(bountyId) {\n"
        "        Bounty storage b = bounties[bountyId];\n"
        "        if (msg.sender != b.researcher) revert Unauthorized();\n"
        "        bool timeoutPath = (b.state == BountyState.PendingCompany) && (block.timestamp > b.deadline + b.claimTimeout);\n"
        "        bool disputePath = (b.state == BountyState.Disputed) && (block.timestamp > disputeDeadlines[bountyId]);\n"
        "        if (b.state != BountyState.PendingCompany && b.state != BountyState.Disputed) revert BountyNotActive();\n"
        "        if (!timeoutPath && !disputePath) revert ClaimTimeoutNotReached();\n"
        "        if (disputePath) delete disputeDeadlines[bountyId];\n\n"
        "        b.state = BountyState.ForceReleased;\n"
        "        uint256 fee    = (b.reward * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;\n"
        "        uint256 payout = b.reward - fee;\n\n"
        "        emit ForceRelease(bountyId, b.researcher, payout);\n"
        "        _safeTransfer(b.researcher, payout);\n"
        "        _safeTransfer(feeRecipient, fee);\n"
        "    }\n",
        "    function _requiredBond(uint256 reward) internal pure returns (uint256) {\n"
        "        uint256 pct = (reward * RESEARCHER_BOND_BPS) / BPS_DENOMINATOR;\n"
        "        return pct < MIN_BOND ? MIN_BOND : pct;\n"
        "    }\n",
        "forceRelease->requiredBond")
    # 16. buang canForceRelease (merujuk mekanik yang dah tiada)
    s = rep(s,
        "    function canForceRelease(uint256 bountyId) external view returns (bool) {\n"
        "        Bounty storage b = bounties[bountyId];\n"
        "        return (b.state == BountyState.PendingCompany && block.timestamp > b.deadline + b.claimTimeout)\n"
        "            || (b.state == BountyState.Disputed && block.timestamp > disputeDeadlines[bountyId]);\n"
        "    }\n\n",
        "",
        "remove-canForceRelease")
    return s

def main():
    write = "--write" in sys.argv
    if not os.path.isfile(SRC): die(f"{SRC} (v0.6) tak jumpa (set SRC_PATH?)")
    src = open(SRC, encoding="utf-8").read()
    if "contract zkBountyV7" in src:
        die(f"{SRC} nampak dah v0.7 — ini patutnya v0.6 TULEN. Jangan jalankan atas fail salah.")
    if os.path.isfile(OUT):
        print(f"SKIP: {OUT} dah wujud (idempotent). Padam dulu kalau nak jana semula."); return

    new = transform(src)   # throw automatik kalau mana-mana anchor gagal

    # sanity: v0.7 mesti ada semua simbol ni, dan TIADA forceRelease/setArbitrator function
    for must in ["contract zkBountyV7", "function escalate", "function disputeTimeout",
                 "function _requiredBond", "immutable arbitrator", "immutable treasury", "researcherBond"]:
        if must not in new: die(f"pasca-transform: '{must}' hilang — abort")
    for gone in ["function setArbitrator", "function forceRelease", "function canForceRelease"]:
        if gone in new: die(f"pasca-transform: '{gone}' masih ada — abort")
    if "contract zkBounty {" in new: die("pasca-transform: nama lama 'contract zkBounty' masih ada — abort")

    if not write:
        print("=== DRY-RUN: SEMUA anchor PADAN (tiada throw) ===")
        print(f"v0.6 ({SRC}) TAK disentuh. v0.7 akan ditulis ke: {OUT}")
        print(f"Δ panjang: {len(src)} -> {len(new)} (+{len(new)-len(src)} char)")
        print("v0.7: contract zkBountyV7, escalate/disputeTimeout/_requiredBond ADA; forceRelease/setArbitrator/canForceRelease TIADA.")
        print("Guna --write untuk tulis fail baru."); return

    open(OUT,"w",encoding="utf-8").write(new)
    print(f"OK ditulis fail BARU: {OUT} (contract zkBountyV7). v0.6 {SRC} TAK disentuh (28 test kekal).")
    print("Seterusnya: forge build && forge test --match-contract ZkBountyV7Test -vvv")

if __name__ == "__main__":
    main()
