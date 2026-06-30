-- =============================================================
-- 文件: dwd_person_info_quality_check.sql
-- 目标: dwd_person_info 数据质量校验 (8大质控点)
-- 作者: codex
-- 日期: 2026-06-22
-- =============================================================

-- =============================================================
-- Q1: 总体概览（总行数 / 唯一人员数）
-- =============================================================
SELECT
  COUNT(*)              AS 总行数,
  COUNT(DISTINCT person_id) AS 唯一人员数,
  MIN(birthday)         AS 最小出生日期,
  MAX(birthday)         AS 最大出生日期,
  COUNT(DISTINCT sex_code)  AS 性别类别数
FROM MIHDB_DWD.dwd_person_info;

-- =============================================================
-- Q2: 各列空值率（目标表所有NOT NULL列）
-- =============================================================
SELECT
  SUM(CASE WHEN person_id   IS NULL THEN 1 ELSE 0 END) AS person_id_null,
  SUM(CASE WHEN idcard      IS NULL THEN 1 ELSE 0 END) AS idcard_null,
  SUM(CASE WHEN sex_code    IS NULL THEN 1 ELSE 0 END) AS sex_code_null,
  SUM(CASE WHEN birthday    IS NULL THEN 1 ELSE 0 END) AS birthday_null,
  SUM(CASE WHEN is_valid    IS NULL THEN 1 ELSE 0 END) AS is_valid_null,
  SUM(CASE WHEN nation_code IS NULL THEN 1 ELSE 0 END) AS nation_null,
  COUNT(*)                                              AS total_rows
FROM MIHDB_DWD.dwd_person_info;

-- =============================================================
-- Q3: 性别分布校验（必须严格匹配 dim_sex.code）
-- =============================================================
SELECT
  p.sex_code,
  s.sex_name,
  COUNT(*) AS 人数,
  ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,2) AS 占比
FROM MIHDB_DWD.dwd_person_info p
LEFT JOIN MIHDB_DWD.dim_sex s ON p.sex_code = s.sex_code
GROUP BY p.sex_code, s.sex_name
ORDER BY COUNT(*) DESC;

-- =============================================================
-- Q4: birthday 异常值校验（未来 / 1900前 / 年龄>120）
-- =============================================================
SELECT
  category, COUNT(*) AS 异常行数, ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,2) AS 占比
FROM (
  SELECT
    birthday,
    CASE
      WHEN birthday > CURDATE() THEN '未来日期'
      WHEN birthday < '1900-01-01' THEN '1900年以前'
      WHEN TIMESTAMPDIFF(YEAR, birthday, CURDATE()) > 120 THEN '年龄超过120岁'
      ELSE '正常'
    END AS category
  FROM MIHDB_DWD.dwd_person_info
) t
GROUP BY category;

-- =============================================================
-- Q5: idcard 格式校验（源表上游已 MD5 加密成 32 位 hex，不是明文身份证号）
-- =============================================================
SELECT
  category, COUNT(*) AS 行数, ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,2) AS 占比
FROM (
  SELECT
    idcard,
    CASE
      WHEN idcard REGEXP '^[0-9a-f]{32}$' THEN '32位MD5哈希'
      WHEN idcard REGEXP '^[0-9A-Fa-f]{32}$' THEN '32位HEX(大小写混)'
      ELSE '非32位HEX异常'
    END AS category
  FROM MIHDB_DWD.dwd_person_info
) t
GROUP BY category;

-- =============================================================
-- Q6: person_id 唯一性校验（Unique Key 重复兜底）
-- =============================================================
SELECT person_id, COUNT(*) AS 重复次数
FROM MIHDB_DWD.dwd_person_info
GROUP BY person_id
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC
LIMIT 50;

-- =============================================================
-- Q7: 与源表核对（源表总idcard数 vs 目标表写入数）
-- =============================================================
SELECT
  '源表check_info_all去重后idcard数' AS 指标, COUNT(*) AS 数值
FROM (SELECT DISTINCT TRIM(idcard) FROM MIHDB_ODS.check_info_all WHERE idcard IS NOT NULL AND TRIM(idcard) <> '' AND TRIM(idcard) <> '\\N') t
UNION ALL
SELECT '目标表dwd_person_info写入数', COUNT(*) FROM MIHDB_DWD.dwd_person_info;

-- =============================================================
-- Q8: 年龄分布概览（分年龄段抽查合理性）
-- =============================================================
SELECT
  CASE
    WHEN TIMESTAMPDIFF(YEAR, birthday, CURDATE()) < 18  THEN '0-17岁'
    WHEN TIMESTAMPDIFF(YEAR, birthday, CURDATE()) < 30  THEN '18-29岁'
    WHEN TIMESTAMPDIFF(YEAR, birthday, CURDATE()) < 45  THEN '30-44岁'
    WHEN TIMESTAMPDIFF(YEAR, birthday, CURDATE()) < 60  THEN '45-59岁'
    WHEN TIMESTAMPDIFF(YEAR, birthday, CURDATE()) < 75  THEN '60-74岁'
    WHEN TIMESTAMPDIFF(YEAR, birthday, CURDATE()) < 100 THEN '75-99岁'
    ELSE '100岁以上'
  END AS 年龄段,
  COUNT(*) AS 人数,
  ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,2) AS 占比
FROM MIHDB_DWD.dwd_person_info
GROUP BY 1
ORDER BY 1;
