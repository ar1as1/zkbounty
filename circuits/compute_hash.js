const { buildPoseidon } = require("circomlibjs");

async function main() {
    const poseidon = await buildPoseidon();
    
    // Same values as input.json exploit_data
    const exploit_data = [
        BigInt("123456789"),
        BigInt("987654321"),
        BigInt("111222333"),
        BigInt("444555666")
    ];
    
    const hash = poseidon(exploit_data);
    const hashStr = poseidon.F.toString(hash);
    
    console.log("Poseidon Hash:", hashStr);
    
    // Auto-update input.json
    const fs = require("fs");
    const input = {
        exploit_data: ["123456789", "987654321", "111222333", "444555666"],
        severity: "4",
        committed_hash: hashStr,
        target_id: "42",
        min_severity: "3"
    };
    
    fs.writeFileSync("input.json", JSON.stringify(input, null, 2));
    console.log("input.json updated with real hash!");
}

main().catch(console.error);
