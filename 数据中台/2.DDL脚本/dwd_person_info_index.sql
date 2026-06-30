-- =====================================================================
-- 文件: dwd_person_info_index.sql
-- 表名: MIHDB_DWD.dwd_person_info  （存量 ~1.0954 亿行, Unique Key + MoW）
-- 目的: 给高频查询列建索引
--        - idcard       : BloomFilter (高基数等值)
--        - person_name  : 倒排（中文分词, 支持等值 + LIKE）
--        - birthday     : 倒排（范围查询）
--        - etl_load_time: 倒排（增量/回溯）
-- 备注: person_id 是 Unique Key, 无需再加索引
-- 跳过列: sex_code / nation_code / blood_type / is_valid (低基数, 加索引反而负优化)
--
-- !!! 注意: 不要一把把整个脚本灌给 mysql。
-- BloomFilter 的 ALTER 会触发 schema change, 后续 ALTER 会被 "Table state(SCHEMA_CHANGE) is not NORMAL" 拒绝。
-- 正确顺序:
--   阶段 1: 执行第 1 条 BloomFilter, 然后 SHOW ALTER TABLE COLUMN 等到 State=FINISHED
--   阶段 2: 执行 2/3/4 三条 ADD INDEX (倒排)
--   阶段 3: 执行 5 的 BUILD INDEX, 然后 SHOW BUILD INDEX 等 State=FINISHED
-- 2026-06-23 实测: BloomFilter ~86s, 三条倒排 BUILD INDEX ~25-30s 各自完成。
-- =====================================================================

USE MIHDB_DWD;

-- 1) BloomFilter：身份证号
ALTER TABLE dwd_person_info
SET ("bloom_filter_columns" = "idcard");

-- 2) 倒排索引：姓名（中文分词 + LIKE）
ALTER TABLE dwd_person_info
ADD INDEX idx_person_name (person_name)
USING INVERTED
PROPERTIES("parser" = "chinese", "parser_mode" = "fine_grained")
COMMENT '姓名倒排';

-- 3) 倒排索引：出生日期
ALTER TABLE dwd_person_info
ADD INDEX idx_birthday (birthday)
USING INVERTED
COMMENT '出生日期范围';

-- 4) 倒排索引：ETL 加载时间
ALTER TABLE dwd_person_info
ADD INDEX idx_etl_load_time (etl_load_time)
USING INVERTED
COMMENT 'ETL时间范围';

-- 5) 对存量 1 亿数据触发 BUILD INDEX
--    Doris 2.x: ADD INDEX 只登记元数据, 历史数据不会自动建索引, 必须手动 BUILD
BUILD INDEX idx_person_name      ON dwd_person_info;
BUILD INDEX idx_birthday         ON dwd_person_info;
BUILD INDEX idx_etl_load_time    ON dwd_person_info;

-- 6) 验证
-- SHOW INDEX FROM dwd_person_info;
-- SHOW BUILD INDEX FROM MIHDB_DWD;
-- SHOW ALTER TABLE COLUMN FROM MIHDB_DWD ORDER BY CreateTime DESC LIMIT 5;
