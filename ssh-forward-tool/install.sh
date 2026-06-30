#!/usr/bin/env bash
# SSH Forward Tool - 安装脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "📦 开始安装 SSH Forward Tool ..."
echo ""

# 检查Python3
if ! command -v python3 &>/dev/null; then
    echo "❌ 未找到 Python3，请先安装 Python3"
    exit 1
fi

# 创建用户配置目录
mkdir -p ~/.ssh_forwarder

# 复制配置文件示例（如果不存在）
if [ ! -f ~/.ssh_forwarder/config.yaml ]; then
    cp "$SCRIPT_DIR/config.yaml" ~/.ssh_forwarder/config.yaml
    echo "✅ 配置文件已复制到 ~/.ssh_forwarder/config.yaml"
else
    echo "⚠️  配置文件已存在，跳过复制 (~/.ssh_forwarder/config.yaml)"
fi

# 设置脚本执行权限
chmod +x "$SCRIPT_DIR/ssh_forward.py"
chmod +x "$SCRIPT_DIR/run.sh"
chmod +x "$SCRIPT_DIR/stop.sh"
chmod +x "$SCRIPT_DIR/install.sh"
chmod +x "$SCRIPT_DIR/uninstall.sh"

# 安装Python依赖
echo ""
echo "🔧 安装 Python 依赖 ..."
if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
    pip3 install -r "$SCRIPT_DIR/requirements.txt" --user
fi

echo ""
echo "安装完成！"
echo ""
echo "📌 使用方式："
echo "   cd $SCRIPT_DIR"
echo "   ./run.sh -c ~/.ssh_forwarder/config.yaml"
echo "   或: python3 ssh_forward.py -c ~/.ssh_forwarder/config.yaml"
echo ""
echo "📝 配置文件位置："
echo "   ~/.ssh_forwarder/config.yaml"
echo ""
