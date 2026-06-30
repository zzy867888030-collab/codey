-- =============================================================
-- 文件: dwd_fact_checkin_create_indexes.sql
-- 用途: 在 MIHDB_DWD.dwd_fact_checkin 上建 4 个 inverted index
--       (checkin_id 已是 Unique Key 主键, 自带前缀索引, 无需重复建)
--
-- 索引列:
--   person_id     人员唯一标识 (高基数, 等值查询)
--   book_optime   预约时间     (datetime, 范围查询)
--   checkin_date  体检日期     (date, 范围查询)
--   report_date   出报告日期   (date, 范围查询)
--   checkin_branch_code 到检分院编码 (低基数, 等值/IN 查询)
--
-- 备注:
--   Doris 的 ADD INDEX 是异步的, 跑完 ALTER 之后需要 BUILD INDEX 才会
--   对存量数据生效; 对新写入的数据是即时生效的.
--
-- 作者: codex
-- 日期: 2026-06-24
-- =============================================================

USE MIHDB_DWD;

-- 1. 创建索引 (元数据级操作, 秒级)
ALTER TABLE dwd_fact_checkin
    ADD INDEX idx_person_id    (person_id)    USING INVERTED COMMENT '人员唯一标识倒排索引',
    ADD INDEX idx_book_optime  (book_optime)  USING INVERTED COMMENT '预约时间倒排索引',
    ADD INDEX idx_checkin_date (checkin_date) USING INVERTED COMMENT '体检日期倒排索引',
    ADD INDEX idx_report_date  (report_date)  USING INVERTED COMMENT '出报告日期倒排索引',
    ADD INDEX idx_checkin_branch_code (checkin_branch_code) USING INVERTED COMMENT '到检分院编码倒排索引';

-- 2. 对存量数据构建索引 (异步, 看 SHOW BUILD INDEX 进度)
BUILD INDEX idx_person_id    ON dwd_fact_checkin;
BUILD INDEX idx_book_optime  ON dwd_fact_checkin;
BUILD INDEX idx_checkin_date ON dwd_fact_checkin;
BUILD INDEX idx_report_date  ON dwd_fact_checkin;
BUILD INDEX idx_checkin_branch_code ON dwd_fact_checkin;

-- 3. 验证: 查看索引定义和构建进度
-- SHOW INDEX FROM dwd_fact_checkin;
-- SHOW BUILD INDEX FROM dwd_fact_checkin;
