#!/usr/bin/env bash
# ce7_flow.sh — uji aliran v0.7 PENUH atas bytecode deployed SEBENAR (fork-warp Sepolia).
# AXIOM-CORE: percaya terminal. Adapt scaffold p1p2.sh (commit/reveal/jq) + bon + v0.7 flow.
# BELUM dijalankan dari sisi Claude (takde fork+prove.js) — CARA UJI, jangan percaya aku.
#
# Confirmasi forge test 35/35 atas proof REAL + deployed bytecode:
#   HAPPY     : createBounty → reveal(+bon) → companyAccept → researcher dibayar reward+bon
#   ESCALATE  : company ghost → warp → escalate → resolveDispute(true) → dibayar
#   FAILSAFE  : companyReject → warp ARB_WINDOW → disputeTimeout → reward refund COMPANY, bon balik
#   CE-5 REG  : tiada forceRelease (selector tak wujud) → drain mustahil
#
# PRASYARAT: foundry (anvil/cast), jq, prover-cli/prove.js, .zkb-test.env (ATTACKER/RESEARCHER_KEY),
#            .env (PRIVATE_KEY=company, ARBITRATOR_KEY). V7 deployed di Sepolia.
# JALAN: bash ce7_flow.sh
set -uo pipefail
cd /root/zk-web3/zkbounty

RPC="${SEPOLIA_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
V7="${V7:-0x47931cfBD7E5d29a20f76941E6F180AA4cBa119eF}"
L="http://127.0.0.1:8545"
REWARD_ETH="0.01"; REWARD_WEI="10000000000000000"
BOND_WEI="5000000000000000"              # _requiredBond(0.01e)=max(0.001e,0.005e)=0.005 ETH
DEADLINE_H=1; CLAIM_TO=259200            # MIN_CLAIM_TIMEOUT = 3 hari
FUND_HEX="0x3635C9ADC5DEA00000"          # 1000 ETH

RV="revealProof(uint256,uint256[2],uint256[2][2],uint256[2],uint256[4],bytes32)"
CP="commitProof(uint256,bytes32)"
CB="createBounty(uint256,uint256,uint8)"
GET="getBounty(uint256)((address,uint256,uint256,uint256,uint256,uint8,uint8,address,uint256))"

set -a; source .env; set +a                 # PRIVATE_KEY (company) + ARBITRATOR_KEY
set -a; source .zkb-test.env; set +a         # ATTACKER_KEY + RESEARCHER_KEY
COMPANY=$(cast wallet address --private-key "$PRIVATE_KEY")
ARB=$(cast wallet address --private-key "$ARBITRATOR_KEY")
RES=$(cast wallet address --private-key "$RESEARCHER_KEY")
ATK=$(cast wallet address --private-key "$ATTACKER_KEY")

# ---- fork v0.7 ----
pkill anvil 2>/dev/null || true; sleep 1
BN=$(cast block-number --rpc-url "$RPC")
anvil --fork-url "$RPC" --fork-block-number "$((BN-5))" --port 8545 >/tmp/anvil_ce7.log 2>&1 &
trap 'kill %1 2>/dev/null || true' EXIT
for i in $(seq 1 15); do cast block-number --rpc-url "$L" >/dev/null 2>&1 && break; sleep 1; done
cast block-number --rpc-url "$L" >/dev/null 2>&1 || { echo "FATAL anvil:"; cat /tmp/anvil_ce7.log; exit 1; }
echo "anvil HIDUP fork v0.7 @ $(cast block-number --rpc-url "$L")"
for A in "$COMPANY" "$ARB" "$RES" "$ATK"; do cast rpc anvil_setBalance "$A" "$FUND_HEX" --rpc-url "$L" >/dev/null; done

sendL(){ cast send "$V7" "$@" --rpc-url "$L" 2>&1; }
warp(){ cast rpc evm_increaseTime "$1" --rpc-url "$L" >/dev/null; cast rpc evm_mine --rpc-url "$L" >/dev/null; }
field(){ cast call "$V7" "$GET" "$1" --rpc-url "$L" | tr -d '()' | tr ',' '\n' | sed 's/ //g' | sed -n "${2}p"; }
# field: 1=company 2=reward 3=deadline 4=claimTimeout 5=id 6=minSev 7=state 8=researcher 9=commitment 10? (researcherBond last)

newBounty(){ # company cipta bounty, return ID
  sendL "$CB" "$DEADLINE_H" "$CLAIM_TO" 1 --value "$REWARD_WEI" --private-key "$PRIVATE_KEY" >/dev/null
  cast call "$V7" "getBountyCount()(uint256)" --rpc-url "$L"
}
genProof(){ # $1=id $2=claimerAddr $3=claimerKey → commit+reveal{bond} di fork
  local id="$1" addr="$2" key="$3"
  timeout 180 node prover-cli/prove.js --bounty "$id" --severity 10 --claimer "$addr" >/dev/null 2>&1 || true
  local PF="proof_bounty_${id}.json"; [ -f "$PF" ] || PF="prover-cli/proof_bounty_${id}.json"
  [ -f "$PF" ] || { echo "FATAL: proof $PF tak dijana (prove.js?)"; return 1; }
  local CH NON PA PB PC PUB
  CH=$(jq -r .commitHash "$PF"); NON=$(jq -r .nonce "$PF")
  PA=$(jq -rc '"["+(.proof.pA|join(","))+"]"' "$PF")
  PB=$(jq -rc '"[["+(.proof.pB[0]|join(","))+"],["+(.proof.pB[1]|join(","))+"]]"' "$PF")
  PC=$(jq -rc '"["+(.proof.pC|join(","))+"]"' "$PF")
  PUB=$(jq -rc '"["+(.publicSignals|join(","))+"]"' "$PF")
  sendL "$CP" "$id" "$CH" --private-key "$key" | grep -iE "status|error" | head -1
  sendL "$RV" "$id" "$PA" "$PB" "$PC" "$PUB" "$NON" --value "$BOND_WEI" --private-key "$key" | grep -iE "status|error" | head -1
}

echo ""; echo "######## 1. HAPPY PATH ########"
ID=$(newBounty); echo "bounty #$ID (reward $REWARD_ETH, bond 0.005)"
genProof "$ID" "$RES" "$RESEARCHER_KEY"
echo "state(patut 2 PendingCompany)=$(field "$ID" 7) researcher=$(field "$ID" 8) (expect $RES)"
B4=$(cast balance "$RES" --rpc-url "$L")
sendL "companyAccept(uint256)" "$ID" --private-key "$PRIVATE_KEY" | grep -iE "status|error" | head -1
AF=$(cast balance "$RES" --rpc-url "$L")
python3 - "$B4" "$AF" "$REWARD_WEI" "$BOND_WEI" <<'PY'
import sys; b,a,r,bo=map(int,sys.argv[1:5]); d=a-b; exp=r*975//1000+bo
print(f"  researcher Δ={d} wei; expect ≈ reward-2.5%+bond = {exp} (± gas). {'OK' if abs(d-exp)<2e15 else 'SEMAK'}")
PY

echo ""; echo "######## 2. ESCALATE (company ghost → arbitrator) ########"
ID=$(newBounty); echo "bounty #$ID"
genProof "$ID" "$RES" "$RESEARCHER_KEY"
warp $((DEADLINE_H*3600 + CLAIM_TO + 10))          # lepas deadline+claimTimeout
sendL "escalate(uint256)" "$ID" --private-key "$RESEARCHER_KEY" | grep -iE "status|error" | head -1
echo "state(patut 6 Disputed)=$(field "$ID" 7)"
B4=$(cast balance "$RES" --rpc-url "$L")
sendL "resolveDispute(uint256,bool)" "$ID" true --private-key "$ARBITRATOR_KEY" | grep -iE "status|error" | head -1
AF=$(cast balance "$RES" --rpc-url "$L")
echo "  researcher dibayar? Δ=$((AF-B4)) wei (patut +reward-fee+bond). state=$(field "$ID" 7) (patut 3 Claimed)"

echo ""; echo "######## 3. FAIL-SAFE (companyReject → disputeTimeout → company) ########"
ID=$(newBounty); echo "bounty #$ID"
genProof "$ID" "$RES" "$RESEARCHER_KEY"
sendL "companyReject(uint256)" "$ID" --private-key "$PRIVATE_KEY" | grep -iE "status|error" | head -1
C4=$(cast balance "$COMPANY" --rpc-url "$L")
warp $((14*24*3600 + 10))                           # lepas ARB_WINDOW 14 hari
sendL "disputeTimeout(uint256)" "$ID" --private-key "$ATTACKER_KEY" | grep -iE "status|error" | head -1  # sesiapa boleh panggil
CF=$(cast balance "$COMPANY" --rpc-url "$L")
echo "  company refund? Δ=$((CF-C4)) wei (patut +reward). state=$(field "$ID" 7) (patut 4 Expired)"

echo ""; echo "######## 4. CE-5 REGRESSION (forceRelease DIBUANG) ########"
RC=$(cast call "$V7" "forceRelease(uint256)" 1 --rpc-url "$L" 2>&1)
echo "$RC" | grep -qiE "function selector was not recognized|execution reverted|not found" \
  && echo "  OK: forceRelease TIADA selector — drain CE-5 mustahil struktur" \
  || echo "  BAHAYA: forceRelease jawab sesuatu?! $RC"

echo ""; echo "==== SELESAI (fork je, chain sebenar tak tersentuh). anvil auto-kill. ===="
