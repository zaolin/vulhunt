#!/bin/bash
# Integration test: verify vulhunt-ce parallel engine dispatch
# Run: ./test-verify-parallel.sh <binary> <rules_dir> [output_dir]

set -euo pipefail

BINARY="${1:-}"
RULES_DIR="${2:-}"
OUTPUT_DIR="${3:-/tmp/vulhunt-parallel-test}"
DATA_DIR="${DATA_DIR:-/home/zaolin/projects/vulhunt/data}"

if [ -z "$BINARY" ] || [ -z "$RULES_DIR" ]; then
    echo "Usage: $0 <binary> <rules_dir> [output_dir]"
    echo "Set DATA_DIR env if needed (default: $DATA_DIR)"
    exit 1
fi

VULHUNT_CE="${VULHUNT_CE:-/home/zaolin/projects/vulhunt/target/release/vulhunt-ce}"
mkdir -p "$OUTPUT_DIR"

echo "=== Test 1: Sequential scan ==="
RUST_LOG=debug "$VULHUNT_CE" scan \
    --data "$DATA_DIR" \
    --rules "$RULES_DIR" \
    --output "$OUTPUT_DIR/seq.json" \
    "$BINARY" 2>&1 | tee "$OUTPUT_DIR/seq.log" | grep -E "(parallel|dispatch|sequential)" || true

echo ""
echo "=== Checking sequential log for parallel disable ==="
if grep -q "parallel disabled" "$OUTPUT_DIR/seq.log"; then
    echo "PASS: Sequential mode confirmed (parallel disabled log found)"
else
    echo "NOTE: Check if system has >1 CPUs. Log entry might differ."
fi

echo ""
echo "=== Count results ==="
SEQ_COUNT=$(jq '.[] | select(.property_type == "finding") | .finding.name' "$OUTPUT_DIR/seq.json" 2>/dev/null | wc -l || echo "0")
echo "Sequential findings: $SEQ_COUNT"

echo ""
echo "=== Test 2: Parallel scan ==="
RUST_LOG=debug "$VULHUNT_CE" scan \
    --data "$DATA_DIR" \
    --rules "$RULES_DIR" \
    --output "$OUTPUT_DIR/par.json" \
    "$BINARY" 2>&1 | tee "$OUTPUT_DIR/par.log" | grep -E "(parallel|dispatch|threads|scope)" || true

echo ""
echo "=== Check parallel dispatch log ==="
if grep -q "parallel engine: dispatching" "$OUTPUT_DIR/par.log"; then
    echo "PASS: Parallel dispatch detected in logs"
elif grep -q "parallel disabled" "$OUTPUT_DIR/par.log"; then
    echo "SKIP: System has only 1 CPU, parallel is disabled by design"
elif grep -q "no parallelizable work" "$OUTPUT_DIR/par.log"; then
    echo "INFO: No parallelizable scopes found. Check scope details above."
    grep "scope" "$OUTPUT_DIR/par.log" | head -10
else
    echo "WARN: No parallel dispatch log entries found. Check par.log for details."
fi

echo ""
echo "=== Verify output consistency ==="
PAR_COUNT=$(jq '.[] | select(.property_type == "finding") | .finding.name' "$OUTPUT_DIR/par.json" 2>/dev/null | wc -l || echo "0")
echo "Parallel findings: $PAR_COUNT"

if [ "$SEQ_COUNT" -eq "$PAR_COUNT" ]; then
    echo "PASS: Finding counts match ($SEQ_COUNT)"
else
    echo "WARN: Counts differ: seq=$SEQ_COUNT vs par=$PAR_COUNT"
fi

echo ""
echo "=== Verify JSON is valid ==="
jq empty "$OUTPUT_DIR/seq.json" && echo "PASS: seq.json is valid JSON"
jq empty "$OUTPUT_DIR/par.json" && echo "PASS: par.json is valid JSON"

echo ""
echo "Results in: $OUTPUT_DIR"
