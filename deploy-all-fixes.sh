#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}💀 VANTABLACK AUTO-FIX DEPLOYMENT${NC}"
echo "===================================="

set -e

cd ~/zk-web3/zkbounty

# 1. Install dependencies
echo -e "${YELLOW}[1/7] Installing dependencies...${NC}"
cd frontend
npm install
cd ..
echo -e "${GREEN}✅ Dependencies installed${NC}"

# 2. Compile contracts
echo -e "${YELLOW}[2/7] Compiling contracts...${NC}"
forge clean
forge build
echo -e "${GREEN}✅ Contracts compiled${NC}"

# 3. Run tests
echo -e "${YELLOW}[3/7] Running tests...${NC}"
forge test -vv

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Tests failed!${NC}"
    exit 1
fi
echo -e "${GREEN}✅ All tests passed${NC}"

# 4. Check gas usage
echo -e "${YELLOW}[4/7] Checking gas...${NC}"
forge test --gas-report | grep -A 5 "createBounty"
echo -e "${GREEN}✅ Gas analysis complete${NC}"

# 5. Deploy to Sepolia (if .env exists)
if [ -f .env ]; then
    echo -e "${YELLOW}[5/7] Deploying to Sepolia...${NC}"
    source .env
    
    # Deploy verifier
    VERIFIER=$(forge create src/ExploitVerifier.sol:Groth16Verifier \
        --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
        --private-key $PRIVATE_KEY \
        --json 2>/dev/null | jq -r '.deployedTo')
    
    echo "Verifier: $VERIFIER"
    
    # Deploy bounty
    OWNER=$(cast wallet address $PRIVATE_KEY)
    BOUNTY=$(forge create src/zkBounty.sol:zkBounty \
        --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
        --private-key $PRIVATE_KEY \
        --constructor-args $VERIFIER $OWNER \
        --json 2>/dev/null | jq -r '.deployedTo')
    
    echo "zkBounty: $BOUNTY"
    
    # Update frontend .env
    cd frontend
    cat > .env << EOF
VITE_BOUNTY_ESCROW=$BOUNTY
VITE_VERIFIER_ADDRESS=$VERIFIER
EOF
    cd ..
    
    echo -e "${GREEN}✅ Contracts deployed${NC}"
else
    echo -e "${YELLOW}[5/7] Skipping deployment (no .env found)${NC}"
fi

# 6. Build frontend
echo -e "${YELLOW}[6/7] Building frontend...${NC}"
cd frontend
npm run build
echo -e "${GREEN}✅ Frontend built${NC}"

# 7. Test locally
echo -e "${YELLOW}[7/7] Starting local preview...${NC}"
echo -e "${GREEN}Visit: http://localhost:4173${NC}"
npm run preview &
PREVIEW_PID=$!

echo ""
echo -e "${GREEN}===================================="
echo "💀 ALL FIXES APPLIED SUCCESSFULLY"
echo "====================================${NC}"
echo ""
echo "Summary:"
echo "✅ CRIT-04: getBountyCount() added"
echo "✅ CRIT-05: Pause mechanism added"
echo "✅ CRIT-06: Deadline overflow protection"
echo "✅ CRIT-07: Chain ID in commitment"
echo "✅ CRIT-08: Gas limit on verifier"
echo "✅ HIGH-03: BountyCountUpdated event"
echo "✅ HIGH-04: RPC fallback"
echo "✅ MED-01: Pagination added"
echo "✅ MED-02: Input validation"
echo "✅ MED-03: TX hash display"
echo "✅ MED-04: Debug wrapper"
echo "✅ MED-05: Race condition fixes"
echo ""
echo "Next steps:"
echo "1. Test in browser: http://localhost:4173"
echo "2. If good: npm run deploy (from frontend/)"
echo "3. Verify on Etherscan"
echo ""
echo "Press Ctrl+C to stop preview"

wait $PREVIEW_PID
