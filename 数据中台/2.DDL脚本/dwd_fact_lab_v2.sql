-- =============================================================
-- 文件: dwd_fact_lab_v2.sql
-- 用途: dwd_fact_lab 升级草案 (v2)
--       目标: 落地 "原始词 / 标准词" 双轨建模, 拆分定量/定性结果,
--             结构化参考范围, 显式单位归一与字典版本控制.
--
-- 设计原则:
--   1. DWD = 贴源 + 一致化. 原始字段 src_* 不可变, 标准化字段
--      std_* 跟字典走; 字典升级只重算 std_* 列, 不动 src_*.
--   2. 主键不绑定会演进的标准码, 改用
--        MD5(checkin_id + src_item_code + lab_date + sub_order)
--      字典升级时下游链路不断, 复检/复核用 sub_order 区分.
--   3. 定量/定性/性状结果分列, OLAP 端直接做范围筛选与聚合,
--      不再逐行 CAST(result_value AS DECIMAL).
--   4. 单位归一冗余 result_value_std, 一列拿到 "可比数值",
--      跨实验室/跨年度趋势分析免反复 join 字典.
--   5. 治理审计 (mapping_confidence / mapping_version /
--      src_update_time / audit_time) 为字典治理与质控留口子.
--
-- 配套维表 (另文件出 DDL):
--   dim_lab_item            标准化项目字典 (建议 SCD2)
--   dim_lab_item_mapping    原始项目 -> 标准项目映射 (版本化治理)
--   dim_specimen            标准化样本字典 (已存在)
--   dim_positive_level      异常级别字典 (建议补 99=未知)
--
-- 作者: codex
-- 日期: 2026-06-24
-- =============================================================

USE `MIHDB_DWD`;

DROP TABLE IF EXISTS `MIHDB_DWD`.`dwd_fact_lab_v2`;
CREATE TABLE `MIHDB_DWD`.`dwd_fact_lab_v2` (
  -- ---------- 主键 / 关联键 ----------
  `lab_result_id`          VARCHAR(64)   NOT NULL COMMENT '检验结果主键 = MD5(checkin_id + src_item_code + lab_date + sub_order)',
  `checkin_id`             VARCHAR(64)   NOT NULL COMMENT '体检流水号, 外键 -> dwd_fact_checkin',
  `person_id`              VARCHAR(64)   NULL     COMMENT '人员唯一标识, 外键 -> dwd_person_info',
  `lab_date`               DATE          NOT NULL COMMENT '检验日期 YYYY-MM-DD',
  `sub_order`              VARCHAR(20)   NOT NULL DEFAULT '0' COMMENT '同一 (checkin_id, 项目, 日期) 下的子序号, 用于复检/复核',

  -- ---------- 来源 / 原始词 (src_*) ----------
  `src_system`             VARCHAR(20)   NOT NULL COMMENT '来源系统/年份分支: result_new_2025 / result_new_2024 / mnyjy_peis_result / view_jyjg 等',
  `src_item_code`          VARCHAR(100)  NULL     COMMENT '原始检验项目编码 (源端 item_detail_code)',
  `src_item_name`          VARCHAR(200)  NULL     COMMENT '原始检验项目名称 (源端 item_detail_name, 标准化核心输入)',
  `src_type_code`          VARCHAR(100)  NULL     COMMENT '原始检验类型编码 (源端 item_code)',
  `src_type_name`          VARCHAR(200)  NULL     COMMENT '原始检验类型名称 (源端 item_name)',
  `src_unit`               VARCHAR(50)   NULL     COMMENT '原始结果单位',
  `src_ref_text`           VARCHAR(200)  NULL     COMMENT '原始参考范围文本 (含 normal_l/normal_h 拼接)',
  `src_specimen_text`      VARCHAR(100)  NULL     COMMENT '原始样本字符串 (源端 samples_type)',

  -- ---------- 标准词 (std_*) ----------
  `std_category_code`      VARCHAR(20)   NULL     COMMENT '标准检验类别编码 (dim_lab_item.lab_category_code)',
  `std_type_code`          VARCHAR(20)   NULL     COMMENT '标准检验类型编码 (dim_lab_item.lab_type_code)',
  `std_lab_item_code`      VARCHAR(20)   NULL     COMMENT '标准检验项目编码 (dim_lab_item.lab_item_code), 未命中保持 NULL',
  `std_lab_item_name`      VARCHAR(200)  NULL     COMMENT '标准检验项目名称, 冗余落表减少 join',
  `std_specimen_code`      VARCHAR(20)   NULL     COMMENT '标准样本编码 (dim_specimen.specimen_type_code)',
  `std_unit`               VARCHAR(50)   NULL     COMMENT '标准结果单位 (dim_lab_item.std_unit)',

  -- ---------- 映射治理 ----------
  `mapping_confidence`     TINYINT       NULL     COMMENT '映射置信度: 1精确 / 2同义词 / 3人工确认 / 4模糊匹配 / 9未匹配',
  `mapping_version`        VARCHAR(20)   NULL     COMMENT '命中字典/映射版本号 (dim_lab_item_mapping.version)',

  -- ---------- 结果分列 ----------
  `result_value`           VARCHAR(500)  NULL     COMMENT '原始结果文本, 保留全部信息',
  `result_value_num`       DECIMAL(18,4) NULL     COMMENT '定量数值, 定性/性状为 NULL',
  `result_value_std`       DECIMAL(18,4) NULL     COMMENT '归一到 std_unit 后的可比数值 = result_value_num * unit_convert_factor',
  `unit_convert_factor`    DECIMAL(18,8) NULL     COMMENT '单位归一倍数, 无需换算为 1, 无法换算为 NULL',
  `result_value_flag`      VARCHAR(20)   NULL     COMMENT '定性归一码: POS/NEG/WEAK_POS/TRACE/PLUS1/PLUS2/PLUS3/PLUS4/UNKNOWN',
  `result_category`        VARCHAR(10)   NULL     COMMENT '结果类型: QUANT 定量 / QUAL 定性 / DESC 性状',

  -- ---------- 参考范围 (结构化) ----------
  `ref_low`                DECIMAL(18,4) NULL     COMMENT '参考下界, 解析失败为 NULL',
  `ref_high`               DECIMAL(18,4) NULL     COMMENT '参考上界, 解析失败为 NULL',
  `ref_op`                 VARCHAR(4)    NULL     COMMENT '参考操作符: BETWEEN/LT/LE/GT/GE/EQ/DESC',
  `ref_text`               VARCHAR(100)  NULL     COMMENT '原始参考范围文本副本, 兜底显示用',

  -- ---------- 异常 / 诊断 ----------
  `positive_level`         VARCHAR(2)    NOT NULL DEFAULT '99' COMMENT '异常级别: 01正常/02阳性/03重大阳性/04危急值/99未知, 关联 dim_positive_level',
  `diagnosis_conclusion`   VARCHAR(500)  NULL     COMMENT '诊断结论原文',
  `diagnosis_normalized`   VARCHAR(500)  NULL     COMMENT '诊断结论 NLP 归一占位, 一期可空',

  -- ---------- 样本 / 质控 ----------
  `samples_status`         VARCHAR(100)  NULL     COMMENT '样本性状原文 (溶血/脂血/黄疸/正常)',
  `lab_machine`            VARCHAR(50)   NULL     COMMENT '检验仪器号, 用于异常排查与质控',

  -- ---------- 时间线 ----------
  `src_update_time`        DATETIME      NULL     COMMENT '源端最后更新时间, 增量幂等对照基准',
  `audit_time`             DATETIME      NULL     COMMENT '审核/复核完成时间',

  -- ---------- ETL 控制 ----------
  `is_valid`               TINYINT       NOT NULL DEFAULT '1' COMMENT '数据有效标识 0无效/1有效',
  `report_month`           VARCHAR(7)    NOT NULL COMMENT '体检月份 YYYY-MM, 用于检索分月报告',
  `etl_load_time`          DATETIME      NOT NULL COMMENT 'ETL 加载时间戳'
) ENGINE=OLAP
UNIQUE KEY(`lab_result_id`)
COMMENT 'DWD层 · 实验室检验结果事实表 v2 (原始词/标准词双轨, 数值/定性分列)'
DISTRIBUTED BY HASH(`checkin_id`) BUCKETS 64
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);

-- =============================================================
-- 倒排索引 (与 dwd_fact_checkin 索引组合保持一致, 按查询模式裁剪)
-- =============================================================
ALTER TABLE `MIHDB_DWD`.`dwd_fact_lab_v2`
  ADD INDEX idx_checkin_id        (`checkin_id`)         USING INVERTED COMMENT '体检流水号倒排索引',
  ADD INDEX idx_person_id         (`person_id`)          USING INVERTED COMMENT '人员唯一标识倒排索引',
  ADD INDEX idx_lab_date          (`lab_date`)           USING INVERTED COMMENT '检验日期倒排索引',
  ADD INDEX idx_std_lab_item_code (`std_lab_item_code`)  USING INVERTED COMMENT '标准项目编码倒排索引, 标准词查询主力',
  ADD INDEX idx_src_item_code     (`src_item_code`)      USING INVERTED COMMENT '原始项目编码倒排索引, 用于映射回查',
  ADD INDEX idx_report_month      (`report_month`)       USING INVERTED COMMENT '月份倒排索引, 分月扫描',
  ADD INDEX idx_positive_level    (`positive_level`)     USING INVERTED COMMENT '异常级别倒排索引, 异常筛查';

-- =============================================================
-- 与 v1 字段对照 (评审用)
-- -------------------------------------------------------------
-- v1 lab_type_code        -> v2 src_type_code   + std_type_code
-- v1 lab_item_code        -> v2 src_item_code   + std_lab_item_code
-- v1 result_value         -> v2 result_value (原文)
--                              + result_value_num / result_value_std (数值)
--                              + result_value_flag                   (定性)
-- v1 unit                 -> v2 src_unit + std_unit + unit_convert_factor
-- v1 result_ref           -> v2 src_ref_text + ref_low/ref_high/ref_op/ref_text
-- v1 specimen_type_code   -> v2 src_specimen_text + std_specimen_code
-- v1 positive_level       -> v2 positive_level (扩 VARCHAR(2), 默认 99)
-- 新增: src_system / sub_order / mapping_confidence / mapping_version /
--       std_lab_item_name / diagnosis_normalized / lab_machine /
--       src_update_time / audit_time
-- =============================================================
