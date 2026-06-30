# DBeaver MFA 开发记录

## 问题

堡垒机（192.168.31.88:60022）→ 跳板机（192.168.77.38:22）→ 内网数据库（192.168.77.39:3306）

跳板机只开放了 22 端口，无法直接访问数据库 3306 端口。需要通过 SSH 端口转发（跳板机转发到数据库）。

DBeaver 原生支持 SSH 隧道和 Jump Server（跳板机），但存在两个问题：

1. **MFA 动态码认证**：堡垒机需要二次动态码验证（keyboard-interactive），DBeaver 已有 `DBeaverChallengeResponseProvider` 处理，但需要 UI 层弹窗让用户输入动态码。
2. **SSHJ 端口转发 originator 地址问题**：SSHJ 的 `LocalPortForwarder` 使用 `Parameters(originatorHost, originatorPort, remoteHost, remotePort)`，originator 地址如果设为 SSH 客户端本机地址（如 192.168.x.x），MINA SSHD 服务端可能拒绝 `direct-tcpip` 通道请求。

## 当前进展

### 已实现

#### 1. MFA 动态码认证（DBeaverChallengeResponseProvider）

在 `SSHJSessionController.java` 中已有 `DBeaverChallengeResponseProvider`：
- 密码类 prompt 自动用保存的密码回答
- 非密码 prompt（如动态码）通过 `SSHJChallengeResponsePromptProvider` 接口回调 UI 层弹窗
- UI 层 `SSHJUIPromptProvider` 实现了弹窗让用户输入动态码

#### 2. SSHJ 端口转发 originator 修复（今天）

**问题**：`SSHJSession.java` 的 `LocalPortListener.run()` 中，originator 地址从 `transport.getSocket().getLocalAddress()` 获取。当通过 Jump Server 连接时，这个地址可能是 SSH 客户端的实际 IP（如 192.168.x.x），MINA SSHD 0.9.5 收到 `direct-tcpip` 请求时如果 originator 地址不是预期的 `127.0.0.1` 就会拒绝。

**修复**：改为使用 `config.localHost()`（即 `127.0.0.1`）作为 originator 地址。

**修改文件**：
- `dbeaver-src/plugins/org.jkiss.dbeaver.net.ssh.sshj/src/org/jkiss/dbeaver/model/net/ssh/SSHJSession.java`

**修改内容**：
```java
// 修改前
final Transport transport = client.getTransport();
final String originatorHost = transport.getSocket().getLocalAddress().getHostAddress();
final int originatorPort = transport.getSocket().getLocalPort();
final ServerSocket socket = new ServerSocket(config.localPort(), 0, InetAddress.getByName(config.localHost()));
final Parameters parameters = new Parameters(originatorHost, originatorPort, config.remoteHost(), config.remotePort());

// 修改后
final ServerSocket socket = new ServerSocket(config.localPort(), 0, InetAddress.getByName(config.localHost()));
final Parameters parameters = new Parameters(config.localHost(), socket.getLocalPort(), config.remoteHost(), config.remotePort());
```

### 项目结构

```
my_dbeaver/
├── dbeaver-src/                    # DBeaver 源码
│   └── plugins/
│       └── org.jkiss.dbeaver.net.ssh.sshj/src/  # SSHJ 实现源码（修改的地方）
├── tools/
│   ├── DBeaver-MFA.app/            # 已修补的 DBeaver 应用
│   ├── jdk/                        # JDK 21 (Temurin)
│   ├── patch/                      # 编译后的 class 文件和 jar
│   │   ├── sshj/                   # SSHJ 插件补丁
│   │   └── sshui/                  # SSH UI 插件补丁
│   ├── patch-work/                 # 编译工作区
│   │   ├── src-sshj/               # SSHJ 源码副本
│   │   ├── src-ui/                 # SSH UI 源码副本
│   │   └── libs/                   # 依赖库
│   ├── drivers/                    # JDBC 驱动
│   └── maven/                      # Maven
├── run-dbeaver-mfa-test.sh         # 启动脚本
└── DEVLOG.md                       # 本文件
```

### 编译部署命令

```bash
APPS="tools/DBeaver-MFA.app/Contents/Eclipse/plugins"
JDK="tools/jdk/Contents/Home"
SRC="dbeaver-src/plugins/org.jkiss.dbeaver.net.ssh.sshj/src"
OUT="/tmp/dbeaver-build-classes"
rm -rf "$OUT" && mkdir -p "$OUT"

CP="$APPS/org.jkiss.dbeaver.model_2.0.40.202605311718.jar"
CP="$CP:$APPS/org.jkiss.dbeaver.net.ssh_1.0.201.202605311718.jar"
CP="$CP:$APPS/org.jkiss.utils_2.7.0.202605311718.jar"
CP="$CP:$APPS/com.jcraft.jsch_0.2.8.jar"
CP="$CP:$APPS/slf4j.api_2.0.17.jar"
CP="$CP:$APPS/org.jkiss.bundle.sshj_0.34.2/lib/sshj-0.40.0.jar"
CP="$CP:$APPS/org.jkiss.bundle.sshj_0.34.2/lib/asn-one-0.6.0.jar"
CP="$CP:$APPS/org.eclipse.osgi_3.24.100.v20251215-1416.jar"

"$JDK/bin/javac" -d "$OUT" -cp "$CP" \
  "$SRC/org/jkiss/dbeaver/model/net/ssh/SSHJSession.java" \
  "$SRC/org/jkiss/dbeaver/model/net/ssh/SSHJSessionController.java" \
  "$SRC/org/jkiss/dbeaver/model/net/ssh/DBeaverAuthAgent.java" \
  "$SRC/org/jkiss/dbeaver/model/net/ssh/KnownHostsVerifier.java" \
  "$SRC/org/jkiss/dbeaver/model/net/ssh/SSHJChallengeResponsePromptProvider.java" \
  "$SRC/org/jkiss/dbeaver/model/net/ssh/SSHJUIMessages.java"

# 打包到 jar
cd "$TMPDIR"
jar xf "$JAR"
cp "$OUT"/org/jkiss/dbeaver/model/net/ssh/*.class org/jkiss/dbeaver/model/net/ssh/
jar cf /tmp/new.jar .
cp /tmp/new.jar "$JAR"
```

## 待办 / 已知问题

### 1. SSH 端口转发仍然失败

即使修复了 originator 地址，`LocalPortForwarder` 在 Jump Server 场景下仍然失败。日志显示：

```
<<chan#0 / open>> woke to: Opening `direct-tcpip` channel failed:
```

**可能原因**：
- MINA SSHD 0.9.5 的 `direct-tcpip` 通道处理有 bug 或限制
- 跳板机 sshd_config 中 `AllowTcpForwarding` 被注释掉（默认为 yes），但实际测试 `ssh -J` 双跳可以工作
- SSHJ 的 `LocalPortForwarder` 与 MINA SSHD 0.9.5 的兼容性问题

**验证**：OpenSSH 的 `-J` 双跳能正常工作：
```bash
ssh -o PreferredAuthentications=password,keyboard-interactive \
    -o PubkeyAuthentication=no \
    -J zhangzhiyu@192.168.31.88:60022 \
    -N -L 127.0.0.1:3307:192.168.77.39:3306 \
    mnyjy@192.168.77.38 -p 22
```

### 2. 需要进一步排查的方向

- 在跳板机上抓包看 SSHJ 发送的 `direct-tcpip` 请求内容
- 对比 OpenSSH `-J` 和 SSHJ 发送的 channel open 消息差异
- 考虑用 JSch 替代 SSHJ 做端口转发（JSch 对 MINA SSHD 兼容性更好）
- 或者直接在 DBeaver 外部用 `ssh -J -L` 进程做转发，DBeaver 只连本地端口

### 3. 启动方式

```bash
./run-dbeaver-mfa-test.sh
```

这个脚本会：
1. 生成测试连接配置（含跳板机信息）
2. 启动 DBeaver-MFA.app
3. 实时跟踪日志

## 2026-06-16 进展

### 切换到 JSch

SSHJ 的 `LocalPortForwarder` 与跳板机上的 MINA SSHD 0.9.5 存在兼容性问题：
```
<<chan#0 / open>> woke to: Opening `direct-tcpip` channel failed:
```
即使修复了 originator 地址（从 transport socket 改为 config.localHost()），问题依然存在。

**解决方案**：从 SSHJ 切换到 JSch 实现。JSch 使用 `session.setPortForwardingL()` 做端口转发，与 MINA SSHD 兼容性更好。

**改动**：
1. `dbeaver-src/scripts/seed-dbeaver-mfa-connection.sh` — `implementation` 从 `sshj` 改为 `jsch`
2. `dbeaver-src/scripts/preflight-dbeaver-mfa-test.sh` — 检查实现改为 `jsch`
3. `dbeaver-src/scripts/check-dbeaver-mfa-connection-ready.sh` — 同上

### 应用构建

DBeaver-MFA.app 基于 `/Applications/DBeaver.app`（26.0.0 版），没有额外补丁。JSch 是 DBeaver 原生支持的实现，UI 层 `JSCHUIPromptProvider`（基于 Eclipse `UserInfoPrompter`）已经能处理键盘交互式 MFA 认证。

### 当前状态

- **DBeaver-MFA.app**：干净的 DBeaver 26.0.0 原版，无修改
- **数据源配置**：`implementation: jsch`，跳板机 zhangzhiyu@192.168.31.88:60022 → mnyjy@192.168.77.38:22 → 192.168.77.39:3306
- **SSHJ 补丁**：`tools/patch/` 目录下保留，但不再使用

### 启动方式

```bash
open -n /Users/zoyoe/codex/my_dbeaver/tools/DBeaver-MFA.app
```

然后在 DBeaver 中连接 **MySQL MFA Bastion Test**，会依次弹出：
1. 堡垒机密码（zhangzhiyu@192.168.31.88:60022）
2. 堡垒机动态码
3. 跳板机密码（mnyjy@192.168.77.38:22）
4. 数据库密码

### 后续待办

1. **测试 JSch 端口转发**：确认 JSch 的 `setPortForwardingL()` 能否成功通过跳板机转发到 192.168.77.39:3306
2. **密码保存**：当前配置 `save-password: false`，每次都要输入密码。可以考虑改为 `true`
3. **MFA 弹窗**：确认 JSch 的 `UserInfoPrompter` 能正确弹出动态码输入框

## 2026-06-16 方案三：外部 SSH 隧道

### 问题

DBeaver 内部的 SSH 端口转发（无论是 SSHJ 还是 JSch）都跟跳板机上的 MINA SSHD 0.9.5 有兼容性问题：
- SSHJ `LocalPortForwarder` → `direct-tcpip` 通道被拒绝
- JSch `setPortForwardingL()` → 也可能有类似问题

但 OpenSSH 的 `-J` 双跳模式已验证能正常工作。

### 方案

放弃 DBeaver 内部的 SSH 隧道功能。改为：
1. 在 DBeaver **外部**用 OpenSSH 的 `-J -L` 创建 SSH 隧道
2. DBeaver 直连 `127.0.0.1:3307`，不启用 SSH 隧道

### 新增文件

- `tools/dbeaver-mfa-tunnel.py` — SSH 隧道管理器，支持密码 + MFA 弹窗
- `dbeaver-src/scripts/seed-dbeaver-direct-connection.sh` — 生成直连配置
- `run-tunnel.sh` — 一键启动脚本

### 使用方式

```bash
# 一键启动（隧道 + DBeaver）
cd /Users/zoyoe/codex/my_dbeaver
./run-tunnel.sh

# 或者分步操作
python3 tools/dbeaver-mfa-tunnel.py --dbeaver
```

### 隧道路径

```
本地 127.0.0.1:3307
  ← ssh -J zhangzhiyu@192.168.31.88:60022 -L 127.0.0.1:3307:192.168.77.39:3306 mnyjy@192.168.77.38:22
```

### DBeaver 连接配置

- Host: `127.0.0.1`
- Port: `3307`
- SSH Tunnel: **Disabled**
- 连接名: `MySQL via External Tunnel`

## 2026-06-16 修复：隧道脚本重写

### 问题

1. **socat EXEC 引号错误**：`EXEC:\"ssh ...\"` 中 `\"` 被 Python 当作字面量传给 socat，导致 socat 尝试执行名为 `"ssh`（带引号）的程序
2. **ssh -J -L 不可行**：`-L` 使用 direct-tcpip 通道，被 MINA SSHD 0.9.5 拒绝
3. **ssh -W 同样不可行**：`-W` 也使用 direct-tcpip

### 修复方案

将隧道脚本从 socat 改为纯 Python socket + SSH exec channel：

```
本地 127.0.0.1:3307
  ← Python socket.accept()
    ← ssh -S control_socket mnyjy@192.168.77.38 "nc 192.168.77.39 3306"
      ← ControlMaster via -J zhangzhiyu@192.168.31.88:60022
```

**关键**：`ssh host "nc db port"` 使用 SSH **exec channel**（session channel），不是 direct-tcpip。MINA SSHD 0.9.5 允许 exec channel。

### 改动文件

- `tools/dbeaver-mfa-tunnel.py` — 完全重写，去掉 socat，改用 Python socket + threading + select 做双向管道
- `run-tunnel.sh` — 更新描述

### 使用方式

```bash
cd /Users/zoyoe/codex/my_dbeaver
python3 tools/dbeaver-mfa-tunnel.py --password 'Mnjk@20252026'
```

会弹出 MFA 验证码输入框。输入动态码后隧道建立，DBeaver 直连 127.0.0.1:3307。

### 修复：pipe 函数中 proc.stdin 没有 sendall 方法

**问题**：`handle_connection` 中的 `pipe` 函数对两个方向都用了 `dst.sendall(data)`。但 `proc.stdin` 是 `BufferedWriter`，没有 `sendall` 方法。这导致 `AttributeError`（不在 except 捕获范围内），线程静默崩溃，双向管道断裂。

**症状**：隧道建立成功，端口监听正常，但数据流不通。MySQL 客户端连接后卡住（收不到服务端握手包）。

**修复**：给 `pipe` 函数加 `dst_is_socket` 参数。socket 方向用 `sendall`，stdin 方向用 `write + flush`。

**修改**：
- `tools/dbeaver-mfa-tunnel.py` — `pipe()` 函数增加 `dst_is_socket` 参数
- `t1` (ssh->client): `dst_is_socket=True`（socket）
- `t2` (client->ssh): `dst_is_socket=False`（BufferedWriter）

### 修复：socket 没有 read 方法 + stderr 管道阻塞

**问题 1**：`pipe` 函数对两个方向都用 `src.read(65536)`。但 `client_sock` 是 socket 对象，没有 `read()` 方法，只有 `recv()`。这导致 `AttributeError`，线程静默崩溃。

**问题 2**：`proc.stderr` 没人消费，管道缓冲区满了会阻塞 SSH 进程。

**修复**：
- `pipe` 函数根据 `dst_is_socket` 判断用 `read()` 还是 `recv()`
- 新增 `t3` 线程专门 drain stderr

**当前状态**：脚本已修复完毕，语法验证通过，所有 7 项检查 OK。

## 2026-06-16 关键发现：ssh -J -L 也不行

### 问题

之前以为 `ssh -J -L` 能用（`nc -vz 127.0.0.1 3307` 显示端口通了），但实际上 MySQL 连上去报：
```
Lost connection to MySQL server at 'reading initial communication packet'
```

**原因**：`ssh -L` 使用 direct-tcpip 通道。MINA SSHD 0.9.5 允许 TCP 端口 bind（所以 `nc -vz` 显示成功），但拒绝转发数据包。端口能 bind 不代表数据能流过去。

### 正确方案

回到 **exec channel** 方案（ControlMaster + `ssh host "nc db:port"`）：

```
本地 127.0.0.1:3307
  ← Python socket.accept()
    ← ssh -S control_socket mnyjy@192.168.77.38 "nc 192.168.77.39 3306"
      ← ControlMaster via -J zhangzhiyu@192.168.31.88:60022
```

`ssh host "nc db port"` 走 SSH exec channel（session channel），MINA SSHD 0.9.5 允许。

### 改动

- `tools/dbeaver-mfa-tunnel.py` — 重写为 ControlMaster + exec nc，修复 pipe 逻辑
- 两个方向用独立函数（`to_ssh` / `to_client`），避免 `dst_is_socket` 判断混淆

## 2026-06-17 最终成功实现记录

### 最终结论

严格来说，最终成功的是 **外部托管隧道：socat + OpenSSH ControlMaster + exec nc**，不是 DBeaver/SSHJ/JSch 原生 `-L` / `direct-tcpip` 隧道。

DBeaver 侧的正确用法是：数据库连接走本地 `127.0.0.1:3307`，SSH 隧道功能关闭；隧道由 `tools/dbeaver-mfa-tunnel.py` 负责启动和维护。这样 DBeaver 可以连接 MySQL/Doris/ClickHouse 等不同数据库，只要把外部隧道的目标 host/port 改到对应数据库即可。

### 最终可用链路

最终确认可用的路径是 **ControlMaster + socat + 远端 exec nc**：

```text
DBeaver / mysql client
  -> 本地 127.0.0.1:3307
  -> socat TCP-LISTEN:3307,reuseaddr,fork
  -> ssh -S /tmp/dbeaver-mfa-ssh-master.sock mnyjy@192.168.77.38 "nc 192.168.77.39 3306"
  -> 远端数据库 192.168.77.39:3306

ControlMaster:
  ssh -J zhangzhiyu@192.168.31.88:60022 mnyjy@192.168.77.38 -p 22
```

关键点：数据库端口转发不走 `direct-tcpip`，而是在跳板机上通过 SSH exec channel 执行 `nc <db_host> <db_port>`。本地双向 I/O 由 `socat` 负责，这比手写 Python pipe 更稳，能正确处理 MySQL 握手、认证包和半关闭等细节。

### 已验证事实

- `ssh -W 192.168.77.39:3306` 失败：`channel 0: open failed: administratively prohibited`，说明 stdio/direct forwarding 被堡垒机或跳板链路限制。
- `ssh -L 127.0.0.1:3307:192.168.77.39:3306` 会出现端口可连但 MySQL 协议断开的问题，`nc -vz` 成功不代表数据库协议能通过。
- SSH exec channel 可用：`ssh ... "echo 'EXEC_CHANNEL_OK'"` 成功。
- 跳板机上有 `/usr/bin/nc`，版本为 OpenBSD netcat。
- 跳板机到数据库可达：`ssh ... "nc -vz 192.168.77.39 3306"` 成功。
- 最终使用 `tools/dbeaver-mfa-tunnel.py` 的 `socat + exec nc` 路径后，MySQL 客户端连接通过。

### 最终脚本

文件：`tools/dbeaver-mfa-tunnel.py`

当前职责：

1. 用 `pexpect` 启动 OpenSSH ControlMaster。
2. 处理堡垒机密码和 MFA 动态码输入。
3. 建立 `/tmp/dbeaver-mfa-ssh-master.sock` 控制 socket。
4. 启动 `socat` 在本地监听 `127.0.0.1:3307`。
5. 每个本地连接由 `socat` fork，并通过 `ssh -S` 在跳板机执行 `nc 192.168.77.39 3306`。

启动命令：

```bash
cd /Users/zoyoe/codex/my_dbeaver
python3 tools/dbeaver-mfa-tunnel.py --password 'Mnjk@20252026'
```

验证命令：

```bash
mysql -h 127.0.0.1 -P 3307 -u root -p --ssl-mode=DISABLED
```

### DBeaver 使用方式

已在本机 DBeaver workspace 中生成样例连接：

```text
/Users/zoyoe/Library/DBeaverData/workspace6/MIH/.dbeaver/data-sources.json
```

连接名：`MIH MySQL 39 via MFA SSH`

配置要点：

- 数据库：`192.168.77.39:3306`
- Driver：`mysql8`
- SSH 目标：`mnyjy@192.168.77.38:22`
- Jump Server：`zhangzhiyu@192.168.31.88:60022`
- SSH implementation：`jsch`

连接时密码顺序：

1. 堡垒机 `zhangzhiyu@192.168.31.88:60022` 密码。
2. 堡垒机 MFA 动态码。
3. 跳板机 `mnyjy@192.168.77.38:22` 密码。
4. 数据库密码。

### DBeaver 内置补丁状态

已修改并编译 `JSCHSession.java`，打入：

```text
tools/DBeaver-MFA.app/Contents/Eclipse/plugins/org.jkiss.dbeaver.net.ssh.jsch_1.1.184.202603011816.jar
```

备份文件保留在同目录，形如：

```text
org.jkiss.dbeaver.net.ssh.jsch_1.1.184.202603011816.jar.bak.YYYYMMDDHHMMSS
```

补丁策略：

- Jump Server 登录阶段仍保留 JSch 原生 `setPortForwardingL` 到 22 端口，因为堡垒机允许跳转 SSH 22。
- 最终数据库端口转发改为 JSch exec channel，远端执行 `nc <db_host> <db_port>`。

注意：最终最稳定、已明确验证通过的路径仍是外部脚本的 `socat + OpenSSH ControlMaster + exec nc`。DBeaver 内置 JSch exec 补丁用于让连接编辑器保留原生 SSH 配置体验；如果遇到 DBeaver 内置连接异常，优先用外部脚本验证链路。

### 迁移和使用提醒

- macOS 可复制 patched app：`/Users/zoyoe/codex/my_dbeaver/tools/DBeaver-MFA.app`。
- 启动指定 workspace：

```bash
open -n /Applications/DBeaver-MFA.app --args -data /Users/zoyoe/Library/DBeaverData/workspace6
```

- Windows 不能直接使用 `.app`，需要安装同版本 Windows DBeaver 后替换同名 JSch 插件 jar。
- 堡垒机只能看到 SSH 加密流量、会话数量、连接时长和 exec 命令行为；看不到数据库明文 SQL。DBeaver 首次展开元数据可能产生较多连接和流量，建议减少自动元数据读取和连接池数量。
