-- MIHDB_ODS.mnyjy_peis_result add AUTO_INCREMENT id migration
-- 2023 结果表加 id：新建 _new 表 -> 按月迁移 -> 校验 -> 手动换表。
-- Doris 换表语法：ALTER TABLE db.table RENAME new_table_name; 不要写 RENAME TO。

SHOW TABLES FROM MIHDB_ODS LIKE 'mnyjy_peis_result%';

CREATE TABLE IF NOT EXISTS MIHDB_ODS.mnyjy_peis_result_new (
  `id` bigint NOT NULL AUTO_INCREMENT(1) COMMENT "自增主键",
  `vid` varchar(512) NULL,
  `exam_date` datetime NULL,
  `branch_code` varchar(64) NULL,
  `branch_name` varchar(512) NULL,
  `item_code` varchar(64) NULL,
  `item_name` varchar(512) NULL,
  `item_detail_name` varchar(512) NULL,
  `item_detail_code` varchar(64) NULL,
  `short_name` varchar(512) NULL,
  `title` varchar(512) NULL,
  `result` text NULL,
  `unit` varchar(256) NULL,
  `normal_l` varchar(512) NULL,
  `normal_h` varchar(512) NULL,
  `result_flag` varchar(256) NULL,
  `positive_level` varchar(256) NULL,
  `exam_doctors` varchar(512) NULL,
  `institutions` varchar(512) NULL,
  `samples_status` varchar(256) NULL,
  `samples_type` varchar(512) NULL,
  `report_time` datetime NULL,
  `report_status` varchar(256) NULL,
  `submit_final_check` bigint NULL,
  `comments` text NULL,
  `logic_delete` bigint NULL,
  `create_at` datetime NULL,
  `update_at` datetime NULL,
  `create_by` varchar(256) NULL,
  `update_by` varchar(256) NULL,
  `type` varchar(256) NULL,
  `detail_type` varchar(512) NULL,
  `lis_report_id` text NULL,
  `abnormal_name` text NULL,
  `conclusioncode` varchar(512) NULL,
  `conclusionname` text NULL,
  INDEX idx_item_name_inverted (`item_name`) USING INVERTED PROPERTIES("lower_case" = "true", "parser" = "standard", "support_phrase" = "true"),
  INDEX idx_item_detail_inverted (`item_detail_name`) USING INVERTED PROPERTIES("lower_case" = "true", "parser" = "standard", "support_phrase" = "true")
) ENGINE=OLAP
DUPLICATE KEY(`id`)
PARTITION BY RANGE(`exam_date`)
(PARTITION p_202301 VALUES [('2023-01-01 00:00:00'), ('2023-02-01 00:00:00')),
PARTITION p_202302 VALUES [('2023-02-01 00:00:00'), ('2023-03-01 00:00:00')),
PARTITION p_202303 VALUES [('2023-03-01 00:00:00'), ('2023-04-01 00:00:00')),
PARTITION p_202304 VALUES [('2023-04-01 00:00:00'), ('2023-05-01 00:00:00')),
PARTITION p_202305 VALUES [('2023-05-01 00:00:00'), ('2023-06-01 00:00:00')),
PARTITION p_202306 VALUES [('2023-06-01 00:00:00'), ('2023-07-01 00:00:00')),
PARTITION p_202307 VALUES [('2023-07-01 00:00:00'), ('2023-08-01 00:00:00')),
PARTITION p_202308 VALUES [('2023-08-01 00:00:00'), ('2023-09-01 00:00:00')),
PARTITION p_202309 VALUES [('2023-09-01 00:00:00'), ('2023-10-01 00:00:00')),
PARTITION p_202310 VALUES [('2023-10-01 00:00:00'), ('2023-11-01 00:00:00')),
PARTITION p_202311 VALUES [('2023-11-01 00:00:00'), ('2023-12-01 00:00:00')),
PARTITION p_202312 VALUES [('2023-12-01 00:00:00'), ('2024-01-01 00:00:00')))
DISTRIBUTED BY HASH(`vid`) BUCKETS 16
PROPERTIES (
"replication_allocation" = "tag.location.default: 2",
"min_load_replica_num" = "-1",
"is_being_synced" = "false",
"storage_medium" = "hdd",
"storage_format" = "V2",
"inverted_index_storage_format" = "V3",
"light_schema_change" = "true",
"disable_auto_compaction" = "false",
"enable_single_replica_compaction" = "false",
"group_commit_interval_ms" = "10000",
"group_commit_data_bytes" = "134217728"
);

-- Data migration. id is intentionally excluded; Doris AUTO_INCREMENT generates it.

-- 2023-01
INSERT INTO MIHDB_ODS.mnyjy_peis_result_new (vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname)
SELECT vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname
FROM MIHDB_ODS.mnyjy_peis_result
WHERE exam_date >= '2023-01-01 00:00:00' AND exam_date < '2023-02-01 00:00:00';

-- 2023-02
INSERT INTO MIHDB_ODS.mnyjy_peis_result_new (vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname)
SELECT vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname
FROM MIHDB_ODS.mnyjy_peis_result
WHERE exam_date >= '2023-02-01 00:00:00' AND exam_date < '2023-03-01 00:00:00';

-- 2023-03
INSERT INTO MIHDB_ODS.mnyjy_peis_result_new (vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname)
SELECT vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname
FROM MIHDB_ODS.mnyjy_peis_result
WHERE exam_date >= '2023-03-01 00:00:00' AND exam_date < '2023-04-01 00:00:00';

-- 2023-04
INSERT INTO MIHDB_ODS.mnyjy_peis_result_new (vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname)
SELECT vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname
FROM MIHDB_ODS.mnyjy_peis_result
WHERE exam_date >= '2023-04-01 00:00:00' AND exam_date < '2023-05-01 00:00:00';

-- 2023-05
INSERT INTO MIHDB_ODS.mnyjy_peis_result_new (vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname)
SELECT vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname
FROM MIHDB_ODS.mnyjy_peis_result
WHERE exam_date >= '2023-05-01 00:00:00' AND exam_date < '2023-06-01 00:00:00';

-- 2023-06
INSERT INTO MIHDB_ODS.mnyjy_peis_result_new (vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname)
SELECT vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname
FROM MIHDB_ODS.mnyjy_peis_result
WHERE exam_date >= '2023-06-01 00:00:00' AND exam_date < '2023-07-01 00:00:00';

-- 2023-07
INSERT INTO MIHDB_ODS.mnyjy_peis_result_new (vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname)
SELECT vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname
FROM MIHDB_ODS.mnyjy_peis_result
WHERE exam_date >= '2023-07-01 00:00:00' AND exam_date < '2023-08-01 00:00:00';

-- 2023-08
INSERT INTO MIHDB_ODS.mnyjy_peis_result_new (vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname)
SELECT vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname
FROM MIHDB_ODS.mnyjy_peis_result
WHERE exam_date >= '2023-08-01 00:00:00' AND exam_date < '2023-09-01 00:00:00';

-- 2023-09
INSERT INTO MIHDB_ODS.mnyjy_peis_result_new (vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname)
SELECT vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname
FROM MIHDB_ODS.mnyjy_peis_result
WHERE exam_date >= '2023-09-01 00:00:00' AND exam_date < '2023-10-01 00:00:00';

-- 2023-10
INSERT INTO MIHDB_ODS.mnyjy_peis_result_new (vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname)
SELECT vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname
FROM MIHDB_ODS.mnyjy_peis_result
WHERE exam_date >= '2023-10-01 00:00:00' AND exam_date < '2023-11-01 00:00:00';

-- 2023-11
INSERT INTO MIHDB_ODS.mnyjy_peis_result_new (vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname)
SELECT vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname
FROM MIHDB_ODS.mnyjy_peis_result
WHERE exam_date >= '2023-11-01 00:00:00' AND exam_date < '2023-12-01 00:00:00';

-- 2023-12
INSERT INTO MIHDB_ODS.mnyjy_peis_result_new (vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname)
SELECT vid, exam_date, branch_code, branch_name, item_code, item_name, item_detail_name, item_detail_code, short_name, title, result, unit, normal_l, normal_h, result_flag, positive_level, exam_doctors, institutions, samples_status, samples_type, report_time, report_status, submit_final_check, comments, logic_delete, create_at, update_at, create_by, update_by, type, detail_type, lis_report_id, abnormal_name, conclusioncode, conclusionname
FROM MIHDB_ODS.mnyjy_peis_result
WHERE exam_date >= '2023-12-01 00:00:00' AND exam_date < '2024-01-01 00:00:00';


-- Verification: every diff should be 0.
SELECT COALESCE(s.ym, d.ym) AS ym,
       s.cnt AS src_cnt,
       d.cnt AS dst_cnt,
       d.cnt - s.cnt AS diff
FROM (
  SELECT EXTRACT(YEAR_MONTH FROM exam_date) ym, COUNT(*) cnt
  FROM MIHDB_ODS.mnyjy_peis_result
  GROUP BY 1
) s
LEFT JOIN (
  SELECT EXTRACT(YEAR_MONTH FROM exam_date) ym, COUNT(*) cnt
  FROM MIHDB_ODS.mnyjy_peis_result_new
  GROUP BY 1
) d ON s.ym = d.ym
ORDER BY ym;

SELECT 'src_total', COUNT(*) FROM MIHDB_ODS.mnyjy_peis_result;
SELECT 'dst_total', COUNT(*) FROM MIHDB_ODS.mnyjy_peis_result_new;
SELECT 'id_check', COUNT(*), COUNT(id), SUM(CASE WHEN id IS NULL THEN 1 ELSE 0 END), MIN(id), MAX(id)
FROM MIHDB_ODS.mnyjy_peis_result_new;

-- Rename after verification passes. Keep backup table until business validation finishes.
-- ALTER TABLE MIHDB_ODS.mnyjy_peis_result RENAME mnyjy_peis_result_bak;
-- ALTER TABLE MIHDB_ODS.mnyjy_peis_result_new RENAME mnyjy_peis_result;
