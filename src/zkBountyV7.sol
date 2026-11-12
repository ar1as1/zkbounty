// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IExploitVerifierV7 {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[4] calldata _pubSignals
    ) external view returns (bool);
}

contract zkBountyV7 {
    error Unauthorized();
    error BountyNotFound();
    error BountyNotActive();
    error BountyAlreadyClaimed();
    error InvalidCommitment();
    error CommitRevealMismatch();
    error RevealWindowNotOpen();
    error RevealWindowExpired();
    error ClaimTimeoutNotReached();
    error ClaimTimeoutExpired();
    error InvalidProof();
    error AddressMismatch();
    error InsufficientFund();
    error DeadlinePassed();
    error TransferFailed();
    error AlreadyCommitted();
    error NotCommitted();
    error InvalidDeadline();
    error InvalidTimeout();
    error ZeroAddress();
    error ReentrancyGuard();
    error ContractPaused();
    error InvalidSeverity();
    error NotArbitrator();
    error NoActiveDispute();
    error DisputeNotExpired();
    error DisputeWindowClosed();
    error MaxDisputesReached();
    error InsufficientBond();

    uint256 public constant MIN_REVEAL_WINDOW  = 1 hours;
    uint256 public constant MAX_REVEAL_WINDOW  = 24 hours;
    uint256 public constant MIN_CLAIM_TIMEOUT  = 3 days;
    uint256 public constant MAX_CLAIM_TIMEOUT  = 90 days;
    uint256 public constant MAX_DEADLINE       = 365 days;
    uint256 public constant PLATFORM_FEE_BPS   = 250;
    uint256 public constant BPS_DENOMINATOR    = 10_000;
    uint256 public constant MAX_DEADLINE_HOURS = 8_760;
    uint256 public constant MIN_BOUNTY         = 0.001 ether;
    uint256 public constant DISPUTE_WINDOW     = 7 days;
    uint8   public constant MAX_DISPUTE_COUNT  = 2;
    uint16  public constant RESEARCHER_BOND_BPS = 1000;      // 10% reward
    uint256 public constant MIN_BOND            = 0.005 ether;
    uint256 public constant ARB_WINDOW          = 14 days;

    address public immutable owner;
    address public immutable verifier;
    address public feeRecipient;

    uint256 private _bountyIdCounter;
    uint256 private _reentrancyStatus;
    bool public paused;
    address public immutable arbitrator;
    address public immutable treasury;
    mapping(uint256 => uint256) public disputeDeadlines;
    mapping(uint256 => uint8) public disputeCount;

    event BountyCountUpdated(uint256 newCount);
    event DisputeOpened(uint256 indexed bountyId, address indexed company, uint256 disputeDeadline);
    event DisputeResolved(uint256 indexed bountyId, bool researcherWins, address arbitrator);
    event ArbitratorUpdated(address indexed newArbitrator);
    event DisputeTimedOut(uint256 indexed bountyId, address indexed researcher, uint256 rewardToCompany);
    event BondForfeited(uint256 indexed bountyId, uint256 amount);

    struct Commitment {
        bytes32 commitHash;
        uint256 commitBlock;
        uint256 revealDeadline;
        bool    revealed;
    }

    struct Bounty {
        address company;
        uint256 reward;
        uint256 deadline;
        uint256 claimTimeout;
        uint256 bountyId;
        uint8   minSeverity;
        BountyState state;
        address researcher;
        uint256 commitment;
        uint256 researcherBond;
    }

    enum BountyState {
        Active,
        PendingReveal,
        PendingCompany,
        Claimed,
        Expired,
        ForceReleased,
        Disputed
    }

    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => uint256) public commitEpoch;
    mapping(bytes32 => mapping(address => Commitment)) public commitments;

    function _slot(uint256 bountyId) internal view returns (bytes32) {
        return keccak256(abi.encode(bountyId, commitEpoch[bountyId]));
    }
    mapping(uint256 => mapping(uint256 => bool)) public usedCommitment;

    event BountyCreated(uint256 indexed bountyId, address indexed company, uint256 reward, uint256 deadline, uint256 claimTimeout);
    event ProofCommitted(uint256 indexed bountyId, address indexed researcher, bytes32 commitHash, uint256 revealDeadline);
    event ProofRevealed(uint256 indexed bountyId, address indexed researcher, uint256 commitment);
    event BountyClaimed(uint256 indexed bountyId, address indexed researcher, uint256 amount);
    event BountyRejected(uint256 indexed bountyId, address indexed company);
    event BountyRefunded(uint256 indexed bountyId, address indexed company, uint256 amount);
    event ForceRelease(uint256 indexed bountyId, address indexed researcher, uint256 amount);
    event CompanyAccepted(uint256 indexed bountyId, address indexed company);

    modifier nonReentrant() {
        if (_reentrancyStatus == 2) revert ReentrancyGuard();
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier onlyCompany(uint256 bountyId) {
        if (msg.sender != bounties[bountyId].company) revert Unauthorized();
        _;
    }

    modifier bountyExists(uint256 bountyId) {
        if (bounties[bountyId].company == address(0)) revert BountyNotFound();
        _;
    }

    constructor(address _verifier, address _feeRecipient, address _arbitrator, address _treasury) {
        if (_verifier == address(0)) revert ZeroAddress();
        if (_feeRecipient == address(0)) revert ZeroAddress();
        if (_arbitrator == address(0)) revert ZeroAddress();   // arbitrator=0 mustahil (tutup brick v0.6)
        if (_treasury == address(0)) revert ZeroAddress();
        owner        = msg.sender;
        verifier     = _verifier;
        feeRecipient = _feeRecipient;
        arbitrator   = _arbitrator;   // immutable — tiada swap (H5-1 tutup)
        treasury     = _treasury;     // immutable — sink forfeit
        _reentrancyStatus = 1;
    }

    function createBounty(
        uint256 deadline_hours,
        uint256 claimTimeout,
        uint8   minSeverity
    ) external payable nonReentrant whenNotPaused returns (uint256 bountyId) {
        if (deadline_hours == 0 || deadline_hours > MAX_DEADLINE_HOURS) revert InvalidDeadline();
        if (claimTimeout < MIN_CLAIM_TIMEOUT || claimTimeout > MAX_CLAIM_TIMEOUT) revert InvalidTimeout();
        if (msg.value < MIN_BOUNTY) revert InsufficientFund();
        if (minSeverity < 1 || minSeverity > 10) revert InvalidSeverity();

        uint256 deadline = block.timestamp + (deadline_hours * 3600);
        bountyId = ++_bountyIdCounter;
        emit BountyCountUpdated(_bountyIdCounter);

        bounties[bountyId] = Bounty({
            company     : msg.sender,
            reward      : msg.value,
            deadline    : deadline,
            claimTimeout: claimTimeout,
            bountyId    : bountyId,
            minSeverity : minSeverity,
            state       : BountyState.Active,
            researcher  : address(0),
            commitment  : 0,
            researcherBond: 0
        });

        emit BountyCreated(bountyId, msg.sender, msg.value, deadline, claimTimeout);
    }

    function commitProof(uint256 bountyId, bytes32 commitHash) external bountyExists(bountyId) whenNotPaused {
        Bounty storage b = bounties[bountyId];
        if (b.state != BountyState.Active) revert BountyNotActive();
        if (block.timestamp >= b.deadline) revert DeadlinePassed();
        bytes32 slot = _slot(bountyId);
        if (commitments[slot][msg.sender].commitHash != bytes32(0)) revert AlreadyCommitted();

        uint256 revealDeadline = block.timestamp + MAX_REVEAL_WINDOW;
        commitments[slot][msg.sender] = Commitment({
            commitHash    : commitHash,
            commitBlock   : block.number,
            revealDeadline: revealDeadline,
            revealed      : false
        });

        // NOTE (PATCH J1-FR): b.state / b.researcher NO LONGER set here.
        // Bounty stays Active during the whole commit+reveal race; state only
        // transitions on a VALID reveal (see revealProof). This is what stops
        // a garbage front-run commit from locking out honest researchers.

        emit ProofCommitted(bountyId, msg.sender, commitHash, revealDeadline);
    }

    function revealProof(
        uint256 bountyId,
        uint[2]    calldata pA,
        uint[2][2] calldata pB,
        uint[2]    calldata pC,
        uint[4]    calldata pubSignals,
        bytes32 nonce
    ) external payable nonReentrant bountyExists(bountyId) {
        Bounty     storage b = bounties[bountyId];
        bytes32 slot = _slot(bountyId);
        Commitment storage c = commitments[slot][msg.sender];

        if (c.commitHash == bytes32(0)) revert NotCommitted();
        // PATCH J1-FR: win condition is 'bounty still Active' (no one has won yet),
        // not 'this address holds the global PendingReveal slot' — that slot no
        // longer exists. First VALID reveal flips state and locks out the rest.
        if (b.state != BountyState.Active) revert RevealWindowNotOpen();
        if (c.revealed) revert BountyAlreadyClaimed();
        if (block.timestamp > c.revealDeadline) revert RevealWindowExpired();

        bytes32 expectedHash = keccak256(abi.encode(pA, pB, pC, pubSignals, nonce));
        if (expectedHash != c.commitHash) revert CommitRevealMismatch();
        if (pubSignals[2] != bountyId) revert InvalidProof();
        if (pubSignals[3] != uint256(uint160(msg.sender))) revert AddressMismatch();
        if (pubSignals[1] < b.minSeverity) revert InvalidProof();
        if (usedCommitment[bountyId][pubSignals[0]]) revert BountyAlreadyClaimed();

        bool proofValid = IExploitVerifierV7(verifier).verifyProof(pA, pB, pC, pubSignals);
        if (!proofValid) revert InvalidProof();

        uint256 need = _requiredBond(b.reward);
        if (msg.value < need) revert InsufficientBond();
        b.researcherBond = need;

        usedCommitment[bountyId][pubSignals[0]] = true;
        c.revealed   = true;
        b.commitment = pubSignals[0];
        b.researcher = msg.sender;   // PATCH J1-FR: assigned on WIN, not on commit
        b.state      = BountyState.PendingCompany;

        emit ProofRevealed(bountyId, msg.sender, pubSignals[0]);

        uint256 excess = msg.value - need;
        if (excess > 0) _safeTransfer(msg.sender, excess);
    }

    function companyAccept(uint256 bountyId) external nonReentrant bountyExists(bountyId) onlyCompany(bountyId) {
        Bounty storage b = bounties[bountyId];
        if (b.state != BountyState.PendingCompany) revert BountyNotActive();
        if (block.timestamp > b.deadline + b.claimTimeout) revert ClaimTimeoutExpired();

        b.state = BountyState.Claimed;
        uint256 fee    = (b.reward * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 payout = b.reward - fee;
        uint256 bond   = b.researcherBond; b.researcherBond = 0;

        emit BountyClaimed(bountyId, b.researcher, payout);
        emit CompanyAccepted(bountyId, msg.sender);

        _safeTransfer(b.researcher, payout + bond);
        _safeTransfer(feeRecipient, fee);
    }

    function companyReject(uint256 bountyId) external nonReentrant bountyExists(bountyId) onlyCompany(bountyId) {
        Bounty storage b = bounties[bountyId];
        if (b.state != BountyState.PendingCompany) revert BountyNotActive();

        if (disputeCount[bountyId] >= MAX_DISPUTE_COUNT) revert MaxDisputesReached();
        disputeCount[bountyId] += 1;
        b.state = BountyState.Disputed;
        disputeDeadlines[bountyId] = block.timestamp + ARB_WINDOW;

        emit BountyRejected(bountyId, msg.sender);
        emit DisputeOpened(bountyId, msg.sender, disputeDeadlines[bountyId]);
    }

    function resolveDispute(uint256 bountyId, bool researcherWins) external nonReentrant bountyExists(bountyId) {
        if (msg.sender != arbitrator) revert NotArbitrator();
        Bounty storage b = bounties[bountyId];
        if (b.state != BountyState.Disputed) revert NoActiveDispute();
        // tiada DisputeWindowClosed revert: lepas tingkap, disputeTimeout() yang flip (fail-safe company)
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
            // CEI: SEMUA state write dulu, baru external transfer (elak reentrancy-eth)
            if (block.timestamp < b.deadline) {
                commitEpoch[bountyId] += 1;
                b.state      = BountyState.Active;
                b.researcher = address(0);
                b.commitment = 0;
                if (bond > 0) { emit BondForfeited(bountyId, bond); _safeTransfer(treasury, bond); }
            } else {
                uint256 r = b.reward; b.reward = 0;
                b.state = BountyState.Expired;
                if (bond > 0) { emit BondForfeited(bountyId, bond); _safeTransfer(treasury, bond); }
                emit BountyRefunded(bountyId, b.company, r);
                _safeTransfer(b.company, r);
            }
        }
    }

    function escalate(uint256 bountyId) external nonReentrant bountyExists(bountyId) {
        Bounty storage b = bounties[bountyId];
        if (msg.sender != b.researcher) revert Unauthorized();
        if (b.state != BountyState.PendingCompany) revert BountyNotActive();
        if (block.timestamp <= b.deadline + b.claimTimeout) revert ClaimTimeoutNotReached();
        b.state = BountyState.Disputed;
        disputeDeadlines[bountyId] = block.timestamp + ARB_WINDOW;
        emit DisputeOpened(bountyId, msg.sender, disputeDeadlines[bountyId]);
    }

    function disputeTimeout(uint256 bountyId) external nonReentrant bountyExists(bountyId) {
        Bounty storage b = bounties[bountyId];
        if (b.state != BountyState.Disputed) revert NoActiveDispute();
        if (block.timestamp <= disputeDeadlines[bountyId]) revert DisputeNotExpired();
        delete disputeDeadlines[bountyId];
        uint256 bond = b.researcherBond; b.researcherBond = 0;
        uint256 r    = b.reward;         b.reward = 0;
        b.state = BountyState.Expired;
        emit DisputeTimedOut(bountyId, b.researcher, r);
        if (bond > 0) _safeTransfer(b.researcher, bond);   // bon balik (tak di-adjudicate false)
        _safeTransfer(b.company, r);                       // reward balik company (fail-safe)
    }

    function _requiredBond(uint256 reward) internal pure returns (uint256) {
        uint256 pct = (reward * RESEARCHER_BOND_BPS) / BPS_DENOMINATOR;
        return pct < MIN_BOND ? MIN_BOND : pct;
    }

    function refundExpired(uint256 bountyId) external nonReentrant bountyExists(bountyId) onlyCompany(bountyId) {
        Bounty storage b = bounties[bountyId];
        // PATCH J1-FR: PendingReveal is never entered pre-claim anymore (commitProof
        // no longer sets it) — 'nobody won yet' is fully captured by state==Active,
        // whether zero commits, garbage commits, or expired per-committer windows.
        if (b.state != BountyState.Active) revert BountyNotActive();
        if (block.timestamp <= b.deadline) revert DeadlinePassed();

        b.state = BountyState.Expired;
        uint256 refund = b.reward;

        emit BountyRefunded(bountyId, b.researcher, refund);
        _safeTransfer(b.company, refund);
    }

    function _safeTransfer(address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) return;
        (bool success, bytes memory data) = to.call{value: amount}("");
        if (!success) {
            if (data.length > 0) {
                assembly { revert(add(data, 32), mload(data)) }
            }
            revert TransferFailed();
        }
    }

    function getBounty(uint256 bountyId) external view returns (Bounty memory) {
        return bounties[bountyId];
    }

    function getCommitment(uint256 bountyId, address committer) external view returns (Commitment memory) {
        return commitments[_slot(bountyId)][committer];
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function getBountyCount() external view returns (uint256) {
        return _bountyIdCounter;
    }

    function getActiveBounties() external view returns (uint256[] memory) {
        uint256 count;
        for (uint256 i = 1; i <= _bountyIdCounter; i++) {
            if (bounties[i].state == BountyState.Active) count++;
        }
        uint256[] memory active = new uint256[](count);
        uint256 idx;
        for (uint256 i = 1; i <= _bountyIdCounter; i++) {
            if (bounties[i].state == BountyState.Active) active[idx++] = i;
        }
        return active;
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        feeRecipient = newRecipient;
    }

    receive() external payable { revert("Use createBounty"); }
    fallback() external payable { revert("Invalid call"); }
}
