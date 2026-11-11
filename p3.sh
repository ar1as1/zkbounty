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
ID=4
PF=proof_bounty_4.json; [ -f "$PF" ] || PF=prover-cli/proof_bounty_4.json
CH=$(jq -r .commitHash "$PF"); NON=$(jq -r .nonce "$PF")
PA=$(jq -rc '.proof.pA|"["+join(",")+"]"' "$PF")
PB=$(jq -rc '.proof.pB|"[["+(.[0]|join(","))+"],["+(.[1]|join(","))+"]]"' "$PF")
PC=$(jq -rc '.proof.pC|"["+join(",")+"]"' "$PF")
PUB=$(jq -rc '.publicSignals|"["+join(",")+"]"' "$PF")
send(){ cast send "$C" "$@" --rpc-url "$RPC" 2>&1; }
echo "=== P3 reveal-snipe bounty $ID ==="
echo "[B3] ATTACKER curi commitHash + commit DULU..."; send "$CP" "$ID" "$CH" --private-key "$ATTACKER_KEY" | grep -iE "status|error"|head -1
sleep 5; echo "[B4] P3: ATTACKER reveal proof researcher (patut AddressMismatch)..."
R3=$(send "$RV" "$ID" "$PA" "$PB" "$PC" "$PUB" "$NON" --private-key "$ATTACKER_KEY")
echo "$R3" | grep -qiE "revert|AddressMismatch|error" && echo "OK P3 REVERT (J5: proof terikat researcher)" || echo "BAHAYA: $R3"
sleep 5; echo "[B5] RESEARCHER commit..."; send "$CP" "$ID" "$CH" --private-key "$RESEARCHER_KEY" | grep -iE "status|error"|head -1
sleep 5; echo "[B6] RESEARCHER reveal (tetap menang)..."; send "$RV" "$ID" "$PA" "$PB" "$PC" "$PUB" "$NON" --private-key "$RESEARCHER_KEY" | grep -iE "status|error"|head -1
sleep 6; B=$(cast call "$C" "$GET" "$ID" --rpc-url "$RPC" | tr -d '()' | tr ',' '\n' | sed 's/ //g')
echo "--- state=$(echo "$B"|sed -n 7p) (2=WIN) researcher=$(echo "$B"|sed -n 8p) expect=$RES"
