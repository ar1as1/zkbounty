# zkBounty v0.7 — MIGRATION + DEPLOY RUNBOOK (CARA UJI)

> AXIOM-CORE: betul → audit → baru deploy. JANGAN mainnet sebelum semua test LULUS +
> arbitrator = multisig bebas SEBENAR (bukan deployer). Chain tak menipu — cast call sahkan tiap langkah.

## FASA 0 — Gate sebelum sentuh deploy
```bash
cd /root/zk-web3/zkbounty
# 0a. CE-5 PoC repeatable (bukti masalah yang v0.7 selesaikan)
bash ce5_fork.sh                      # mesti tunjuk DELTA>0 (drain v0.6)
# 0b. apply CHANGE SPEC (zkbounty_v7_changes.md) atas src/ → build + test
forge build
forge test --match-contract ZkBountyV7Test -vvv
#   SEMUA 6 invariant mesti PASS. Kalau test_CE5_* GAGAL (drain berjaya) — JANGAN deploy.
# 0c. slither (static) atas kontrak v0.7
slither src/zkBounty.sol || true      # review reentrancy/arithmetic; 0 high mesti
```

## FASA 1 — Sediakan arbitrator + treasury BEBAS (gate mainnet sebenar)
- **arbitrator** = Gnosis Safe 2-of-3, **3 signer custody BERASINGAN** (bukan 2 kau pegang —
  independence = custody kunci, bukan bilangan; CE-3 eksploit tepat "2 kunci company").
  - Testnet: boleh Safe 2-of-3 wallet berasingan kau untuk uji aliran.
  - Mainnet: 3 entiti bebas betul. Kalau tak jumpa 3 → pertimbang jalan-2 (trusted-company,
    lebih lemah) atau Kleros — JANGAN multisig palsu.
- **treasury** = address sink forfeit. Cadang Safe berasingan, atau `0x…dEaD` (burn) kalau
  tiada guna ops. JANGAN = company/owner (elak motif kolusi).
- Sahkan Safe wujud + threshold:
```bash
cast call <SAFE_ARB> "getThreshold()(uint256)" --rpc-url $SEPOLIA_RPC   # = 2
cast call <SAFE_ARB> "getOwners()(address[])"   --rpc-url $SEPOLIA_RPC   # = 3 bebas
```

## FASA 2 — Deploy v0.7 (Pengajaran #11: --constructor-args PALING AKHIR; --broadcast depan args)
```bash
# reuse verifier v0.4 (uint[4]) yang dah padan circuit — JANGAN redeploy verifier
VER=0xb7645218565e27d599cA47D67eB89EF9285C59a2
FEE=0x8A534d5d7892adB16F191E7c11B4A2c9671D5781     # feeRecipient (sahkan ikut kau)
ARB=<SAFE_ARB_2of3>
TRE=<TREASURY_ADDR>

forge create src/zkBountyV7.sol:zkBountyV7 \
  --rpc-url $SEPOLIA_RPC --private-key $DEPLOYER_KEY \
  --broadcast \
  --constructor-args $VER $FEE $ARB $TRE
```
Sahkan SELEPAS deploy (R0):
```bash
V7=<alamat_baru>
cast call $V7 "arbitrator()(address)" --rpc-url $SEPOLIA_RPC   # = $ARB (BUKAN 0x0!)
cast call $V7 "treasury()(address)"   --rpc-url $SEPOLIA_RPC   # = $TRE
cast call $V7 "verifier()(address)"   --rpc-url $SEPOLIA_RPC   # = $VER
# cuba setArbitrator → mesti TIADA (revert/no-selector): bukti setter dibuang
cast call $V7 "setArbitrator(address)" $ARB --rpc-url $SEPOLIA_RPC 2>&1 | grep -qi "execution reverted\|not found" \
  && echo "OK: setArbitrator tiada" || echo "AMARAN: setArbitrator masih wujud?!"
```

## FASA 3 — Migrasi v0.6 (tiada dana sebenar: getBountyCount real = 0)
- Bounty test #3,#4 (PendingCompany, ~0.004 ETH, wallet test): settle atas v0.6 —
  `companyAccept` (bayar test-researcher) ATAU biar, ia testnet. Tiada migrasi dana sebenar.
- Frontend: App.jsx BOUNTY_ESCROW → $V7. Build + gh-pages (JANGAN guna `gh-pages` npm tool —
  cache token, R6/Pengajaran #12): `cd frontend && npm run build && cp dist/* <gh-root>/ && push`.
- **v0.6 (0x32F8) = DEPRECATE** — jangan createBounty real di situ (CE-5 live sana).

## FASA 4 — Smoke test aliran penuh atas v0.7 (fork dulu, baru testnet)
```bash
# fork v0.7: ulang pola ce5_fork.sh TAPI jangkaan = forceRelease TIADA (dibuang),
# drain GAGAL. Aliran sah: createBounty → reveal(+bond) → escalate → resolveDispute(true) → bayar.
```

## OPSEC push (R6) — token sekali guna, remote bersih
```bash
export HISTCONTROL=ignorespace
 git push "https://ar1as1:$(cat /root/.git-token)@github.com/ar1as1/zkbounty.git" main
grep -rl "ghp_" /root/*/.git/config; find /root -name "*ghp_*"   # kedua MESTI kosong
```
Commit TANPA Co-Authored-By trailer (keputusan black). `git log` nama egold je.
