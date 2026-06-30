# SSH 端口转发工具 - 高级用法

## 1. 配置文件高级选项

### 环境变量支持（需自行扩展）

可修改 `ssh_forward.py` 以支持环境变量覆盖配置：

```python
import os

# 环境变量优先
self.bastion_user = os.getenv("SSH_BASTION_USER", self.bastion_user)
self.bastion_host = os.getenv("SSH_BASTION_HOST", self.bastion_host)
self.bastion_port = os.getenv("SSH_BASTION_PORT", self.bastion_port)
```

使用方式：
```bash
export SSH_BASTION_USER=zhangzhiyu
export SSH_BASTION_HOST=192.168.31.88
export SSH_BASTION_PORT=60022
python3 ssh_forward.py
```

## 2. 后台运行与日志

### 使用 nohup 后台运行

```bash
nohup python3 ssh_forward.py -l 2222 -t 192.168.77.38 -p 22 > ~/ssh_forward.log 2>&1 &

# 查看日志
tail -f ~/ssh_forward.log
```

### 查看运行中的转发

```bash
# 查看SSH进程
ps aux | grep "ssh -fN -L"

# 查看端口占用
lsof -i -P | grep LISTEN
```

## 3. 系统密钥对免密登录

推荐配置 SSH Key 登录堡垒机，避免每次输入密码：

```bash
# 生成密钥（如果还没有）
ssh-keygen -t ed25519 -C "your_email@example.com"

# 复制公钥到堡垒机
ssh-copy-id -p 60022 zhangzhiyu@192.168.31.88

# 测试免密登录
ssh -p 60022 zhangzhiyu@192.168.31.88

# 之后使用转发工具将不再需要输入密码
python3 ssh_forward.py -l 2222 -t 192.168.77.38 -p 22
```

## 4. macOS 开机自启

### 创建 LaunchAgent（推荐）

```xml
<!-- ~/Library/LaunchAgents/com.user.sshforward.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.sshforward</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/python3</string>
        <string>/path/to/ssh_forward.py</string>
        <string>-l</string>
        <string>2222</string>
        <string>-t</string>
        <string>192.168.77.38</string>
        <string>-p</string>
        <string>22</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/sshforward.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/sshforward.err</string>
</dict>
</plist>
```

加载：
```bash
launchctl load ~/Library/LaunchAgents/com.user.sshforward.plist
launchctl start com.user.sshforward
```

## 5. Linux 系统服务（systemd）

```ini
# /etc/systemd/system/ssh-forward.service
[Unit]
Description=SSH Port Forwarder
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=yourname
WorkingDirectory=/path/to/ssh-forward-tool
ExecStart=/usr/bin/python3 /path/to/ssh-forward-tool/ssh_forward.py -l 2222 -t 192.168.77.38 -p 22
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

启用：
```bash
sudo systemctl daemon-reload
sudo systemctl enable ssh-forward
sudo systemctl start ssh-forward
sudo systemctl status ssh-forward
```

## 6. 多配置管理

当需要管理多个环境时，建议创建多个配置文件：

```bash
ssh-forward-tool/
├── config.yaml           # 开发环境（默认）
├── config_test.yaml      # 测试环境
├── config_prod.yaml      # 生产环境
```

切换使用：
```bash
# 开发环境
python3 ssh_forward.py -c config.yaml -l 2222 -t 192.168.77.38 -p 22

# 测试环境
python3 ssh_forward.py -c config_test.yaml -l 2222 -t 10.0.0.38 -p 22
```

## 7. 安全建议

1. **不要用 root 运行**：使用普通用户权限运行转发即可
2. **限制监听范围**：本脚本默认绑定 `0.0.0.0`，局域网内其他机器也能访问。如需仅本机访问，可修改脚本为 `127.0.0.1`
3. **定期更换密码**：堡垒机密码建议定期更新
4. **使用密钥而非密码**：尽量配置 SSH Key 登录
5. **防火墙限制**：只开放必要的本地端口
6. **监控日志**：定期检查 `/tmp/sshforward.err` 等日志文件

## 8. 常见问题（FAQ）

### Q: 本脚本能否支持 Windows？
A: 核心依赖是 Python3 和 `ssh` 命令。如果在 Windows 上安装了 OpenSSH 客户端和 Python3，理论可以运行，但未经过测试。推荐在 WSL2 或 Git Bash 中使用。

### Q: 能否支持跳板机 / 多级跳转？
A: 当前脚本使用单级堡垒机。如需多级跳转，建议改用 `ssh -J` 参数，或直接使用 SSH 配置文件 `~/.ssh/config`：

```
Host bastion
    HostName 192.168.31.88
    User zhangzhiyu
    Port 60022

Host dev-server
    HostName 192.168.77.38
    User root
    ProxyJump bastion
```

然后直接 `ssh dev-server`。

### Q: 转发成功后没有反应？
A: `ssh -fN` 是后台模式，启动后会立即挂起。这是正常行为，端口已经在后台转发了。可通过 `lsof -i :<端口>` 验证。

### Q: 程序卡住无法输入验证码？
A: 这是由于交互式密码输入与 Python subprocess 的冲突。建议配置 SSH Key 免密登录，或使用 `sshpass` 等工具（不推荐生产环境使用）。
