#!/usr/bin/env bash
set -euo pipefail

USAGE="Usage: $0 [verify|test|seq-test] [cn|cn-test-gen|cn-seq-test-gen|all]"

COMMAND=${1:-}
DIR=${2:-all}

if [ -z "$COMMAND" ]; then
    echo "$USAGE"
    exit 1
fi

run_test() {
    local cmd=$1
    local dir=$2
    local config_file="$dir/${cmd}.json"

    if [ ! -f "$config_file" ]; then
        echo "⚠ No config: $config_file (skipping)"
        return 0
    fi

    echo "▶ Running: cn $cmd on $dir"
    ./diff-prog.py cn "$config_file" 2>&1 | tail -5
    echo ""
}

case "$DIR" in
    cn)
        run_test "$COMMAND" "cn"
        ;;
    cn-test-gen)
        run_test "$COMMAND" "cn-test-gen/src"
        ;;
    cn-seq-test-gen)
        run_test "$COMMAND" "cn-seq-test-gen/src"
        ;;
    all)
        run_test "$COMMAND" "cn"
        run_test "$COMMAND" "cn-test-gen/src"
        run_test "$COMMAND" "cn-seq-test-gen/src"
        ;;
    *)
        echo "$USAGE"
        exit 1
        ;;
esac
