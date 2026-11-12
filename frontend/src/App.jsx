import { useState, useEffect } from "react"
import { ethers } from "ethers"

// v0.7 contract — alamat di-inject guna cast compute-address (JANGAN hand-type).
const BOUNTY_ESCROW = "0x47931cfB7E5d29a20f76941E6F180AA4cBa119eF"

// ABI v0.7 (afirmasi-only): forceRelease & canForceRelease DIBUANG; escalate/disputeTimeout/treasury
// ditambah; getBounty tuple tambah researcherBond (10 field); revealProof uint[4] payable.
const ABI = [
  "function createBounty(uint256 deadline_hours, uint256 claimTimeout, uint8 minSeverity) payable returns (uint256)",
  "function getBounty(uint256 bountyId) view returns (tuple(address company, uint256 reward, uint256 deadline, uint256 claimTimeout, uint256 bountyId, uint8 minSeverity, uint8 state, address researcher, uint256 commitment, uint256 researcherBond))",
  "function getBountyCount() view returns (uint256)",
  "function commitProof(uint256 bountyId, bytes32 commitHash)",
  "function revealProof(uint256 bountyId, uint[2] pA, uint[2][2] pB, uint[2] pC, uint[4] pubSignals, bytes32 nonce) payable",
  "function companyAccept(uint256 bountyId)",
  "function companyReject(uint256 bountyId)",
  "function escalate(uint256 bountyId)",
  "function disputeTimeout(uint256 bountyId)",
  "function resolveDispute(uint256 bountyId, bool researcherWins)",
  "function refundExpired(uint256 bountyId)",
  "function getActiveBounties() view returns (uint256[])",
  "function disputeDeadlines(uint256 bountyId) view returns (uint256)",
  "function arbitrator() view returns (address)",
  "function treasury() view returns (address)",
  "function MIN_BOUNTY() view returns (uint256)",
  "function ARB_WINDOW() view returns (uint256)",
  "function RESEARCHER_BOND_BPS() view returns (uint16)",
  "function MIN_BOND() view returns (uint256)",
  "function PLATFORM_FEE_BPS() view returns (uint256)",
  "function BPS_DENOMINATOR() view returns (uint256)",
  "event DisputeOpened(uint256 indexed bountyId, address indexed company, uint256 disputeDeadline)",
  "event DisputeResolved(uint256 indexed bountyId, bool researcherWins, address arbitrator)",
  "event DisputeTimedOut(uint256 indexed bountyId, address indexed researcher, uint256 rewardToCompany)",
]

// enum BountyState { Active, PendingReveal, PendingCompany, Claimed, Expired, ForceReleased, Disputed }
const STATUS = ["Active", "Pending Reveal", "Pending Company", "Claimed", "Expired", "Force Released", "Disputed"]
const STATUS_COLOR = ["bg-green-900 text-green-300", "bg-yellow-900 text-yellow-300", "bg-blue-900 text-blue-300", "bg-purple-900 text-purple-300", "bg-gray-700 text-gray-300", "bg-orange-900 text-orange-300", "bg-red-900 text-red-300"]
const SEVERITY = ["", "Low", "Medium", "High", "Critical"]
const SEV_COLOR = ["", "text-green-400", "text-yellow-400", "text-orange-400", "text-red-500"]
const SEV_BG = ["", "bg-green-900", "bg-yellow-900", "bg-orange-900", "bg-red-900"]

// Fee 2.5% (PLATFORM_FEE_BPS) + researcher bond max(10%, 0.005 ETH) di-escrow masa reveal (via
// prover-cli/claim.js). Nilai didedah sebagai teks pada tab Researcher/Post — reveal itu sendiri CLI,
// bukan frontend, jadi frontend tak kira/hantar bon.

function StatCard({ label, value, sub }) {
  return (
    <div className="bg-gray-900 border border-gray-700 rounded-lg p-4 flex flex-col gap-1">
      <p className="text-xs text-gray-500 uppercase tracking-wider">{label}</p>
      <p className="text-2xl font-bold text-white">{value}</p>
      {sub && <p className="text-xs text-gray-400">{sub}</p>}
    </div>
  )
}

function BountyCard({ b, walletAddr, onAccept, onReject, onEscalate, onTimeout }) {
  const deadline = new Date(Number(b.deadline) * 1000)
  const claimCutoff = new Date((Number(b.deadline) + Number(b.claimTimeout)) * 1000)
  const now = new Date()
  const expired = deadline < now
  const timeLeft = expired ? "Expired" : deadline.toLocaleDateString()

  const isCompany = walletAddr && b.company && walletAddr.toLowerCase() === b.company.toLowerCase()
  const isResearcher = walletAddr && b.researcher && walletAddr.toLowerCase() === b.researcher.toLowerCase()
  const pendingCompany = b.status === 2n
  const disputed = b.status === 6n

  return (
    <div className="bg-gray-900 border border-gray-700 hover:border-red-800 rounded-xl p-5 transition-all">
      <div className="flex justify-between items-start mb-3">
        <div className="flex items-center gap-2">
          <span className="text-xs text-gray-500 font-mono">#{b.id}</span>
          <span className={"text-xs px-2 py-0.5 rounded font-bold " + STATUS_COLOR[Number(b.status)]}>
            {STATUS[Number(b.status)]}
          </span>
          <span className={"text-xs px-2 py-0.5 rounded font-bold " + SEV_BG[Number(b.minSeverity)] + " " + SEV_COLOR[Number(b.minSeverity)]}>
            {SEVERITY[Number(b.minSeverity)]} +
          </span>
        </div>
        <p className="text-green-400 font-bold text-xl">{ethers.formatEther(b.reward || 0n)} ETH</p>
      </div>

      <div className="grid grid-cols-2 gap-3 mb-4">
        <div className="bg-gray-800 rounded-lg p-3">
          <p className="text-xs text-gray-500">Bounty ID</p>
          <p className="font-mono font-bold text-white">#{b.id}</p>
        </div>
        <div className="bg-gray-800 rounded-lg p-3">
          <p className="text-xs text-gray-500">Deadline</p>
          <p className={"font-bold text-sm " + (expired ? "text-red-400" : "text-white")}>{timeLeft}</p>
        </div>
      </div>

      {b.commitment && b.commitment !== 0n && (
        <div className="bg-gray-800 rounded-lg p-3 mb-4">
          <p className="text-xs text-gray-500 mb-1">Committed Hash</p>
          <p className="font-mono text-xs text-yellow-300 break-all">{b.commitment?.toString().slice(0, 30)}...</p>
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        {/* Company: terima (bayar) atau tolak (buka dispute) — hanya PendingCompany */}
        {isCompany && pendingCompany && (
          <>
            <button onClick={() => onAccept(b.id)}
              className="flex-1 bg-green-700 hover:bg-green-600 py-2 rounded-lg text-sm font-bold transition-colors">
              Accept &amp; Pay (−2.5% fee)
            </button>
            <button onClick={() => onReject(b.id)}
              className="flex-1 bg-gray-700 hover:bg-gray-600 py-2 rounded-lg text-sm font-bold transition-colors">
              Reject → Dispute
            </button>
          </>
        )}
        {/* Researcher: escalate kalau company diam lepas claimTimeout */}
        {isResearcher && pendingCompany && now > claimCutoff && (
          <button onClick={() => onEscalate(b.id)}
            className="flex-1 bg-blue-700 hover:bg-blue-600 py-2 rounded-lg text-sm font-bold transition-colors">
            Escalate to Arbitrator
          </button>
        )}
        {/* Sesiapa: fail-safe disputeTimeout kalau arbitrator diam lepas ARB_WINDOW */}
        {disputed && now > claimCutoff && (
          <button onClick={() => onTimeout(b.id)}
            className="flex-1 bg-orange-800 hover:bg-orange-700 py-2 rounded-lg text-sm font-bold transition-colors">
            Resolve Timeout → Refund Company
          </button>
        )}
        <a href={"https://sepolia.etherscan.io/address/" + BOUNTY_ESCROW}
          target="_blank" rel="noreferrer"
          className="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg text-xs text-gray-300 transition-colors">
          Etherscan
        </a>
      </div>
    </div>
  )
}

export default function App() {
  const [tab, setTab] = useState("bounties")
  const [wallet, setWallet] = useState(null)
  const [walletAddr, setWalletAddr] = useState("")
  const [bounties, setBounties] = useState([])
  const [loading, setLoading] = useState(false)
  const [msg, setMsg] = useState({ text: "", type: "info" })
  const [targetId, setTargetId] = useState("42")
  const [minSev, setMinSev] = useState("3")
  const [hours, setHours] = useState("24")
  const [reward, setReward] = useState("0.01")
  const [refreshing, setRefreshing] = useState(false)

  function showMsg(text, type = "info") {
    setMsg({ text, type })
    if (type !== "error") setTimeout(() => setMsg({ text: "", type: "info" }), 5000)
  }

  async function connectWallet() {
    if (!window.ethereum) return showMsg("Install MetaMask!", "error")
    try {
      const provider = new ethers.BrowserProvider(window.ethereum)
      await provider.send("eth_requestAccounts", [])
      const signer = await provider.getSigner()
      const addr = await signer.getAddress()
      setWallet(signer)
      setWalletAddr(addr)
      showMsg("Connected: " + addr.slice(0, 6) + "..." + addr.slice(-4), "success")
      loadBounties(provider)
    } catch (e) {
      showMsg("Connection failed: " + e.message, "error")
    }
  }

  async function loadBounties(provider) {
    setRefreshing(true)
    try {
      const p = provider || new ethers.JsonRpcProvider("https://ethereum-sepolia-rpc.publicnode.com")
      const contract = new ethers.Contract(BOUNTY_ESCROW, ABI, p)
      const count = await contract.getBountyCount()
      const list = []
      for (let i = 1; i <= Number(count); i++) {
        const b = await contract.getBounty(i)
        list.push({
          id: i,
          company: b[0], reward: b[1], deadline: b[2],
          claimTimeout: b[3], bountyId: b[4], minSeverity: b[5],
          status: b[6], researcher: b[7], commitment: b[8], researcherBond: b[9],
        })
      }
      setBounties(list)
    } catch (e) {
      showMsg("Error loading: " + e.message, "error")
    }
    setRefreshing(false)
  }

  async function postBounty() {
    if (!wallet) return showMsg("Connect wallet first!", "error")
    setLoading(true)
    try {
      const contract = new ethers.Contract(BOUNTY_ESCROW, ABI, wallet)
      const tx = await contract.createBounty(hours, 259200, minSev, {
        value: ethers.parseEther(reward),
      })
      showMsg("TX sent... waiting confirmation", "info")
      await tx.wait()
      showMsg("Bounty posted successfully!", "success")
      loadBounties()
      setTab("bounties")
    } catch (e) {
      showMsg("Error: " + e.message, "error")
    }
    setLoading(false)
  }

  // --- aksi v0.7: afirmasi-only, tiada forceRelease ---
  async function callTx(fn, id, successText) {
    if (!wallet) return showMsg("Connect wallet first!", "error")
    setLoading(true)
    try {
      const contract = new ethers.Contract(BOUNTY_ESCROW, ABI, wallet)
      const tx = await contract[fn](id)
      showMsg("TX sent... waiting confirmation", "info")
      await tx.wait()
      showMsg(successText, "success")
      loadBounties()
    } catch (e) {
      showMsg("Error: " + e.message, "error")
    }
    setLoading(false)
  }
  const acceptBounty = (id) => callTx("companyAccept", id, "Payment released to researcher (minus 2.5% fee).")
  const rejectBounty = (id) => callTx("companyReject", id, "Dispute opened — arbitrator will rule.")
  const escalateBounty = (id) => callTx("escalate", id, "Escalated to arbitrator.")
  const timeoutDispute = (id) => callTx("disputeTimeout", id, "Dispute timed out — reward refunded to company.")

  useEffect(() => { loadBounties() }, [])

  const openBounties = bounties.filter(b => b.status === 0n).length
  // Kontrak TIDAK zero b.reward pada refund/claim (H5-2 LOW) — jadi jumlah hanya atas state yang
  // masih pegang dana: Active(0), PendingReveal(1), PendingCompany(2), Disputed(6).
  const STILL_LOCKED_STATUS = [0n, 1n, 2n, 6n]
  const totalLocked = bounties.reduce(
    (sum, b) => (STILL_LOCKED_STATUS.includes(b.status) ? sum + (b.reward || 0n) : sum),
    0n
  )

  return (
    <div className="min-h-screen bg-gray-950 text-white font-mono">

      {/* Header */}
      <div className="border-b border-red-900 bg-gray-900">
        <div className="max-w-4xl mx-auto px-6 py-4 flex justify-between items-center">
          <div className="flex items-center gap-4">
            <div>
              <h1 className="text-xl font-bold text-red-500 tracking-wider">⚡ zkBounty</h1>
              <p className="text-xs text-gray-500">Trustless ZK Exploit Disclosure</p>
            </div>
            <span className="text-xs bg-red-900 text-red-300 px-2 py-1 rounded">Sepolia Testnet</span>
          </div>
          <button onClick={connectWallet}
            className={"px-4 py-2 rounded-lg text-sm font-bold transition-colors " +
              (wallet ? "bg-green-900 text-green-300 border border-green-700" : "bg-red-700 hover:bg-red-600")}>
            {wallet ? "✓ " + walletAddr.slice(0, 6) + "..." + walletAddr.slice(-4) : "Connect Wallet"}
          </button>
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-6 py-6">

        {/* Message */}
        {msg.text && (
          <div className={"mb-4 p-3 rounded-lg text-sm border " +
            (msg.type === "error" ? "bg-red-950 border-red-800 text-red-300" :
              msg.type === "success" ? "bg-green-950 border-green-800 text-green-300" :
                "bg-gray-800 border-gray-700 text-gray-300")}>
            {msg.text}
          </div>
        )}

        {/* Stats */}
        <div className="grid grid-cols-3 gap-4 mb-6">
          <StatCard label="Total Bounties" value={bounties.length} sub="on Sepolia" />
          <StatCard label="Open Bounties" value={openBounties} sub="awaiting claims" />
          <StatCard label="Total Locked" value={ethers.formatEther(totalLocked) + " ETH"} sub="in escrow" />
        </div>

        {/* Tabs */}
        <div className="flex gap-2 mb-6 border-b border-gray-800 pb-3">
          {[
            { id: "bounties", label: "Bounties" },
            { id: "post", label: "Post Bounty" },
            { id: "researcher", label: "Researcher" },
            { id: "how", label: "How It Works" }
          ].map(t => (
            <button key={t.id} onClick={() => setTab(t.id)}
              className={"px-4 py-2 rounded-lg text-sm font-bold transition-colors " +
                (tab === t.id ? "bg-red-700 text-white" : "text-gray-400 hover:text-white hover:bg-gray-800")}>
              {t.label}
            </button>
          ))}
        </div>

        {/* BOUNTIES */}
        {tab === "bounties" && (
          <div>
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-lg font-bold text-red-400">Active Bounties</h2>
              <button onClick={() => loadBounties()}
                className={"text-xs px-3 py-1 rounded bg-gray-800 hover:bg-gray-700 transition-colors " + (refreshing ? "animate-pulse" : "")}>
                {refreshing ? "Loading..." : "↻ Refresh"}
              </button>
            </div>
            {bounties.length === 0 ? (
              <div className="text-center py-12 text-gray-600">
                <p className="text-4xl mb-3">🔍</p>
                <p>No bounties yet. Be the first!</p>
              </div>
            ) : (
              <div className="grid gap-4">
                {bounties.map(b => (
                  <BountyCard key={b.id} b={b} walletAddr={walletAddr}
                    onAccept={acceptBounty} onReject={rejectBounty}
                    onEscalate={escalateBounty} onTimeout={timeoutDispute} />
                ))}
              </div>
            )}
          </div>
        )}

        {/* POST BOUNTY */}
        {tab === "post" && (
          <div className="max-w-lg">
            <h2 className="text-lg font-bold text-red-400 mb-4">Post New Bounty</h2>
            <div className="bg-gray-900 border border-gray-700 rounded-xl p-5 space-y-4">
              <div>
                <label className="text-xs text-gray-400 block mb-1">Target ID</label>
                <input value={targetId} onChange={e => setTargetId(e.target.value)}
                  className="w-full bg-gray-800 border border-gray-600 focus:border-red-700 rounded-lg px-3 py-2 text-sm outline-none transition-colors" />
                <p className="text-xs text-gray-600 mt-1">Contract address or app identifier</p>
              </div>
              <div>
                <label className="text-xs text-gray-400 block mb-1">Minimum Severity</label>
                <div className="grid grid-cols-4 gap-2">
                  {["Low", "Medium", "High", "Critical"].map((s, i) => (
                    <button key={s} onClick={() => setMinSev(String(i + 1))}
                      className={"py-2 rounded-lg text-xs font-bold transition-colors " +
                        (minSev === String(i + 1) ? SEV_BG[i + 1] + " " + SEV_COLOR[i + 1] + " border border-current" : "bg-gray-800 text-gray-400")}>
                      {s}
                    </button>
                  ))}
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-xs text-gray-400 block mb-1">Deadline (hours)</label>
                  <input value={hours} onChange={e => setHours(e.target.value)}
                    className="w-full bg-gray-800 border border-gray-600 focus:border-red-700 rounded-lg px-3 py-2 text-sm outline-none" />
                </div>
                <div>
                  <label className="text-xs text-gray-400 block mb-1">Reward (ETH)</label>
                  <input value={reward} onChange={e => setReward(e.target.value)}
                    className="w-full bg-gray-800 border border-gray-600 focus:border-red-700 rounded-lg px-3 py-2 text-sm outline-none" />
                </div>
              </div>
              <div className="bg-gray-800 rounded-lg p-3 flex justify-between text-sm">
                <span className="text-gray-400">You lock:</span>
                <span className="text-green-400 font-bold">{reward} ETH</span>
              </div>
              <p className="text-xs text-gray-500">
                On payout, researcher receives reward minus a <span className="text-gray-300">2.5% protocol fee</span>.
                Refunds (timeout / dispute) return the full reward to you.
              </p>
              <button onClick={postBounty} disabled={loading || !wallet}
                className="w-full bg-red-700 hover:bg-red-600 disabled:opacity-40 py-3 rounded-lg font-bold text-sm transition-colors">
                {loading ? "Posting..." : !wallet ? "Connect Wallet First" : "Lock " + reward + " ETH as Bounty"}
              </button>
            </div>
          </div>
        )}

        {/* RESEARCHER */}
        {tab === "researcher" && (
          <div className="max-w-lg">
            <h2 className="text-lg font-bold text-red-400 mb-4">Researcher Flow</h2>
            <div className="space-y-3">
              <div className="bg-yellow-950 border border-yellow-800 rounded-xl p-4">
                <p className="text-yellow-300 text-sm font-bold mb-1">Zero-Knowledge Exploit Disclosure</p>
                <p className="text-yellow-200 text-xs">Prove you know a vulnerability WITHOUT revealing it. The ZK proof is front-run resistant (bound to your address + bounty + severity). Validity is judged off-chain by the company or an independent arbitrator.</p>
              </div>
              <div className="bg-blue-950 border border-blue-800 rounded-xl p-4">
                <p className="text-blue-300 text-sm font-bold mb-1">Bond &amp; fee (read first)</p>
                <p className="text-blue-200 text-xs">Revealing locks a <span className="font-bold">refundable bond</span> = max(10% of reward, 0.005 ETH). It is returned in full when you are paid, and forfeited to the treasury only if an arbitrator rules your claim invalid. On payout you receive the reward minus a 2.5% protocol fee.</p>
              </div>
              {[
                { step: "1", title: "Find Exploit", desc: "Discover a vulnerability in the target contract/app.", cmd: null },
                { step: "2", title: "Generate ZK Proof", desc: "Prove you know it without revealing it (bound to this bounty + your address).", cmd: "node prover-cli/prove.js --bounty <id> --severity <1-10> --claimer <your_address>" },
                { step: "3", title: "Commit + Reveal (+bond)", desc: "Commit the hash, then reveal — the reveal transaction sends your refundable bond.", cmd: "node prover-cli/claim.js --bounty <id> --proof proof_bounty_<id>.json" },
                { step: "4", title: "Get Paid", desc: "Company accepts → you are paid reward − 2.5% fee + bond back. If the company ignores you past the claim timeout, Escalate to the arbitrator.", cmd: null },
                { step: "5", title: "Reveal Exploit", desc: "Share full details after payment is confirmed.", cmd: null },
              ].map(s => (
                <div key={s.step} className="bg-gray-900 border border-gray-700 rounded-xl p-4">
                  <div className="flex items-start gap-3">
                    <span className="bg-red-700 text-white text-xs font-bold w-6 h-6 rounded-full flex items-center justify-center flex-shrink-0">{s.step}</span>
                    <div className="flex-1">
                      <p className="font-bold text-sm text-white">{s.title}</p>
                      <p className="text-xs text-gray-400 mt-0.5">{s.desc}</p>
                      {s.cmd && (
                        <div className="bg-gray-800 rounded-lg p-2 mt-2">
                          <code className="text-xs text-green-400 break-all">{s.cmd}</code>
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              ))}
              <div className="bg-gray-900 border border-gray-700 rounded-xl p-4">
                <p className="text-xs text-gray-400 mb-1">Contract Address (v0.7)</p>
                <code className="text-xs text-green-400 break-all">{BOUNTY_ESCROW}</code>
              </div>
            </div>
          </div>
        )}

        {/* HOW IT WORKS */}
        {tab === "how" && (
          <div className="max-w-lg">
            <h2 className="text-lg font-bold text-red-400 mb-4">How zkBounty Works</h2>
            <div className="space-y-4">
              <div className="bg-gray-900 border border-gray-700 rounded-xl p-4">
                <h3 className="font-bold text-red-300 mb-2">The Problem</h3>
                <p className="text-sm text-gray-300">Traditional bug bounties have a trust problem. Researchers must reveal exploits before getting paid, and companies can walk away without paying.</p>
              </div>
              <div className="bg-gray-900 border border-gray-700 rounded-xl p-4">
                <h3 className="font-bold text-green-300 mb-2">The ZK Solution</h3>
                <p className="text-sm text-gray-300">Using Groth16 zero-knowledge proofs, a researcher commits then reveals a proof bound to their address, the bounty id and the severity — front-run and reveal-snipe resistant. The exploit itself is disclosed off-chain only after payment.</p>
              </div>
              <div className="bg-gray-900 border border-gray-700 rounded-xl p-4">
                <h3 className="font-bold text-blue-300 mb-2">Payment &amp; Disputes (v0.7)</h3>
                <ul className="text-sm text-gray-300 list-disc list-inside space-y-1">
                  <li>Payment settles only when <span className="text-white">affirmed</span> — the company accepts, or an independent arbitrator rules in the researcher&apos;s favor.</li>
                  <li>If the company ignores a claim, the researcher escalates to the arbitrator (no unilateral timeout payout).</li>
                  <li>If the arbitrator never acts, <span className="text-white">disputeTimeout</span> refunds the company — a safe default, never a drain.</li>
                  <li>Researchers lock a refundable bond at reveal; forfeited to the treasury only on an invalid ruling.</li>
                  <li>No single party — company, owner or arbitrator — can seize escrowed funds.</li>
                </ul>
              </div>
              <div className="bg-gray-900 border border-gray-700 rounded-xl p-4">
                <h3 className="font-bold text-blue-300 mb-2">Tech Stack</h3>
                <div className="grid grid-cols-2 gap-2 mt-2">
                  {[
                    ["Circuit", "Circom + Groth16"],
                    ["Proof", "SnarkJS"],
                    ["Hash", "Poseidon"],
                    ["Contract", "Solidity + Foundry"],
                    ["Network", "Ethereum Sepolia"],
                    ["Frontend", "React + ethers.js"],
                  ].map(([k, v]) => (
                    <div key={k} className="bg-gray-800 rounded-lg p-2">
                      <p className="text-xs text-gray-500">{k}</p>
                      <p className="text-xs text-white font-bold">{v}</p>
                    </div>
                  ))}
                </div>
              </div>
              <div className="bg-gray-900 border border-gray-700 rounded-xl p-4">
                <h3 className="font-bold text-yellow-300 mb-2">Built By</h3>
                <p className="text-sm text-gray-300">mrZk @ka eGold — ZK Security Researcher</p>
                <p className="text-xs text-gray-500 mt-1">BlackArch Linux + ZK Proofs + Web3</p>
              </div>
            </div>
          </div>
        )}

      </div>

      {/* Footer */}
      <div className="border-t border-gray-800 mt-12 py-6 text-center">
        <p className="text-xs text-gray-600">zkBounty — Trustless ZK Exploit Disclosure Protocol</p>
        <p className="text-xs text-gray-700 mt-1">Built by mrZk @ka eGold · Sepolia Testnet · Powered by Groth16</p>
      </div>
    </div>
  )
}
