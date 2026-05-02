
const { ethers } = require("ethers");
const snarkjs = require("snarkjs");
const fs = require("fs");

const BOUNTY_ESCROW = "0xC991A32470FF35Ec594d594Dcd343514E38a4737";
const ABI = [
  "function claimBounty(uint256 bountyId, uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[4] calldata _pubSignals) external"
];

async function main() {
  const args = process.argv.slice(2);
  const bountyId = args[args.indexOf("--bounty") + 1] || "0";
  const proofFile = args[args.indexOf("--proof") + 1] || "proof_bounty_0.json";

  console.log("=== zkBounty Claim CLI ===");
  console.log("Bounty ID :", bountyId);
  console.log("Proof file:", proofFile);

  // Load proof
  const data = JSON.parse(fs.readFileSync(proofFile));
  const { proof, publicSignals, committedHash } = data;

  // Format calldata
  const calldata = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
  const calldataArr = JSON.parse("[" + calldata + "]");

  const pA = calldataArr[0];
  const pB = calldataArr[1];
  const pC = calldataArr[2];

  // Use committed hash from publicSignals[1] — exact format verifier expects
  const hashForContract = BigInt(publicSignals[1]).toString();

  console.log("\n[1] Proof formatted for on-chain submission");
  console.log("    Committed Hash:", hashForContract);

  // Connect wallet
  const privKey = process.env.PRIVATE_KEY;
  if (!privKey) {
    console.log("\n❌ Set PRIVATE_KEY env var!");
    console.log("   export PRIVATE_KEY=0x...");
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(
    process.env.SEPOLIA_RPC || "https://ethereum-sepolia-rpc.publicnode.com"
  );
  const wallet = new ethers.Wallet(privKey, provider);
  const contract = new ethers.Contract(BOUNTY_ESCROW, ABI, wallet);

  console.log("\n[2] Submitting ZK proof on-chain...");
  console.log("    Wallet:", wallet.address);

  // Guna publicSignals terus dari proof file — exact order dari circuit
  // Guna signals dari exportSolidityCallData - format yang verifier expect
  // Convert hex signals to BigInt untuk ethers
  const pubSignals = calldataArr[3].map(s => BigInt(s));
  const tx = await contract.claimBounty(
    bountyId,
    pA, pB, pC,
    pubSignals
  );

  console.log("    TX sent:", tx.hash);
  const receipt = await tx.wait();
  console.log("\n✅ BOUNTY CLAIMED!");
  console.log("   Block:", receipt.blockNumber);
  console.log("   Gas used:", receipt.gasUsed.toString());
  console.log("\n   Exploit hidden. Wait for company to release payment.");
  console.log("   Then reveal your exploit to complete disclosure.");
}

main().catch(console.error);
