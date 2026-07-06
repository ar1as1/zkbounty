// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../src/zkBounty.sol";

contract MockVerifierArb {
    function verifyProof(
        uint[2] calldata,
        uint[2][2] calldata,
        uint[2] calldata,
        uint[5] calldata
    ) external pure returns (bool) {
        return true;
    }
}

contract ArbitratorTests is Test {
    zkBounty public bounty;
    MockVerifierArb public verifier;
    address company    = address(0x1);
    address researcher = address(0x2);
    address arbitrator = address(0x3);
    address stranger   = address(0x4);
    address owner      = address(this);

    receive() external payable {}

    function setUp() public {
        verifier = new MockVerifierArb();
        bounty = new zkBounty(address(verifier), owner);
        bounty.setArbitrator(arbitrator);
        vm.deal(company, 100 ether);
        vm.deal(researcher, 10 ether);
    }

    // Helper: bawa bounty sampai state PendingCompany
    function _toPendingCompany() internal returns (uint256 id) {
        vm.prank(company);
        id = bounty.createBounty{value: 1 ether}(24, 3 days, 5);

        vm.startPrank(researcher);
        uint[2] memory pA;
        uint[2][2] memory pB;
        uint[2] memory pC;
        uint[5] memory pub;
        pub[0] = 12345;                          // commitment
        pub[1] = 8;                              // severity >= minSeverity(5)
        pub[2] = id;                             // bountyId
        pub[3] = uint256(uint160(researcher));   // researcher address
        pub[4] = block.chainid;                  // chainid
        bytes32 nonce = keccak256("arb-test-nonce");
        bytes32 ch = keccak256(abi.encode(pA, pB, pC, pub, nonce));
        bounty.commitProof(id, ch);
        vm.roll(block.number + 1);
        bounty.revealProof(id, pA, pB, pC, pub, nonce);
        vm.stopPrank();
    }

    function testRejectOpensDispute() public {
        uint256 id = _toPendingCompany();
        vm.prank(company);
        bounty.companyReject(id);

        zkBounty.Bounty memory b = bounty.getBounty(id);
        assertEq(uint8(b.state), uint8(zkBounty.BountyState.Disputed));
        assertEq(bounty.disputeDeadlines(id), block.timestamp + bounty.DISPUTE_WINDOW());
        // Researcher masih tercatat - tak dibuang macam dulu
        assertEq(b.researcher, researcher);
    }

    function testArbitratorResolvesResearcherWins() public {
        uint256 id = _toPendingCompany();
        vm.prank(company);
        bounty.companyReject(id);

        uint256 balBefore = researcher.balance;
        vm.prank(arbitrator);
        bounty.resolveDispute(id, true);

        zkBounty.Bounty memory b = bounty.getBounty(id);
        assertEq(uint8(b.state), uint8(zkBounty.BountyState.Claimed));
        // Payout = 1 ether - 2.5% fee
        assertEq(researcher.balance, balBefore + 1 ether - 0.025 ether);
        assertEq(bounty.disputeDeadlines(id), 0);
    }

    function testArbitratorResolvesCompanyWins() public {
        uint256 id = _toPendingCompany();
        vm.prank(company);
        bounty.companyReject(id);

        vm.prank(arbitrator);
        bounty.resolveDispute(id, false);

        zkBounty.Bounty memory b = bounty.getBounty(id);
        assertEq(uint8(b.state), uint8(zkBounty.BountyState.Active));
        assertEq(b.researcher, address(0));
        assertEq(b.commitment, 0);
    }

    function testNonArbitratorCannotResolve() public {
        uint256 id = _toPendingCompany();
        vm.prank(company);
        bounty.companyReject(id);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("NotArbitrator()"));
        bounty.resolveDispute(id, true);

        // Company pun tak boleh
        vm.prank(company);
        vm.expectRevert(abi.encodeWithSignature("NotArbitrator()"));
        bounty.resolveDispute(id, false);
    }

    function testExpiredDisputeForceRelease() public {
        uint256 id = _toPendingCompany();
        vm.prank(company);
        bounty.companyReject(id);

        // Arbitrator tidur - lepas window, researcher force release
        vm.warp(block.timestamp + 7 days + 1);
        assertTrue(bounty.canForceRelease(id));

        uint256 balBefore = researcher.balance;
        vm.prank(researcher);
        bounty.forceRelease(id);

        zkBounty.Bounty memory b = bounty.getBounty(id);
        assertEq(uint8(b.state), uint8(zkBounty.BountyState.ForceReleased));
        assertEq(researcher.balance, balBefore + 1 ether - 0.025 ether);
    }

    function testArbitratorCannotResolveAfterWindow() public {
        uint256 id = _toPendingCompany();
        vm.prank(company);
        bounty.companyReject(id);

        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(arbitrator);
        vm.expectRevert(abi.encodeWithSignature("DisputeWindowClosed()"));
        bounty.resolveDispute(id, true);
    }

    function testOnlyOwnerSetsArbitrator() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        bounty.setArbitrator(stranger);
    }
}
