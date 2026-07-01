# DolphinScheduler 开发记录

这个文件用于持续记录本仓库每次开发、排障、热补丁和重要脚本命令。后续每次处理问题时，优先在这里追加摘要；如果单次内容较长，可以另建专题记录文件，并在本文件中引用。

## 记录规则

- 每次开发或排障结束后追加一条记录。
- 记录要包含：日期、目标、改动文件、验证结果、重要命令、遗留问题。
- 命令尽量保留可直接复用的完整写法。
- 涉及远端机器、数据库、账号、密码、token 等敏感信息时，只记录必要上下文，不记录明文密钥。
- 本地执行 shell 命令默认使用 `rtk` 前缀，例如 `rtk git status --short`。

## 常用本地命令

```bash
rtk pwd
rtk git status --short
rtk rg --files
rtk rg "关键字"
rtk find . -maxdepth 3 -type f
```

## DolphinScheduler 远端常用命令

目标环境如无特别说明，历史排障环境为 `mnyjy@127.0.0.1:3911`，程序目录为 `/opt/dolphinscheduler`。

仓库级新会话说明已写入 `AGENTS.md`，后续新开会话应优先读取该文件中的远端环境信息。

```bash
# 登录方式（先以 mnyjy 登录，sudo 用 echo 管道传密码）
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 3911 mnyjy@127.0.0.1

# sudo 操作
echo 'mnjk2026' | sudo -S <command>

# DS 服务管理
cd /opt/dolphinscheduler
bash ./bin/dolphinscheduler-daemon.sh start standalone-server
bash ./bin/dolphinscheduler-daemon.sh stop standalone-server
bash ./bin/dolphinscheduler-daemon.sh restart standalone-server
bash ./bin/dolphinscheduler-daemon.sh status standalone-server

# 查看日志
tail -n 200 /opt/dolphinscheduler/standalone-server/logs/dolphinscheduler-standalone.log
ps -ef | grep StandaloneServer
ss -lntp | grep 12345

# 上传文件到 DS 资源目录
rtk scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P 3911 /tmp/local_file.py mnyjy@127.0.0.1:/tmp/
echo 'mnjk2026' | sudo -S cp /tmp/local_file.py /opt/dolphinscheduler/resources/default/resources/ch2doris/

# 语法检查
echo 'mnjk2026' | sudo -S python3 -m py_compile /opt/dolphinscheduler/resources/default/resources/ch2doris/xxx.py

# DS API 登录
curl -s -X POST "http://127.0.0.1:12345/dolphinscheduler/login" -d "userName=admin&userPassword=admin@123"
```

## 专题记录索引

- [2026-06-08 DolphinScheduler Standalone 排障记录](./dev-log-2026-06-08-dolphinscheduler-standalone.md)

## 开发记录

### 2026-06-13 建立长期开发记录

目标：

- 在仓库根目录建立长期维护的开发记录文件。
- 汇总后续每次开发需要记录的内容和重要脚本命令。

改动文件：

- `DEVELOPMENT_LOG.md`

重要命令：

```bash
rtk git status --short
rtk rg --files -g 'README*' -g 'AGENTS.md' -g '*LOG*.md' -g '*log*.md' -g '*开发*.md'
```

验证结果：

- 已确认仓库中存在历史专题记录 `dev-log-2026-06-08-dolphinscheduler-standalone.md`。
- 已将该专题记录加入索引，后续新记录可以继续在本文件追加。

遗留问题：

- 当前工作区已有未跟踪文件：`dev-log-2026-06-08-dolphinscheduler-standalone.md`、`patch/`。
- 本次未提交 git commit。

### 2026-06-13 补充远端登录与 DS 路径记忆

目标：

- 将 DolphinScheduler 远端登录方式、安装路径、服务名、日志路径写到仓库本地说明中，方便新会话继承上下文。

改动文件：

- `AGENTS.md`
- `DEVELOPMENT_LOG.md`

重要命令：

```bash
rtk ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 3911 mnyjy@127.0.0.1

cd /opt/dolphinscheduler
bash ./bin/dolphinscheduler-daemon.sh status standalone-server
tail -n 200 /opt/dolphinscheduler/standalone-server/logs/dolphinscheduler-standalone.log
```

验证结果：

- 已记录 SSH 目标：`mnyjy@127.0.0.1:3911`。

### 2026-06-14 更新 AGENTS.md 环境信息，查看最新任务状态

目标：

- 将登录方式、ClickHouse/Doris/DS 资源目录信息写入 AGENTS.md
- 查看最新 DS 任务失败情况

改动文件：

- `AGENTS.md` — 更新登录命令、添加 ClickHouse/Doris/DS 资源目录信息
- `DEVELOPMENT_LOG.md` — 追加本条记录

重要命令：

```bash
# 登录
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 3911 mnyjy@127.0.0.1

# 查看 DS 日志
tail -n 200 /opt/dolphinscheduler/standalone-server/logs/dolphinscheduler-standalone.log

# 查看任务实例状态
bash ./bin/dolphinscheduler-daemon.sh status standalone-server
```

### 2026-06-14 编写 3 个新表抽取脚本并上传到 DS 资源目录

目标：

- 参考 `result_new2024_to_doris_from3_12.py`（已成功跑完 `result_new2024_Encry01`），编写 3 个新表的 ClickHouse→Doris 抽取脚本
- 上传到 `/opt/dolphinscheduler/resources/default/resources/ch2doris/`

3 个新脚本：

| 脚本 | 源表 | 目标表 | 行数 | 分批方式 |
|---|---|---|---|---|
| `check_info_new_2024_Encry.py` | `check_info_new_2024_Encry` | `MIHDB_ODS.check_info_new_2024_Encry` | ~2426 万 | `checkin_time` 按天（2024-01-01 ~ 2025-01-01） |
| `check_info_new_2024_Encry01.py` | `check_info_new_2024_Encry01` | `MIHDB_ODS.check_info_new_2024_Encry01` | ~2426 万 | offset 分页全量 |
| `peis_chekup_ans_2024_Encry.py` | `peis_chekup_ans_2024_Encry` | `MIHDB_ODS.peis_chekup_ans_2024_Encry` | ~1.15 亿 | `create_at` 按天（2024-01-01 ~ 2025-01-01） |

改动文件：

- `scripts/ch2doris/check_info_new_2024_Encry.py` — 新建
- `scripts/ch2doris/check_info_new_2024_Encry01.py` — 新建
- `scripts/ch2doris/peis_chekup_ans_2024_Encry.py` — 新建
- `AGENTS.md` — 更新
- `DEVELOPMENT_LOG.md` — 追加

重要命令：

```bash
# 本地创建脚本到 /tmp
cat > /tmp/check_info_new_2024_Encry.py << 'PYEOF'
...
PYEOF

# scp 上传到服务器 /tmp
rtk scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P 3911 /tmp/check_info_new_2024_Encry.py mnyjy@127.0.0.1:/tmp/

# sudo 复制到目标目录
echo 'mnjk2026' | sudo -S cp /tmp/check_info_new_2024_Encry.py /opt/dolphinscheduler/resources/default/resources/ch2doris/

# 语法检查
echo 'mnjk2026' | sudo -S python3 -m py_compile /opt/dolphinscheduler/resources/default/resources/ch2doris/check_info_new_2024_Encry.py

# 复制到本地仓库
cp /tmp/check_info_new_2024_Encry.py /Users/zoyoe/codex/dolphinscheduler/scripts/ch2doris/
```

验证结果：

- 3 个脚本语法检查全部通过
- 已上传到服务器 `/opt/dolphinscheduler/resources/default/resources/ch2doris/`
- 已保存到本地仓库 `scripts/ch2doris/`

遗留问题：

- 3 个脚本尚未在 DS 中创建任务定义和运行
- DS API 登录成功（admin/admin@123），但 sessionId 传递方式需要确认（Header/Cookie 均返回 401），建议在网页上建任务
- sudo 密码 `mnjk2026` 用 `echo '...' | sudo -S` 管道方式可用

### 2026-06-14 编写 check_info_all 抽取脚本

目标：
- 为 ClickHouse 表 `check_info_all`（7332 万行，6 列）编写 Doris 抽取脚本
- 上传到 DS 资源目录

改动文件：
- `scripts/ch2doris/check_info_all.py` — 新建
- `DEVELOPMENT_LOG.md` — 追加

重要命令：
```bash
# 创建并上传
cat > /tmp/check_info_all.py << 'PYEOF' ...
rtk scp -P 3911 /tmp/check_info_all.py mnyjy@127.0.0.1:/tmp/
echo 'mnjk2026' | sudo -S cp /tmp/check_info_all.py /opt/dolphinscheduler/resources/default/resources/ch2doris/
echo 'mnjk2026' | sudo -S python3 -m py_compile /opt/dolphinscheduler/resources/default/resources/ch2doris/check_info_all.py
cp /tmp/check_info_all.py scripts/ch2doris/
```

验证结果：
- 语法检查通过
- 已上传到服务器 `/opt/dolphinscheduler/resources/default/resources/ch2doris/check_info_all.py`
- 已保存到本地仓库 `scripts/ch2doris/check_info_all.py`

### 2026-06-14 编写 SQL Server → Doris Seatunnel 配置文件

目标：
- 为 SQL Server 表 `MNDJK_YanJiuYuan.dbo.mnyjy_peis_result`（~1.6T，~30 亿行）编写 Seatunnel 配置文件
- 上传到 `/opt/dolphinscheduler/resources/default/resources/ss2doris/`

改动文件：
- `scripts/ch2doris/mnyjy_peis_result.conf` — 新建
- `DEVELOPMENT_LOG.md` — 追加

配置要点：
- Source: SQL Server JDBC，`exam_date` 分区（2020-01-01 ~ 2026-01-01，32 分区并行）
- Sink: Doris Stream Load，CSV 格式，35 列
- 并行度 32，batch size 100000

重要命令：
```bash
# 创建目录
echo 'mnjk2026' | sudo -S mkdir -p /opt/dolphinscheduler/resources/default/resources/ss2doris/

# 上传
rtk scp -P 3911 /tmp/mnyjy_peis_result.conf mnyjy@127.0.0.1:/tmp/
echo 'mnjk2026' | sudo -S cp /tmp/mnyjy_peis_result.conf /opt/dolphinscheduler/resources/default/resources/ss2doris/

# 本地保存
cp /tmp/mnyjy_peis_result.conf scripts/ch2doris/
```

遗留问题：
- 需要在 DS 网页上创建 Seatunnel 任务运行此配置
- 首次运行前建议先用小数据量测试连通性

### 2026-06-14 查看最新任务日志：mnyjy_peis_result

目标：
- 继续上服务器查看最新任务日志，确认当前活跃任务的进度与异常

改动文件：
- `DEVELOPMENT_LOG.md` — 追加本次查看结果

重要命令：
```bash
rtk ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 3911 mnyjy@127.0.0.1 'cd /opt/dolphinscheduler && tail -n 300 standalone-server/logs/dolphinscheduler-standalone.log'
rtk ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 3911 mnyjy@127.0.0.1 'cd /opt/dolphinscheduler && find standalone-server/logs -type f \( -name "*.log" -o -name "*.out" \) -printf "%TY-%Tm-%Td %TH:%TM:%TS %p\\n" | sort -r | head -n 80'
rtk ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 3911 mnyjy@127.0.0.1 'cd /opt/dolphinscheduler && tail -n 200 standalone-server/logs/20260614/176120933176736/2/63/66.log'
```

验证结果：
- 最新任务日志定位为 `standalone-server/logs/20260614/176120933176736/2/63/66.log`
- 任务为 `mnyjy_peis_result` 的 SeaTunnel 作业，11:00 左右启动，14:15 仍处于 running 状态
- 进度统计一直停留在 `Read Count So Far = 0`、`Write Committed Count So Far = 0`
- 日志在 14:00:28 出现 SQL Server 源端读取超时：`com.microsoft.sqlserver.jdbc.SQLServerException: Read timed out`
- 远端仍可见 SeaTunnel 相关进程：`/opt/seatunnel/bin/seatunnel.sh --config /tmp/dolphinscheduler/exec/process/66/seatunnel_66.conf --deploy-mode local`

遗留问题：
- 当前更像是源库读取超时，而不是 DolphinScheduler 服务本身挂掉
- 下一步可继续追 `mnyjy_peis_result` 的源端查询参数、SQL Server 连通性或 Seatunnel 超时配置

### 2026-06-17 查看最新任务状态：mnyjy_peis_result 正常运行中

目标：
- 杀掉进程 87（view_yyqkb_Encry）
- 查看 mnyjy_peis_result 最新任务状态

改动文件：
- `DEVELOPMENT_LOG.md` — 追加本条记录

重要命令：
```bash
# 登录（sshpass 方式，mnyjy 密码与 sudo 密码相同均为 mnjk2026）
sshpass -p 'mnjk2026' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 3911 mnyjy@127.0.0.1 'command'

# 查看最新日志
cd /opt/dolphinscheduler && tail -n 300 standalone-server/logs/dolphinscheduler-standalone.log

# 查看进度
tail -n 100 standalone-server/logs/dolphinscheduler-standalone.log | grep -E "(batch|Error|error|Traceback|FAILED|speed|total)"
```

任务状态：
- **mnyjy_peis_result**：正常运行中，batch 35061，总计 17.53 亿行，速度 10,438 rows/s
- **view_yyqkb_Encry（任务 87）**：已杀掉（KILLED）
- mnyjy_peis_result 无报错，每个 batch 的 Stream Load 均为 Success，NumberFilteredRows=0

估算：
- 剩余 ~9.47 亿行，速度 ~10,438 rows/s
- 预计剩余时间 ~25 小时（约 2026-06-18 上午 9 点完成）

遗留问题：
- 进程 87（view_yyqkb_Encry）已杀掉，但该工作流可能还有未完成的任务需要处理
- 后续新会话应先读 AGENTS.md 获取环境信息

### 2026-06-18 装 PyMySQL 修复 lis_test_result_all_slxnl.py 405 错

目标：
- 任务 99 (`lis_test_result_all_slxnl`) 启动失败，原因：`load_target_vids()` 用了错的 Doris HTTP API `/api/{db}/query`，Doris 4.0.5 返回 405
- 改用 pymysql 直连 9030 端口查询目标 VID

服务器环境：
- Ubuntu 22.04, Python 3.10.12，无 pip3，无外网，apt 源也无 python3-pymysql

步骤：
1. 本机下载 PyMySQL-1.1.1-py3-none-any.whl（44KB 纯 Python 包）
2. scp 上传 → 用 Python zipfile 解压 → 复制到 `/usr/lib/python3/dist-packages/pymysql/`
3. 验证 `python3 -c "import pymysql"` OK，连 Doris 9030 测试通过
4. 修补脚本：替换 `load_target_vids()` 函数，改用 pymysql 直连
5. 给 UNION 子查询的表名加 `MNDJK.` 前缀

改动文件：
- `/opt/dolphinscheduler/resources/default/resources/ss2doris/lis_test_result_all_slxnl.py`
- 备份：`lis_test_result_all_slxnl.py.bak.20260618_092540`

重要命令：
```bash
# 下载并上传 whl
curl -L -o /tmp/PyMySQL-1.1.1-py3-none-any.whl \
  "https://files.pythonhosted.org/packages/0c/94/e4181a1f6286f545507528c78016e00065ea913276888db2262507693ce5/PyMySQL-1.1.1-py3-none-any.whl"
sshpass -p 'mnjk2026' scp -P 3911 /tmp/PyMySQL-1.1.1-py3-none-any.whl mnyjy@127.0.0.1:/tmp/

# 服务器上离线安装
echo 'mnjk2026' | sudo -S python3 -c "import zipfile; zipfile.ZipFile('/tmp/PyMySQL-1.1.1-py3-none-any.whl').extractall('/tmp/pymysql_extracted')"
echo 'mnjk2026' | sudo -S cp -r /tmp/pymysql_extracted/pymysql /usr/lib/python3/dist-packages/

# 验证
python3 -c "import pymysql; print(pymysql.__version__)"
```

验证结果：
- pymysql 安装成功
- 连 Doris 9030 + SHOW DATABASES 测试通过
- 新脚本语法检查通过
- 备份+部署完成

遗留问题：
- 用户重新触发任务 99 后需要再确认运行成功
- Doris FE 节点 java.security 没改成功（systemctl restart 无效，因为老 FE 进程是手动起的，systemd 起不了新进程，端口被占）
- catalog 暂时不能创建，等所有任务跑完后再处理 FE TLS 问题

### 2026-06-18 改 lis_test_slxnl 为临时表 JOIN（B 方案）

背景：
- 任务 100 卡死 6 小时，CPU 0%、3 个 SQL Server 连接 ESTABLISHED 但都没返回
- 卡在 `WHERE LOWER(CONVERT(VARCHAR(MAX), VID, 2)) IN (5000个)` 全表扫
- VID 字段是 VARBINARY 二进制，CONVERT 让索引完全失效
- mnyjy_peis_result 已成功完成（27.4 亿行入 Doris）

改动文件：
- `/opt/dolphinscheduler/resources/default/resources/ss2doris/lis_test_result_all_slxnl.py`
- 备份：`lis_test_result_all_slxnl.py.bak.20260618_154621`（pymysql 基础版）
- 备份：`lis_test_result_all_slxnl.py.bak.20260618_092540`（最初 HTTP API 错误版）

核心改动：
1. `build_select_sql()` — 不再接收 vid_batch 参数，改成 `INNER JOIN #target_vids ON t.VID = v.vid`
2. `extract_single_table()` —
   - 每个 worker 自建会话级临时表 `#target_vids (vid VARBINARY(32) PRIMARY KEY)`
   - 用 `INSERT VALUES (0x...), (0x...)` 批量 1000/批灌入
   - 整张分表只跑 1 次 JOIN 查询，不再循环 N 次 IN

预期效果：
- SQL Server 单表查询次数：N 次 → 1 次
- 全表扫常数大幅下降（避免逐行 CONVERT）
- 总耗时预期降低 5-50 倍

操作命令：
```bash
# 杀任务 100
echo 'mnjk2026' | sudo -S kill -9 2784766 2784758 2784755

# 部署
sshpass -p 'mnjk2026' scp -P 3911 /tmp/lis_test_result_all_slxnl_v2.py mnyjy@127.0.0.1:/tmp/
echo 'mnjk2026' | sudo -S cp /tmp/lis_test_result_all_slxnl_v2.py \
  /opt/dolphinscheduler/resources/default/resources/ss2doris/lis_test_result_all_slxnl.py
echo 'mnjk2026' | sudo -S python3 -m py_compile \
  /opt/dolphinscheduler/resources/default/resources/ss2doris/lis_test_result_all_slxnl.py
```

遗留问题：
- 等用户重新启动任务后观察是否真的快很多
- 如果 SQL Server 端有 hash join 内存压力（target_vids 太大），可能需要分多个临时表批次

### 2026-06-19 lis_test_result_all_Encry A+C 全套提速部署

目标：
- 之前 12h 才跑完 1.7 亿行（≈3,800 行/秒），72 张分表中只有 1 张完成，8 张半完成
- 用户要 A+B+C "全套"提速：A=PARALLEL_NUM 8→16；B=orjson 替代 json；C=单 worker fetch/load 流水线

实际部署：A+C，B 留 fallback（脚本里 `try import orjson` 失败时退化到 stdlib json，部署时透明）
- 本机 + 服务器都没法拉 orjson whl（DNS 全断），等下一次能联网时单独装包，**不阻塞抽数**
- 加 orjson 后再走一次 `python3 -c "import orjson"` 即可生效，无需改脚本

改动文件：
- `/opt/dolphinscheduler/resources/default/resources/ss2doris/lis_test_result_all_Encry.py`
- 备份：`lis_test_result_all_Encry.py.bak.20260618_161639`
- 备份：`lis_test_result_all_Encry.py.bak.20260618_160301`（断点续跑改造版）

核心改动：
1. **A**: `PARALLEL_NUM = 16`（原 8）
2. **B**: `to_json_body` 优先 orjson，缺包时 fallback 到 `json.dumps`；启动日志会打印 `orjson=on/off`
3. **C**: `extract_single_table` 内部 producer/consumer 流水线
   - producer 线程：循环 `fetchmany(BATCH_SIZE)` → 塞进 `Queue(maxsize=2)`
   - 主线程作为 consumer：`get` → `to_json_body` → `stream_load`
   - 让 SQL Server 取数和 Doris 写入并行，单 worker 内不再阻塞等 load
   - SENTINEL 收尾，异常时排空队列让 producer 退出

预期提速：
- A 单独：~2x（线程数翻倍，CPU 还能挖）
- C 单独：~1.5-2x（fetch 和 load 异步化）
- A+C 合计：~2.5-3x，从 ~3,800 行/秒 涨到 ~10,000 行/秒
- 加上 B（orjson）后再 +30%-50%

操作命令：
```bash
# 上传新脚本
sshpass -p 'mnjk2026' scp -P 3911 \
  /tmp/lis_test_result_all_Encry_v2.py \
  mnyjy@127.0.0.1:/tmp/

# 服务器上备份并部署
sshpass -p 'mnjk2026' ssh -p 3911 mnyjy@127.0.0.1 \
  'echo "mnjk2026" | sudo -S bash -c "
   TS=\$(date +%Y%m%d_%H%M%S)
   cp /opt/dolphinscheduler/resources/default/resources/ss2doris/lis_test_result_all_Encry.py \
      /opt/dolphinscheduler/resources/default/resources/ss2doris/lis_test_result_all_Encry.py.bak.\$TS
   cp /tmp/lis_test_result_all_Encry_v2.py \
      /opt/dolphinscheduler/resources/default/resources/ss2doris/lis_test_result_all_Encry.py
   chown root:root /opt/dolphinscheduler/resources/default/resources/ss2doris/lis_test_result_all_Encry.py
   python3 -m py_compile /opt/dolphinscheduler/resources/default/resources/ss2doris/lis_test_result_all_Encry.py
   "'
```

验证：
- 服务器侧 `python3 -m py_compile` 通过 ✅
- 文件 owner=root:root, mode=644 ✅
- 当前 jj_comm_jc_result_all_Encry 还在跑（PID 2335007），lis_test_result_all_slxnl 也在跑（PID 3196910）
- 等用户在 DS 重新启动 lis_test_result_all_Encry 任务即可看到新版本生效
- 启动日志会打印 `启动批量抽取，共72张表，并行度16，orjson=off`（装 orjson 后变 on）

遗留 / 后续：
- orjson Linux whl（`orjson-3.10.7-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl`）
  - 等本机或服务器能联网时，下载后 scp 到服务器 `/tmp`
  - 再 `unzip -d /tmp/orjson_extracted` + 把 `orjson/` 目录复制到 `/usr/lib/python3/dist-packages/`
  - 不需要改脚本，重启任务即可
- 如果 orjson 始终装不上，可以改用 ujson（也是纯 Python fallback 麻烦）或者放弃 B，单 A+C 已经够用


### 2026-06-19 orjson 离线安装到服务器（B 方案补完）

目标：
- A+C 已部署，补上 B（orjson）让 JSON 序列化再快 30%-50%

文件来源：
- 用户在本机下载好：`/Users/zoyoe/Downloads/orjson-3.10.7-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl`（141 KB）

操作命令：
```bash
# 上传 whl 到服务器
sshpass -p 'mnjk2026' scp -P 3911 \
  /Users/zoyoe/Downloads/orjson-3.10.7-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl \
  mnyjy@127.0.0.1:/tmp/orjson-3.10.7.whl

# 服务器上解压并部署到 dist-packages
sshpass -p 'mnjk2026' ssh -p 3911 mnyjy@127.0.0.1 \
  'echo "mnjk2026" | sudo -S bash -c "
   rm -rf /tmp/orjson_extracted
   python3 -c \"import zipfile; zipfile.ZipFile(\\\"/tmp/orjson-3.10.7.whl\\\").extractall(\\\"/tmp/orjson_extracted\\\")\"
   rm -rf /usr/lib/python3/dist-packages/orjson /usr/lib/python3/dist-packages/orjson-*.dist-info
   cp -r /tmp/orjson_extracted/orjson /usr/lib/python3/dist-packages/
   cp -r /tmp/orjson_extracted/orjson-*.dist-info /usr/lib/python3/dist-packages/ 2>/dev/null || true
   python3 -c \"import orjson; print(orjson.__version__)\"
   "'
```

验证：
- `import orjson` 成功，version 3.10.7
- `orjson.dumps({"x":1,"y":"中文"})` 正常返回字节串
- lis_test_result_all_Encry.py 重启时会自动选用 orjson，启动日志会打印 `orjson=on`

效果：
- A+B+C 三件套全部到位
- 预期速度：~3,800 行/秒 → ~12,000 行/秒（3x 提速）
- 全量预期：5.6 天 → 1.7 天

### 2026-06-19 jj_comm_jc_result_all_Encry 改造（A+B+C+断点续跑）

背景：
- 老脚本 PARALLEL_NUM=3，跑了 14h09m 入库 4.72 亿行（速度 ~9300 行/秒）
- 全表总量从 SQL Server `sys.partitions` 元数据查得 **79.49 亿行**
- 剩余 ~69 亿，按老速度还要 8.6 天

通过 SQL Server 元数据 + Doris 行数对账，分类如下：
- **完整 5 张**（Doris 行数 = 源表行数）：201701、201702、201703、201704、201706
- **半完成 3 张**：201705 (90.8%)、201707 (90.9%)、201708 (20.2%)
- **未抽 64 张**：201709 起到 202212

操作步骤：
1. `kill -TERM 2335007` 杀老进程（已确认退出）
2. 改造脚本 `jj_comm_jc_result_all_Encry.py`：
   - **A**: PARALLEL_NUM 3 → 16
   - **B**: 加 orjson fallback
   - **C**: 单 worker producer/consumer 流水线（fetchmany 与 stream_load 并行）
   - **断点续跑**: COMPLETED_TABLES 列出 5 张完整表跳过；启动时通过 pymysql 连 Doris 9030 查行数，对半完成表 DELETE 后重抽
   - 所有 `print()` 都加 `flush=True`，避免 stdout block 缓冲让 DS 看不到日志（解决之前两个任务 stdout 黑屏的问题）

改动文件：
- `/opt/dolphinscheduler/resources/default/resources/ss2doris/jj_comm_jc_result_all_Encry.py`
- 备份：`jj_comm_jc_result_all_Encry.py.bak.20260618_165400`
- 本地副本：`/Users/zoyoe/codex/dolphinscheduler/ss2doris/jj_comm_jc_result_all_Encry.py`
- patch 脚本：`/Users/zoyoe/codex/dolphinscheduler/scripts/patch/jj_patch_{a,b,c,d}.py`

部署验证：
- `python3 -m py_compile` 通过 ✅
- import smoke test：`PARALLEL_NUM=16, orjson=True, COMPLETED=5`

预期：
- 启动时 5 张完整表跳过，3 张半完成 DELETE 后重抽（约 2.18 亿要丢掉重抽）
- 实际净抽量 = 0.87 亿 (半完成差额) + 73.13 亿 (未抽) + 2.18 亿 (半完成重抽) = ~76 亿
- 按 lis_test_result_all_Encry 实测 16 并发 + orjson + 流水线 ≈ 19000 行/秒
- 全部完成预估 **3-4 天**，比原 8.6 天快 ~2-3x

下一步：
- 用户在 DS 重新触发 jj_comm_jc_result_all_Encry 任务
- 启动日志会打 `启动批量抽取，共72张表，并行度16，orjson=on`
- 接着打 5 行 [跳过-已完成]、3 行 [清理]、本次抽取 67 张表

### 2026-06-19 lis_test_result_all_Encry 改 ProcessPoolExecutor（破 GIL）

发现问题：
- A+B+C 部署 35 分钟后实测速度只有 ~4000 行/秒，比预期 19000 慢 5 倍
- 进程 CPU 226%（≈ 2.3 核），16 worker 线程每个 13.5%——典型 GIL 串行
- 服务器 16 核空闲 85.7%，SQL Server 端 16 个连接 recv-q 都堆了 130KB-670KB（Python 来不及消费）
- ens18 入流量正常，**网络不是瓶颈**，**GIL 是瓶颈**

根因：
- `to_json_body` + `clean_value` + `safe_decode` 是 CPU 密集（每行 27 列处理 + JSON 序列化）
- Python 多线程跑 CPU 密集时 GIL 锁定，16 个 worker 实际只能跑 ~2 核
- orjson C 扩展能 release GIL，但 fallback 路径（safe_decode、Decimal→float）还是纯 Python，瓶颈仍在

修复：
1. `from concurrent.futures import ProcessPoolExecutor`：每个 worker 独立 GIL，能真正用 16 核
2. `multiprocessing.set_start_method('spawn', force=True)`：用 spawn 干净启动子进程，避免 fork 继承父进程状态/连接
3. `sys.stdout.reconfigure(line_buffering=True)` + 21 处 print 全加 `flush=True`：保证多进程下 DS 能实时看到日志
4. 子进程内 SQL Server 和 stream load 完全独立，互不干扰

改动文件：
- `/opt/dolphinscheduler/resources/default/resources/ss2doris/lis_test_result_all_Encry.py`
- 备份：`lis_test_result_all_Encry.py.bak.20260618_165855`
- 本地副本：`/Users/zoyoe/codex/dolphinscheduler/ss2doris/lis_test_result_all_Encry.py`
- patch 脚本：`scripts/patch/lis_patch_{mp,spawn,flush}.py`

操作命令：
```bash
# kill 老进程（PID 3229243，已抽 0.84 亿行有效净抽量）
kill -TERM 3229243
# 部署
sshpass -p 'mnjk2026' scp -P 3911 /tmp/lis_test_result_all_Encry_v3.py mnyjy@127.0.0.1:/tmp/
sshpass -p 'mnjk2026' ssh -p 3911 mnyjy@127.0.0.1 \
  'echo mnjk2026 | sudo -S cp /tmp/lis_test_result_all_Encry_v3.py \
    /opt/dolphinscheduler/resources/default/resources/ss2doris/lis_test_result_all_Encry.py'
```

预期：
- 16 个独立进程，每进程 ≈ 5000 行/秒（CPU 占满 1 核 + 流水线 + orjson）
- 总速度 16 × 5000 = ~80,000 行/秒，比之前的 4000 快 20 倍
- 但实际会被 SQL Server 端 IO/CPU 限制，估计实测 30000-50000 行/秒
- 全部 ~50 亿行剩余 → 1-2 天

后续观察点：
- 如果 SQL Server 端 IO 压力大，也许要把 PARALLEL_NUM 调到 12 或 8
- 如果用户同时跑 jj_comm_jc，两个任务一起 32 进程同源 SQL Server，需要错峰

下一步：用户在 DS 重新触发 lis_test_result_all_Encry 任务

### 2026-06-19 jj_comm_jc_result_all_Encry 同步改 ProcessPoolExecutor

参考 lis_test 的 GIL 诊断，jj_comm_jc 同步移植：
- ThreadPoolExecutor → ProcessPoolExecutor
- 加 `multiprocessing.set_start_method('spawn')`
- 顶部 `sys.stdout.reconfigure(line_buffering=True)`
- 21 处 print 全加 `flush=True`

改动文件：
- `/opt/dolphinscheduler/resources/default/resources/ss2doris/jj_comm_jc_result_all_Encry.py`
- 备份：`jj_comm_jc_result_all_Encry.py.bak.20260618_170257`
- 本地副本：`/Users/zoyoe/codex/dolphinscheduler/ss2doris/jj_comm_jc_result_all_Encry.py`
- patch 脚本：`scripts/patch/jj_patch_mp.py`

部署验证：`SYNTAX_OK`, `PARALLEL=16 orjson=True COMPLETED=5`

资源规划：
- 服务器 16 核 / 62 GB
- lis_test_result_all_Encry：16 进程
- jj_comm_jc_result_all_Encry：16 进程
- 两个一起跑 = 32 进程，会**严重超核**。建议二选一，或者两个都改 PARALLEL_NUM=8 一起跑
- 单跑一个时 PARALLEL_NUM=16 最优；同时跑两个时改 8/8 比较稳

下一步：
- 用户在 DS 重新触发任意一个任务即可
- 启动日志会实时滚动（多进程 + flush 双保险）
- 速度预期 30,000-50,000 行/秒

### 2026-06-19 jj_comm_jc PARALLEL_NUM 16→6 应对并发

背景：
- lis_test_result_all_Encry 多进程版起来后实测 138,000 行/秒，占 ~9.2 核
- lis_test_result_all_slxnl 还在跑占 1-2 核
- 16 核服务器剩下 ~5 核给 jj_comm_jc
- 同时跑两个都 16 进程会变 33 进程抢 16 核，反而拖慢

调整：
- jj_comm_jc_result_all_Encry.py `PARALLEL_NUM = 16 → 6`
- 备份：`jj_comm_jc_result_all_Encry.py.bak.20260618_170726`
- 6 进程预期速度：6 × ~8500 = ~50,000 行/秒，剩余 ~76 亿 → 约 2 天

资源规划（同时跑时）：
- lis_test_result_all_Encry: 16 进程 ≈ 9-10 核
- lis_test_result_all_slxnl: 1-2 核
- jj_comm_jc_result_all_Encry: 6 进程 ≈ 4-5 核
- 总计：~15 核，刚好契合 16 核服务器

后续：
- 等 lis_test_result_all_Encry 跑完（预计 2-3 小时），可以把 jj_comm_jc 调回 PARALLEL_NUM=16

### 2026-06-19 任务进度复盘 + jj_comm_jc 不调并发

10 小时后再看：
- lis_test_result_all_Encry: 44.98 亿行入库（净抽 44.80 亿），平均 ~122k 行/秒，抽到 202201
- jj_comm_jc_result_all_Encry: 35.17 亿行入库（净抽 33.42 亿），平均 ~92k 行/秒，抽到 202006
- 系统 load 16.69（16 核接近满载）

jj_comm_jc 是否调回 PARALLEL_NUM=16？
- 算下来"现在改"和"等 lis 跑完再改"差距约 1 小时
- 用户决定不调，保持 6 进程跑到底
- 理由：免去 kill + 部署 + 重启 + DELETE 半完成表的折腾，净收益不明显

预期完成时间：
- lis_test_result_all_Encry: 再 2-3 小时
- jj_comm_jc_result_all_Encry: 再约 14 小时（保持 6 进程）
- lis_test_result_all_slxnl: 跟随 jj_comm_jc 节奏

下一节点：lis_test_result_all_Encry 跑完时同步一次状态

### 2026-06-22 DataX 插件部署 - 路径 B 受阻

**现状**:
- DS 网页保存 DataX 任务报 `请求参数[{0}]无效`
- 根因: DS 3.4.0 默认未打 DataX 插件 jar (TaskPluginManager.getTaskChannel 找不到 DATAX)
- 缺失: `dolphinscheduler-task-datax-3.4.0-shade.jar` + DataX 引擎本体

**用户选择路径 B**: Codex 控制本地 Chrome 帮忙下载 DataX 资产。

**受阻点**:
- 本机沙箱网络全断 (DNS/连接全部 timeout)
- 服务器内网无外网, 包都得本机下了 scp
- Computer Use 不能用 Apple Terminal
- Chrome 地址栏输入 Maven URL 后回车被 Omnibox 拦截回 newtab, 没真正访问

**待用户决策**:
1. 用户自行在 Chrome 打开 https://repo1.maven.org/maven2/org/apache/dolphinscheduler/dolphinscheduler-task-datax/ 看可用版本, 把 jar 下到 ~/Downloads/, Codex 接手 scp 上服务器
2. 改用已部署的 SeaTunnel (前面 mnyjy_peis_result 已验证可用), 把 DataX 任务改写成 SeaTunnel 配置或 Python 脚本
3. 把外网代理打通后再让 Codex 走 fetch/curl 下包

**风险点**: DataX 3.4.0 plugin jar 可能在社区根本没发布 (3.4 移除了),如果 Maven 上没有,建议直接切到方案 2。

### 2026-06-22 下午 DataX 部署进展

**plugin jar**: 已成功 scp + 部署
- 路径: /opt/dolphinscheduler/plugins/task-plugins/dolphinscheduler-task-datax-3.4.0-shade.jar
- 权限: mnyjy:dolphinscheduler 644 (与同目录其他 plugin 一致)
- 大小: 4.0 MB (3.9MB 上传)

**DataX 引擎**: 传输极慢, 已成为瓶颈
- 本地路径: /Users/zoyoe/Downloads/datax.tar.gz (1.5G)
- 远端进度: 26MB / 8 分钟, 即 ~50 KB/s
- 按此速度需 5-8 小时
- 原因: SSH 隧道 127.0.0.1:3911 走中间代理, 带宽受限
- 已部署 plugin jar 后 DS 重启就能保存 DATAX 任务类型,但实际执行仍依赖 /opt/datax 引擎到位

**两条路待选**:
- A) 让 scp 后台慢慢传完,期间先重启 DS 让 plugin 生效,后续补 DATAX_HOME 配置
- B) 切 SeaTunnel: 之前 mnyjy_peis_result 27 亿行已用 SeaTunnel 跑通, 把这个新 DataX 任务用 SeaTunnel 等价配置重写, 立刻能跑

**用户决策: 路径 A** - scp 后台慢传, Codex 每隔一阵轮询进度, 传完后立刻解压 + 配 DATAX_HOME + 重启 DS standalone-server。

### 2026-06-22 DataX 部署完成

**用户已离线 scp**: /opt/offline/datax.tar.gz (1.6G, 完整)

**执行步骤**:
1. 备份旧引擎 (如有): mv /opt/datax /opt/datax.bak.$(date +%s)
2. tar -xzf /opt/offline/datax.tar.gz -C /opt/
3. chown -R mnyjy:dolphinscheduler /opt/datax
4. 在五个 env.sh 写入 `export DATAX_HOME=/opt/datax`:
   - /opt/dolphinscheduler/bin/env/dolphinscheduler_env.sh
   - /opt/dolphinscheduler/standalone-server/conf/dolphinscheduler_env.sh
   - /opt/dolphinscheduler/worker-server/conf/dolphinscheduler_env.sh
   - /opt/dolphinscheduler/master-server/conf/dolphinscheduler_env.sh
   - /opt/dolphinscheduler/api-server/conf/dolphinscheduler_env.sh
   (注意: standalone 启动会用 bin/env/ 覆盖 standalone-server/conf/,所以 bin/env/ 是真正生效源)
5. plugin jar 已部署: /opt/dolphinscheduler/plugins/task-plugins/dolphinscheduler-task-datax-3.4.0-shade.jar
6. stop + start standalone-server (daemon 脚本不支持 restart)
7. 验证: 日志出现 `Success register task plugin: DATAX` ✅

**验证脚本**:
```bash
sshpass -p 'mnjk2026' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 3911 mnyjy@127.0.0.1 \
  'grep -i "Success register task plugin: DATAX" /opt/dolphinscheduler/standalone-server/logs/dolphinscheduler-standalone.log'
```

**下一步**: 用户去 DS 网页 (admin/admin@123) 重新保存原来报错的 DATAX 任务,应不再出现 `请求参数[{0}]无效`,可以提交运行。

### 2026-06-22 DataX 报错 `unknown option --jvm=` 根因

**症状**: 跑 DataX 任务报 `unknown option --jvm=-Xms1G -Xmx1G` + 显示 `python -h` 帮助。

**根因**:
- DS 生成的命令是 `${PYTHON_LAUNCHER} ${DATAX_LAUNCHER} --jvm=...`
- DS 真正执行: `sudo -u root -i /tmp/.../<id>.sh`
- `sudo -i` 走 root 的 login shell, 完全无视 `/opt/dolphinscheduler/.../dolphinscheduler_env.sh`
- 结果 `${DATAX_LAUNCHER}` 为空, 命令塌成 `/bin/python3 --jvm=...`, python 不认 --jvm 报错。

**修法**: 写 `/etc/profile.d/datax.sh`(系统级 login shell 都会自动 source):
```bash
export DATAX_HOME=/opt/datax
export DATAX_LAUNCHER=/opt/datax/bin/datax.py
export PYTHON_LAUNCHER=/usr/bin/python3
```
chmod 644。验证: `sudo -u root -i bash -c 'echo $DATAX_LAUNCHER'` 可见 `/opt/datax/bin/datax.py`。

**结论**: DS 3.4.0 通过 `sudo -u root -i` 跑 shell 任务,环境变量必须放到 root 能继承的全局位置 (`/etc/profile.d/*.sh` 最稳),光改 DS 自家的 env.sh 不生效。

### 2026-06-22 DataX clickhousereader MissingResourceException

**症状**: DS DataX 任务 107 跑起来了 (env 变量修复生效),DataX 启动成功打印版本号,但 ClickhouseReader 静态初始化时报:
```
Can't find bundle for base name com.alibaba.datax.plugin.reader.clickhousereader.LocalStrings, locale zh_CN
ClickhouseReader$Job.<clinit>(ClickhouseReader.java:30)
```

**根因**: DataX 离线包里的 `clickhousereader-0.0.1-SNAPSHOT.jar` 完全没打 `LocalStrings*.properties` i18n 资源(jar tf 验证),JDK 17 下 ResourceBundle.getBundle 找不到任何 locale 的 properties 就直接抛异常。

**修法 (双保险)**:
1. 改 `/opt/datax/bin/datax.py` 的 `DEFAULT_PROPERTY_CONF`,追加 `-Duser.language=en -Duser.country=US`,让 JVM 走英文 locale。
2. 往 `clickhousereader-0.0.1-SNAPSHOT.jar` 里注入三个空的 properties:
   - `com/alibaba/datax/plugin/reader/clickhousereader/LocalStrings.properties`
   - `com/alibaba/datax/plugin/reader/clickhousereader/LocalStrings_en_US.properties`
   - `com/alibaba/datax/plugin/reader/clickhousereader/LocalStrings_zh_CN.properties`
   命令: `jar uf <jar> <files>`

**风险点**: 其他 reader/writer 插件(比如 mysqlreader 也无 LocalStrings)将来跑到也可能犯同样的错,届时按相同方式补 properties。

**备份**: datax.py 旧版已备份为 `/opt/datax/bin/datax.py.bak.<ts>`。

### 2026-06-22 ClickHouse 新建 datax 用户

**背景**: DataX 的 ClickhouseReader 调 CommonRdbmsReader,后者强制 `password` 字段必填非空,而 ClickHouse 的 `default` 用户只接受空密码,两边互斥。

**解决**: 在 ClickHouse 上单独建一个带密码的 datax 用户,DS 数据源改用该用户。

**操作 (走 HTTP 8123 默认无密码接口,raw POST body)**:
```bash
curl -s --data-binary "CREATE USER IF NOT EXISTS datax IDENTIFIED BY 'Mnjk@2026'" http://192.168.77.131:8123/
curl -s --data-binary "GRANT SELECT ON mndjk.* TO datax"                          http://192.168.77.131:8123/
```

**验证**:
```bash
curl -u "datax:Mnjk@2026" --data-binary "SELECT count() FROM mndjk.item_dict_stats" http://192.168.77.131:8123/
# -> 872750
curl --data-binary "SHOW GRANTS FOR datax" http://192.168.77.131:8123/
# -> GRANT SELECT ON mndjk.* TO datax
```

**注意**:
- 权限最小化: 只有 `SELECT ON mndjk.*`,不开 `*.*`
- 密码: `Mnjk@2026`
- 该用户只能 SELECT mndjk 库;若以后要抽别的 ClickHouse 库, 需另行 GRANT
- HTTP API 必须用 `--data-binary` 走 raw body, 不能用 `--data-urlencode "query=..."` (CH 把 `query=` 当成 SQL 起始字符直接报 syntax error)

**用户下一步**: DS 网页 → 数据源中心 → 编辑 id=2 那个 ClickHouse 数据源 → 用户名 `datax` 密码 `Mnjk@2026` → 测试连接 + 保存 → 重跑 DataX 任务。

### 2026-06-22 Doris 新建 datax 用户 (对称 ClickHouse 处理)

**背景**: 修完 Reader 端 password 必填后,Writer 端 mysqlwriter 报同样的 `[password]是必填参数`。 Doris 的 root@% 也是空密码。

**操作 (走 Doris MySQL 协议 9030,root 空密码)**:
```sql
CREATE USER IF NOT EXISTS 'datax'@'%' IDENTIFIED BY 'Mnjk@2026';
GRANT LOAD_PRIV, SELECT_PRIV ON MIHDB_ODS.* TO 'datax'@'%';
GRANT SELECT_PRIV ON information_schema.* TO 'datax'@'%';
```

**验证**:
- SHOW GRANTS: `MIHDB_ODS: Select_priv,Load_priv; information_schema: Select_priv; mysql: Select_priv (Doris 默认)`
- 用 datax/Mnjk@2026 登录, CURRENT_USER()='datax'@'%', 能 SHOW TABLES FROM MIHDB_ODS

**用户下一步**: DS 网页 → 数据源中心 → 编辑 id=6 那个 Doris/MySQL 数据源 → 用户名 `datax` 密码 `Mnjk@2026` → 测试连接 + 保存 → 重跑 DataX 任务。

### 2026-06-22 DataX 提速 57 倍: mysqlwriter -> doriswriter

**问题**: DS DataX 任务用 mysqlwriter 走 JDBC INSERT 写 Doris,实测 1500 rec/s,87 万行要 14 分钟。

**根因**: mysqlwriter 是按 channel=1 + batch=1024 连续发 `INSERT INTO ... VALUES`,FE 需要解析 SQL + 行锁,代价大。之前 Python 抽数快是因为走 Doris Stream Load,直接 HTTP body 批量推 BE,绕过 FE SQL 层。

**修法**: DS DataX 任务切到「自定义模板」模式,writer 换成 doriswriter (DataX 自带,路径 `/opt/datax/plugin/writer/doriswriter`),内部走 Stream Load。

**关键 job.json 片段** (item_dict_stats):
```json
"writer": {
  "name": "doriswriter",
  "parameter": {
    "username": "datax",
    "password": "Mnjk@2026",
    "column": ["..."],
    "loadUrl": ["192.168.77.38:8030"],
    "connection": [{
      "jdbcUrl": "jdbc:mysql://192.168.77.38:9030/",
      "selectedDatabase": "MIHDB_ODS",
      "table": ["item_dict_stats"]
    }],
    "loadProps": {
      "format": "json",
      "strip_outer_array": "true",
      "max_filter_ratio": "0.0"
    }
  }
}
```
配 `"speed": {"channel": 4}` 4 并行。

**实测对比** (87 万行 / 9 列 / 单表):
| 方案 | 耗时 | 速率 |
| --- | --- | --- |
| mysqlwriter (channel=1, record_limit=1000) | 14 分钟 | 1024 rec/s |
| mysqlwriter (channel=1, 不限速) | ~7 分钟 | ~1500 rec/s |
| doriswriter (channel=4, Stream Load) | **10 秒** | **87275 rec/s** |

**模板存档**: /Users/zoyoe/codex/dolphinscheduler/datax-jobs/item_dict_stats_doriswriter.json

**结论**: 写 Doris 一律用 doriswriter,不要用 mysqlwriter。其它 CH→Doris 任务直接复用这份模板,改 querySql/column/table 即可。

## 2026-06-22 建立 MIHDB_DWD 库与 26 张 DWD 表

### 目标
按 `《DWD_体检数据仓库表结构设计_V1.2》.xlsx` 在 Doris 上建库 `MIHDB_DWD`，所有表副本=2。

### 产物
- DDL 生成器: `ddl-dwd/gen_ddl.py`（openpyxl 解析 Excel，按事实表 / 数据字典表 Type A/B / 列定义表 Type C 三种格式生成 DDL）
- 生成的 SQL: `ddl-dwd/MIHDB_DWD.sql`（583 行）
- 远端临时文件: `/tmp/MIHDB_DWD.sql`

### 关键决策
- 模型：Unique Key + Merge-on-Write + ZSTD
- 分桶：事实表 32 buckets，维度表 4 buckets
- 类型映射修正：Doris 不支持 `NVARCHAR(n)`，统一映射为 `VARCHAR(min(n*3, 65533))`；`NTEXT/TEXT` 映射为 `STRING`；`TINYINT(1)` → `TINYINT`
- `dim_date` sheet 是列定义格式（"字段名/类型/说明"三列），单独走 Type C 解析

### 执行命令
```bash
# 本地生成
python3 /Users/zoyoe/codex/dolphinscheduler/ddl-dwd/gen_ddl.py

# 上传（scp 在该环境会 Permission denied，改用 ssh + base64 灌入）
B64=$(base64 < /Users/zoyoe/codex/dolphinscheduler/ddl-dwd/MIHDB_DWD.sql | tr -d '\n')
sshpass -p 'mnjk2026' ssh -p 3911 mnyjy@127.0.0.1 \
  "echo '$B64' | base64 -d > /tmp/MIHDB_DWD.sql && \
   mysql -h 192.168.77.38 -P 9030 -u root --skip-password --force --database MIHDB_DWD < /tmp/MIHDB_DWD.sql"
```

### 验证
- `SHOW TABLES FROM MIHDB_DWD` → 26 张表（8 事实 + 18 维度）
- `SHOW PARTITIONS FROM MIHDB_DWD.dwd_fact_lab` → `Buckets: 32`, `ReplicationNum: 2`
- `SHOW PARTITIONS FROM MIHDB_DWD.dim_date` → `Buckets: 4`, `ReplicationNum: 2`
- DESC 抽查 `dwd_fact_lab` / `dwd_person_info`，PK 标识、类型、默认值、注释全部正常

### 易踩坑
- `scp -P 3911 mnyjy@127.0.0.1` 该环境下会 `Permission denied (publickey,password)`，但 `ssh` 同密码 OK。统一用 `ssh + base64` 落盘
- Excel 维度表实际 18 张（含 dim_date），不是之前文档里说的 17 张

## 2026-06-22 灌入 17 张维度表字典数据（782 行）

### 目标
把 Excel `《DWD_体检数据仓库表结构设计_V1.2》.xlsx` 维度表 sheet 已填的字典值导入 Doris MIHDB_DWD。

### 产物
- INSERT 生成器: `ddl-dwd/gen_dim_inserts.py`
- 生成的 INSERT SQL: `ddl-dwd/MIHDB_DWD_dim_data.sql`（含 17 张 INSERT，共 782 行）

### 关键修复
1. **PK 选择不当**：`gen_ddl.py` 原本固定第一列为 Unique Key，导致 `dim_lab_item` 等层级字典表（lab_category_code -> lab_type_code -> lab_item_code）被合并掉 305 行。增加 PK override：
   - dim_lab_item → `lab_item_code`
   - dim_specimen_item → `specimen_item_code`
   - dim_exam_item → `exam_item_code`
   - dim_age → `age`
2. **typo 列名**：Excel `维度表_检验项目` 第 3 行英文表头有 typo（`lab_category_namegory` / `lab_type_namee`），第 4 行才是正确列名。改 generator 优先取第 4 行（也是英文 header 且 typo 修正版）。
3. **header detection 不够**：`gen_dim_inserts.py` 数据起始行判定原本 break 太早，对 Type B 有两行 snake_case 英文 header 的 sheet 会少跳一行，导致后续数据丢失。改为 `while` 循环连续吃英文 header 行。
4. **0 被吃掉**：`str(c or "")` 对数字 0 会变成空串。改为 `("" if c is None else str(c))`。

### 执行命令
```bash
# 重新生成 DDL + INSERT
python3 ddl-dwd/gen_ddl.py
python3 ddl-dwd/gen_dim_inserts.py

# 上传 + DROP/CREATE + INSERT
B64DDL=$(base64 < ddl-dwd/MIHDB_DWD.sql | tr -d '\n')
B64INS=$(base64 < ddl-dwd/MIHDB_DWD_dim_data.sql | tr -d '\n')
ssh -p 3911 mnyjy@127.0.0.1 "
  echo '$B64DDL' | base64 -d > /tmp/MIHDB_DWD.sql
  echo '$B64INS' | base64 -d > /tmp/MIHDB_DWD_dim_data.sql
  mysql -h 192.168.77.38 -P 9030 -u root --skip-password --force --database MIHDB_DWD < /tmp/MIHDB_DWD.sql
  mysql -h 192.168.77.38 -P 9030 -u root --skip-password --force --database MIHDB_DWD < /tmp/MIHDB_DWD_dim_data.sql
"
```

### 验证
17 张维度表行数合计 782，与 Excel 数据完全一致。`dim_date` 是列定义表，Excel 没数据，留空是正确的。

## 2026-06-23 DS 任务 122 (dwd_person_info ETL) 失败 → datax 用户缺 LOAD_PRIV

### 现象
DolphinScheduler 任务 122 (workflow 119, `DWD_ETL/dwd_person_info`) 用 DataX 把 ODS `check_info_all` 加工写入 `MIHDB_DWD.dwd_person_info`，失败。

DS 日志路径：`/opt/dolphinscheduler/standalone-server/logs/20260623/176895531917184/2/119/122.log`

报错堆栈结论：
```
Code:[Framework-14], 脏数据条数检查不通过，限制是[0]条，但实际上捕获了[2502]条
```

### 根因
不是数据问题。日志里上面那段 WARN 才是真正原因：
```
LOAD command denied to user 'datax'@'192.168.77.39' for table 'MIHDB_DWD.dwd_person_info'
```
`datax` 用户在 `MIHDB_DWD` 库只有 `Select_priv`，没有 `Load_priv`，每条写入都被 Doris 拒绝。DataX 的 mysqlwriter 把"被服务端拒"也计成脏数据，超过阈值 0 就 Framework-14 终止。

### 修复
```sql
GRANT SELECT_PRIV, LOAD_PRIV ON MIHDB_DWD.* TO 'datax';
```
执行后 `SHOW GRANTS FOR datax` 显示：`internal.MIHDB_DWD: Select_priv,Load_priv`。在 DS 重跑任务即可。

### 经验
- DataX → Doris 任务失败先看 mysqlwriter 那段的原始 WARN（`回滚此次写入, 采用每次写入一行方式提交. 因为:errCode = 2, detailMessage = ...`），别被最后那条 "脏数据 2502 条" 误导。
- 新建 Doris 库以后必须 `GRANT SELECT_PRIV, LOAD_PRIV` 给所有 DataX/SeaTunnel 用户。

### 2026-06-23 dwd_person_info 建索引（1 亿存量）

#### 背景
事实表 `MIHDB_DWD.dwd_person_info` 已灌入 ~1.0954 亿行，开始有按身份证/姓名/出生日期/ETL 时间的检索诉求，需要根据列特性配索引。低基数列（sex_code、nation_code、blood_type、is_valid）不建索引。`person_id` 是 Unique Key，自带主键索引也不再加。

#### 索引方案
| 列 | 索引类型 | 说明 |
| --- | --- | --- |
| idcard | BloomFilter | 高基数等值匹配 |
| person_name | Inverted（chinese / fine_grained） | 等值 + 中文 LIKE |
| birthday | Inverted | 范围查询（生日 / 年龄段） |
| etl_load_time | Inverted | 增量 / 回溯 |

脚本：`2.DDL脚本/dwd_person_info_index.sql`

#### 关键点
- `ADD INDEX` 在 Doris 2.x 只登记元数据，**存量数据不会自动建索引**，必须显式 `BUILD INDEX` 才会对历史行生效。
- BloomFilter 不需要 BUILD，会随 compaction 自然重写；急用可手动 `ALTER TABLE ... COMPACT "cumulative"`。
- 表已开 `enable_unique_key_merge_on_write = true`，倒排索引在 MoW Unique 表上是受支持的。
- 1 亿行 BUILD INDEX 较重，串行执行避免业务高峰。

#### 执行命令
连 Doris（本地不能直连 192.168.77.38:9030 时，先走 DS 跳板）：
```bash
# 本地直连（VPN 开启时可用）
mysql -h 192.168.77.38 -P 9030 -u root --skip-password --force \
  --database MIHDB_DWD < 2.DDL脚本/dwd_person_info_index.sql

# 经跳板（VPN 未开时）
scp -P 3911 -o StrictHostKeyChecking=no 2.DDL脚本/dwd_person_info_index.sql mnyjy@127.0.0.1:/tmp/
ssh -p 3911 mnyjy@127.0.0.1 \
  "mysql -h 192.168.77.38 -P 9030 -u root --skip-password --force \
   --database MIHDB_DWD < /tmp/dwd_person_info_index.sql"
```

#### 验证
```sql
SHOW INDEX FROM MIHDB_DWD.dwd_person_info;
SHOW BUILD INDEX FROM MIHDB_DWD;
SHOW ALTER TABLE COLUMN FROM MIHDB_DWD ORDER BY CreateTime DESC LIMIT 5;

-- EXPLAIN 看索引是否被命中
EXPLAIN SELECT person_id FROM MIHDB_DWD.dwd_person_info
WHERE birthday BETWEEN '1990-01-01' AND '1990-12-31';
```

#### 执行状态（2026-06-23 已落地）
经跳板 `sshpass -p 'mnjk2026' ssh -p 3911 mnyjy@127.0.0.1` 在跳板机上对 `192.168.77.38:9030` 实际执行：

1. **BloomFilter（idcard）**：`ALTER TABLE … SET ("bloom_filter_columns"="idcard")` 触发了一次 schema change（JobId 1779700573706），全表 64 个 tablet（32 buckets × 2 副本）重写，11:03:21 → 11:04:14，约 86s 完成。
2. **三个倒排索引**：BloomFilter 完成后逐条执行
   - `idx_person_name` (person_name, INVERTED + chinese/fine_grained)
   - `idx_birthday` (birthday, INVERTED)
   - `idx_etl_load_time` (etl_load_time, INVERTED)
   均登记成功。
3. **BUILD INDEX**：三条任务并发提交（JobId 1779700573871/872/873），从 `WAITING_TXN` → `FINISHED`，各自耗时 ~25-30s（Doris 按 tablet 并行 build，1 亿行被分散到多 BE，所以比预期快很多）。
4. **结果核对**
   - `SHOW CREATE TABLE` 已包含 `bloom_filter_columns="idcard"` 和三条 `INDEX … USING INVERTED`。
   - 真实查询：
     - `SELECT COUNT(*) WHERE birthday BETWEEN '1990-01-01' AND '1990-12-31'` → 3,389,303 行
     - `SELECT COUNT(*) WHERE etl_load_time >= '2026-06-22 00:00:00'` → 109,539,220 行
   - EXPLAIN 显示谓词正常下推到 `VOlapScanNode`（Doris 4.0 的 plan 输出不显式打 "inverted index filter"，索引在 storage 层自动生效）。

#### 踩坑提醒
- 一次性把 `SET bloom_filter_columns` 和后续 `ADD INDEX` 写在同一份脚本里会失败：BloomFilter 是 schema change，会把表状态置为 `SCHEMA_CHANGE`，后续 ALTER 会立刻报 `Table[…]'s state(SCHEMA_CHANGE) is not NORMAL`。**正确做法**：先 SET BloomFilter，轮询 `SHOW ALTER TABLE COLUMN` 直至 `State=FINISHED` 再下发倒排 ALTER。
- `SHOW INDEX FROM` 只列倒排 / Bitmap，不列 BloomFilter；BloomFilter 要看 `SHOW CREATE TABLE` 的 `PROPERTIES("bloom_filter_columns"=…)`。
- 这次脚本里 `BUILD INDEX` 紧跟 ALTER，落到上面这种 SCHEMA_CHANGE 状态时会直接 `Index ... is not exist`。后续可以把脚本拆成 2 阶段（BloomFilter / 倒排+BUILD），或者去掉脚本里的 BloomFilter 那条单独手动跑。

#### 遗留 / 后续
- 后续如需按 `idcard` 模糊匹配，可加 NGram BloomFilter：`ADD INDEX idx_idcard_ngram (idcard) USING NGRAM_BF PROPERTIES('gram_size'='3','bf_size'='256')`。
- `idcard` 现在已有 BloomFilter，做等值查询应该非常快，下一步可对接业务实际查询场景拉一组 P95 看看。
- 同样的索引组合可以平移到其他大事实表（`dwd_fact_checkin / dwd_fact_lab / dwd_fact_exam / dwd_fact_questionnaire / dwd_fact_followup`），但要根据每张表的实际查询模式再裁剪。

### 2026-06-24 编写 dwd_fact_checkin ETL 脚本（4 个 ODS 源合并）

目标：
- 把 2017~2025 的体检登记数据汇总到 `MIHDB_DWD.dwd_fact_checkin`，按设计文档（Excel 21 字段）做字段映射 + 清洗

改动文件：
- `4.ETL脚本/dwd_fact_checkin_from_ods.sql` — 新建，4 段 INSERT

数据源 → 目标段切分：

| 段 | 年份 | 源表 | checkin_id / person_id 来源 |
|---|---|---|---|
| 1 | 2025 | `MIHDB_ODS.check_info_2025_Encry` | `visitor_id / idcard` |
| 2 | 2024 | `check_info_new_2024_Encry a` JOIN `check_info_new_2024_Encry01 b` ON `visitor_id` | `a.visitor_id` / `b.idcard` (mobile/cust_name 同样取 b) |
| 3 | 2023 | `mnyjy_peis_check_info_new01_Encry` | `visitor_id / idcard` |
| 4 | 2017~2022 | `view_yyqkb_Encry` | `VID / BZ_SFZHM` |

核心清洗规则：
- 所有字符串列：`NULLIF(NULLIF(TRIM(x), ''), '\N')`（沿用 dwd_person_info 排过的 `\N` 字面量坑）
- 日期：`STR_TO_DATE` 解析失败返回 NULL；`book_optime < '2000-01-01'` 或 `> NOW()` 置 NULL
- `age = TIMESTAMPDIFF(YEAR, birthday, checkin_dt)`，超出 0~120 置 NULL
- `report_month`：源 YYYYMM → DWD `YYYY-MM`；缺失时降级用 checkin_time 推
- `is_valid`：源 `is_deleted=1` → 0，其余 1（view_yyqkb 无 is_deleted，固定 1）
- 兜底过滤：`checkin_id IS NULL` 或 `person_id IS NULL` 或 `report_month IS NULL` 整行丢弃

暂走默认值 / 待业务映射的字段：
- `health_check_code`：源 (Z/N/M/...) → DWD ('01'~'13','99') 缺映射，统一 '99'
- `personnel_unit_code`：源 corp_code 是企业代码（如 `3622461231207204`），与 dim_personnel_unit (A001/B001…) 口径不同，置 NULL，等单位主数据
- `member_code` / `report_query_code` / `report_collection_code`：源是 `0/1/2/00` 等数字标志，DWD 是 '01/02/...'，缺映射，走表 DEFAULT
- `external_inspection_code`：默认 'N'，view_yyqkb 没该字段
- `marital_code` / `fertility_code`：源表都没有，默认 '99'

待执行：
1. 跳板机用 `mysql ... < 4.ETL脚本/dwd_fact_checkin_from_ods.sql` 灌入
2. 体量预估 1.5~2 亿行，可考虑按段串行跑（每段 INSERT 单独 commit）
3. 入库后写同款质控脚本 `5.数据质控脚本/dwd_fact_checkin_quality_check.sql`

#### 2026-06-24 修复: report_date 降级链 (print_time 空率高)

改动：`report_date` 不再只依赖 print_time，改成降级链：
- 2023~2025 段：`COALESCE(print_time, update_time, checkin_time)`
- 2017~2022 view_yyqkb 段：`COALESCE(PRINT_TIME, TJZZSJ, QTDJSJ)`
  - `TJZZSJ` 是老库"体检终止时间"，语义上最贴近出报告，最后兜底用登记时间 `QTDJSJ`

#### 2026-06-24 dwd_fact_checkin 小批量验证 + 质控

**改动**:
- view_yyqkb 段 idcard 降级: `COALESCE(BZ_SFZHM, VID)`
- view_yyqkb 段去重: `NOT EXISTS (SELECT 1 FROM mnyjy_peis_check_info_new01_Encry x WHERE x.visitor_id = v.VID)`
- 目标表 `dwd_fact_checkin.mobile` 由 `VARCHAR(20)` 扩到 `VARCHAR(128)` (各源最长 44 字符的 base64 密文)
- `3.代码生成器/gen_ddl.py` 增加 hardcode override, 保证下次重生成 DDL 仍是 128
- `2.DDL脚本/MIHDB_DWD.sql` 中 mobile 同步改 128

**验证**:
- 先 TRUNCATE 清空之前 3895 条
- 4 段各 LIMIT 1000, 共 4000 行全部成功落库 (4 * 1000)
- mobile 长度分布: 20(2025)/32(2024)/44(2023), 无截断
- checkin_id 4000 全唯一; person_id 唯一 3933 (有少量同期多次体检)
- 与 dwd_person_info 对账: 3000 匹配 + 1000 孤儿 (view_yyqkb 走 VID 兜底, 预期内)
- 时间字段: 73 行 checkin_date < book_optime, 2 行 report_date < checkin_date

**新增文件**:
- `5.数据质控脚本/dwd_fact_checkin_quality_check.sql`
- `5.数据质控脚本/dwd_fact_checkin_quality_check_result_20260624_verify.md`

#### 2026-06-24 修正 Q5 归因: 孤儿来自 2024 段而非 view_yyqkb

**起初判断错**: 以为 1000 行孤儿来自 view_yyqkb 段 idcard 降级取 VID。

**实际**: 分年份重查后, 孤儿 100% 来自 2024 段, view_yyqkb 段命中率 100%。

**根因**: `check_info_new_2024_Encry` 与 `check_info_new_2024_Encry01` 的 idcard 加密口径与 `check_info_all` (dwd_person_info 数据来源) 不一致, 直接拿 a.idcard / b.idcard 各 1000 条到 dwd_person_info 都是 0 命中。view_yyqkb 段的 BZ_SFZHM 空率仅 2%, 不是主要因素。

**附带验证**: 2024 段 a.idcard ≡ b.idcard (visitor_id 维度上完全相同), 业务"idcard 取 b 表"的规则在数据层面无差异, 但仍按业务约定保留。

**待业务/数据治理处理**: 统一 2024 ODS 表的加密 key, 或把 check_info_new_2024_Encry 并入 check_info_all 后重灌 dwd_person_info。

#### 2026-06-24 2024 段切换到 b.idcard1 / b.mobile1 (业务脱敏口径)

**业务澄清**: `check_info_new_2024_Encry01` (b 表) 里 `idcard / mobile / cust_name` 是早期错误口径, `idcard1 / mobile1 / cust_name1` 才是与 `dwd_person_info` 加密一致的正确脱敏字段。

**改动**: `4.ETL脚本/dwd_fact_checkin_from_ods.sql` 第 2 段 (2024)
- `b.idcard` → `b.idcard1`
- `b.mobile` → `b.mobile1`
- 注释里同步说明 b.idcard / b.mobile 是另一套 key, 不要用

**验证**: 清表重灌 4 段 LIMIT 1000 后:
- Q5 person_id 对账: 4000/4000 全部命中 dwd_person_info, 孤儿 0 行
- 直接抽 b.idcard1 1000 条到 dwd_person_info 反查: 1000/1000 命中
- 其他 10 项质控全部维持原状, 无回归

之前判定"check_info_all 加密 key 与 2024 不一致"是错的, 实际是 ETL 用错了 b 表字段。

#### 2026-06-24 dwd_fact_checkin 6 个枚举字段映射实装

**业务对照**（基于 mnyjy_peis_check_info 字段说明）：

| DWD 字段 | 源字段 | 映射规则 |
|---|---|---|
| health_check_code | health_check_type | Y→01入职, N→02年度, X→03优先, W→04外检, F→05妇检, Z→06职业病, Q→07_3650卡, C→08_CT卡, U→09下午, H→10核磁, S→11个检, B→12上午单卡, T→13云检, 其他/空→99 |
| member_code | member_type | VIP→01, 空/'00'/'普通'→02, 其他→99 |
| external_inspection_code | need_partner | Y→01是, N→02否, 其他/空→99 |
| report_query_code | report_search_type | 0→01全部, 1→02仅单位, 2→03仅个人, 3→04全禁用, 其他/空→99 |
| report_collection_code | report_send_type | 1→01送达单位, 2→02自取, 3→03邮寄, 4→04网络查询, 5→05给业务员, 6→06个人, 7→01(给单位到付并入送达单位), 其他/空→99 |
| personnel_unit_code | corp_code (view_yyqkb 段取 DWDM) | 原值 SUBSTR(1,100) |

view_yyqkb 段无 health_check_type / need_partner / report_search_type / report_send_type 字段, 一律落到 99 (符合 dim_字典 99 兜底)。

**配套 DDL 调整**:
- `external_inspection_code`: VARCHAR(1) → VARCHAR(2), 对齐 dim_external_inspection 字典 01/02/99
- 同步更新 `2.DDL脚本/MIHDB_DWD.sql` 与 `3.代码生成器/gen_ddl.py`

**验证结果** (4000 行 LIMIT 1000 样本):
- 8 项枚举字段成功打散到 dim 字典各码值, 不再清一色 99
- health_check_code: 02年度占 51%, 99占 30%, 11个检/04外检/01入职等真实分布
- external_inspection_code 在前 3 段正常分布 01/02, view_yyqkb 1000 行因源端无字段全 99
- person_id 与 dwd_person_info 命中率 100%; 其他 10 项质控全部通过, 无回归

## 2026-06-24 dwd_fact_checkin 建查询索引

**背景**: 全量灌完 2.11 亿行后, 业务侧常用查询围绕"体检流水号 / 人员唯一标识 / 预约时间 / 体检日期 / 出报告日期"五个字段。

**索引方案**:
- `checkin_id` (体检流水号): 已是 UNIQUE KEY 主键, 自带前缀索引, 不重复建
- 其余 5 个字段全部用 Doris INVERTED index:
  - `idx_person_id`    person_id    人员唯一标识
  - `idx_book_optime`  book_optime  预约时间
  - `idx_checkin_date` checkin_date 体检日期
  - `idx_report_date`  report_date  出报告日期
  - `idx_checkin_branch_code` checkin_branch_code 到检分院编码 (2026-06-24 补建)

**脚本**: `4.ETL脚本/dwd_fact_checkin_create_indexes.sql`

**执行**: 
- ALTER + ADD INDEX 元数据秒级完成, 4 个 schema-change job 全 `FINISHED`
- `BUILD INDEX` 在 06:34:43 触发, 进度通过 `SHOW BUILD INDEX WHERE TableName='dwd_fact_checkin'` 观察 (Progress n/64), 后台对存量 64 个 tablet 异步构建
- 新写入数据立即用上索引, 无需等存量构建完

**查看进度命令**:
```sql
USE MIHDB_DWD;
SHOW INDEX FROM dwd_fact_checkin;
SHOW BUILD INDEX WHERE TableName='dwd_fact_checkin';
```

## 2026-06-24 · dwd_fact_lab v2 DDL 草案
- 落地 `2.DDL脚本/dwd_fact_lab_v2.sql`，目标解决"原始词 vs 标准词"双轨缺失、定量/定性混存、参考范围非结构化、单位未归一、字典版本不可追溯等 v1 痛点。
- 关键变更：
  - 主键改为 `MD5(checkin_id + src_item_code + lab_date + sub_order)`，字典演进不影响下游。
  - 拆 `src_*` (8 列) / `std_*` (6 列) 双轨；新增 `mapping_confidence` / `mapping_version` 治理列。
  - 结果分列：`result_value` 原文 + `result_value_num` 定量 + `result_value_std` 归一可比 + `unit_convert_factor` + `result_value_flag` 定性 + `result_category` 分类。
  - 参考范围结构化：`ref_low` / `ref_high` / `ref_op` / `ref_text`。
  - 治理：`positive_level` 扩 `VARCHAR(2)` 默认 `99`，新增 `lab_machine` / `src_update_time` / `audit_time`。
  - 索引按 `dwd_fact_checkin` 索引组合裁剪：checkin/person/lab_date/std_lab_item_code/src_item_code/report_month/positive_level 倒排。
- 配套维表待出 DDL：`dim_lab_item` (SCD2)、`dim_lab_item_mapping` (版本化)、`dim_positive_level` (补 99=未知)。
- 落地次序建议：先 v2 空表 + 双跑校验 → 维表补齐 → 切流量 → 下线 v1。


### 2026-06-29 ODS 结果表加自增 id 迁移记录

目标：
- `MIHDB_ODS.result_new2024_Encry01` 按 2024 结果表方案重建为带 `AUTO_INCREMENT id` 的新表，并完成 1-4 月缺口补数。
- 为 2023 结果表 `MIHDB_ODS.mnyjy_peis_result` 生成同方案 SQL 文件，由人工执行。

2024 执行结果：
- 新表：`MIHDB_ODS.result_new2024_Encry01_new`
- 已补齐月份：2024-01、2024-02、2024-03、2024-04
- 逐月源表/新表差异：12 个月全部为 0
- 源表总量：2,710,669,639
- 新表总量：2,710,669,639
- `id` 校验：COUNT(*) = COUNT(id) = 2,710,669,639，NULL id = 0，MIN(id)=8,471,278,960，MAX(id)=13,892,922,977

2024 注意事项：
- Doris 换表语法不是 `RENAME TO`，正确写法：

```sql
ALTER TABLE MIHDB_ODS.result_new2024_Encry01 RENAME result_new2024_Encry01_bak;
ALTER TABLE MIHDB_ODS.result_new2024_Encry01_new RENAME result_new2024_Encry01;
```

2023 交付文件：
- `2.DDL脚本/mnyjy_peis_result_add_id_migration.sql`

2023 SQL 方案：
- 新建 `MIHDB_ODS.mnyjy_peis_result_new`
- 第一列新增 `id bigint NOT NULL AUTO_INCREMENT(1)`
- `DUPLICATE KEY` 改为 `id`
- 保留原表 2023 月分区、倒排索引、分桶、属性
- `INSERT INTO ... SELECT ...` 显式排除 `id`，由 Doris 自动生成
- 迁移按 2023-01 到 2023-12 逐月执行
- 文件末尾包含月度对账、总量对账、id 空值/范围校验，以及注释状态的换表 SQL

遗留问题：
- 2023 SQL 尚未执行。
- 2023 执行前如已存在 `mnyjy_peis_result_new`，需要先确认是否为空或是否已有部分月份数据，避免重复插入。
- 备份表不自动删除，需业务验证后再决定。


### 2026-06-29 ODS 两张历史检验结果表加自增 id 迁移 SQL

目标：
- 为 `MIHDB_ODS.jj_comm_jc_result_all_Encry` 生成加 `AUTO_INCREMENT id` 的重建迁移 SQL。
- 为 `MIHDB_ODS.lis_test_result_all_Encry` 生成加 `AUTO_INCREMENT id` 的重建迁移 SQL。

交付文件：
- `2.DDL脚本/jj_comm_jc_result_all_Encry_add_id_migration.sql`
- `2.DDL脚本/lis_test_result_all_Encry_add_id_migration.sql`
- `3.代码生成器/gen_add_id_migration_sql.js`

方案要点：
- 从附件里的原始 Doris DDL 自动生成 `_new` 表 DDL。
- 第一列新增 `id bigint NOT NULL AUTO_INCREMENT(1)`。
- `DUPLICATE KEY` 改为 `DUPLICATE KEY(id)`。
- 保留原表 `part_month` 月分区、动态分区、分桶、属性。
- INSERT 显式排除 `id`，由 Doris 自动生成。
- 按 `part_month` 的 124 个分区逐月生成 INSERT，便于断点恢复和校验。
- 文件末尾包含月度差异、总量、id 空值/范围校验，以及注释状态的 Doris 正确换表 SQL。

验证结果：
- 两个 SQL 文件均包含 `AUTO_INCREMENT`、`DUPLICATE KEY(id)`、124 条 INSERT、校验 SQL、注释换表 SQL。
- 未生成 `.sh` 迁移脚本。


### 2026-07-01 dwd_fact_lab 表结构补全 (24→25 字段)

目标：
- 根据业务需求补齐 `dwd_fact_lab` 缺少的字段，从 v1 的 17 字段升级到 v2 的 25 字段。

交付文件：
- `2.DDL脚本/dwd_fact_lab_v2.sql` (66行)

新增字段（共 8 个）：
- `lab_type_name` VARCHAR(200) — 检项名称
- `lab_item_name` VARCHAR(200) — 细项名称
- `short_name` VARCHAR(100) — 细项简称（2026-07-01 追加）
- `ref_low` VARCHAR(50) — 参考下界（VARCHAR 非 DECIMAL，因源数据含非数值如 `>5.0`、`阴性`）
- `ref_high` VARCHAR(50) — 参考上界
- `result_flag` VARCHAR(20) — 阳性标识
- `abnormal_name` VARCHAR(200) — 异常描述
- `table_source` VARCHAR(50) — 数据来源

关键修正：
- `positive_level` 从 TINYINT 改为 VARCHAR(2) DEFAULT '99'，字典码 01/02/03/04/99 不应丢前导零。

倒排索引（6 个）：
- `idx_checkin_id`、`idx_person_id`、`idx_lab_date`、`idx_report_month`、`idx_positive_level`、`idx_lab_item_code`

Git 提交：
- `9d7b205` dwd_fact_lab: 补全24字段DDL
- `44d8731` dwd_fact_lab: 新增 short_name 细项简称字段, 25字段版

经验教训：
- `positive_level` 是字典码，永远是 VARCHAR，不能用 TINYINT。
- `ref_low`/`ref_high` 源数据含非数值，DWD 层保留 VARCHAR，数值转换放到 DWS/ADS。
- apply_patch 在此环境多次失败，用 heredoc (`cat > file <<'EOF'`) 替代。


### 2026-07-01 dwd_fact_lab 表结构深度优化 (分区 + 索引精简)

依据表结构评估意见，完成三项核心优化：

**P0 新增分区**：
- 新增 `PARTITION BY RANGE(report_month)()` 按月范围分区
- 开启动态分区: 保留 36 个月历史 + 预创建 3 个月未来分区
- 收益: 按月查询直接分区裁剪，性能提升 1~2 个数量级

**P1 索引精简 (13→4 核心 + 2 全文)**：
- 保留: `idx_person_id`, `idx_checkin_id`, `idx_lab_item_code`, `idx_lab_date`
- 删除: `idx_report_month`(改分区), `idx_lab_type_name/idx_lab_item_name/idx_short_name`(冗余), `idx_result_value`(高基数长字符串), `idx_result_flag`(极低基数), `idx_positive_level`(5个取值)
- `idx_abnormal_name`/`idx_diagnosis_conclusion` 从普通倒排改为 `PARSER unicode` 全文索引

**P3 细节修正**：
- `is_valid` DEFAULT `'1'` → `1`, 类型统一

Git 提交：
- `21b56bb` (上一版 13 索引)
- 本次提交将覆盖为优化版


### 2026-07-01 dwd_fact_lab 建表报错修复 (COMMENT顺序 + 分区列类型)

报错：
- `errCode = 2, mismatched input 'COMMENT' expecting {<EOF>, ';'}(line 30)`

根因 (两层)：
1. 子句顺序错误: 上一版为 `UNIQUE KEY -> PARTITION BY -> COMMENT`,
   Doris 要求 COMMENT(表注释) 必须在 PARTITION BY 之前。
2. 隐藏坑: `PARTITION BY RANGE` 分区列不能是 VARCHAR(7), 必须 DATE/DATETIME;
   且普通 dynamic_partition 不会为 2017-2025 历史数据自动建分区, 回填会失败。

修复方案：
- 参考已验证的 dwd_fact_lab_v3.sql (分区列用 DATE)。
- 改用 lab_date(DATE) 做 `AUTO PARTITION BY RANGE(date_trunc(lab_date,'month'))()`,
  按数据自动建月分区, 永不过期, 历史回填不缺分区。
- lab_date 提到第 2 列, UNIQUE KEY = (lab_result_id, lab_date) (Unique 模型
  分区列必须是 key 列, key 列必须前置)。
- report_month 保留为 VARCHAR(7) 普通列 + idx_report_month 倒排索引, 供分月统计。
- 正确子句顺序: UNIQUE KEY -> COMMENT -> AUTO PARTITION -> DISTRIBUTED -> PROPERTIES。

经验教训 (记入坑位)：
- Doris CREATE TABLE 子句顺序固定: 列定义 -> ENGINE -> UNIQUE/DUP KEY ->
  COMMENT -> PARTITION -> DISTRIBUTED -> PROPERTIES。COMMENT 放错位置即报
  mismatched input 'COMMENT'。
- RANGE/动态分区列必须 DATE/DATETIME, 不能 VARCHAR。
- 需导入任意历史区间数据时用 AUTO PARTITION, 而非 dynamic_partition(后者只建
  当前时间附近的未来分区)。

未验证项：
- 本地无法连内网 Doris(192.168.77.38:9030 超时), 未当场执行建表;
  语法顺序与分区列类型已对齐 v3 已验证约定。

实测验证 (2026-07-01)：
- 连接路径: SSH 隧道 mnyjy@127.0.0.1:3911 -> 内网 Doris
  192.168.77.38:9030 (root, --skip-password, DB=MIHDB_DWD)。
- scp/ssh 需强制密码认证: -o PreferredAuthentications=password
  -o PubkeyAuthentication=no (默认走 publickey 会被拒)。
- 执行 dwd_fact_lab_v2.sql: EXIT_CODE=0, 建表零报错。
- SHOW CREATE TABLE 确认: 25 字段齐全, AUTO PARTITION BY
  RANGE(date_trunc(lab_date,'month')) 生效, UNIQUE KEY(lab_result_id,
  lab_date), 6 个倒排索引全部挂上; 两个全文索引 Doris 自动补齐
  lower_case/support_phrase 属性。
- 结论: mismatched input 'COMMENT' 报错已彻底解决并线上验证通过。


### 2026-07-01 重建 dim_lab_item 并导入标化字典 (源自 表结构设计V1.2)

目标：
- 依据《DWD_体检数据仓库表结构设计_V1.2》sheet「维度表_检验项目」重建
  MIHDB_DWD.dim_lab_item, 并导入 Excel 全量数据。

交付文件：
- `2.DDL脚本/dim_lab_item.sql` (建表, 14 字段 + 3 倒排索引)
- `4.ETL脚本/dim_lab_item_data.sql` (数据导入, 40 批 INSERT)
- 同步更新 `2.DDL脚本/MIHDB_DWD.sql` 内旧的 dim_lab_item 定义

结构变更 (旧 7 字段 -> 新 14 字段)：
- 旧表是「类别/类型」结构; 新文档是「原始词→标化词」映射字典。
- Excel 12 列: raw_item_name / raw_item_detail_name / raw_specimen_name /
  lab_level1_category / lab_level2_category / standard_name /
  item_detail_code / lab_level1_code / lab_level2_code /
  related_diseases / related_disease_systems / is_effective。
- 主键: item_detail_code 是标化编码(877 唯一值, 一码多写法), 不能做主键;
  改用 mapping_id = MD5(原始大项|原始细项|原始标本)。

数据处理：
- Excel 19860 数据行, 按原始三元组去重掉 2 行完全重复(HPV 小结), 得 19858 行。
- is_effective 全为 0(有效); raw_item_name 无空值。
- 引号转义: 5'-核苷酸酶 -> 5\'-核苷酸酶; 空串/None 一律写 NULL。

线上验证 (SSH 隧道 -> 192.168.77.38:9030, DDL_EXIT=0, DATA_EXIT=0)：
- COUNT(*) = 19858, DISTINCT mapping_id = 19858 (主键无冲突)。
- DISTINCT item_detail_code = 877 (与分析一致)。
- is_effective 全 0; raw_item_name null=0; 抽样映射正确。

经验教训：
- 大批量 INSERT 用 Python 生成分批(500/批)文件, 避免超长单条与引号转义坑。
- INSERT 前 SET enable_insert_strict=false, 容忍个别宽松值。
