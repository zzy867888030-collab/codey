-- =============================================================
-- 文件: dwd_fact_checkin_quality_check.sql
-- 目标: dwd_fact_checkin 数据质量校验 (10 个质控点)
-- 作者: codex
-- 日期: 2026-06-24
-- =============================================================

-- Q1 总览
SELECT
  COUNT(*)                    AS total_rows,
  COUNT(DISTINCT checkin_id)  AS unique_checkin_id,
  COUNT(DISTINCT person_id)   AS unique_person_id,
  COUNT(DISTINCT report_month) AS unique_report_months,
  MIN(checkin_date)           AS min_checkin_date,
  MAX(checkin_date)           AS max_checkin_date
FROM MIHDB_DWD.dwd_fact_checkin;

-- Q2 关键列空值统计 (NOT NULL 列必须 0)
SELECT
  SUM(CASE WHEN checkin_id    IS NULL THEN 1 ELSE 0 END) AS checkin_id_null,
  SUM(CASE WHEN person_id     IS NULL THEN 1 ELSE 0 END) AS person_id_null,
  SUM(CASE WHEN report_month  IS NULL THEN 1 ELSE 0 END) AS report_month_null,
  SUM(CASE WHEN marital_code  IS NULL THEN 1 ELSE 0 END) AS marital_null,
  SUM(CASE WHEN fertility_code IS NULL THEN 1 ELSE 0 END) AS fertility_null,
  SUM(CASE WHEN is_valid       IS NULL THEN 1 ELSE 0 END) AS is_valid_null,
  SUM(CASE WHEN etl_load_time  IS NULL THEN 1 ELSE 0 END) AS etl_load_time_null,
  SUM(CASE WHEN checkin_date   IS NULL THEN 1 ELSE 0 END) AS checkin_date_null
FROM MIHDB_DWD.dwd_fact_checkin;

-- Q3 年份分布 (从 report_month 拆年)
SELECT
  SUBSTR(report_month,1,4) AS yr,
  COUNT(*) AS cnt,
  ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,2) AS pct
FROM MIHDB_DWD.dwd_fact_checkin
GROUP BY 1 ORDER BY 1;

-- Q4 checkin_id 重复兜底 (Unique Key 应该 0 行)
SELECT checkin_id, COUNT(*) AS dup_cnt
FROM MIHDB_DWD.dwd_fact_checkin
GROUP BY checkin_id HAVING COUNT(*) > 1
ORDER BY dup_cnt DESC LIMIT 20;

-- Q5 person_id 与 dwd_person_info 的对账 (孤儿 person_id)
SELECT
  '匹配上 dwd_person_info' AS bucket, COUNT(*) AS cnt
FROM MIHDB_DWD.dwd_fact_checkin f
JOIN MIHDB_DWD.dwd_person_info p ON f.person_id = p.person_id
UNION ALL
SELECT
  '孤儿 (person_info 找不到)', COUNT(*)
FROM MIHDB_DWD.dwd_fact_checkin f
LEFT JOIN MIHDB_DWD.dwd_person_info p ON f.person_id = p.person_id
WHERE p.person_id IS NULL;

-- Q6 枚举字段值分布 (应只命中 dim 字典里的码)
SELECT 'health_check_code' AS col, health_check_code AS val, COUNT(*) AS cnt
FROM MIHDB_DWD.dwd_fact_checkin GROUP BY 1,2
UNION ALL
SELECT 'marital_code', marital_code, COUNT(*) FROM MIHDB_DWD.dwd_fact_checkin GROUP BY 1,2
UNION ALL
SELECT 'fertility_code', fertility_code, COUNT(*) FROM MIHDB_DWD.dwd_fact_checkin GROUP BY 1,2
UNION ALL
SELECT 'member_code', member_code, COUNT(*) FROM MIHDB_DWD.dwd_fact_checkin GROUP BY 1,2
UNION ALL
SELECT 'external_inspection_code', external_inspection_code, COUNT(*) FROM MIHDB_DWD.dwd_fact_checkin GROUP BY 1,2
UNION ALL
SELECT 'report_query_code', report_query_code, COUNT(*) FROM MIHDB_DWD.dwd_fact_checkin GROUP BY 1,2
UNION ALL
SELECT 'report_collection_code', report_collection_code, COUNT(*) FROM MIHDB_DWD.dwd_fact_checkin GROUP BY 1,2
UNION ALL
SELECT 'is_valid', CAST(is_valid AS STRING), COUNT(*) FROM MIHDB_DWD.dwd_fact_checkin GROUP BY 1,2
ORDER BY col, cnt DESC;

-- Q7 时间字段合理性 (book_optime / checkin_date / report_date 三段逻辑)
SELECT
  SUM(CASE WHEN book_optime IS NOT NULL AND book_optime < '2000-01-01' THEN 1 ELSE 0 END)  AS book_too_old,
  SUM(CASE WHEN book_optime IS NOT NULL AND book_optime > NOW()        THEN 1 ELSE 0 END)  AS book_future,
  SUM(CASE WHEN checkin_date IS NOT NULL AND book_optime IS NOT NULL AND checkin_date < DATE(book_optime) THEN 1 ELSE 0 END) AS checkin_before_book,
  SUM(CASE WHEN report_date  IS NOT NULL AND checkin_date IS NOT NULL AND report_date  < checkin_date     THEN 1 ELSE 0 END) AS report_before_checkin,
  SUM(CASE WHEN report_date  IS NOT NULL AND report_date  > CURDATE() THEN 1 ELSE 0 END)   AS report_future
FROM MIHDB_DWD.dwd_fact_checkin;

-- Q8 age 合理性
SELECT
  SUM(CASE WHEN age IS NULL THEN 1 ELSE 0 END)                AS age_null,
  SUM(CASE WHEN age < 0 OR age > 120 THEN 1 ELSE 0 END)       AS age_out_of_range,
  MIN(age) AS min_age, MAX(age) AS max_age, AVG(age) AS avg_age
FROM MIHDB_DWD.dwd_fact_checkin;

-- Q9 mobile 长度分布 (扩到 128 后, 验证无截断)
SELECT LENGTH(mobile) AS mobile_len, COUNT(*) AS cnt
FROM MIHDB_DWD.dwd_fact_checkin
WHERE mobile IS NOT NULL
GROUP BY 1 ORDER BY 1;

-- Q10 report_month 格式校验 (必须 YYYY-MM)
SELECT
  SUM(CASE WHEN report_month REGEXP '^[0-9]{4}-[0-9]{2}$' THEN 0 ELSE 1 END) AS bad_format,
  COUNT(*) AS total
FROM MIHDB_DWD.dwd_fact_checkin;
