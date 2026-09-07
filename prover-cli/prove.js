const { buildPoseidon } = require("circomlibjs");
const snarkjs = require("snarkjs");
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

function arg(a, name, def) {
  const i = a.indexOf(name);
  if (i === -1) return def;
  const v = a[i + 1];
  if (v === undefined) throw new Error(`Flag ${name} tiada nilai`);
  return v;
}
function randField() {
  // 31 byte rawak → pasti < BN254 scalar field
  return BigInt("0x" + crypto.randomBytes(31).toString("hex")).toString();
}

async function main() {
  const a = process.argv.slice(2);
  const bountyId  = arg(a, "--bounty", null);
  const severity  = arg(a, "--severity", null);
  const claimer   = arg(a, "--claimer", null);   // address white-hat (0x...)
  const secret    = arg(a, "--secret", randField());
  const salt      = arg(a, "--salt", randField());

  if (bountyId === null) throw new Error("--bounty wajib");
  if (severity === null) throw new Error("--severity wajib");
  if (claimer === null)  throw new Error("--claimer wajib (address white-hat)");
  if (!ethers.isAddress(claimer)) throw new Error("--claimer bukan address sah");

  const sev = Number(severity);
  if (!Number.isInteger(sev) || sev < 1 || sev > 10) throw new Error("severity mesti 1..10");

  const claimerBig = BigInt(claimer).toString();          // uint160 → field
  const circuitDir = path.join(__dirname, "../circuits");

  console.log("=== zkBounty Prover CLI (Poseidon5) ===");
  console.log("Bounty  :", bountyId);
  console.log("Severity:", severity);
  console.log("Claimer :", claimer);

  // Poseidon(5): secret, salt, severity, bounty_id, claimer_addr
  const poseidon = await buildPoseidon();
  const F = poseidon.F;
  const commitment = F.toString(poseidon([
    BigInt(secret), BigInt(salt), BigInt(sev), BigInt(bountyId), BigInt(claimerBig)
  ]));
  console.log("Commitment:", commitment);

  const input = {
    secret: secret,
    salt: salt,
    commitment: commitment,
    severity: String(sev),
    bounty_id: bountyId,
    claimer_addr: claimerBig
  };
  fs.writeFileSync("/tmp/ek2_input.json", JSON.stringify(input, null, 2));

  const wasmPath = path.join(circuitDir, "exploit_knowledge_js/exploit_knowledge.wasm");
  const zkeyPath = path.join(circuitDir, "exploit_knowledge_final.zkey");
  const vkeyPath = path.join(circuitDir, "verification_key.json");

  for (const p of [wasmPath, zkeyPath, vkeyPath]) {
    if (!fs.existsSync(p)) throw new Error(`Artifact hilang: ${p} — jalankan trusted setup dulu`);
  }

  const wtnsPath = "/tmp/ek2_witness.wtns";
  await snarkjs.wtns.calculate(input, wasmPath, wtnsPath);

  const { proof, publicSignals } = await snarkjs.groth16.prove(zkeyPath, wtnsPath);

  const vkey = JSON.parse(fs.readFileSync(vkeyPath));
  const ok = await snarkjs.groth16.verify(vkey, publicSignals, proof);
  if (!ok) throw new Error("Proof tak sah selepas jana — berhenti");

  // publicSignals layout: [commitment, severity, bounty_id, claimer_addr]
  // Format calldata untuk revealProof
  const cd = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
  const [pA, pB, pC, pub] = JSON.parse("[" + cd + "]");

  // commitHash untuk commit-reveal: keccak256(abi.encode(pA,pB,pC,pubSignals,nonce))
  const nonce = "0x" + crypto.randomBytes(32).toString("hex");
  const coder = ethers.AbiCoder.defaultAbiCoder();
  const commitHash = ethers.keccak256(coder.encode(
    ["uint256[2]", "uint256[2][2]", "uint256[2]", "uint256[4]", "bytes32"],
    [pA, pB, pC, pub, nonce]
  ));

  const out = {
    bountyId, severity: sev, claimer,
    commitment, secret, salt, nonce, commitHash,
    proof: { pA, pB, pC }, publicSignals: pub,
    timestamp: new Date().toISOString()
  };
  const outFile = `proof_bounty_${bountyId}.json`;
  fs.writeFileSync(outFile, JSON.stringify(out, null, 2));

  console.log("\n✅ PROOF + COMMIT-REVEAL SIAP");
  console.log("   File       :", outFile);
  console.log("   commitHash :", commitHash);
  console.log("   nonce      :", nonce, "(RAHSIA sampai reveal)");
  console.log("\n   1) commitProof(", bountyId, ", commitHash)");
  console.log("   2) tunggu, lepas tu revealProof(", bountyId, ", pA,pB,pC, publicSignals, nonce)");
}

main().catch(e => { console.error("ERROR:", e.message); process.exit(1); });
