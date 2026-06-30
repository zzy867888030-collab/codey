#!/usr/bin/env bash
# SSH Forward Tool - 停止状态栏应用及其 SSH 会话

set -e

echo "🛑 正在停止 SSH Forward Tool ..."

APP_PIDS=$(pgrep -f "python3 .*ssh_forward.py" || true)
if [ -n "$APP_PIDS" ]; then
    echo "$APP_PIDS" | xargs kill -TERM 2>/dev/null || true
    echo "✅ 已请求停止状态栏应用"
else
    echo "ℹ️  未发现运行中的状态栏应用"
fi

SSH_PIDS=$(pgrep -f "ssh -N .*ControlMaster=yes" || true)
if [ -n "$SSH_PIDS" ]; then
    echo "$SSH_PIDS" | xargs kill -TERM 2>/dev/null || true
    echo "✅ 已停止残留 SSH ControlMaster 进程"
else
    echo "ℹ️  未发现残留 SSH ControlMaster 进程"
fi

SOCAT_PIDS=$(pgrep -f "socat TCP-LISTEN:.*EXEC:ssh -S" || true)
if [ -n "$SOCAT_PIDS" ]; then
    echo "$SOCAT_PIDS" | xargs kill -TERM 2>/dev/null || true
    echo "✅ 已停止残留 socat 转发进程"
else
    echo "ℹ️  未发现残留 socat 转发进程"
fi

echo "🎉 完成"
