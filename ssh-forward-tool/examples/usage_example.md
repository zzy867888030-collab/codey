# SSH 端口转发工具 - 使用示例

## 1. 基础使用

### 交互模式（推荐）

```bash
python3 ssh_forward.py
```

按提示输入：
- 本地转发端口（如 `2222`）
- 目标内网IP（如 `192.168.77.38`）
- 目标端口（如 `22`）
- 然后按提示输入 **密码** 和 **MFA验证码**

### 命令行参数模式

```bash
python3 ssh_forward.py -l 2222 -t 192.168.77.38 -p 22
```

## 2. 常见场景

### 访问内网 SSH 服务器

```bash
# 启动
python3 ssh_forward.py -l 2222 -t 192.168.77.38 -p 22

# 连接方式
ssh -p 2222 localhost
```

### 访问内网 MySQL

```bash
# 启动
python3 ssh_forward.py -l 3307 -t 192.168.77.39 -p 3306

# 连接方式
mysql -h 127.0.0.1 -P 3307 -u root -p
```

### 访问内网 Redis

```bash
# 启动
python3 ssh_forward.py -l 6380 -t 192.168.77.39 -p 6379

# 连接方式
redis-cli -p 6380
```

### 访问内网 Web 服务

```bash
# 启动
python3 ssh_forward.py -l 8080 -t 192.168.77.100 -p 80

# 浏览器访问
http://localhost:8080
```

## 3. 停止转发

### 方式一：快捷键
在运行窗口中按 `Ctrl+C`，程序会自动清理占用的端口。

### 方式二：停止脚本
```bash
./stop.sh
```

### 方式三：手动停止
```bash
# 查看SSH转发进程
ps aux | grep "ssh -fN -L"

# 停止特定端口
lsof -ti:2222 | xargs kill -9
```

## 4. 批量转发示例

```bash
#!/bin/bash
# start_all.sh

python3 ssh_forward.py -l 2222 -t 192.168.77.38 -p 22 &
python3 ssh_forward.py -l 3307 -t 192.168.77.39 -p 3306 &
python3 ssh_forward.py -l 8080 -t 192.168.77.100 -p 80 &

wait
echo "所有转发已启动"
```

## 5. 使用自定义配置

```bash
# 复制示例配置并编辑
cp examples/example_config.yaml my_config.yaml
vim my_config.yaml

# 指定配置文件运行
python3 ssh_forward.py -c my_config.yaml
```

## 6. 故障排查

| 问题 | 解决方法 |
|------|---------|
| 端口被占用 | 使用 `lsof -i :2222` 查看并 `kill -9 PID` |
| 密码输错 | 按 `Ctrl+C`，重新运行 |
| 连接失败 | 检查堡垒机IP、端口、VPN是否正常 |
| 找不到Python | 确保安装了 Python3，并使用 `python3` 命令 |
