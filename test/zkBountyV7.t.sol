// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// AXIOM-CORE: test ENCODE invariant v0.7 (jalan 1). Verifier test = AlwaysTrueVerifier =
// MODEL TEPAT realiti CE-5 (circuit preimage-only: apa-apa proof verify). Jadi proof boleh
// zeros; yang penting pub-signals + commitHash padan. Soundness circuit = kerja prover-cli,
// bukan fail ni.
import "forge-std/Test.sol";
import "../src/zkBountyV7.sol";

contract AlwaysTrueVerifier {
    function verifyProof(uint[2] calldata, uint[2][2] calldata, uint[2] calldata, uint[4] calldata)
        external pure returns (bool) { return true; }
}

contract ZkBountyV7Test is Test {
    zkBountyV7 zk;
    AlwaysTrueVerifier verifier;

    address company    = makeAddr("company");     // = owner/deployer
    address arbitrator = makeAddr("arbitrator");   // multisig bebas (independent)
    address treasury   = makeAddr("treasury");
    address feeRecip   = makeAddr("feeRecip");
    address researcher = makeAddr("researcher");
    address attacker   = makeAddr("attacker");

    uint256 constant REWARD = 1 ether;

    function setUp() public {
        verifier = new AlwaysTrueVerifier();
        vm.prank(company);
        zk = new zkBountyV7(address(verifier), feeRecip, arbitrator, treasury);
        vm.deal(company, 100 ether);
        vm.deal(researcher, 10 ether);
        vm.deal(attacker, 10 ether);
    }

    // Helper: create + commit + reveal (proof preimage, bond di-escrow) -> PendingCompany.
    function _createAndClaim(address claimer, uint256 bond) internal returns (uint256 id) {
        vm.prank(company);
        id = zk.createBounty{value: REWARD}(72, 7 days, 1);
        uint[2] memory pA; uint[2][2] memory pB; uint[2] memory pC;   // zeros (AlwaysTrueVerifier)
        uint[4] memory pub;
        pub[0] = uint256(keccak256(abi.encodePacked(claimer, id, bond)));  // commitment unik
        pub[1] = 10;                           // severity >= minSeverity(1)
        pub[2] = id;                           // bountyId
        pub[3] = uint256(uint160(claimer));    // claimer
        bytes32 nonce = bytes32(uint256(1));
        bytes32 commitHash = keccak256(abi.encode(pA, pB, pC, pub, nonce));
        vm.prank(claimer); zk.commitProof(id, commitHash);
        vm.prank(claimer); zk.revealProof{value: bond}(id, pA, pB, pC, pub, nonce);
    }

    function _bond() internal pure returns (uint256) {
        uint256 pct = REWARD * 1000 / 10_000;      // RESEARCHER_BOND_BPS
        uint256 floorB = 0.005 ether;              // MIN_BOND
        return pct < floorB ? floorB : pct;
    }

    // ---- INVARIANT 1: CE-5 drain MUSTAHIL (claimant tanpa afirmasi tak dibayar reward) ----
    function test_CE5_attacker_cannot_drain_via_timeout() public {
        uint256 bond = _bond();
        uint256 id = _createAndClaim(attacker, bond);
        uint256 balBefore = attacker.balance;                 // sudah tolak bond (dibayar masa reveal)

        // company GHOST — tiada forceRelease (dibuang). Attacker escalate ke arbitrator.
        vm.warp(block.timestamp + 72 hours + 7 days + 1);
        vm.prank(attacker); zk.escalate(id);

        // arbitrator ghost juga -> sesiapa disputeTimeout -> reward ke COMPANY, bond balik attacker
        vm.warp(block.timestamp + 14 days + 1);
        zk.disputeTimeout(id);

        assertEq(attacker.balance, balBefore + bond, "attacker only recovers own bond, NO reward");
    }

    // attacker tak boleh self-resolve (tiada authority arbitrator)
    function test_CE5_no_self_resolve() public {
        uint256 id = _createAndClaim(attacker, _bond());
        vm.warp(block.timestamp + 72 hours + 7 days + 1);
        vm.prank(attacker); zk.escalate(id);
        vm.prank(attacker);
        vm.expectRevert(zkBountyV7.NotArbitrator.selector);
        zk.resolveDispute(id, true);
    }

    // ---- INVARIANT 2: arbitrator immutable, tiada setter ----
    function test_arbitrator_immutable() public view {
        assertEq(zk.arbitrator(), arbitrator);
        assertEq(zk.treasury(), treasury);
        // setArbitrator DIBUANG -> baris ni takkan compile kalau di-uncomment (bukti tiada setter):
        // zk.setArbitrator(attacker);
    }

    // ---- INVARIANT 3: honest researcher dibayar via escalate (J1) ----
    function test_honest_paid_via_escalate() public {
        uint256 bond = _bond();
        uint256 id = _createAndClaim(researcher, bond);
        uint256 before = researcher.balance;
        vm.warp(block.timestamp + 72 hours + 7 days + 1);
        vm.prank(researcher); zk.escalate(id);
        vm.prank(arbitrator); zk.resolveDispute(id, true);
        uint256 fee = REWARD * 250 / 10_000;                  // PLATFORM_FEE_BPS
        assertEq(researcher.balance, before + (REWARD - fee) + bond, "reward(-fee) + bond balik");
    }

    // ---- INVARIANT 4: resolveDispute(false) -> forfeit ke TREASURY, bukan company ----
    function test_false_forfeits_to_treasury() public {
        uint256 bond = _bond();
        uint256 id = _createAndClaim(attacker, bond);
        uint256 tBefore = treasury.balance;
        vm.prank(company); zk.companyReject(id);
        vm.prank(arbitrator); zk.resolveDispute(id, false);   // sebelum deadline -> reopen, bond->treasury
        assertEq(treasury.balance, tBefore + bond, "bond forfeit ke treasury");
    }

    // ---- INVARIANT 5: disputeTimeout fail-safe -> reward company, bond researcher ----
    function test_dispute_timeout_failsafe_to_company() public {
        uint256 bond = _bond();
        uint256 id = _createAndClaim(researcher, bond);
        uint256 cBefore = company.balance;
        uint256 rBefore = researcher.balance;
        vm.prank(company); zk.companyReject(id);
        vm.warp(block.timestamp + 14 days + 1);
        zk.disputeTimeout(id);
        assertEq(company.balance, cBefore + REWARD, "reward balik company");
        assertEq(researcher.balance, rBefore + bond, "bond balik researcher");
    }

    // ---- INVARIANT 6: reveal tolak bon kurang ----
    function test_reveal_requires_bond() public {
        uint256 need = _bond();
        vm.prank(company);
        uint256 id = zk.createBounty{value: REWARD}(72, 7 days, 1);
        uint[2] memory pA; uint[2][2] memory pB; uint[2] memory pC;
        uint[4] memory pub;
        pub[0] = uint256(keccak256(abi.encodePacked(attacker, id)));
        pub[1] = 10; pub[2] = id; pub[3] = uint256(uint160(attacker));
        bytes32 nonce = bytes32(uint256(1));
        bytes32 commitHash = keccak256(abi.encode(pA, pB, pC, pub, nonce));
        vm.prank(attacker); zk.commitProof(id, commitHash);
        vm.prank(attacker);
        vm.expectRevert(zkBountyV7.InsufficientBond.selector);
        zk.revealProof{value: need - 1}(id, pA, pB, pC, pub, nonce);
    }
}
