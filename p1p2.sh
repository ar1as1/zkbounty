#!/usr/bin/env bash
set -uo pipefail
cd /root/zk-web3/zkbounty
RPC=https://ethereum-sepolia-rpc.publicnode.com
C=0x32F8e9Ba3b43586A34F9ba0CB2325433a23943F6
RV="revealProof(uint256,uint256[2],uint256[2][2],uint256[2],uint256[4],bytes32)"
CP="commitProof(uint256,bytes32)"
GET="getBounty(uint256)((address,uint256,uint256,uint256,uint256,uint8,uint8,address,uint256))"
set -a; source .zkb-test.env; set +a
ATK=$(cast wallet address --private-key "$ATTACKER_KEY")
RES=$(cast wallet address --private-key "$RESEARCHER_KEY")
ID=3
PF=proof_bounty_3.json; [ -f "$PF" ] || PF=prover-cli/proof_bounty_3.json
CH=$(jq -r .commitHash "$PF"); NON=$(jq -r .nonce "$PF")
PA=$(jq -rc '.proof.pA|"["+join(",")+"]"' "$PF")
PB=$(jq -rc '.proof.pB|"[["+(.[0]|join(","))+"],["+(.[1]|join(","))+"]]"' "$PF")
PC=$(jq -rc '.proof.pC|"["+join(",")+"]"' "$PF")
PUB=$(jq -rc '.publicSignals|"["+join(",")+"]"' "$PF")
send(){ cast send "$C" "$@" --rpc-url "$RPC" 2>&1; }
echo "=== bounty $ID researcher=$RES ==="
echo "[A3] ATTACKER commit garbage..."; send "$CP" "$ID" 0xdead000000000000000000000000000000000000000000000000000000000000 --private-key "$ATTACKER_KEY" | grep -iE "status|error"|head -1
sleep 5; echo "[A4] RESEARCHER commit (P1 mesti jaya)..."; send "$CP" "$ID" "$CH" --private-key "$RESEARCHER_KEY" | grep -iE "status|error"|head -1
sleep 5; echo "[A5] RESEARCHER reveal (menang)..."; send "$RV" "$ID" "$PA" "$PB" "$PC" "$PUB" "$NON" --private-key "$RESEARCHER_KEY" | grep -iE "status|error"|head -1
sleep 6; B=$(cast call "$C" "$GET" "$ID" --rpc-url "$RPC" | tr -d '()' | tr ',' '\n' | sed 's/ //g')
echo "--- state=$(echo "$B"|sed -n 7p) (2=WIN) researcher=$(echo "$B"|sed -n 8p) expect=$RES"
sleep 2; echo "[A6] P2 ATTACKER reveal (patut REVERT)..."; R2=$(send "$RV" "$ID" "$PA" "$PB" "$PC" "$PUB" "$NON" --private-key "$ATTACKER_KEY")
echo "$R2" | grep -qiE "revert|RevealWindowNotOpen|error" && echo "OK P2 REVERT" || echo "BAHAYA: $R2"
