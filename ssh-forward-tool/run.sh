#!/usr/bin/env bash
# SSH Forward Tool - macOS 状态栏启动脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 检查Python3
if ! command -v python3 &>/dev/null; then
    echo "❌ 未找到 Python3，请先安装"
    exit 1
fi

if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
    echo "🔍 检查 Python 依赖 ..."
    python3 - <<'PY'
import importlib.util
import sys

missing = [
    name
    for name in ("yaml", "pexpect", "rumps")
    if importlib.util.find_spec(name) is None
]
if missing:
    sys.exit(1)
PY
    if [ $? -ne 0 ]; then
        echo "🔧 检测到缺少依赖，正在安装 requirements.txt ..."
        pip3 install -r "$SCRIPT_DIR/requirements.txt"
    fi
fi

echo "🚀 启动 SSH Forward Tool 状态栏应用 ..."
python3 "$SCRIPT_DIR/ssh_forward.py" "$@"
