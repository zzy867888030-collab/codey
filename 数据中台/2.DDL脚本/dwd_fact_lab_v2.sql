-- =============================================================
-- 文件: dwd_fact_lab_v2.sql
-- 用途: DWD层 实验室检验结果事实表 (25 字段 · 自动分区版)
--       在 v1 基础上补齐 8 个字段, 修正 positive_level 类型,
--       按 lab_date 月度 AUTO PARTITION(保留全部历史, 自动建分区),
--       索引精简至 4 核心 + 2 全文检索
-- 说明:
--   1. 子句顺序必须为: UNIQUE KEY -> AUTO PARTITION -> DISTRIBUTED
--      -> PROPERTIES; COMMENT 表注释放到 PROPERTIES 之前会报
--      mismatched input 'COMMENT', 故本版将表注释下沉。
--   2. Unique 模型分区/分桶列必须是 key 列, key 列必须是表前置列;
--      故 lab_date 提到第 2 列, UNIQUE KEY = (lab_result_id, lab_date)。
--   3. RANGE/动态分区不接受 VARCHAR 且不自动建历史分区; 改用
--      AUTO PARTITION BY RANGE(date_trunc(lab_date,'month')),
--      导入 2017-2025 历史数据时按数据自动建月分区, 永不过期。
-- 日期: 2026-07-01
-- =============================================================

DROP TABLE IF EXISTS `MIHDB_DWD`.`dwd_fact_lab`;
CREATE TABLE `MIHDB_DWD`.`dwd_fact_lab` (
  `lab_result_id`        VARCHAR(64)   NOT NULL COMMENT '检验结果主键',
  `lab_date`             DATE          NOT NULL COMMENT '检验日期(分区列)',
  `checkin_id`           VARCHAR(64)   NOT NULL COMMENT '体检流水号',
  `person_id`            VARCHAR(64)   NULL     COMMENT '人员唯一标识',
  `lab_type_code`        VARCHAR(100)  NULL     COMMENT '检项编码',
  `lab_type_name`        VARCHAR(200)  NULL     COMMENT '检项名称',
  `lab_item_code`        VARCHAR(100)  NULL     COMMENT '细项编码',
  `lab_item_name`        VARCHAR(200)  NULL     COMMENT '细项名称',
  `short_name`           VARCHAR(100)  NULL     COMMENT '细项简称',
  `result_value`         VARCHAR(500)  NULL     COMMENT '检验结果值',
  `result_category`      VARCHAR(50)   NULL     COMMENT '检验结果值类型',
  `unit`                 VARCHAR(50)   NULL     COMMENT '结果单位',
  `result_ref`           VARCHAR(200)  NULL     COMMENT '参考范围',
  `ref_low`              VARCHAR(50)   NULL     COMMENT '参考下界',
  `ref_high`             VARCHAR(50)   NULL     COMMENT '参考上界',
  `result_flag`          VARCHAR(20)   NULL     COMMENT '阳性标识',
  `positive_level`       VARCHAR(2)    NULL     DEFAULT '99' COMMENT '异常级别: 01正常/02阳性/03重大阳性/04危急值/99未知',
  `abnormal_name`        VARCHAR(200)  NULL     COMMENT '异常描述',
  `diagnosis_conclusion` VARCHAR(500)  NULL     COMMENT '诊断结论',
  `specimen_type_code`   VARCHAR(100)  NULL     COMMENT '样本类型',
  `samples_status`       VARCHAR(100)  NULL     COMMENT '样本性状',
  `is_valid`             TINYINT       NOT NULL DEFAULT 1 COMMENT '数据有效标识',
  `report_month`         VARCHAR(7)    NOT NULL COMMENT '数据月份, 格式 YYYY-MM',
  `table_source`         VARCHAR(50)   NULL     COMMENT '数据来源: result_new_2025/result_new_2024/mnyjy_peis_result/view_jyjg',
  `etl_load_time`        DATETIME      NOT NULL COMMENT 'ETL加载时间'
) ENGINE=OLAP
UNIQUE KEY(`lab_result_id`, `lab_date`)
COMMENT 'DWD层 · 实验室检验结果事实表（dwd_fact_lab）'
AUTO PARTITION BY RANGE (date_trunc(`lab_date`, 'month')) ()
DISTRIBUTED BY HASH(`lab_result_id`) BUCKETS 32
PROPERTIES (
  "replication_allocation" = "tag.location.default: 2",
  "min_load_replica_num" = "-1",
  "is_being_synced" = "false",
  "storage_medium" = "hdd",
  "storage_format" = "V2",
  "inverted_index_storage_format" = "V3",
  "enable_unique_key_merge_on_write" = "true",
  "light_schema_change" = "true",
  "disable_auto_compaction" = "false",
  "enable_single_replica_compaction" = "false",
  "group_commit_interval_ms" = "10000",
  "group_commit_data_bytes" = "134217728",
  "enable_mow_light_delete" = "false"
);

-- =============================================================
-- 倒排索引 (精简至 4 核心 + 2 全文检索)
-- =============================================================
ALTER TABLE `MIHDB_DWD`.`dwd_fact_lab`
  ADD INDEX idx_person_id     (`person_id`)     USING INVERTED COMMENT '人员ID, 高频维度筛选',
  ADD INDEX idx_checkin_id    (`checkin_id`)    USING INVERTED COMMENT '体检流水号, 关联查询',
  ADD INDEX idx_lab_item_code (`lab_item_code`) USING INVERTED COMMENT '检验细项编码, 指标筛选核心',
  ADD INDEX idx_report_month  (`report_month`)  USING INVERTED COMMENT '月份, 分月统计';

-- 全文检索索引: 支持异常描述、诊断结论的关键词搜索
ALTER TABLE `MIHDB_DWD`.`dwd_fact_lab`
  ADD INDEX idx_abnormal_ft             (`abnormal_name`)        USING INVERTED PROPERTIES("parser" = "unicode") COMMENT '异常描述全文检索',
  ADD INDEX idx_diagnosis_conclusion_ft (`diagnosis_conclusion`) USING INVERTED PROPERTIES("parser" = "unicode") COMMENT '诊断结论全文检索';
