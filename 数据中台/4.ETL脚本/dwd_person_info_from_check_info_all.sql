-- =============================================================
-- 文件: dwd_person_info_from_check_info_all.sql
-- 目标: 从 MIHDB_ODS.check_info_all 抽取人员信息到 MIHDB_DWD.dwd_person_info
-- 主键: person_id = idcard  (visitor_id 是单次体检流水号，不能作为人员主键)
-- 去重: 按 idcard 分组, 取 checkin_time 最新的一条; idcard 为空整体过滤
-- 性别: cust_sex 映射到 dim_sex (01 男 / 02 女 / 99 未知)
-- 兜底: birthday 在目标表是 NOT NULL, 故过滤掉 birthday 为空的记录
-- 重跑: dwd_person_info 是 Unique Key + MoW, 重跑会按 person_id 自动覆盖
-- 作者: codex
-- 日期: 2026-06-22
-- =============================================================

-- 备注: 源表 birthday/cust_sex/idcard 都是字符串列, 且 NULL 被序列化成字面量 '\N',
--      所以这里统一用 NULLIF 把 '\N'/'' 转成真 NULL 再处理, 避免 CAST AS DATE 报错.
INSERT INTO MIHDB_DWD.dwd_person_info
  (person_id, idcard, sex_code, birthday, etl_load_time)
SELECT
  t.idcard                                                  AS person_id,
  t.idcard                                                  AS idcard,
  CASE
    WHEN t.cust_sex IN ('1','01','男','M','MALE','男性')    THEN '01'
    WHEN t.cust_sex IN ('2','02','女','F','FEMALE','女性')  THEN '02'
    ELSE '99'
  END                                                        AS sex_code,
  t.birthday_dt                                              AS birthday,
  NOW()                                                      AS etl_load_time
FROM (
  SELECT
    TRIM(idcard) AS idcard,
    NULLIF(NULLIF(TRIM(cust_sex), ''), '\\N')        AS cust_sex,
    STR_TO_DATE(
      NULLIF(NULLIF(TRIM(birthday), ''), '\\N'),
      '%Y-%m-%d'
    )                                                AS birthday_dt,
    checkin_time,
    ROW_NUMBER() OVER (
      PARTITION BY TRIM(idcard)
      ORDER BY checkin_time DESC
    ) AS rn
  FROM MIHDB_ODS.check_info_all
  WHERE idcard IS NOT NULL
    AND TRIM(idcard) <> ''
    AND TRIM(idcard) <> '\\N'
    AND NULLIF(NULLIF(TRIM(birthday), ''), '\\N') IS NOT NULL
) t
WHERE t.rn = 1
  AND t.birthday_dt IS NOT NULL;
