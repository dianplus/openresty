#!/bin/bash
# Run ShellCheck on all scripts
# Usage: ./run-shellcheck.sh

set -e

# Check if shellcheck is installed
if ! command -v shellcheck &> /dev/null; then
    echo "ShellCheck is not installed. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install shellcheck
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y shellcheck
    else
        echo "Please install ShellCheck manually: https://github.com/koalaman/shellcheck"
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXIT_CODE=0

echo "Running ShellCheck on all scripts..."
echo ""

for script in "$SCRIPT_DIR"/*.sh; do
    if [ -f "$script" ]; then
        echo "Checking: $(basename "$script")"
        if shellcheck -x "$script"; then
            echo "✓ $(basename "$script") passed"
        else
            echo "✗ $(basename "$script") failed"
            EXIT_CODE=1
        fi
        echo ""
    fi
done

if [ $EXIT_CODE -eq 0 ]; then
    echo "All scripts passed ShellCheck!"
else
    echo "Some scripts failed ShellCheck. Please fix the issues above."
fi

exit $EXIT_CODE

