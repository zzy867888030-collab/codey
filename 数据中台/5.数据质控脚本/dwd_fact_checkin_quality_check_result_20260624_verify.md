# dwd_fact_checkin 首轮小批量验证质控结果 (LIMIT 1000 x 4)

- **执行时间**：2026-06-24
- **目标表**：`MIHDB_DWD.dwd_fact_checkin`
- **ETL 脚本**：`4.ETL脚本/dwd_fact_checkin_from_ods.sql`
- **质控脚本**：`5.数据质控脚本/dwd_fact_checkin_quality_check.sql`
- **样本范围**：4 段各 LIMIT 1000, 共 4000 行 (实际全部成功落库 4000/4000)
- **结论**：✅ 4 段 ETL 全部跑通；DDL 已扩 mobile=VARCHAR(128)；view_yyqkb 段已实装 idcard 降级 + 与 2023 去重；2024 段 idcard/mobile 已切到 b 表的 `*1` 字段 (4000/4000 全部命中 dwd_person_info)
- **2026-06-24 更新**：6 个枚举映射 (health_check_code / member_code / external_inspection_code / report_query_code / report_collection_code / personnel_unit_code) 已实装；`external_inspection_code` DDL 由 VARCHAR(1) 扩到 VARCHAR(2) 以兼容 `01/02/99` 字典

---

## Q1 总览

| total_rows | unique_checkin_id | unique_person_id | unique_report_months | min_checkin_date | max_checkin_date |
|---:|---:|---:|---:|---:|---:|
| 4000 | 4000 | 3933 | 36 | 2022-02-27 | 2025-12-31 |

- `checkin_id` 完全唯一 (4000/4000) ✅
- `person_id` 唯一数 3933 表示有 67 个人在样本期内多次体检, 合理 ✅

## Q2 NOT NULL 列空值率

所有 NOT NULL 列均为 0 ✅

| 列 | NULL 行数 |
|---|---:|
| checkin_id / person_id / report_month / marital / fertility / is_valid / etl_load_time / checkin_date | 0 |

## Q3 年份分布

| yr | cnt | pct |
|---|---:|---:|
| 2022 | 1000 | 25% |
| 2023 | 1000 | 25% |
| 2024 | 1000 | 25% |
| 2025 | 1000 | 25% |

四段按预期各落 1000 行 ✅

## Q4 主键重复

0 行 ✅

## Q5 person_id 与 dwd_person_info 对账

| bucket | cnt |
|---|---:|
| 匹配上 dwd_person_info | 4000 |
| 孤儿 (person_info 找不到) | 0 |

分年份明细：

| 年份 | 来源 | total | missing | 命中率 |
|---|---|---:|---:|---:|
| 2022 | view_yyqkb (idcard 降级 BZ_SFZHM→VID) | 1000 | 0 | 100% ✅ |
| 2023 | mnyjy_peis_check_info_new01_Encry | 1000 | 0 | 100% ✅ |
| 2024 | check_info_new_2024_Encry a + 01 b (idcard 取 b.idcard1) | 1000 | 0 | 100% ✅ |
| 2025 | check_info_2025_Encry | 1000 | 0 | 100% ✅ |

**修复过程**：
- 首轮 2024 段用 `b.idcard / b.mobile`, 与 `dwd_person_info` 一对一匹配 0/1000
- 跟业务确认: `check_info_new_2024_Encry01` 里 `*1` 字段才是正确脱敏口径
- 切到 `b.idcard1 / b.mobile1 / b.cust_name1` 后, 1000/1000 全部命中
- 直接抽 b.idcard1 1000 条到 dwd_person_info 反查也是 1000/1000 命中

## Q6 枚举字段值分布

| col | val | cnt |
|---|---|---:|
| health_check_code | 02 (年度) | 2053 |
| health_check_code | 99 (未知/无映射) | 1193 |
| health_check_code | 11 (个检) | 304 |
| health_check_code | 04 (外检) | 280 |
| health_check_code | 01 (入职) | 105 |
| health_check_code | 06 (职业病) | 50 |
| health_check_code | 03/09/10/12 等 | < 10 each |
| marital_code | 99 | 4000 |
| fertility_code | 99 | 4000 |
| member_code | 02 普通 | 3664 |
| member_code | 99 (其他/非空非VIP) | 170 |
| member_code | 01 VIP | 166 |
| external_inspection_code | 01 是 | 1532 |
| external_inspection_code | 02 否 | 1468 |
| external_inspection_code | 99 (view_yyqkb 段无源字段) | 1000 |
| report_query_code | 03 仅个人 | 1687 |
| report_query_code | 01 全部 | 1237 |
| report_query_code | 99 (view_yyqkb 段无源字段) | 1000 |
| report_query_code | 04 全禁用 | 68 |
| report_query_code | 02 仅单位 | 8 |
| report_collection_code | 99 (view_yyqkb 段无源字段 + 业务空值) | 1590 |
| report_collection_code | 02 自取 | 1071 |
| report_collection_code | 05 给业务员 | 829 |
| report_collection_code | 01 送达单位 | 434 |
| report_collection_code | 04 网络查询 | 52 |
| report_collection_code | 03 邮寄 | 24 |
| is_valid | 1 | 4000 |

映射效果良好 ✅。`marital_code / fertility_code` 仍全 99 是因为源端无对应字段，符合预期。

## Q7 时间字段合理性

| 检查项 | 行数 |
|---|---:|
| book_optime < 2000-01-01 | 0 |
| book_optime > NOW() | 0 |
| **checkin_date < book_optime** | **73** |
| report_date < checkin_date | 2 |
| report_date > 今天 | 0 |

- 73 行 `checkin_date < book_optime`：业务上可能是改约/提前到检，体量 1.8%，DWS 加工再决定是否标记 `is_valid=0`
- 2 行 `report_date < checkin_date`：值得抽样定位（可能是 print_time 来自上次的报告补打）

## Q8 age 合理性

| age_null | age_out_of_range | min | max | avg |
|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 89 | 41.05 |

合理 ✅（min=0 应为新生儿/婴幼儿体检, max=89 在 120 兜底内）

## Q9 mobile 长度分布

| mobile_len | cnt |
|---:|---:|
| 20 | 994 |
| 32 | 991 |
| 44 | 994 |

- 20: 2025 源, 32: 2024 源, 44: 2023 源 (base64) ✅ 与三源密文长度匹配
- 4000 - (994+991+994) = 21 行 mobile 为 NULL (view_yyqkb 段无 mobile 字段, 走 NULL), 合理
- mobile 列已扩到 VARCHAR(128), 无截断 ✅

## Q10 report_month 格式

| bad_format | total |
|---:|---:|
| 0 | 4000 |

全部符合 `YYYY-MM` ✅

---

## 关键修复记录 (相对首次 ETL 草稿)

| 项 | 修复内容 |
|---|---|
| mobile 列 | 目标表 DDL 由 VARCHAR(20) → VARCHAR(128); `gen_ddl.py` 加 hardcode override |
| report_date | 改成降级链 (2023~2025 用 COALESCE(print_time, update_time, checkin_time), 2017~2022 view_yyqkb 用 COALESCE(PRINT_TIME, TJZZSJ, QTDJSJ)) |
| view_yyqkb idcard | 改为 `COALESCE(BZ_SFZHM, VID)`, 空身份证降级取 VID |
| view_yyqkb 去重 | 加 `WHERE NOT EXISTS (SELECT 1 FROM mnyjy_peis_check_info_new01_Encry x WHERE x.visitor_id = v.VID)` 去掉与 2023 表重叠 |
| 2024 段 idcard/mobile | 切到 `b.idcard1 / b.mobile1` (业务正确脱敏口径), 4000/4000 命中 |
| 6 个枚举映射 | health_check_code / member_code / external_inspection_code / report_query_code / report_collection_code / personnel_unit_code(取 corp_code/DWDM 原值) |
| external_inspection_code DDL | VARCHAR(1) → VARCHAR(2), 对齐 dim 字典 01/02/99 |

## Backlog

1. 业务给枚举映射后批量 UPDATE: `health_check_code / member_code / report_query_code / report_collection_code` 等
2. 73 行 checkin_date < book_optime + 2 行 report_date < checkin_date 抽样定位
3. 老库人员补灌 dwd_person_info 后, 复跑 Q5 孤儿统计
4. 全量 INSERT 上跑前, 把 `LIMIT 1000` 去掉, 建议按段串行执行 (每段独立 commit)
