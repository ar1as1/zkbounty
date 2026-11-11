#!/usr/bin/env bash
set -uo pipefail
cd /root/zk-web3/zkbounty
RPC=https://ethereum-sepolia-rpc.publicnode.com
C=0x32F8e9Ba3b43586A34F9ba0CB2325433a23943F6
GET="getBounty(uint256)((address,uint256,uint256,uint256,uint256,uint8,uint8,address,uint256))"
RV="revealProof(uint256,uint256[2],uint256[2][2],uint256[2],uint256[4],bytes32)"
CP="commitProof(uint256,bytes32)"
GARBAGE=0xdead000000000000000000000000000000000000000000000000000000000000
set -a; source .zkb-test.env; set +a
DEP=$(grep -oE 'PRIVATE_KEY=0x[0-9a-fA-F]{64}' .env | head -1 | cut -d= -f2)
ATK=$(cast wallet address --private-key "$ATTACKER_KEY")
RES=$(cast wallet address --private-key "$RESEARCHER_KEY")
send(){ cast send "$C" "$@" --rpc-url "$RPC" 2>&1; }
st(){ echo "$1" | grep -oiE "status +[0-9]+ *\(?(success|failed)?" | head -1; }
mkbounty(){ send "createBounty(uint256,uint256,uint8)" 72 604800 5 --value 0.001ether --private-key "$DEP" >/dev/null; sleep 6; cast call "$C" "getBountyCount()(uint256)" --rpc-url "$RPC"; }
genproof(){ node prover-cli/prove.js --bounty "$1" --severity 5 --claimer "$RES" >/dev/null 2>&1; ls -t proof_bounty_$1.json prover-cli/proof_bounty_$1.json 2>/dev/null | head -1; }
f(){ jq -rc "$2" "$1"; }
load(){ PF=$1; CH=$(f "$PF" .commitHash); NON=$(f "$PF" .nonce)
  PA=$(f "$PF" '.proof.pA|"["+join(",")+"]"'); PB=$(f "$PF" '.proof.pB|"[["+(.[0]|join(","))+"],["+(.[1]|join(","))+"]]"')
  PC=$(f "$PF" '.proof.pC|"["+join(",")+"]"'); PUB=$(f "$PF" '.publicSignals|"["+join(",")+"]"'); }

echo "=========== P1+P2 (bounty A) ==========="
IDA=$(mkbounty); echo "[A] createBounty -> id=$IDA"; [ "$IDA" = 0 ] && { echo "STOP id0"; exit 1; }
load "$(genproof "$IDA")"; echo "    commitHash=$CH"
echo "[A3] ATTACKER commit garbage (front-run)..."; st "$(send "$CP" "$IDA" "$GARBAGE" --private-key "$ATTACKER_KEY")"
sleep 4; echo "[A4] RESEARCHER commit (P1: MESTI jaya)..."; st "$(send "$CP" "$IDA" "$CH" --private-key "$RESEARCHER_KEY")"
sleep 4; echo "[A5] RESEARCHER reveal (P1: menang)..."; st "$(send "$RV" "$IDA" "$PA" "$PB" "$PC" "$PUB" "$NON" --private-key "$RESEARCHER_KEY")"
B=$(cast call "$C" "$GET" "$IDA" --rpc-url "$RPC" | tr -d '()' | tr ',' '\n' | sed 's/ //g')
echo "    state=$(echo "$B"|sed -n 7p) (2=PendingCompany=WIN)  researcher=$(echo "$B"|sed -n 8p)"
echo "    expect researcher=$RES"
sleep 4; echo "[A6] P2: ATTACKER reveal (patut REVERT)..."
R2=$(send "$RV" "$IDA" "$PA" "$PB" "$PC" "$PUB" "$NON" --private-key "$ATTACKER_KEY")
echo "$R2" | grep -qiE "revert|RevealWindowNotOpen|error" && echo "    OK P2 REVERT (attacker tak menang)" || echo "    BAHAYA: $R2"

echo ""; echo "=========== P3 reveal-snipe (bounty B) ==========="
IDB=$(mkbounty); echo "[B] createBounty -> id=$IDB"
load "$(genproof "$IDB")"
echo "[B3] ATTACKER curi commitHash + commit dulu..."; st "$(send "$CP" "$IDB" "$CH" --private-key "$ATTACKER_KEY")"
sleep 4; echo "[B4] P3: ATTACKER reveal proof researcher (patut AddressMismatch)..."
R3=$(send "$RV" "$IDB" "$PA" "$PB" "$PC" "$PUB" "$NON" --private-key "$ATTACKER_KEY")
echo "$R3" | grep -qiE "revert|AddressMismatch|error" && echo "    OK P3 REVERT (J5: proof terikat researcher)" || echo "    BAHAYA: $R3"
sleep 4; echo "[B5] RESEARCHER commit+reveal (tetap menang)..."
st "$(send "$CP" "$IDB" "$CH" --private-key "$RESEARCHER_KEY")"; sleep 4
st "$(send "$RV" "$IDB" "$PA" "$PB" "$PC" "$PUB" "$NON" --private-key "$RESEARCHER_KEY")"
echo ""; echo "=========== SIAP ==========="
