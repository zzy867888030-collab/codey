#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/zoyoe/codex/my_dbeaver"
APP="$ROOT/tools/DBeaver-MFA.app"
WORKSPACE="$ROOT/tools/dbeaver-mfa-workspace"
TUNNEL="$ROOT/tools/dbeaver-mfa-tunnel.py"
LOG="$WORKSPACE/.metadata/dbeaver-debug.log"

# Clean workspace metadata for fresh start
rm -rf "$WORKSPACE/.metadata"
mkdir -p "$WORKSPACE"

# Seed connection
bash "$ROOT/dbeaver-src/scripts/seed-dbeaver-direct-connection.sh"

echo "============================================"
echo " DBeaver MFA Tunnel Launcher"
echo " (ssh -J -L, direct OpenSSH)"
echo "============================================"
echo ""
echo "Route: zhangzhiyu@192.168.31.88:60022"
echo "  └─> mnyjy@192.168.77.38:22"
echo "       └─> 192.168.77.39:3306"
echo "Local: 127.0.0.1:3307"
echo ""
echo "Uses ssh -J -L (OpenSSH native) instead of DBeaver internal tunnel"
echo "to work around MINA SSHD 0.9.5 direct-tcpip bug."
echo "============================================"
echo ""

# Start tunnel
python3 "$TUNNEL" &
TUNNEL_PID=$!

# Wait for tunnel to be ready
echo "Waiting for tunnel on 127.0.0.1:3307..."
for i in $(seq 1 60); do
  if nc -vz 127.0.0.1 3307 2>/dev/null; then
    echo "Tunnel is ready!"
    break
  fi
  if ! kill -0 $TUNNEL_PID 2>/dev/null; then
    echo "Tunnel process died unexpectedly"
    exit 1
  fi
  sleep 1
done

# Launch DBeaver
echo "Launching DBeaver..."
open -n -a "$APP" --args -data "$WORKSPACE"

echo ""
echo "DBeaver launched with workspace: $WORKSPACE"
echo "Log: $LOG"
echo ""
echo "Press Ctrl-C to stop everything."

# Wait for log and tail
while [ ! -f "$LOG" ]; do sleep 1; done
tail -n 80 -f "$LOG" &
TAIL_PID=$!

# Cleanup on exit
trap "kill $TUNNEL_PID $TAIL_PID 2>/dev/null; echo 'Stopped.'" EXIT
wait $TUNNEL_PID
