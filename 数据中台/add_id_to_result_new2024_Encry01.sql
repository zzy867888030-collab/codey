-- ============================================================
-- 给 result_new2024_Encry01 加自增 id 主键 (重建法)
-- 27.1 亿行, 按月分区逐月灌入
-- ============================================================

-- 1. 建新表: DUPLICATE KEY 以 id 开头, 加 AUTO_INCREMENT
CREATE TABLE IF NOT EXISTS `MIHDB_ODS`.`result_new2024_Encry01_new` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT "自增主键",
  `vid` varchar(64) NOT NULL COMMENT "体检者ID",
  `exam_date` datetime NOT NULL COMMENT "检查日期",
  `positive_level` varchar(20) NOT NULL COMMENT "阳性级别",
  `item_name` varchar(255) NOT NULL COMMENT "检查项目名称",
  `branch_code` varchar(64) NOT NULL COMMENT "机构代码",
  `branch_name` varchar(255) NOT NULL COMMENT "机构名称",
  `item_code` varchar(64) NOT NULL COMMENT "检查项目编码",
  `item_detail_name` varchar(255) NOT NULL COMMENT "检查项目明细名称",
  `item_detail_code` varchar(64) NOT NULL COMMENT "检查项目明细编码",
  `short_name` varchar(128) NOT NULL COMMENT "简称",
  `title` varchar(512) NOT NULL COMMENT "标题",
  `result` text NOT NULL COMMENT "检查结果",
  `unit` varchar(64) NOT NULL COMMENT "单位",
  `normal_l` text NOT NULL COMMENT "参考值下限",
  `normal_h` text NOT NULL COMMENT "参考值上限",
  `result_flag` varchar(20) NOT NULL COMMENT "结果标志",
  `exam_doctors` varchar(512) NOT NULL COMMENT "检查医生",
  `institutions` varchar(255) NOT NULL COMMENT "送检机构",
  `samples_status` varchar(64) NOT NULL COMMENT "样本状态",
  `samples_type` varchar(64) NOT NULL COMMENT "样本类型",
  `abnormal_name` text NOT NULL COMMENT "异常名称",
  `conclusioncode` varchar(64) NOT NULL COMMENT "结论编码",
  `conclusionname` text NOT NULL COMMENT "结论名称"
) ENGINE=OLAP
DUPLICATE KEY(`id`)
COMMENT '2024年体检检查结果表 (带自增id)'
PARTITION BY RANGE(`exam_date`)
(PARTITION p_2024_01 VALUES [('0000-01-01 00:00:00'), ('2024-02-01 00:00:00')),
PARTITION p_2024_02 VALUES [('2024-02-01 00:00:00'), ('2024-03-01 00:00:00')),
PARTITION p_2024_03 VALUES [('2024-03-01 00:00:00'), ('2024-04-01 00:00:00')),
PARTITION p_2024_04 VALUES [('2024-04-01 00:00:00'), ('2024-05-01 00:00:00')),
PARTITION p_2024_05 VALUES [('2024-05-01 00:00:00'), ('2024-06-01 00:00:00')),
PARTITION p_2024_06 VALUES [('2024-06-01 00:00:00'), ('2024-07-01 00:00:00')),
PARTITION p_2024_07 VALUES [('2024-07-01 00:00:00'), ('2024-08-01 00:00:00')),
PARTITION p_2024_08 VALUES [('2024-08-01 00:00:00'), ('2024-09-01 00:00:00')),
PARTITION p_2024_09 VALUES [('2024-09-01 00:00:00'), ('2024-10-01 00:00:00')),
PARTITION p_2024_10 VALUES [('2024-10-01 00:00:00'), ('2024-11-01 00:00:00')),
PARTITION p_2024_11 VALUES [('2024-11-01 00:00:00'), ('2024-12-01 00:00:00')),
PARTITION p_2024_12 VALUES [('2024-12-01 00:00:00'), ('2025-01-01 00:00:00')))
DISTRIBUTED BY HASH(`vid`) BUCKETS 32
PROPERTIES (
"replication_allocation" = "tag.location.default: 1",
"bloom_filter_columns" = "vid",
"storage_medium" = "hdd",
"storage_format" = "V2",
"inverted_index_storage_format" = "V3",
"compression" = "LZ4",
"light_schema_change" = "true",
"disable_auto_compaction" = "false",
"enable_single_replica_compaction" = "false",
"group_commit_interval_ms" = "10000",
"group_commit_data_bytes" = "134217728"
);
