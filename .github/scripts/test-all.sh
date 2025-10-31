#!/bin/bash
# Run all tests: syntax check, shellcheck, and workflow validation
# Usage: ./test-all.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Running All Tests ===${NC}\n"

# Test 1: Script syntax check
echo -e "${YELLOW}[1/3] Testing script syntax...${NC}"
if [ -f "test-scripts.sh" ]; then
    chmod +x test-scripts.sh
    ./test-scripts.sh all
    echo ""
else
    echo "test-scripts.sh not found, skipping..."
fi

# Test 2: ShellCheck
echo -e "${YELLOW}[2/3] Running ShellCheck...${NC}"
if [ -f "run-shellcheck.sh" ]; then
    chmod +x run-shellcheck.sh
    ./run-shellcheck.sh || echo "ShellCheck issues found (non-fatal)"
    echo ""
else
    echo "run-shellcheck.sh not found, skipping..."
fi

# Test 3: Workflow syntax
echo -e "${YELLOW}[3/3] Checking workflow syntax...${NC}"
if [ -f "test-workflow-syntax.sh" ]; then
    chmod +x test-workflow-syntax.sh
    ./test-workflow-syntax.sh || echo "Workflow syntax issues found (non-fatal)"
    echo ""
else
    echo "test-workflow-syntax.sh not found, skipping..."
fi

echo -e "${GREEN}=== All Tests Completed ===${NC}"

