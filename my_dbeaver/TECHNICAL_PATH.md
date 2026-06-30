# DBeaver MFA SSH Tunnel 技术路径

## 目标

在 DBeaver 中访问内网数据库，网络链路如下：

```text
本机 DBeaver / mysql client
  -> 堡垒机 zhangzhiyu@192.168.31.88:60022，需要密码 + MFA 动态码
  -> 跳板机 mnyjy@192.168.77.38:22
  -> 内网数据库，例如 192.168.77.39:3306
```

最终目标不是只连通 MySQL，而是形成一条可复用路径，后续可以连接 MySQL、Doris、ClickHouse 等不同数据库端口。

## 最终结论

最终成功方式是：**外部托管隧道：socat + OpenSSH ControlMaster + SSH exec nc**。

严格来说，成功的不是 DBeaver/SSHJ/JSch 原生 SSH 隧道里的 `direct-tcpip` 端口转发，也不是 `ssh -L` 或 `ssh -W`。这些方式在当前堡垒机/跳板机链路下会失败或表现为“端口可连但数据库协议断开”。

DBeaver 的正确使用方式是：

1. 先启动外部隧道脚本，让本机出现一个本地数据库端口，例如 `127.0.0.1:3307`。
2. DBeaver 连接配置中关闭 SSH Tunnel。
3. DBeaver 数据库 Host 填 `127.0.0.1`，Port 填外部隧道监听端口。

## 成功链路

```text
DBeaver / mysql client
  -> 127.0.0.1:3307
  -> socat TCP-LISTEN:3307,reuseaddr,fork
  -> ssh -S /tmp/dbeaver-mfa-ssh-master.sock mnyjy@192.168.77.38 -p 22 "nc 192.168.77.39 3306"
  -> 192.168.77.39:3306

ControlMaster:
  ssh -J zhangzhiyu@192.168.31.88:60022 \
      -o PreferredAuthentications=password,keyboard-interactive \
      -o PubkeyAuthentication=no \
      -o ControlMaster=yes \
      -o ControlPath=/tmp/dbeaver-mfa-ssh-master.sock \
      -N mnyjy@192.168.77.38 -p 22
```

关键点：

- ControlMaster 负责一次性完成堡垒机密码 + MFA 动态码认证。
- 每个数据库连接由 `socat` fork 一个本地代理进程。
- `socat` 启动 `ssh -S` 复用 ControlMaster，不重复 MFA。
- 远端通过 SSH exec channel 执行 `nc <db_host> <db_port>`。
- 数据库协议字节流由 `socat` 做双向 I/O，避免手写 pipe 对 MySQL 半关闭、握手、认证包处理不完整的问题。

## 为什么其他方案失败

### DBeaver 原生 SSH 隧道

DBeaver 原生 SSH 隧道底层使用 SSHJ 或 JSch 的本地端口转发，本质是 SSH `direct-tcpip` channel。

当前堡垒机/跳板机链路对 `direct-tcpip` 有限制，导致 DBeaver 内置隧道无法稳定转发数据库协议。

### `ssh -L`

`ssh -L 127.0.0.1:3307:192.168.77.39:3306 ...` 可以让本地端口 bind 成功，所以 `nc -vz 127.0.0.1 3307` 看起来成功。

但 MySQL 客户端实际连接时报过：

```text
Lost connection to MySQL server at 'reading initial communication packet'
```

或类似协议阶段断开错误。原因是端口能建立 TCP 连接不代表数据库协议字节流能通过，`-L` 仍然使用 `direct-tcpip`。

### `ssh -W`

`ssh -W 192.168.77.39:3306 ...` 明确失败：

```text
channel 0: open failed: administratively prohibited:
stdio forwarding failed
```

说明 stdio forwarding/direct forwarding 在该链路上被管理策略禁止。

### 手写 Python socket pipe

曾尝试用 Python socket + `ssh host "nc db port"` 手写双向 pipe。该方向理论正确，但实现上遇到过：

- `proc.stdin` 没有 `sendall`。
- socket 没有 `read`。
- stderr 没消费可能阻塞。
- MySQL 认证阶段半关闭处理复杂。

最终改用 `socat` 承担本地双向 I/O，稳定跑通。

## 已验证事实

以下命令和现象已验证：

```bash
ssh -J zhangzhiyu@192.168.31.88:60022 \
    -o PreferredAuthentications=password,keyboard-interactive \
    -o PubkeyAuthentication=no \
    mnyjy@192.168.77.38 -p 22 \
    "echo 'EXEC_CHANNEL_OK'"
```

结果：输出 `EXEC_CHANNEL_OK`，说明 SSH exec channel 可用。

```bash
ssh -J zhangzhiyu@192.168.31.88:60022 \
    mnyjy@192.168.77.38 -p 22 \
    "which nc && nc -h 2>&1 | head -3"
```

结果：跳板机存在 `/usr/bin/nc`，版本为 OpenBSD netcat。

```bash
ssh -J zhangzhiyu@192.168.31.88:60022 \
    mnyjy@192.168.77.38 -p 22 \
    "nc -vz 192.168.77.39 3306"
```

结果：跳板机到数据库 `192.168.77.39:3306` 可达。

最终用 `tools/dbeaver-mfa-tunnel.py` 启动 `socat + exec nc` 后，MySQL 客户端成功通过本地 `127.0.0.1:3307` 连接数据库。

## 关键文件

### `tools/dbeaver-mfa-tunnel.py`

最终稳定隧道脚本。

职责：

1. 用 `pexpect` 启动 OpenSSH ControlMaster。
2. 处理堡垒机密码和 MFA 动态码。
3. 建立 `/tmp/dbeaver-mfa-ssh-master.sock` 控制 socket。
4. 启动 `socat` 监听本地端口。
5. 每个连接通过 `ssh -S` 在跳板机执行 `nc <db_host> <db_port>`。

### `DEVLOG.md`

完整开发流水记录，包括失败路径、错误信息、排查过程和最终结论。

### `dbeaver-src/scripts/seed-dbeaver-direct-connection.sh`

生成 DBeaver 外部隧道直连样例，连接本地 `127.0.0.1:3307`，DBeaver SSH Tunnel 关闭。

### `run-tunnel.sh`

一键启动外部隧道和 DBeaver 的辅助脚本。

## 使用方式

### 启动隧道

```bash
cd /Users/zoyoe/codex/my_dbeaver

pkill -f "dbeaver-mfa\|ssh.*3307\|socat" 2>/dev/null
rm -f /tmp/dbeaver-mfa-ssh-master.sock

python3 tools/dbeaver-mfa-tunnel.py --password 'Mnjk@20252026'
```

启动后按提示输入 MFA 动态码，保持该终端打开。

### 验证 MySQL

另开终端：

```bash
mysql -h 127.0.0.1 -P 3307 -u root -p --ssl-mode=DISABLED
```

### DBeaver 连接

DBeaver 连接配置使用：

```text
Host: 127.0.0.1
Port: 3307
SSH Tunnel: Disabled
```

已生成过一个样例连接：

```text
/Users/zoyoe/Library/DBeaverData/workspace6/MIH/.dbeaver/data-sources.json
```

连接名：

```text
MIH MySQL 39 via MFA SSH
```

注意：如果使用最终外部隧道方式，DBeaver 连接中的 SSH Tunnel 应关闭；否则可能误走 DBeaver 原生 direct-tcpip 隧道。

## 连接其他数据库

最终链路可以用于 MySQL、Doris、ClickHouse 等，但需要修改外部隧道目标。

示例：

- MySQL/MariaDB 常见端口：`3306`
- Doris MySQL 协议端口：通常也是 `9030` 或实际部署端口
- ClickHouse Native：`9000`
- ClickHouse HTTP：`8123`

要连接其他库，需要让 `tools/dbeaver-mfa-tunnel.py` 的目标变量或启动参数指向对应目标：

```text
DB_HOST=<目标内网 IP>
DB_PORT=<目标数据库端口>
LOCAL_PORT=<本地监听端口>
```

当前脚本中默认值是：

```text
DB_HOST = 192.168.77.39
DB_PORT = 3306
LOCAL_PORT = 3307
```

后续建议将这些值参数化，例如：

```bash
python3 tools/dbeaver-mfa-tunnel.py \
  --db-host 192.168.77.39 \
  --db-port 3306 \
  --local-port 3307 \
  --password '...'
```

## DBeaver 内置补丁说明

项目中也尝试过修改 DBeaver JSch 插件：

```text
dbeaver-src/plugins/org.jkiss.dbeaver.net.ssh.jsch/src/org/jkiss/dbeaver/model/net/ssh/JSCHSession.java
```

并将编译产物打入：

```text
tools/DBeaver-MFA.app/Contents/Eclipse/plugins/org.jkiss.dbeaver.net.ssh.jsch_1.1.184.202603011816.jar
```

这个方向的目标是让 DBeaver 保留原生 SSH 配置体验，并在最终数据库端口上用 JSch exec channel 执行 `nc`。但当前已明确验证成功、最稳定的生产使用路径仍是外部脚本：

```text
socat + OpenSSH ControlMaster + exec nc
```

因此排查时优先用外部脚本确认链路，不要把 DBeaver 内置 SSH 隧道误认为已验证成功路径。

## 风险和注意事项

- 堡垒机能看到 SSH 会话数量、连接时长、流量大小，以及跳板机上执行 `nc <db_host> <db_port>` 的行为。
- 数据库 SQL 内容在 SSH 加密通道内，堡垒机通常看不到明文 SQL。
- DBeaver 首次展开 metadata 可能产生大量查询和流量，建议减少自动元数据读取。
- 不要同时打开大量连接或标签页，避免触发堡垒机连接数/流量策略。
- 大查询、导出、全表扫描应谨慎执行。

## Windows 迁移

macOS 的 `.app` 不能直接在 Windows 使用。

Windows 要使用：

1. 安装同版本 DBeaver。
2. 使用外部隧道脚本的 Windows 兼容版本，或在 Windows 上安装 OpenSSH、Python、pexpect 替代方案和 socat/ncat。
3. DBeaver 连接仍然指向本地监听端口，例如 `127.0.0.1:3307`。

如果尝试迁移 DBeaver 插件补丁，需要替换 Windows DBeaver 安装目录下同名 JSch 插件 jar，但这不是当前最终验证成功路径。

## 下次继续开发建议

优先做这三件事：

1. 将 `tools/dbeaver-mfa-tunnel.py` 参数化，支持 `--db-host`、`--db-port`、`--local-port`。
2. 增加一个 JSON/YAML 配置文件，维护 MySQL、Doris、ClickHouse 多个目标。
3. 做一个 DBeaver 启动器脚本：先启动选定隧道，再启动 DBeaver 指定 workspace。

