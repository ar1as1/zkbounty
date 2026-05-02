
const { buildPoseidon } = require("circomlibjs");
const snarkjs = require("snarkjs");
const fs = require("fs");
const path = require("path");

async function main() {
  const args = process.argv.slice(2);
  const bountyId = args[args.indexOf("--bounty") + 1] || "0";
  const e0 = args[args.indexOf("--e0") + 1] || "123456789";
  const e1 = args[args.indexOf("--e1") + 1] || "987654321";
  const e2 = args[args.indexOf("--e2") + 1] || "111222333";
  const e3 = args[args.indexOf("--e3") + 1] || "444555666";
  const severity = args[args.indexOf("--severity") + 1] || "4";
  const minSeverity = args[args.indexOf("--min") + 1] || "3";
  const targetId = args[args.indexOf("--target") + 1] || "42";

  const circuitDir = path.join(__dirname, "../circuits");

  console.log("=== zkBounty Prover CLI ===");
  console.log("Bounty ID  :", bountyId);
  console.log("Target ID  :", targetId);
  console.log("Severity   :", severity);

  // Step 1: Compute Poseidon hash
  console.log("\n[1] Computing Poseidon hash...");
  const poseidon = await buildPoseidon();
  const exploit_data = [BigInt(e0), BigInt(e1), BigInt(e2), BigInt(e3)];
  const hash = poseidon(exploit_data);
  const hashStr = poseidon.F.toString(hash);
  console.log("    Hash:", hashStr);

  // Step 2: Build input.json
  const input = {
    exploit_data: [e0, e1, e2, e3],
    severity: severity,
    committed_hash: hashStr,
    target_id: targetId,
    min_severity: minSeverity
  };
  fs.writeFileSync("/tmp/input_temp.json", JSON.stringify(input, null, 2));
  console.log("    Input saved.");

  // Step 3: Generate witness using circom generated script
  console.log("\n[2] Generating witness...");
  const wasmPath = path.join(circuitDir, "exploit_knowledge_js/exploit_knowledge.wasm");
  const wtnsPath = "/tmp/witness_temp.wtns";

  // Use snarkjs.wtns.calculate correctly
  await snarkjs.wtns.calculate(
    input,
    wasmPath,
    wtnsPath
  );
  console.log("    Witness generated.");

  // Step 4: Generate proof
  console.log("\n[3] Generating Groth16 proof...");
  const zkeyPath = path.join(circuitDir, "exploit_knowledge_final.zkey");
  const { proof, publicSignals } = await snarkjs.groth16.prove(
    zkeyPath,
    wtnsPath
  );

  // Step 5: Verify locally
  console.log("\n[4] Verifying proof...");
  const vkeyPath = path.join(circuitDir, "verification_key.json");
  const vkey = JSON.parse(fs.readFileSync(vkeyPath));
  const valid = await snarkjs.groth16.verify(vkey, publicSignals, proof);
  console.log("    Valid:", valid);

  // Step 6: Save output
  const output = {
    bountyId: bountyId,
    committedHash: hashStr,
    proof: proof,
    publicSignals: publicSignals,
    timestamp: new Date().toISOString()
  };
  const outFile = "proof_bounty_" + bountyId + ".json";
  fs.writeFileSync(outFile, JSON.stringify(output, null, 2));

  if (valid) {
    console.log("\n✅ PROOF GENERATED!");
    console.log("   File:", outFile);
    console.log("   Hash:", hashStr);
    console.log("\n   Next:");
    console.log("   node prover-cli/claim.js --bounty", bountyId, "--proof", outFile);
  } else {
    console.log("\n ERROR: Proof invalid!");
  }

  // Cleanup
  try { fs.unlinkSync(wtnsPath); } catch(e) {}
  try { fs.unlinkSync("/tmp/input_temp.json"); } catch(e) {}
}

main().catch(console.error);
