-- =====================================================
-- 目标表: MIHDB_DWD.dim_institution
-- 源表:   MIHDB_DICT.dict_branch_info
-- 逻辑:   branch_code -> institution_code
--         branch_name -> institution_name
--         province    -> institution_province
--         city        -> institution_city (自动补"市")
--         province    -> institution_region (大区派生)
--         固定 'Y'    -> is_effective
--         按 branch_code 去重，重复时取 branch_name 最长的一条
-- 作者: codex  日期: 2026-06-25
-- =====================================================

INSERT INTO MIHDB_DWD.dim_institution
(
    institution_code,
    institution_name,
    institution_region,
    institution_province,
    institution_city,
    is_effective
)
SELECT
    s.branch_code  AS institution_code,
    s.branch_name  AS institution_name,
    CASE
        WHEN s.province IN ('北京市','天津市','河北省','山西省','内蒙古自治区') THEN '华北'
        WHEN s.province IN ('辽宁省','吉林省','黑龙江省') THEN '东北'
        WHEN s.province IN ('上海市','江苏省','浙江省','安徽省','福建省','江西省','山东省') THEN '华东'
        WHEN s.province IN ('河南省','湖北省','湖南省') THEN '华中'
        WHEN s.province IN ('广东省','广西壮族自治区','海南省') THEN '华南'
        WHEN s.province IN ('重庆市','四川省','贵州省','云南省','西藏自治区') THEN '西南'
        WHEN s.province IN ('陕西省','甘肃省','青海省','宁夏回族自治区','新疆维吾尔自治区') THEN '西北'
        WHEN s.province IN ('香港特别行政区','澳门特别行政区','台湾省') THEN '港澳台'
        ELSE '未知'
    END AS institution_region,
    s.province AS institution_province,
    CASE
        WHEN s.city IS NULL OR TRIM(s.city) IN ('','\\N') THEN ''
        WHEN s.city LIKE '%市' OR s.city LIKE '%区'
          OR s.city LIKE '%县' OR s.city LIKE '%州'
          OR s.city LIKE '%盟' THEN s.city
        ELSE CONCAT(s.city, '市')
    END AS institution_city,
    'Y' AS is_effective
FROM (
    SELECT
        branch_code,
        branch_name,
        city,
        province,
        ROW_NUMBER() OVER (
            PARTITION BY branch_code
            ORDER BY LENGTH(branch_name) DESC
        ) AS rn
    FROM (
        SELECT DISTINCT
            TRIM(branch_code) AS branch_code,
            TRIM(branch_name) AS branch_name,
            TRIM(city)        AS city,
            TRIM(province)    AS province
        FROM MIHDB_DICT.dict_branch_info
        WHERE branch_code IS NOT NULL
          AND TRIM(branch_code) <> ''
    ) t
) s
WHERE s.rn = 1;
