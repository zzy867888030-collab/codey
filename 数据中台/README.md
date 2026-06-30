# 美年健康数据中台 - DWD 层

## 目录结构

```
数据中台/
├── README.md                                         # 本文件
├── 《DWD_体检数据仓库表结构设计_V1.2》.xlsx           # 设计源文档（事实表 + 维度表）
├── 《DWS_体检数据仓库表结构设计_V2.3》.xlsx           # DWS 设计源文档（下阶段）
├── 1.开发记录/
│   └── DEVELOPMENT_LOG.md                            # 历次开发与排障记录
├── 2.DDL脚本/
│   ├── MIHDB_DWD.sql                                 # MIHDB_DWD 完整建表脚本（26 张表）
│   └── MIHDB_DWD_dim_data.sql                        # 17 张维度表字典数据 INSERT（782 行）
└── 3.代码生成器/
    ├── gen_ddl.py                                    # 从 Excel 生成 DDL
    └── gen_dim_inserts.py                            # 从 Excel 生成维度数据 INSERT
├── 4.ETL脚本/
│   ├── dwd_person_info_from_check_info_all.sql       # dwd_person_info 全量抽取脚本
│   └── dwd_fact_checkin_from_ods.sql                 # dwd_fact_checkin 4 段合并 ETL (2017~2025)
└── 5.数据质控脚本/
    └── dwd_person_info_quality_check.sql             # dwd_person_info 8大质控点脚本
```

## 当前进度（截至 2026-06-22）

### 已完成
- Doris `MIHDB_DWD` 库已建好
- 8 张事实表 + 18 张维度表（共 26 张）已建表，副本数=2，Unique Key + MoW + ZSTD
- 17 张维度字典表已灌入数据，共 782 行（dim_date 是日期生成表，无需 Excel 数据）
- 事实表 `dwd_person_info`（人员主表）已灌入 1.0954 亿行，首轮质控通过率 99.99%

### 表清单
**事实表（8）**：dwd_person_info / dwd_fact_checkin / dwd_fact_lab / dwd_fact_exam / dwd_fact_questionnaire / dwd_fact_followup / dwd_calc_indicator / dwd_calc_label

**维度表（18）**：dim_date / dim_sex / dim_marital / dim_fertility / dim_nation / dim_age / dim_institution / dim_health_check_type / dim_personnel_unit / dim_external_inspection / dim_member / dim_report_query / dim_report_collection / dim_lab_item / dim_specimen_item / dim_exam_item / dim_positive_level / dim_visit_status

## Doris 环境

- Host: `192.168.77.38`
- HTTP Port: `8030`
- MySQL Port: `9030`
- Database: `MIHDB_DWD`

## DolphinScheduler 跳板

```bash
sshpass -p 'mnjk2026' ssh -p 3911 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null mnyjy@127.0.0.1
```
- sudo 密码：`mnjk2026`
- DS 路径：`/opt/dolphinscheduler`

## 重新生成 + 部署流程

```bash
# 本地生成（macOS）
python3 3.代码生成器/gen_ddl.py
python3 3.代码生成器/gen_dim_inserts.py

# 上传 + 执行
B64DDL=$(base64 < 2.DDL脚本/MIHDB_DWD.sql | tr -d '\n')
B64INS=$(base64 < 2.DDL脚本/MIHDB_DWD_dim_data.sql | tr -d '\n')
sshpass -p 'mnjk2026' ssh -p 3911 mnyjy@127.0.0.1 "
  echo '$B64DDL' | base64 -d > /tmp/MIHDB_DWD.sql
  echo '$B64INS' | base64 -d > /tmp/MIHDB_DWD_dim_data.sql
  mysql -h 192.168.77.38 -P 9030 -u root --skip-password --force --database MIHDB_DWD < /tmp/MIHDB_DWD.sql
  mysql -h 192.168.77.38 -P 9030 -u root --skip-password --force --database MIHDB_DWD < /tmp/MIHDB_DWD_dim_data.sql
"
```

## 注意事项（踩过的坑）

1. **Doris 不支持 NVARCHAR**：generator 已映射为 `VARCHAR(n*3)`（UTF-8 安全）。
2. **scp 在该环境会 Permission denied**：用 `ssh + base64` 灌入 `/tmp/`。
3. **层级字典表 PK 必须用叶子节点**：`dim_lab_item` 等三张表 PK = `xxx_item_code`，否则 Unique Key 会合并掉所有非叶子行。已在 generator 里 hardcode override。
4. **Excel sheet `维度表_检验项目` 第 3 行有 typo**（`lab_category_namegory` / `lab_type_namee`），generator 会自动跳到第 4 行取正确列名。

## 下一步开发

- DWS 层建表（参考 `《DWS_体检数据仓库表结构设计_V2.3》.xlsx`）
- DWD 各事实表的 ETL Job（从 ODS 加工到 DWD）
- `dim_date` 数据生成（用 SQL 或 DataX 灌入日期范围）
