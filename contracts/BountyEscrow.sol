// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IExploitVerifier {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[3] calldata _pubSignals
    ) external view returns (bool);
}

contract BountyEscrow {

    IExploitVerifier public verifier;

    enum Status { Open, Claimed, Revealed, Cancelled }

    struct Bounty {
        address company;        // who posted bounty
        address researcher;     // who claimed it
        uint256 reward;         // ETH locked
        uint256 committed_hash; // Poseidon hash of exploit
        uint256 target_id;      // contract/app being reported
        uint256 min_severity;   // minimum severity accepted
        Status status;
        uint256 deadline;       // claim deadline
    }

    mapping(uint256 => Bounty) public bounties;
    uint256 public bountyCount;

    event BountyPosted(uint256 id, address company, uint256 reward);
    event BountyClaimed(uint256 id, address researcher, uint256 committed_hash);
    event BountyReleased(uint256 id, address researcher, uint256 reward);
    event BountyCancelled(uint256 id);

    constructor(address _verifier) {
        verifier = IExploitVerifier(_verifier);
    }

    // Company post bounty + lock ETH
    function postBounty(
        uint256 target_id,
        uint256 min_severity,
        uint256 deadline_hours
    ) external payable returns (uint256) {
        require(msg.value > 0, "Must lock reward");

        uint256 id = bountyCount++;
        bounties[id] = Bounty({
            company: msg.sender,
            researcher: address(0),
            reward: msg.value,
            committed_hash: 0,
            target_id: target_id,
            min_severity: min_severity,
            status: Status.Open,
            deadline: block.timestamp + (deadline_hours * 1 hours)
        });

        emit BountyPosted(id, msg.sender, msg.value);
        return id;
    }

    // Researcher submit ZK proof (WITHOUT revealing exploit)
    function claimBounty(
        uint256 bountyId,
        uint256 committed_hash,
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC
    ) external {
        Bounty storage b = bounties[bountyId];
        require(b.status == Status.Open, "Not open");
        require(block.timestamp < b.deadline, "Deadline passed");

        // Public signals: [committed_hash, target_id, min_severity]
        uint[3] memory pubSignals = [
            committed_hash,
            b.target_id,
            b.min_severity
        ];

        // Verify ZK proof on-chain
        require(
            verifier.verifyProof(_pA, _pB, _pC, pubSignals),
            "Invalid ZK proof"
        );

        b.researcher = msg.sender;
        b.committed_hash = committed_hash;
        b.status = Status.Claimed;

        emit BountyClaimed(bountyId, msg.sender, committed_hash);
    }

    // Company releases payment after seeing exploit
    function releasePayment(uint256 bountyId) external {
        Bounty storage b = bounties[bountyId];
        require(b.status == Status.Claimed, "Not claimed");
        require(msg.sender == b.company, "Only company");

        b.status = Status.Revealed;
        uint256 reward = b.reward;
        b.reward = 0;

        payable(b.researcher).transfer(reward);
        emit BountyReleased(bountyId, b.researcher, reward);
    }

    // Cancel if no one claims before deadline
    function cancelBounty(uint256 bountyId) external {
        Bounty storage b = bounties[bountyId];
        require(b.status == Status.Open, "Not open");
        require(msg.sender == b.company, "Only company");
        require(block.timestamp > b.deadline, "Deadline not passed");

        b.status = Status.Cancelled;
        payable(b.company).transfer(b.reward);
        emit BountyCancelled(bountyId);
    }

    // View all bounties
    function getBounty(uint256 id) external view returns (Bounty memory) {
        return bounties[id];
    }
}
