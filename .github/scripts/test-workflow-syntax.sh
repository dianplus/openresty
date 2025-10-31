#!/bin/bash
# Test GitHub Actions workflow YAML syntax
# Usage: ./test-workflow-syntax.sh

set -e

# Check if actionlint is installed
if ! command -v actionlint &> /dev/null; then
    echo "actionlint is not installed. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install actionlint
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Download actionlint binary
        curl -sSfL https://raw.githubusercontent.com/rhymond/actionlint/main/scripts/download-actionlint.bash | bash
        sudo mv actionlint /usr/local/bin/
    else
        echo "Please install actionlint manually: https://github.com/rhymond/actionlint"
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(dirname "$SCRIPT_DIR")/workflows"
EXIT_CODE=0

echo "Checking GitHub Actions workflow syntax..."
echo ""

if [ ! -d "$WORKFLOW_DIR" ]; then
    echo "Workflow directory not found: $WORKFLOW_DIR"
    exit 1
fi

for workflow in "$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml; do
    if [ -f "$workflow" ]; then
        echo "Checking: $(basename "$workflow")"
        if actionlint "$workflow"; then
            echo "✓ $(basename "$workflow") passed"
        else
            echo "✗ $(basename "$workflow") failed"
            EXIT_CODE=1
        fi
        echo ""
    fi
done

if [ $EXIT_CODE -eq 0 ]; then
    echo "All workflows passed actionlint!"
else
    echo "Some workflows failed actionlint. Please fix the issues above."
fi

exit $EXIT_CODE

