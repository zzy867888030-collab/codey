# DolphinScheduler 任务部署说明 — dwd_fact_checkin

## 现状（2026-06-24 完成）

- 已在 DS 资源目录 `/opt/dolphinscheduler/resources/default/resources/dwd-etl/` 部署：
  - `dwd_fact_checkin_from_ods.sql`：4 段 ETL SQL
  - `run_dwd_fact_checkin.sh`：Shell wrapper（按段执行 + 自动质控输出）
- 已在跳板机手动跑通一次 `--truncate` 全量模式：2.11 亿行，5 分钟
- 命中率详细见 `5.数据质控脚本/dwd_fact_checkin_quality_check_result_20260624_fullload.md`

## DS 网页建任务步骤（手工操作）

登录 DS 控制台（http://192.168.77.xx:12345，账号 admin/admin@123），按以下步骤建任务：

1. **进入项目** → 工作流定义 → 创建工作流（或选已有 DWD 工作流）
2. **拖入 Shell 任务节点**，配置：
   - 节点名称：`dwd_fact_checkin_etl`
   - 描述：`从 ODS 抽取并清洗到 dwd_fact_checkin`
   - 任务优先级：MEDIUM
   - Worker 分组：default
   - 失败重试次数：1
3. **资源** 区域：勾选 `dwd-etl/run_dwd_fact_checkin.sh` 和 `dwd-etl/dwd_fact_checkin_from_ods.sql`
4. **脚本** 内容（直接调用即可）：
   ```bash
   bash /opt/dolphinscheduler/resources/default/resources/dwd-etl/run_dwd_fact_checkin.sh --truncate
   ```
   - 全量（清表重灌）：带 `--truncate`
   - 增量重跑（依赖 Unique Key + MoW 自动覆盖）：去掉 `--truncate`
5. **保存** → 上线
6. **手动触发** 一次，确认日志里 4 段都 `[OK]` + 总行数 ≈ 2.11 亿
7. （可选）**设定调度**：每天/每周触发一次，建议 ≥ 5 分钟空闲时段

## 任务输出关键日志（参考）

```
===============================================
DWD ETL: dwd_fact_checkin
start_time: 2026-06-24 05:32:05
TRUNCATE  : true
===============================================
[STEP 0] TRUNCATE dwd_fact_checkin ...
----- 第 1 段 INSERT -----
[OK] 第 1 段耗时 54 秒, 当前 dwd_fact_checkin 行数: 23436128
----- 第 2 段 INSERT -----
[OK] 第 2 段耗时 42 秒, 当前 dwd_fact_checkin 行数: 47693951
----- 第 3 段 INSERT -----
[OK] 第 3 段耗时 35 秒, 当前 dwd_fact_checkin 行数: 72226404
----- 第 4 段 INSERT -----
[OK] 第 4 段耗时 182 秒, 当前 dwd_fact_checkin 行数: 211510453
```

## 为什么没有用 DS API 直接建任务

`/Users/zoyoe/codex/dolphinscheduler/DEVELOPMENT_LOG.md`（2026-06-08）记录：
- DS 5.x 后 API 登录返回的 sessionId 通过 Header 或 Cookie 都返回 401
- 同事确认"建议在网页上建任务"

本仓库的脚本和资源已完全准备好，DS 任务节点直接拷上面 5 步即可。

## 后续如果要拆段并行（不推荐）

- 当前 5 分钟即可跑完，串行没必要拆
- 若以后某段（如 view_yyqkb 182 秒）需要单独优化，可把 wrapper 复制 4 份，每份只跑一段，DS 用并行 DAG
