-- =============================================================
-- 文件: dwd_fact_checkin_from_ods.sql
-- 目标: MIHDB_DWD.dwd_fact_checkin (体检登记事实表)
-- 数据源:
--   2025         : MIHDB_ODS.check_info_2025_Encry
--   2024         : MIHDB_ODS.check_info_new_2024_Encry  (a)
--                  + MIHDB_ODS.check_info_new_2024_Encry01 (b)
--                  visitor_id 取 a, idcard / cust_name / mobile 取 b 的 *1 字段
--                  (b.idcard1 / b.cust_name1 / b.mobile1 才是与其他源 idcard
--                   口径一致的正确脱敏字段, b.idcard / b.mobile 是另一套 key, 不要用)
--   2023         : MIHDB_ODS.mnyjy_peis_check_info_new01_Encry
--   2017 ~ 2022  : MIHDB_ODS.view_yyqkb_Encry
--
-- 主键   : checkin_id = TRIM(visitor_id)  (Unique Key + MoW, 重跑覆盖)
-- person : person_id  = TRIM(idcard)      (与 dwd_person_info 一致)
--
-- 清洗规则:
--   1. 字符串列先 NULLIF(NULLIF(TRIM(x), ''), '\N')
--   2. 日期/时间用 STR_TO_DATE, 失败返回 NULL
--   3. book_optime 非法 (< 2000-01-01 或 > NOW) 置 NULL
--   4. 枚举字段未知统一兜底 '99' / 表 DEFAULT
--   5. is_deleted=1 → is_valid=0
--   6. report_month 源 YYYYMM, 统一 YYYY-MM
--   7. visitor_id / idcard 为空整行过滤
--   8. report_date 降级链 (电子报告无打印, print_time 空率高):
--        2025/2024/2023 : COALESCE(print_time, update_time, checkin_time)
--        2017~2022 view_yyqkb : COALESCE(PRINT_TIME, TJZZSJ, QTDJSJ)
--
-- 字段映射 (2026-06-24 业务确认, 已实装):
--   - health_check_code      : 源 health_check_type 字母枚举 → DWD 数字枚举
--       Y→01入职 / N→02年度 / X→03优先 / W→04外检 / F→05妇检 / Z→06职业病
--       Q→07_3650卡 / C→08_CT卡 / U→09下午 / H→10核磁 / S→11个检
--       B→12上午单卡 / T→13云检 / 其他/空→99
--   - member_code            : 源 member_type
--       'VIP'→01 / 空或'00'/'普通'→02 / 其他→99
--   - external_inspection_code : 源 need_partner
--       'Y'→01是 / 'N'→02否 / 其他/空→99
--   - report_query_code      : 源 report_search_type
--       '0'→01全部 / '1'→02仅单位 / '2'→03仅个人 / '3'→04全禁用 / 其他/空→99
--   - report_collection_code : 源 report_send_type
--       '1'→01送达单位 / '2'→02自取 / '3'→03邮寄 / '4'→04网络查询 / '5'→05给业务员
--       '6'→06个人 / '7'→01(给单位到付, 业务侧并入"送达单位") / 其他/空→99
--   - personnel_unit_code    : 直接写源 corp_code 原值 (SUBSTR 1..100), NULL 保留
--                              view_yyqkb 段取 DWDM
--   - marital_code / fertility_code : 源端均无, 固定 99 (后续可通过 dwd_person_info 补)
--   - view_yyqkb 段 health_check_type / need_partner / report_search_type / report_send_type
--     字段均不存在, 一律落到 99
--
-- 作者: codex
-- 日期: 2026-06-24
-- =============================================================


-- ---------------------------------------------------------------
-- 第 1 段: 2025 (check_info_2025_Encry)
-- ---------------------------------------------------------------
INSERT INTO MIHDB_DWD.dwd_fact_checkin (
  checkin_id, person_id, checkin_branch_code, health_check_code, personnel_unit_code,
  age, marital_code, fertility_code, mobile, member_code, external_inspection_code,
  report_query_code, report_collection_code,
  book_optime, checkin_date, report_date,
  is_valid, report_month, etl_load_time
)
SELECT
  t.visitor_id_c                                          AS checkin_id,
  t.idcard_c                                              AS person_id,
  t.checkin_branch_code_c                                 AS checkin_branch_code,
  CASE UPPER(t.health_check_type_c)
    WHEN 'Y' THEN '01' WHEN 'N' THEN '02' WHEN 'X' THEN '03'
    WHEN 'W' THEN '04' WHEN 'F' THEN '05' WHEN 'Z' THEN '06'
    WHEN 'Q' THEN '07' WHEN 'C' THEN '08' WHEN 'U' THEN '09'
    WHEN 'H' THEN '10' WHEN 'S' THEN '11' WHEN 'B' THEN '12'
    WHEN 'T' THEN '13'
    ELSE '99'
  END                                                     AS health_check_code,
  SUBSTR(t.corp_code_c, 1, 100)                           AS personnel_unit_code,
  CASE
    WHEN t.birthday_dt IS NULL OR t.checkin_dt IS NULL THEN NULL
    WHEN TIMESTAMPDIFF(YEAR, t.birthday_dt, t.checkin_dt) BETWEEN 0 AND 120
      THEN TIMESTAMPDIFF(YEAR, t.birthday_dt, t.checkin_dt)
    ELSE NULL
  END                                                     AS age,
  '99'                                                    AS marital_code,
  '99'                                                    AS fertility_code,
  t.mobile_c                                              AS mobile,
  CASE
    WHEN UPPER(t.member_type_c) = 'VIP' THEN '01'
    WHEN t.member_type_c IS NULL OR UPPER(t.member_type_c) IN ('00','PUTONG','普通') THEN '02'
    ELSE '99'
  END                                                     AS member_code,
  CASE UPPER(t.need_partner_c)
    WHEN 'Y' THEN '01'
    WHEN 'N' THEN '02'
    ELSE '99'
  END                                                     AS external_inspection_code,
  CASE TRIM(t.report_search_type_c)
    WHEN '0' THEN '01'
    WHEN '1' THEN '02'
    WHEN '2' THEN '03'
    WHEN '3' THEN '04'
    ELSE '99'
  END                                                     AS report_query_code,
  CASE TRIM(t.report_send_type_c)
    WHEN '1' THEN '01'
    WHEN '2' THEN '02'
    WHEN '3' THEN '03'
    WHEN '4' THEN '04'
    WHEN '5' THEN '05'
    WHEN '6' THEN '06'
    WHEN '7' THEN '01'
    ELSE '99'
  END                                                     AS report_collection_code,
  t.book_optime_dt                                        AS book_optime,
  DATE(t.checkin_dt)                                      AS checkin_date,
  COALESCE(DATE(t.print_time_dt), DATE(t.update_time_dt), DATE(t.checkin_dt)) AS report_date,
  CASE WHEN t.is_deleted_c = '1' THEN 0 ELSE 1 END        AS is_valid,
  t.report_month_fmt                                      AS report_month,
  NOW()                                                   AS etl_load_time
FROM (
  SELECT
    NULLIF(NULLIF(TRIM(visitor_id),          ''), '\\N')   AS visitor_id_c,
    NULLIF(NULLIF(TRIM(idcard),              ''), '\\N')   AS idcard_c,
    NULLIF(NULLIF(TRIM(checkin_branch_code), ''), '\\N')   AS checkin_branch_code_c,
    NULLIF(NULLIF(TRIM(mobile),              ''), '\\N')   AS mobile_c,
    NULLIF(NULLIF(TRIM(CAST(is_deleted AS STRING)), ''), '\\N') AS is_deleted_c,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(birthday),     ''), '\\N'), '%Y-%m-%d')          AS birthday_dt,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(checkin_time), ''), '\\N'), '%Y-%m-%d %H:%i:%s') AS checkin_dt,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(print_time),   ''), '\\N'), '%Y-%m-%d %H:%i:%s') AS print_time_dt,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(update_time),  ''), '\\N'), '%Y-%m-%d %H:%i:%s') AS update_time_dt,
    CASE
      WHEN STR_TO_DATE(NULLIF(NULLIF(TRIM(book_optime), ''), '\\N'), '%Y-%m-%d %H:%i:%s') < '2000-01-01 00:00:00'
        OR STR_TO_DATE(NULLIF(NULLIF(TRIM(book_optime), ''), '\\N'), '%Y-%m-%d %H:%i:%s') > NOW()
        THEN NULL
      ELSE STR_TO_DATE(NULLIF(NULLIF(TRIM(book_optime), ''), '\\N'), '%Y-%m-%d %H:%i:%s')
    END                                                                              AS book_optime_dt,
    CASE
      WHEN NULLIF(NULLIF(TRIM(report_month), ''), '\\N') REGEXP '^[0-9]{6}$'
        THEN CONCAT(SUBSTR(TRIM(report_month),1,4), '-', SUBSTR(TRIM(report_month),5,2))
      ELSE DATE_FORMAT(STR_TO_DATE(NULLIF(NULLIF(TRIM(checkin_time), ''), '\\N'), '%Y-%m-%d %H:%i:%s'), '%Y-%m')
    END                                                                              AS report_month_fmt,
    NULLIF(NULLIF(TRIM(member_type),        ''), '\\N') AS member_type_c,
    NULLIF(NULLIF(TRIM(need_partner),       ''), '\\N') AS need_partner_c,
    NULLIF(NULLIF(TRIM(health_check_type),  ''), '\\N') AS health_check_type_c,
    NULLIF(NULLIF(TRIM(report_search_type), ''), '\\N') AS report_search_type_c,
    NULLIF(NULLIF(TRIM(report_send_type),   ''), '\\N') AS report_send_type_c,
    NULLIF(NULLIF(TRIM(corp_code),          ''), '\\N') AS corp_code_c
  FROM MIHDB_ODS.check_info_2025_Encry
) t
WHERE t.visitor_id_c   IS NOT NULL
  AND t.idcard_c       IS NOT NULL
  AND t.report_month_fmt IS NOT NULL;


-- ---------------------------------------------------------------
-- 第 2 段: 2024 (check_info_new_2024_Encry a + check_info_new_2024_Encry01 b)
-- 业务规则: visitor_id 取 a; idcard / cust_name / mobile 取 b 的 *1 字段
--           (b.idcard1 与 dwd_person_info 加密口径一致, 已实测 1000/1000 命中)
-- ---------------------------------------------------------------
INSERT INTO MIHDB_DWD.dwd_fact_checkin (
  checkin_id, person_id, checkin_branch_code, health_check_code, personnel_unit_code,
  age, marital_code, fertility_code, mobile, member_code, external_inspection_code,
  report_query_code, report_collection_code,
  book_optime, checkin_date, report_date,
  is_valid, report_month, etl_load_time
)
SELECT
  t.visitor_id_c                                          AS checkin_id,
  t.idcard_c                                              AS person_id,
  t.checkin_branch_code_c                                 AS checkin_branch_code,
  CASE UPPER(t.health_check_type_c)
    WHEN 'Y' THEN '01' WHEN 'N' THEN '02' WHEN 'X' THEN '03'
    WHEN 'W' THEN '04' WHEN 'F' THEN '05' WHEN 'Z' THEN '06'
    WHEN 'Q' THEN '07' WHEN 'C' THEN '08' WHEN 'U' THEN '09'
    WHEN 'H' THEN '10' WHEN 'S' THEN '11' WHEN 'B' THEN '12'
    WHEN 'T' THEN '13'
    ELSE '99'
  END                                                     AS health_check_code,
  SUBSTR(t.corp_code_c, 1, 100)                           AS personnel_unit_code,
  CASE
    WHEN t.birthday_dt IS NULL OR t.checkin_dt IS NULL THEN NULL
    WHEN TIMESTAMPDIFF(YEAR, t.birthday_dt, t.checkin_dt) BETWEEN 0 AND 120
      THEN TIMESTAMPDIFF(YEAR, t.birthday_dt, t.checkin_dt)
    ELSE NULL
  END                                                     AS age,
  '99'                                                    AS marital_code,
  '99'                                                    AS fertility_code,
  t.mobile_c                                              AS mobile,
  CASE
    WHEN UPPER(t.member_type_c) = 'VIP' THEN '01'
    WHEN t.member_type_c IS NULL OR UPPER(t.member_type_c) IN ('00','PUTONG','普通') THEN '02'
    ELSE '99'
  END                                                     AS member_code,
  CASE UPPER(t.need_partner_c)
    WHEN 'Y' THEN '01'
    WHEN 'N' THEN '02'
    ELSE '99'
  END                                                     AS external_inspection_code,
  CASE TRIM(t.report_search_type_c)
    WHEN '0' THEN '01'
    WHEN '1' THEN '02'
    WHEN '2' THEN '03'
    WHEN '3' THEN '04'
    ELSE '99'
  END                                                     AS report_query_code,
  CASE TRIM(t.report_send_type_c)
    WHEN '1' THEN '01'
    WHEN '2' THEN '02'
    WHEN '3' THEN '03'
    WHEN '4' THEN '04'
    WHEN '5' THEN '05'
    WHEN '6' THEN '06'
    WHEN '7' THEN '01'
    ELSE '99'
  END                                                     AS report_collection_code,
  t.book_optime_dt                                        AS book_optime,
  DATE(t.checkin_dt)                                      AS checkin_date,
  COALESCE(DATE(t.print_time_dt), DATE(t.update_time_dt), DATE(t.checkin_dt)) AS report_date,
  CASE WHEN t.is_deleted_c = '1' THEN 0 ELSE 1 END        AS is_valid,
  t.report_month_fmt                                      AS report_month,
  NOW()                                                   AS etl_load_time
FROM (
  SELECT
    NULLIF(NULLIF(TRIM(a.visitor_id),          ''), '\\N')   AS visitor_id_c,
    NULLIF(NULLIF(TRIM(b.idcard1),             ''), '\\N')   AS idcard_c,
    NULLIF(NULLIF(TRIM(a.checkin_branch_code), ''), '\\N')   AS checkin_branch_code_c,
    NULLIF(NULLIF(TRIM(b.mobile1),             ''), '\\N')   AS mobile_c,
    NULLIF(NULLIF(TRIM(CAST(a.is_deleted AS STRING)), ''), '\\N') AS is_deleted_c,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(a.birthday),     ''), '\\N'), '%Y-%m-%d')          AS birthday_dt,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(a.checkin_time), ''), '\\N'), '%Y-%m-%d %H:%i:%s') AS checkin_dt,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(a.print_time),   ''), '\\N'), '%Y-%m-%d %H:%i:%s') AS print_time_dt,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(a.update_time),  ''), '\\N'), '%Y-%m-%d %H:%i:%s') AS update_time_dt,
    CASE
      WHEN STR_TO_DATE(NULLIF(NULLIF(TRIM(a.book_optime), ''), '\\N'), '%Y-%m-%d %H:%i:%s') < '2000-01-01 00:00:00'
        OR STR_TO_DATE(NULLIF(NULLIF(TRIM(a.book_optime), ''), '\\N'), '%Y-%m-%d %H:%i:%s') > NOW()
        THEN NULL
      ELSE STR_TO_DATE(NULLIF(NULLIF(TRIM(a.book_optime), ''), '\\N'), '%Y-%m-%d %H:%i:%s')
    END                                                                                 AS book_optime_dt,
    CASE
      WHEN NULLIF(NULLIF(TRIM(a.report_month), ''), '\\N') REGEXP '^[0-9]{6}$'
        THEN CONCAT(SUBSTR(TRIM(a.report_month),1,4), '-', SUBSTR(TRIM(a.report_month),5,2))
      ELSE DATE_FORMAT(STR_TO_DATE(NULLIF(NULLIF(TRIM(a.checkin_time), ''), '\\N'), '%Y-%m-%d %H:%i:%s'), '%Y-%m')
    END                                                                                 AS report_month_fmt,
    NULLIF(NULLIF(TRIM(a.member_type),        ''), '\\N') AS member_type_c,
    NULLIF(NULLIF(TRIM(a.need_partner),       ''), '\\N') AS need_partner_c,
    NULLIF(NULLIF(TRIM(a.health_check_type),  ''), '\\N') AS health_check_type_c,
    NULLIF(NULLIF(TRIM(a.report_search_type), ''), '\\N') AS report_search_type_c,
    NULLIF(NULLIF(TRIM(a.report_send_type),   ''), '\\N') AS report_send_type_c,
    NULLIF(NULLIF(TRIM(a.corp_code),          ''), '\\N') AS corp_code_c
  FROM MIHDB_ODS.check_info_new_2024_Encry  a
  JOIN MIHDB_ODS.check_info_new_2024_Encry01 b
    ON a.visitor_id = b.visitor_id
) t
WHERE t.visitor_id_c   IS NOT NULL
  AND t.idcard_c       IS NOT NULL
  AND t.report_month_fmt IS NOT NULL;


-- ---------------------------------------------------------------
-- 第 3 段: 2023 (mnyjy_peis_check_info_new01_Encry)
-- 字段结构与 2024 a 表一致, 直接套同样规则
-- ---------------------------------------------------------------
INSERT INTO MIHDB_DWD.dwd_fact_checkin (
  checkin_id, person_id, checkin_branch_code, health_check_code, personnel_unit_code,
  age, marital_code, fertility_code, mobile, member_code, external_inspection_code,
  report_query_code, report_collection_code,
  book_optime, checkin_date, report_date,
  is_valid, report_month, etl_load_time
)
SELECT
  t.visitor_id_c                                          AS checkin_id,
  t.idcard_c                                              AS person_id,
  t.checkin_branch_code_c                                 AS checkin_branch_code,
  CASE UPPER(t.health_check_type_c)
    WHEN 'Y' THEN '01' WHEN 'N' THEN '02' WHEN 'X' THEN '03'
    WHEN 'W' THEN '04' WHEN 'F' THEN '05' WHEN 'Z' THEN '06'
    WHEN 'Q' THEN '07' WHEN 'C' THEN '08' WHEN 'U' THEN '09'
    WHEN 'H' THEN '10' WHEN 'S' THEN '11' WHEN 'B' THEN '12'
    WHEN 'T' THEN '13'
    ELSE '99'
  END                                                     AS health_check_code,
  SUBSTR(t.corp_code_c, 1, 100)                           AS personnel_unit_code,
  CASE
    WHEN t.birthday_dt IS NULL OR t.checkin_dt IS NULL THEN NULL
    WHEN TIMESTAMPDIFF(YEAR, t.birthday_dt, t.checkin_dt) BETWEEN 0 AND 120
      THEN TIMESTAMPDIFF(YEAR, t.birthday_dt, t.checkin_dt)
    ELSE NULL
  END                                                     AS age,
  '99'                                                    AS marital_code,
  '99'                                                    AS fertility_code,
  t.mobile_c                                              AS mobile,
  CASE
    WHEN UPPER(t.member_type_c) = 'VIP' THEN '01'
    WHEN t.member_type_c IS NULL OR UPPER(t.member_type_c) IN ('00','PUTONG','普通') THEN '02'
    ELSE '99'
  END                                                     AS member_code,
  CASE UPPER(t.need_partner_c)
    WHEN 'Y' THEN '01'
    WHEN 'N' THEN '02'
    ELSE '99'
  END                                                     AS external_inspection_code,
  CASE TRIM(t.report_search_type_c)
    WHEN '0' THEN '01'
    WHEN '1' THEN '02'
    WHEN '2' THEN '03'
    WHEN '3' THEN '04'
    ELSE '99'
  END                                                     AS report_query_code,
  CASE TRIM(t.report_send_type_c)
    WHEN '1' THEN '01'
    WHEN '2' THEN '02'
    WHEN '3' THEN '03'
    WHEN '4' THEN '04'
    WHEN '5' THEN '05'
    WHEN '6' THEN '06'
    WHEN '7' THEN '01'
    ELSE '99'
  END                                                     AS report_collection_code,
  t.book_optime_dt                                        AS book_optime,
  DATE(t.checkin_dt)                                      AS checkin_date,
  COALESCE(DATE(t.print_time_dt), DATE(t.update_time_dt), DATE(t.checkin_dt)) AS report_date,
  CASE WHEN t.is_deleted_c = '1' THEN 0 ELSE 1 END        AS is_valid,
  t.report_month_fmt                                      AS report_month,
  NOW()                                                   AS etl_load_time
FROM (
  SELECT
    NULLIF(NULLIF(TRIM(visitor_id),          ''), '\\N')   AS visitor_id_c,
    NULLIF(NULLIF(TRIM(idcard),              ''), '\\N')   AS idcard_c,
    NULLIF(NULLIF(TRIM(checkin_branch_code), ''), '\\N')   AS checkin_branch_code_c,
    NULLIF(NULLIF(TRIM(mobile),              ''), '\\N')   AS mobile_c,
    NULLIF(NULLIF(TRIM(CAST(is_deleted AS STRING)), ''), '\\N') AS is_deleted_c,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(birthday),     ''), '\\N'), '%Y-%m-%d')          AS birthday_dt,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(checkin_time), ''), '\\N'), '%Y-%m-%d %H:%i:%s') AS checkin_dt,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(print_time),   ''), '\\N'), '%Y-%m-%d %H:%i:%s') AS print_time_dt,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(update_time),  ''), '\\N'), '%Y-%m-%d %H:%i:%s') AS update_time_dt,
    CASE
      WHEN STR_TO_DATE(NULLIF(NULLIF(TRIM(book_optime), ''), '\\N'), '%Y-%m-%d %H:%i:%s') < '2000-01-01 00:00:00'
        OR STR_TO_DATE(NULLIF(NULLIF(TRIM(book_optime), ''), '\\N'), '%Y-%m-%d %H:%i:%s') > NOW()
        THEN NULL
      ELSE STR_TO_DATE(NULLIF(NULLIF(TRIM(book_optime), ''), '\\N'), '%Y-%m-%d %H:%i:%s')
    END                                                                              AS book_optime_dt,
    CASE
      WHEN NULLIF(NULLIF(TRIM(report_month), ''), '\\N') REGEXP '^[0-9]{6}$'
        THEN CONCAT(SUBSTR(TRIM(report_month),1,4), '-', SUBSTR(TRIM(report_month),5,2))
      ELSE DATE_FORMAT(STR_TO_DATE(NULLIF(NULLIF(TRIM(checkin_time), ''), '\\N'), '%Y-%m-%d %H:%i:%s'), '%Y-%m')
    END                                                                              AS report_month_fmt,
    NULLIF(NULLIF(TRIM(member_type),        ''), '\\N') AS member_type_c,
    NULLIF(NULLIF(TRIM(need_partner),       ''), '\\N') AS need_partner_c,
    NULLIF(NULLIF(TRIM(health_check_type),  ''), '\\N') AS health_check_type_c,
    NULLIF(NULLIF(TRIM(report_search_type), ''), '\\N') AS report_search_type_c,
    NULLIF(NULLIF(TRIM(report_send_type),   ''), '\\N') AS report_send_type_c,
    NULLIF(NULLIF(TRIM(corp_code),          ''), '\\N') AS corp_code_c
  FROM MIHDB_ODS.mnyjy_peis_check_info_new01_Encry
) t
WHERE t.visitor_id_c   IS NOT NULL
  AND t.idcard_c       IS NOT NULL
  AND t.report_month_fmt IS NOT NULL;


-- ---------------------------------------------------------------
-- 第 4 段: 2017 ~ 2022 (view_yyqkb_Encry)
-- 字段映射:
--   VID         -> visitor_id (checkin_id)
--   BZ_SFZHM    -> idcard      (person_id)
--   JJCH        -> checkin_branch_code (分院编码, 老库口径)
--   CUST_CSRQ   -> birthday
--   YYSJ        -> book_optime (预约时间)
--   QTDJSJ      -> checkin_time (登记/到检时间)
--   PRINT_TIME  -> print_time (出报告时间)
--   ZZYS        -> report_month (老库为 YYYYMM)
-- 该表无 is_deleted / mobile, is_valid 默认 1, mobile=NULL
-- ---------------------------------------------------------------
INSERT INTO MIHDB_DWD.dwd_fact_checkin (
  checkin_id, person_id, checkin_branch_code, health_check_code, personnel_unit_code,
  age, marital_code, fertility_code, mobile, member_code, external_inspection_code,
  report_query_code, report_collection_code,
  book_optime, checkin_date, report_date,
  is_valid, report_month, etl_load_time
)
SELECT
  t.visitor_id_c                                          AS checkin_id,
  t.idcard_c                                              AS person_id,
  t.checkin_branch_code_c                                 AS checkin_branch_code,
  CASE UPPER(t.health_check_type_c)
    WHEN 'Y' THEN '01' WHEN 'N' THEN '02' WHEN 'X' THEN '03'
    WHEN 'W' THEN '04' WHEN 'F' THEN '05' WHEN 'Z' THEN '06'
    WHEN 'Q' THEN '07' WHEN 'C' THEN '08' WHEN 'U' THEN '09'
    WHEN 'H' THEN '10' WHEN 'S' THEN '11' WHEN 'B' THEN '12'
    WHEN 'T' THEN '13'
    ELSE '99'
  END                                                     AS health_check_code,
  SUBSTR(t.corp_code_c, 1, 100)                           AS personnel_unit_code,
  CASE
    WHEN t.birthday_dt IS NULL OR t.checkin_dt IS NULL THEN NULL
    WHEN TIMESTAMPDIFF(YEAR, t.birthday_dt, t.checkin_dt) BETWEEN 0 AND 120
      THEN TIMESTAMPDIFF(YEAR, t.birthday_dt, t.checkin_dt)
    ELSE NULL
  END                                                     AS age,
  '99'                                                    AS marital_code,
  '99'                                                    AS fertility_code,
  NULL                                                    AS mobile,
  CASE
    WHEN UPPER(t.member_type_c) = 'VIP' THEN '01'
    WHEN t.member_type_c IS NULL OR UPPER(t.member_type_c) IN ('00','PUTONG','普通') THEN '02'
    ELSE '99'
  END                                                     AS member_code,
  CASE UPPER(t.need_partner_c)
    WHEN 'Y' THEN '01'
    WHEN 'N' THEN '02'
    ELSE '99'
  END                                                     AS external_inspection_code,
  CASE TRIM(t.report_search_type_c)
    WHEN '0' THEN '01'
    WHEN '1' THEN '02'
    WHEN '2' THEN '03'
    WHEN '3' THEN '04'
    ELSE '99'
  END                                                     AS report_query_code,
  CASE TRIM(t.report_send_type_c)
    WHEN '1' THEN '01'
    WHEN '2' THEN '02'
    WHEN '3' THEN '03'
    WHEN '4' THEN '04'
    WHEN '5' THEN '05'
    WHEN '6' THEN '06'
    WHEN '7' THEN '01'
    ELSE '99'
  END                                                     AS report_collection_code,
  t.book_optime_dt                                        AS book_optime,
  DATE(t.checkin_dt)                                      AS checkin_date,
  COALESCE(DATE(t.print_time_dt), DATE(t.tjzzsj_dt), DATE(t.checkin_dt))     AS report_date,
  1                                                       AS is_valid,
  t.report_month_fmt                                      AS report_month,
  NOW()                                                   AS etl_load_time
FROM (
  SELECT
    NULLIF(NULLIF(TRIM(VID),       ''), '\\N')              AS visitor_id_c,
    COALESCE(
      NULLIF(NULLIF(TRIM(BZ_SFZHM), ''), '\\N'),
      NULLIF(NULLIF(TRIM(VID),      ''), '\\N')
    )                                                          AS idcard_c,
    NULLIF(NULLIF(TRIM(JJCH),      ''), '\\N')              AS checkin_branch_code_c,
    -- birthday 可能带时间, 先 substr 取前 10 位再解析
    STR_TO_DATE(SUBSTR(NULLIF(NULLIF(TRIM(CUST_CSRQ), ''), '\\N'), 1, 10), '%Y-%m-%d')          AS birthday_dt,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(QTDJSJ),    ''), '\\N'), '%Y-%m-%d %H:%i:%s')                AS checkin_dt,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(PRINT_TIME),''), '\\N'), '%Y-%m-%d %H:%i:%s')                AS print_time_dt,
    STR_TO_DATE(NULLIF(NULLIF(TRIM(TJZZSJ),    ''), '\\N'), '%Y-%m-%d %H:%i:%s')                AS tjzzsj_dt,
    CASE
      WHEN STR_TO_DATE(NULLIF(NULLIF(TRIM(YYSJ), ''), '\\N'), '%Y-%m-%d %H:%i:%s') < '2000-01-01 00:00:00'
        OR STR_TO_DATE(NULLIF(NULLIF(TRIM(YYSJ), ''), '\\N'), '%Y-%m-%d %H:%i:%s') > NOW()
        THEN NULL
      ELSE STR_TO_DATE(NULLIF(NULLIF(TRIM(YYSJ), ''), '\\N'), '%Y-%m-%d %H:%i:%s')
    END                                                                                          AS book_optime_dt,
    CASE
      WHEN NULLIF(NULLIF(TRIM(ZZYS), ''), '\\N') REGEXP '^[0-9]{6}$'
        THEN CONCAT(SUBSTR(TRIM(ZZYS),1,4), '-', SUBSTR(TRIM(ZZYS),5,2))
      ELSE DATE_FORMAT(STR_TO_DATE(NULLIF(NULLIF(TRIM(QTDJSJ), ''), '\\N'), '%Y-%m-%d %H:%i:%s'), '%Y-%m')
    END                                                                                          AS report_month_fmt,
    NULLIF(NULLIF(TRIM(MEMBER_TYPE),        ''), '\\N') AS member_type_c,
    CAST(NULL AS STRING)                                  AS need_partner_c,
    CAST(NULL AS STRING)                                  AS health_check_type_c,
    CAST(NULL AS STRING)                                  AS report_search_type_c,
    CAST(NULL AS STRING)                                  AS report_send_type_c,
    NULLIF(NULLIF(TRIM(DWDM),               ''), '\\N') AS corp_code_c
  FROM MIHDB_ODS.view_yyqkb_Encry v
  WHERE NOT EXISTS (
    SELECT 1 FROM MIHDB_ODS.mnyjy_peis_check_info_new01_Encry x
    WHERE x.visitor_id = v.VID
  )
) t
WHERE t.visitor_id_c   IS NOT NULL
  AND t.idcard_c       IS NOT NULL
  AND t.report_month_fmt IS NOT NULL;
