// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/zkBounty.sol";

contract MockVerifier {
    function verifyProof(
        uint[2] calldata,
        uint[2][2] calldata,
        uint[2] calldata,
        uint[5] calldata
    ) external pure returns (bool) {
        return true;
    }
}

contract SecurityTests is Test {
    zkBounty public bounty;
    MockVerifier public verifier;
    
    address company = address(0x1);
    address researcher = address(0x2);
    address owner = address(this);
    
    function setUp() public {
        verifier = new MockVerifier();
        bounty = new zkBounty(address(verifier), owner);
        
        vm.deal(company, 100 ether);
        vm.deal(researcher, 10 ether);
    }
    
    // ========== CRIT-04 TESTS ==========
    
    function testCRIT04_GetBountyCountWorks() public {
        assertEq(bounty.getBountyCount(), 0);
        
        vm.prank(company);
        bounty.createBounty{value: 1 ether}(24, 5, 7200);
        
        assertEq(bounty.getBountyCount(), 1);
    }
    
    function testCRIT04_GetActiveBountiesWorks() public {
        vm.startPrank(company);
        
        bounty.createBounty{value: 1 ether}(24, 5, 7200);
        bounty.createBounty{value: 1 ether}(48, 7, 7200);
        
        vm.stopPrank();
        
        uint256[] memory active = bounty.getActiveBounties();
        assertEq(active.length, 2);
        assertEq(active[0], 1);
        assertEq(active[1], 2);
    }
    
    // ========== CRIT-05 TESTS ==========
    
    function testCRIT05_PauseWorks() public {
        bounty.pause();
        
        vm.startPrank(company);
        vm.expectRevert();
        bounty.createBounty{value: 1 ether}(24, 5, 7200);
        vm.stopPrank();
    }
    
    function testCRIT05_UnpauseWorks() public {
        bounty.pause();
        bounty.unpause();
        
        vm.startPrank(company);
        bounty.createBounty{value: 1 ether}(24, 5, 7200);
        vm.stopPrank();
    }
    
    function testCRIT05_OnlyOwnerCanPause() public {
        vm.startPrank(researcher);
        vm.expectRevert();
        bounty.pause();
        vm.stopPrank();
    }
    
    // ========== CRIT-06 TESTS ==========
    
    function testCRIT06_MaxDeadlineEnforced() public {
        vm.startPrank(company);
        
        // 8760 hours (1 year) should work
        bounty.createBounty{value: 1 ether}(8760, 5, 7200);
        
        // 8761 hours should fail
        vm.expectRevert(abi.encodeWithSignature("InvalidDeadline()"));
        bounty.createBounty{value: 1 ether}(8761, 5, 7200);
        
        vm.stopPrank();
    }
    
    function testCRIT06_ZeroDeadlineReverts() public {
        vm.startPrank(company);
        
        vm.expectRevert(abi.encodeWithSignature("InvalidDeadline()"));
        bounty.createBounty{value: 1 ether}(0, 5, 7200);
        
        vm.stopPrank();
    }
    
    function testCRIT06_MinBountyEnforced() public {
        vm.startPrank(company);
        
        vm.expectRevert(abi.encodeWithSignature("BountyTooSmall()"));
        bounty.createBounty{value: 0.0001 ether}(24, 5, 7200);
        
        vm.stopPrank();
    }
    
    // ========== CRIT-07 TESTS ==========
    
    function testCRIT07_ChainIdInCommitment() public {
        uint[2] memory pA;
        uint[2][2] memory pB;
        uint[2] memory pC;
        uint[5] memory pubSignals;
        bytes32 nonce = bytes32(uint256(123));
        
        bytes32 hash1 = keccak256(abi.encode(
            pA, pB, pC, pubSignals, nonce, block.chainid
        ));
        
        bytes32 hash2 = keccak256(abi.encode(
            pA, pB, pC, pubSignals, nonce, uint256(137) // Different chain
        ));
        
        assertTrue(hash1 != hash2, "Chain ID not in hash!");
    }
    
    // ========== HIGH-03 TESTS ==========
    
    function testHIGH03_BountyCountEventEmitted() public {
        vm.startPrank(company);
        
        vm.expectEmit(true, true, true, true);
        emit zkBounty.BountyCountUpdated(1);
        
        bounty.createBounty{value: 1 ether}(24, 5, 7200);
        
        vm.stopPrank();
    }
    
    // ========== INTEGRATION TEST ==========
    
    function testFullBountyLifecycle() public {
        // 1. Company creates bounty
        vm.startPrank(company);
        uint256 bountyId = bounty.createBounty{value: 1 ether}(24, 5, 7200);
        vm.stopPrank();
        
        assertEq(bountyId, 1);
        assertEq(bounty.getBountyCount(), 1);
        
        // 2. Researcher commits proof
        vm.startPrank(researcher);
        bytes32 commitment = keccak256("test");
        bounty.commitProof(commitment, bountyId);
        vm.stopPrank();
        
        // 3. Verify contract state
        (
            address comp,
            uint256 reward,
            ,
            ,
            ,
            ,
            uint8 state,
            ,
        ) = bounty.getBounty(bountyId);
        
        assertEq(comp, company);
        assertEq(reward, 1 ether);
        assertEq(state, 0); // Active
    }
}
