#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/zoyoe/codex/my_dbeaver"
APP="$ROOT/tools/DBeaver-MFA.app"
WORKSPACE="$ROOT/tools/dbeaver-mfa-workspace"
LOG="$WORKSPACE/.metadata/dbeaver-debug.log"
SEED_SCRIPT="$ROOT/dbeaver-src/scripts/seed-dbeaver-mfa-connection.sh"

mkdir -p "$WORKSPACE"
"$SEED_SCRIPT"

open -n -a "$APP" --args -data "$WORKSPACE"

echo "DBeaver-MFA launched with workspace: $WORKSPACE"
echo "Log: $LOG"
echo "Press Ctrl-C to stop watching the log."

while [ ! -f "$LOG" ]; do
  sleep 1
done

tail -n 80 -f "$LOG"
