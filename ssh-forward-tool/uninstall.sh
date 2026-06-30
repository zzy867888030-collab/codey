#!/usr/bin/env bash
# SSH Forward Tool - 卸载脚本

set -e

echo "🗑️  正在卸载 SSH Forward Tool ..."
echo ""

# 先停止所有转发
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/stop.sh" ]; then
    bash "$SCRIPT_DIR/stop.sh"
fi

# 询问是否删除配置
echo ""
read -p "是否删除用户配置文件 (~/.ssh_forwarder/)？(y/n): " -n 1 -r
echo ""
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    rm -rf ~/.ssh_forwarder
    echo "✅ 已删除配置文件"
else
    echo "⚠️  配置文件保留在 ~/.ssh_forwarder/"
fi

echo ""
echo "🎉 卸载完成"
