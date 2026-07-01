-- =============================================================
-- 文件: dim_lab_item.sql
-- 用途: DWD层维度表 检验项目字典 (原始词 -> 标化词 映射)
-- 来源: 《DWD_体检数据仓库表结构设计_V1.2》.xlsx / sheet「维度表_检验项目」
-- 说明:
--   1. 该字典粒度为「原始三元组」(原始大项 + 原始细项 + 原始标本),
--      用于把各院系统的原始检验项目名映射到统一标化名/编码。
--   2. item_detail_code 是标化编码 (877 个唯一值), 一个标化编码对应
--      多个原始写法, 因此不能做主键; 主键改用原始三元组的 MD5。
--   3. Excel 表头: raw_item_name / raw_item_detail_name / raw_specimen_name /
--      lab_level1_category / lab_level2_category / standard_name /
--      item_detail_code / lab_level1_code / lab_level2_code /
--      related_diseases / related_disease_systems / is_effective。
--   4. is_effective 口径: 0=有效, 1=无效 (Excel 内全为 0)。
-- 日期: 2026-07-01
-- =============================================================

DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_lab_item`;
CREATE TABLE `MIHDB_DWD`.`dim_lab_item` (
  `mapping_id`              VARCHAR(32)  NOT NULL COMMENT '映射主键, MD5(raw_item_name|raw_item_detail_name|raw_specimen_name)',
  `raw_item_name`           VARCHAR(128) NOT NULL COMMENT '原始大项名称',
  `raw_item_detail_name`    VARCHAR(128) NULL     COMMENT '原始细项名称',
  `raw_specimen_name`       VARCHAR(32)  NULL     COMMENT '原始标本名称',
  `lab_level1_category`     VARCHAR(64)  NULL     COMMENT '一级分类',
  `lab_level2_category`     VARCHAR(64)  NULL     COMMENT '二级分类',
  `standard_name`           VARCHAR(128) NULL     COMMENT '归一标化名称',
  `item_detail_code`        VARCHAR(32)  NULL     COMMENT '细项标化编码',
  `lab_level1_code`         VARCHAR(16)  NULL     COMMENT '一级分类编码',
  `lab_level2_code`         VARCHAR(32)  NULL     COMMENT '二级分类编码',
  `related_diseases`        VARCHAR(256) NULL     COMMENT '主要相关疾病',
  `related_disease_systems` VARCHAR(128) NULL     COMMENT '疾病系统',
  `is_effective`            VARCHAR(1)   NULL     DEFAULT '0' COMMENT '是否有效: 0有效/1无效',
  `etl_load_time`           DATETIME     NOT NULL COMMENT 'ETL加载时间'
) ENGINE=OLAP
UNIQUE KEY(`mapping_id`)
COMMENT 'dim_lab_item · 检验项目字典（原始词→标化词映射, 源自表结构设计V1.2）'
DISTRIBUTED BY HASH(`mapping_id`) BUCKETS 8
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD",
  "light_schema_change" = "true"
);

-- 倒排索引: 按标化编码/标化名/原始名回查
ALTER TABLE `MIHDB_DWD`.`dim_lab_item`
  ADD INDEX idx_item_detail_code (`item_detail_code`) USING INVERTED COMMENT '标化编码, 标准词查询',
  ADD INDEX idx_standard_name    (`standard_name`)    USING INVERTED COMMENT '标化名称, 按标准项统计',
  ADD INDEX idx_raw_item_name    (`raw_item_name`)    USING INVERTED COMMENT '原始大项名, 映射回查';
