-- =============================================================
-- 文件: ods_lisitem.sql
-- 用途: ODS层 检验项目清单 (源自 lisitem.xlsx / Sheet1, 原样导入)
-- 说明:
--   1. Excel 4 列: item_name / raw_item_detail_name / cnt / item_type。
--   2. item_name 为稀疏列(仅组首有值, 其余为空), 原样保留 NULL, 不做填充。
--   3. raw_item_detail_name 有同名(50 处), 故用 DUPLICATE KEY 模型保留全部行。
-- 日期: 2026-07-01
-- =============================================================

DROP TABLE IF EXISTS `MIHDB_ODS`.`lisitem`;
CREATE TABLE `MIHDB_ODS`.`lisitem` (
  `item_name`            VARCHAR(96)  NULL COMMENT '项目名称(组首标准名, 稀疏列)',
  `raw_item_detail_name` VARCHAR(128) NULL COMMENT '原始细项名称',
  `cnt`                  BIGINT       NULL COMMENT '出现次数/计数',
  `item_type`            VARCHAR(16)  NULL COMMENT '项目类型(检验)'
) ENGINE=OLAP
DUPLICATE KEY(`item_name`)
COMMENT 'ODS层 · 检验项目清单（源自 lisitem.xlsx）'
DISTRIBUTED BY HASH(`raw_item_detail_name`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "compression" = "ZSTD",
  "light_schema_change" = "true"
);
