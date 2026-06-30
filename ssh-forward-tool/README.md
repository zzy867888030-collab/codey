# SSH Forward Tool

一个运行在 macOS 状态栏里的 SSH 端口转发工具。它会把常用的堡垒机转发目标做成菜单项，支持直接在状态栏里启动、停止和查看连接状态。

## 现在是什么样

- mac 状态栏常驻显示当前转发状态
- 从 YAML 配置文件加载堡垒机和目标列表
- 点击菜单项即可启动或停止单个转发
- 通过弹窗输入 SSH 密码和 MFA 验证码
- 支持通过原生配置窗口编辑、新增和删除转发目标
- 支持重新加载配置和一键停止所有转发

## 运行要求

- macOS
- Python 3
- 本机已安装 `ssh`
- 本机已安装 `socat`，例如 `brew install socat`

## 安装

```bash
./install.sh
```

安装脚本会：

- 创建 `~/.ssh_forwarder/config.yaml`
- 安装 Python 依赖
- 保留仓库内的启动和停止脚本

## 启动

```bash
./run.sh -c ~/.ssh_forwarder/config.yaml
```

已经打包好的 macOS 应用也可以直接启动：

```bash
open "/Users/zoyoe/codex/ssh-forward-tool/dist/SSH Forward Tool.app"
```

也可以先只检查配置：

```bash
python3 ssh_forward.py --check-config -c ~/.ssh_forwarder/config.yaml
```

启动后，菜单栏会出现 `SSH:--`。含义大致如下：

- `SSH:--`：当前没有活动转发
- `SSH:1`：有 1 个已连接转发
- `SSH:1+1`：有 1 个已连接、1 个正在连接

## 配置文件

示例：

```yaml
bastion:
  user: "zhangzhiyu"
  host: "192.168.31.88"
  port: 60022

jump_host:
  user: "mnyjy"
  host: "192.168.77.39"
  port: 22

targets:
  dev_server:
    name: "开发服务器"
    ip: "192.168.77.38"
    port: 22
    local_port: 2222
    description: "开发环境SSH访问"

  mysql_server:
    name: "MySQL数据库"
    ip: "192.168.77.39"
    port: 3306
    local_port: 3307
    description: "数据库访问"

  custom_12345:
    name: "12345服务"
    ip: "192.168.77.39"
    port: 12345
    local_port: 12345
    description: "自定义端口访问"

advanced:
  timeout: 20
  bind_host: "127.0.0.1"
  strict_host_key_checking: "accept-new"
  check_interval: 5
```

### 字段说明

- `bastion.user`: 堡垒机用户名
- `bastion.host`: 堡垒机地址
- `bastion.port`: 堡垒机 SSH 端口
- `jump_host.user`: 跳板机用户名
- `jump_host.host`: 跳板机地址
- `jump_host.port`: 跳板机 SSH 端口
- `targets.<key>.name`: 菜单中显示的名称
- `targets.<key>.ip`: 内网目标 IP
- `targets.<key>.port`: 内网目标端口
- `targets.<key>.local_port`: 本机监听端口
- `targets.<key>.description`: 说明文字，目前主要用于配置注释
- `advanced.bind_host`: 默认监听地址，建议保留 `127.0.0.1`

## 菜单栏里的操作

- 点击某个目标：启动或停止该转发
- `配置转发...`：打开配置窗口，编辑并保存 YAML 中的转发目标
- `重新加载配置`：重新读取当前 YAML 文件
- `停止全部转发`：关闭所有活动 SSH 会话
- `退出`：退出状态栏应用并停止会话

## 停止

```bash
./stop.sh
```

这个脚本会尝试停止状态栏应用，以及残留的 SSH ControlMaster 和 `socat` 进程。

## 转发方式

工具现在使用外部托管隧道：先通过堡垒机建立到 `jump_host` 的 OpenSSH ControlMaster，再用 `socat` 监听本地端口。每个本地连接都会复用 ControlMaster，在跳板机上执行 `nc <目标IP> <目标端口>`。

这个方式不依赖 SSH `direct-tcpip`，适合 1433、3306、12345 等数据库或自定义业务端口。客户端连接时只需要访问 `127.0.0.1:<local_port>`，不要再额外启用应用内 SSH Tunnel。

## 依赖

见 [requirements.txt](/Users/zoyoe/codex/ssh-forward-tool/requirements.txt)。当前核心依赖是：

- `PyYAML`
- `pexpect`
- `rumps`
- `PyInstaller`（用于打包 `.app`）

## 打包 `.app`

当前仓库已经包含 PyInstaller 配置，重新打包可执行：

```bash
PYINSTALLER_CONFIG_DIR="$PWD/build/pyinstaller-cache" python3 -m PyInstaller -y ssh_forward_tool.spec
```

打包产物位置：

```bash
dist/SSH Forward Tool.app
```

## 已知限制

- 当前是 macOS 专用，因为状态栏 UI 依赖 `rumps`
- 密码与 MFA 目前通过系统弹窗输入，尚未接入 macOS Keychain

## 后续适合继续做的事

- 增加菜单图标和连接时长展示
- 把密码缓存接到 Keychain
- 增加堡垒机配置项的可视化编辑
