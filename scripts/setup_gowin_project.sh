#!/usr/bin/env bash
# setup_gowin_project.sh — Prepare the Gowin IDE project after a fresh clone.
#
# The Gowin IDE maintains its own source copies under ternarycore-secure/src/
# and expects firmware at ternarycore-secure/firmware/.  These paths are
# gitignored except for the constraint file, which is tracked.
#
# Run once after cloning (or after updating constr/tangnano.cst):
#   bash scripts/setup_gowin_project.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GOWIN_DIR="$ROOT/ternarycore-secure"

echo "[setup] Root: $ROOT"

# 1. Sync RTL sources into the Gowin project src/ directory
mkdir -p "$GOWIN_DIR/src"
for f in "$ROOT"/rtl/*.v; do
    cp "$f" "$GOWIN_DIR/src/"
    echo "[setup] Copied $(basename "$f") → ternarycore-secure/src/"
done

# 2. Sync constraints (source of truth is constr/tangnano.cst)
cp "$ROOT/constr/tangnano.cst"  "$GOWIN_DIR/src/ternarycore-secure.cst"
cp "$ROOT/constr/tangnano.sdc"  "$GOWIN_DIR/src/ternarycore-secure.sdc"
echo "[setup] Synced constraints → ternarycore-secure/src/"

# 3. Make firmware hex available to Gowin synthesis ($readmemh resolution)
mkdir -p "$GOWIN_DIR/firmware"
cp "$ROOT/firmware/firmware_words.hex" "$GOWIN_DIR/firmware/firmware_words.hex"
echo "[setup] Copied firmware_words.hex → ternarycore-secure/firmware/"

echo "[setup] Done. Open ternarycore-secure/ternarycore-secure.gprj in Gowin IDE and run Synthesis → P&R → Bitstream."
