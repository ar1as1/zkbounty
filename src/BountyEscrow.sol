// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IExploitVerifier {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[4] calldata _pubSignals
    ) external view returns (bool);
}

contract BountyEscrow {
    IExploitVerifier public verifier;
    enum Status { Open, Claimed, Revealed, Cancelled }

    struct Bounty {
        address company;
        address researcher;
        uint256 reward;
        uint256 committedHash;
        uint256 targetId;
        uint256 minSeverity;
        Status status;
        uint256 deadline;
    }

    mapping(uint256 => Bounty) public bounties;
    uint256 public bountyCount;

    event BountyPosted(uint256 id, address company, uint256 reward);
    event BountyClaimed(uint256 id, address researcher, uint256 committedHash);
    event BountyReleased(uint256 id, address researcher, uint256 reward);

    constructor(address _verifier) {
        verifier = IExploitVerifier(_verifier);
    }

    function postBounty(
        uint256 targetId,
        uint256 minSeverity,
        uint256 deadlineHours
    ) external payable returns (uint256) {
        require(msg.value > 0, "Must lock reward");
        uint256 id = bountyCount++;
        bounties[id] = Bounty({
            company: msg.sender,
            researcher: address(0),
            reward: msg.value,
            committedHash: 0,
            targetId: targetId,
            minSeverity: minSeverity,
            status: Status.Open,
            deadline: block.timestamp + (deadlineHours * 1 hours)
        });
        emit BountyPosted(id, msg.sender, msg.value);
        return id;
    }

    // Researcher pass pubSignals terus dari proof
    function claimBounty(
        uint256 bountyId,
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[4] calldata _pubSignals
    ) external {
        Bounty storage b = bounties[bountyId];
        require(b.status == Status.Open, "Not open");
        require(block.timestamp < b.deadline, "Expired");

        // Verify proof — pass signals exactly as proof generated
        require(verifier.verifyProof(_pA, _pB, _pC, _pubSignals), "Bad proof");

        // Extract committedHash from signals[1]
        b.researcher = msg.sender;
        b.committedHash = _pubSignals[1];
        b.status = Status.Claimed;

        emit BountyClaimed(bountyId, msg.sender, _pubSignals[1]);
    }

    function releasePayment(uint256 bountyId) external {
        Bounty storage b = bounties[bountyId];
        require(b.status == Status.Claimed, "Not claimed");
        require(msg.sender == b.company, "Only company");
        b.status = Status.Revealed;
        uint256 reward = b.reward;
        b.reward = 0;
        (bool sent, ) = payable(b.researcher).call{value: reward}("");
        require(sent, "Failed");
        emit BountyReleased(bountyId, b.researcher, reward);
    }

    function getBounty(uint256 id) external view returns (Bounty memory) {
        return bounties[id];
    }
}
