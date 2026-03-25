#!/usr/bin/env bash
# Regenerate a single test baseline file with proper format
# Usage: ./regenerate-baseline.sh verify cn/test_file.c

set -euo pipefail

COMMAND=${1:-}
TEST_FILE=${2:-}

if [ -z "$COMMAND" ] || [ -z "$TEST_FILE" ]; then
    echo "Usage: $0 <command> <test-file>"
    echo "Example: $0 verify cn/example.c"
    exit 1
fi

# Extract directory and test config
TEST_DIR=$(dirname "$TEST_FILE")
CONFIG_FILE="$TEST_DIR/${COMMAND}.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: No config file $CONFIG_FILE"
    exit 1
fi

# Extract just the filename for --suffix parameter
TEST_FILENAME=$(basename "$TEST_FILE")
BASELINE_FILE="${TEST_FILE}.${COMMAND}"

echo "Regenerating baseline: $BASELINE_FILE"
./diff-prog.py cn "$CONFIG_FILE" --accept --max-workers=1 --suffix="$TEST_FILENAME"
echo "✓ Baseline updated: $BASELINE_FILE"
