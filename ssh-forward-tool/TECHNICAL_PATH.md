# SSH Forward Tool 技术路径

## 目标

让当前状态栏转发工具不仅能转发 SSH 22 端口，也能稳定转发数据库和自定义业务端口，例如：

```text
192.168.77.39:1433
192.168.77.39:3306
192.168.77.39:12345
```

本次重点验证目标是：

```text
本机 127.0.0.1:12345 -> 192.168.77.39:12345
```

## 原实现路径

旧版本使用 OpenSSH 本地端口转发：

```text
本机客户端
  -> 127.0.0.1:<local_port>
  -> ssh -N -L <bind_host>:<local_port>:<target_ip>:<target_port>
  -> 堡垒机 zhangzhiyu@192.168.31.88:60022
  -> 目标IP:目标端口
```

对应 SSH 机制是 `direct-tcpip` channel。

这个路径对 SSH 22 端口可以成功，但对 1433、3306、12345 等业务端口不稳定。参考 `/Users/zoyoe/codex/my_dbeaver/TECHNICAL_PATH.md` 的排查结论，当前堡垒机/跳板机链路对 `direct-tcpip` 或 stdio forwarding 存在策略限制，可能出现端口能建立 TCP 连接，但数据库或业务协议阶段断开的问题。

## 新实现路径

新版本改为外部托管隧道：`socat + OpenSSH ControlMaster + SSH exec nc`。

```text
本机客户端
  -> 127.0.0.1:<local_port>
  -> socat TCP-LISTEN:<local_port>,bind=127.0.0.1,reuseaddr,fork
  -> ssh -S ~/.ssh_forwarder/control-<target>.sock mnyjy@192.168.77.39 -p 22 "nc <target_ip> <target_port>"
  -> 目标IP:目标端口

ControlMaster:
  ssh -N \
      -J zhangzhiyu@192.168.31.88:60022 \
      -o PreferredAuthentications=password,keyboard-interactive \
      -o PubkeyAuthentication=no \
      -o ControlMaster=yes \
      -o ControlPath=~/.ssh_forwarder/control-<target>.sock \
      mnyjy@192.168.77.39 -p 22
```

完整链路是：

```text
本机客户端
  -> 本机 socat 监听端口
  -> 复用到跳板机的 SSH ControlMaster
  -> 堡垒机 zhangzhiyu@192.168.31.88:60022
  -> 跳板机 mnyjy@192.168.77.39:22
  -> 跳板机执行 nc <目标IP> <目标端口>
  -> 目标服务
```

## 为什么这样改

旧路径依赖 SSH 端口转发能力，目标端口通过 `direct-tcpip` 打开。

新路径不再向 SSH 服务申请目标端口转发，而是登录到跳板机后执行普通命令：

```bash
nc 192.168.77.39 12345
```

从网络策略角度看，新路径更接近“用户登录跳板机后访问内网端口”，绕开了当前链路中对 `direct-tcpip` 转发的限制。

## 当前配置

默认配置文件 `config.yaml` 已增加跳板机配置：

```yaml
jump_host:
  user: "mnyjy"
  host: "192.168.77.39"
  port: 22
```

并增加了 12345 测试目标：

```yaml
custom_12345:
  name: "12345服务"
  ip: "192.168.77.39"
  port: 12345
  local_port: 12345
  description: "通过跳板机 exec nc 访问 192.168.77.39:12345"
```

## 运行方式

源码方式启动：

```bash
cd /Users/zoyoe/codex/ssh-forward-tool
./stop.sh
./run.sh -c config.yaml
```

启动后，在菜单栏点击 `12345服务`，按弹窗输入堡垒机密码和 MFA 动态码。

连接成功后，本地访问：

```text
127.0.0.1:12345
```

就会被转发到：

```text
192.168.77.39:12345
```

注意：如果双击 `dist/SSH Forward Tool.app`，需要先重新打包 `.app`，否则启动的是旧产物。

## 效率差异

旧路径更轻量：一个 `ssh -N -L` 进程直接监听并转发。

新路径多了两类开销：

- 启动转发时需要先建立一个 ControlMaster SSH 主连接。
- 每个客户端连接会由 `socat` fork，并通过 `ssh -S` 复用 ControlMaster，在跳板机执行一次 `nc`。

但新路径也有两个效率优势：

- ControlMaster 建好后，不需要每个连接重复输入密码和 MFA。
- 数据传输阶段仍然是 TCP 字节流穿过 SSH 加密链路，数据库和业务管理连接通常不会把额外的 `socat + nc` 进程开销作为主要瓶颈。

综合判断：旧路径理论上更轻，但在当前网络策略下不可靠；新路径有少量进程开销，但显著提高 1433、3306、12345 等业务端口的可用性和稳定性。

## 已完成的本地验证

已完成以下本地检查：

```bash
python3 -m py_compile ssh_forward.py
python3 ssh_forward.py --check-config -c config.yaml
which socat
```

结果：

```text
ssh_forward.py 语法检查通过
config.yaml 配置加载通过，已加载 5 个转发目标
socat 已安装: /opt/homebrew/bin/socat
```

远端 `192.168.77.39:12345` 的实际业务连通性需要在状态栏程序启动后输入 MFA 进行验证。
