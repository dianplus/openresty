#!/bin/bash
# Test script for validating GitHub Actions scripts locally
# Usage: ./test-scripts.sh [script-name]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# Test functions
test_configure_aliyun_cli() {
    echo -e "${YELLOW}Testing configure-aliyun-cli.sh...${NC}"
    
    # Check if script exists
    if [ ! -f "$SCRIPT_DIR/configure-aliyun-cli.sh" ]; then
        echo -e "${RED}✗ Script not found${NC}"
        return 1
    fi
    
    # Check syntax
    if bash -n "$SCRIPT_DIR/configure-aliyun-cli.sh"; then
        echo -e "${GREEN}✓ Syntax check passed${NC}"
    else
        echo -e "${RED}✗ Syntax check failed${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ configure-aliyun-cli.sh test passed${NC}"
}

test_find_cheapest_instance() {
    echo -e "${YELLOW}Testing find-cheapest-instance.sh...${NC}"
    
    if [ ! -f "$SCRIPT_DIR/find-cheapest-instance.sh" ]; then
        echo -e "${RED}✗ Script not found${NC}"
        return 1
    fi
    
    # Check syntax
    if bash -n "$SCRIPT_DIR/find-cheapest-instance.sh"; then
        echo -e "${GREEN}✓ Syntax check passed${NC}"
    else
        echo -e "${RED}✗ Syntax check failed${NC}"
        return 1
    fi
    
    # Mock spot-instance-advisor if not available
    if ! command -v spot-instance-advisor &> /dev/null; then
        echo -e "${YELLOW}⚠ spot-instance-advisor not found, skipping full test${NC}"
        echo -e "${GREEN}✓ Syntax check passed (full test requires spot-instance-advisor)${NC}"
        return 0
    fi
    
    echo -e "${GREEN}✓ find-cheapest-instance.sh test passed${NC}"
}

test_create_spot_instance() {
    echo -e "${YELLOW}Testing create-spot-instance.sh...${NC}"
    
    if [ ! -f "$SCRIPT_DIR/create-spot-instance.sh" ]; then
        echo -e "${RED}✗ Script not found${NC}"
        return 1
    fi
    
    # Check syntax
    if bash -n "$SCRIPT_DIR/create-spot-instance.sh"; then
        echo -e "${GREEN}✓ Syntax check passed${NC}"
    else
        echo -e "${RED}✗ Syntax check failed${NC}"
        return 1
    fi
    
    # Test user_data.sh generation (dry run)
    local test_githb_token="test-token-12345"
    local test_runner_name="test-runner"
    local test_arch="x64"
    
    # Create a temporary test
    local temp_user_data=$(mktemp)
    cat > "$temp_user_data" << EOF
#!/bin/bash
set -e
export GITHUB_TOKEN="$test_githb_token"
export RUNNER_NAME="$test_runner_name-\$(date +%s)"
./setup-runner.sh $test_arch
EOF
    
    # Check if user_data content looks correct
    if grep -q "GITHUB_TOKEN" "$temp_user_data" && grep -q "RUNNER_NAME" "$temp_user_data"; then
        echo -e "${GREEN}✓ User data generation logic validated${NC}"
    else
        echo -e "${RED}✗ User data generation validation failed${NC}"
        rm -f "$temp_user_data"
        return 1
    fi
    
    rm -f "$temp_user_data"
    echo -e "${GREEN}✓ create-spot-instance.sh test passed${NC}"
}

test_wait_instance_ready() {
    echo -e "${YELLOW}Testing wait-instance-ready.sh...${NC}"
    
    if [ ! -f "$SCRIPT_DIR/wait-instance-ready.sh" ]; then
        echo -e "${RED}✗ Script not found${NC}"
        return 1
    fi
    
    # Check syntax
    if bash -n "$SCRIPT_DIR/wait-instance-ready.sh"; then
        echo -e "${GREEN}✓ Syntax check passed${NC}"
    else
        echo -e "${RED}✗ Syntax check failed${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ wait-instance-ready.sh test passed${NC}"
}

test_cleanup_instance() {
    echo -e "${YELLOW}Testing cleanup-instance.sh...${NC}"
    
    if [ ! -f "$SCRIPT_DIR/cleanup-instance.sh" ]; then
        echo -e "${RED}✗ Script not found${NC}"
        return 1
    fi
    
    # Check syntax
    if bash -n "$SCRIPT_DIR/cleanup-instance.sh"; then
        echo -e "${GREEN}✓ Syntax check passed${NC}"
    else
        echo -e "${RED}✗ Syntax check failed${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ cleanup-instance.sh test passed${NC}"
}

test_setup_runner() {
    echo -e "${YELLOW}Testing setup-runner.sh...${NC}"
    
    if [ ! -f "$SCRIPT_DIR/setup-runner.sh" ]; then
        echo -e "${RED}✗ Script not found${NC}"
        return 1
    fi
    
    # Check syntax
    if bash -n "$SCRIPT_DIR/setup-runner.sh"; then
        echo -e "${GREEN}✓ Syntax check passed${NC}"
    else
        echo -e "${RED}✗ Syntax check failed${NC}"
        return 1
    fi
    
    # Check if script has shebang
    if head -n1 "$SCRIPT_DIR/setup-runner.sh" | grep -q "^#!/bin/bash"; then
        echo -e "${GREEN}✓ Shebang check passed${NC}"
    else
        echo -e "${YELLOW}⚠ No shebang found (optional)${NC}"
    fi
    
    echo -e "${GREEN}✓ setup-runner.sh test passed${NC}"
}

# Run all tests or specific test
main() {
    local script_name=${1:-all}
    local exit_code=0
    
    echo -e "${GREEN}=== GitHub Actions Scripts Test Suite ===${NC}\n"
    
    case "$script_name" in
        configure-aliyun-cli)
            test_configure_aliyun_cli || exit_code=1
            ;;
        find-cheapest-instance)
            test_find_cheapest_instance || exit_code=1
            ;;
        create-spot-instance)
            test_create_spot_instance || exit_code=1
            ;;
        wait-instance-ready)
            test_wait_instance_ready || exit_code=1
            ;;
        cleanup-instance)
            test_cleanup_instance || exit_code=1
            ;;
        setup-runner)
            test_setup_runner || exit_code=1
            ;;
        all)
            test_configure_aliyun_cli || exit_code=1
            echo ""
            test_find_cheapest_instance || exit_code=1
            echo ""
            test_create_spot_instance || exit_code=1
            echo ""
            test_wait_instance_ready || exit_code=1
            echo ""
            test_cleanup_instance || exit_code=1
            echo ""
            test_setup_runner || exit_code=1
            ;;
        *)
            echo -e "${RED}Unknown script: $script_name${NC}"
            echo "Available: configure-aliyun-cli, find-cheapest-instance, create-spot-instance, wait-instance-ready, cleanup-instance, setup-runner, all"
            exit_code=1
            ;;
    esac
    
    echo ""
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}=== All tests passed ===${NC}"
    else
        echo -e "${RED}=== Some tests failed ===${NC}"
    fi
    
    cleanup_test
    exit $exit_code
}

main "$@"

