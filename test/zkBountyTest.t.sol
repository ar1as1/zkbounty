// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/zkBounty.sol";

contract MockVerifier {
    bool public shouldPass = true;
    function setPass(bool v) external { shouldPass = v; }
    function verifyProof(
        uint[2] calldata,
        uint[2][2] calldata,
        uint[2] calldata,
        uint[5] calldata
    ) external view returns (bool) {
        return shouldPass;
    }
}

contract zkBountyTest is Test {
    zkBounty     public bountyContract;
    MockVerifier public mockVerifier;

    address company    = makeAddr("company");
    address researcher = makeAddr("researcher");
    address mevBot     = makeAddr("mevBot");
    address feeRecip   = makeAddr("feeRecipient");

    uint256 REWARD        = 1 ether;
    uint256 DEADLINE_HRS  = 72;
    uint256 CLAIM_TIMEOUT = 7 days;

    function setUp() public {
        mockVerifier   = new MockVerifier();
        bountyContract = new zkBounty(address(mockVerifier), feeRecip);
        vm.deal(company,    10 ether);
        vm.deal(researcher, 1 ether);
        vm.deal(mevBot,     1 ether);
    }

    function _createBounty() internal returns (uint256) {
        vm.prank(company);
        return bountyContract.createBounty{value: REWARD}(
            DEADLINE_HRS, CLAIM_TIMEOUT, 5
        );
    }

    function _buildPubSignals(uint256 bountyId, address claimer)
        internal pure returns (uint[5] memory)
    {
        return [uint(0xDEADBEEF), uint(7), bountyId, uint256(uint160(claimer)), uint(1)];
    }

    function _makeCommitHash(uint256 bountyId, address claimer, bytes32 nonce)
        internal pure returns (bytes32)
    {
        uint[2] memory pA = [uint(1), uint(2)];
        uint[2][2] memory pB = [[uint(3), uint(4)], [uint(5), uint(6)]];
        uint[2] memory pC = [uint(7), uint(8)];
        uint[5] memory pub = _buildPubSignals(bountyId, claimer);
        return keccak256(abi.encode(pA, pB, pC, pub, nonce));
    }

    function test_HIGH01_DeadlineOverflow() public {
        vm.prank(company);
        vm.expectRevert(zkBounty.InvalidDeadline.selector);
        bountyContract.createBounty{value: REWARD}(999_999, CLAIM_TIMEOUT, 5);
    }

    function test_HIGH01_ZeroDeadline() public {
        vm.prank(company);
        vm.expectRevert(zkBounty.InvalidDeadline.selector);
        bountyContract.createBounty{value: REWARD}(0, CLAIM_TIMEOUT, 5);
    }

    function test_CRITICAL02_TimeoutTooShort() public {
        vm.prank(company);
        vm.expectRevert(zkBounty.InvalidTimeout.selector);
        bountyContract.createBounty{value: REWARD}(DEADLINE_HRS, 1 hours, 5);
    }

    function test_CRITICAL01_MEVCannotFrontRun() public {
        uint256 id = _createBounty();
        bytes32 nonce = bytes32(uint256(0xBEEF));
        bytes32 ch = _makeCommitHash(id, researcher, nonce);

        vm.prank(researcher);
        bountyContract.commitProof(id, ch);

        vm.prank(mevBot);
        vm.expectRevert(zkBounty.BountyNotActive.selector);
        bountyContract.commitProof(id, ch);
    }

    function test_CRITICAL01_WrongRevealerFails() public {
        uint256 id = _createBounty();
        bytes32 nonce = bytes32(uint256(0xBEEF));
        bytes32 ch = _makeCommitHash(id, researcher, nonce);

        vm.prank(researcher);
        bountyContract.commitProof(id, ch);

        uint[2] memory pA = [uint(1), uint(2)];
        uint[2][2] memory pB = [[uint(3), uint(4)], [uint(5), uint(6)]];
        uint[2] memory pC = [uint(7), uint(8)];
        uint[5] memory pub = _buildPubSignals(id, researcher);

        vm.prank(mevBot);
        vm.expectRevert(zkBounty.AddressMismatch.selector);
        bountyContract.revealProof(id, pA, pB, pC, pub, nonce);
    }

    function test_CRITICAL02_ForceReleaseAfterTimeout() public {
        uint256 id = _createBounty();
        bytes32 nonce = bytes32(uint256(0xCAFE));
        bytes32 ch = _makeCommitHash(id, researcher, nonce);

        vm.prank(researcher);
        bountyContract.commitProof(id, ch);

        uint[2] memory pA = [uint(1), uint(2)];
        uint[2][2] memory pB = [[uint(3), uint(4)], [uint(5), uint(6)]];
        uint[2] memory pC = [uint(7), uint(8)];
        uint[5] memory pub = _buildPubSignals(id, researcher);

        vm.prank(researcher);
        bountyContract.revealProof(id, pA, pB, pC, pub, nonce);

        vm.warp(block.timestamp + DEADLINE_HRS * 3600 + CLAIM_TIMEOUT + 1);

        uint256 balBefore = researcher.balance;
        vm.prank(researcher);
        bountyContract.forceRelease(id);

        uint256 fee = (REWARD * 250) / 10_000;
        assertEq(researcher.balance - balBefore, REWARD - fee);
    }

    function test_CRITICAL02_ForceReleaseBeforeTimeoutFails() public {
        uint256 id = _createBounty();
        bytes32 nonce = bytes32(uint256(0xCAFE));
        bytes32 ch = _makeCommitHash(id, researcher, nonce);

        vm.prank(researcher);
        bountyContract.commitProof(id, ch);

        uint[2] memory pA = [uint(1), uint(2)];
        uint[2][2] memory pB = [[uint(3), uint(4)], [uint(5), uint(6)]];
        uint[2] memory pC = [uint(7), uint(8)];
        uint[5] memory pub = _buildPubSignals(id, researcher);

        vm.prank(researcher);
        bountyContract.revealProof(id, pA, pB, pC, pub, nonce);

        vm.prank(researcher);
        vm.expectRevert(zkBounty.ClaimTimeoutNotReached.selector);
        bountyContract.forceRelease(id);
    }

    function test_FullFlow_HappyPath() public {
        uint256 id = _createBounty();
        bytes32 nonce = bytes32(uint256(0x1234));
        bytes32 ch = _makeCommitHash(id, researcher, nonce);

        vm.prank(researcher);
        bountyContract.commitProof(id, ch);

        uint[2] memory pA = [uint(1), uint(2)];
        uint[2][2] memory pB = [[uint(3), uint(4)], [uint(5), uint(6)]];
        uint[2] memory pC = [uint(7), uint(8)];
        uint[5] memory pub = _buildPubSignals(id, researcher);

        vm.prank(researcher);
        bountyContract.revealProof(id, pA, pB, pC, pub, nonce);

        uint256 balBefore = researcher.balance;
        vm.prank(company);
        bountyContract.companyAccept(id);

        uint256 fee = (REWARD * 250) / 10_000;
        assertEq(researcher.balance - balBefore, REWARD - fee);
        assertEq(feeRecip.balance, fee);
    }
}
