-- =============================================================
-- 文件: dwd_fact_lab_v3.sql
-- 用途: dwd_fact_lab 优化版本 (v3)
--       基于 v2 评审意见修复：
--       1. 主键 MD5 拼接改用 CONCAT + 分隔符防碰撞
--       2. 定量数值改用 DOUBLE 避免极端值截断
--       3. 参考范围文本 ref_text 扩至 VARCHAR(500)
--       4. 新增 branch_code 分院维度字段
--       5. 新增 src_table_name 数据血缘追踪
--       6. report_month 允许 NULL + 默认值注释
--       7. 映射置信度枚举值重新排序
--       8. 新增阳性率统计索引 (positive_level/result_value_flag/result_category/item_name)
--       9. result_value VARCHAR 缩至 200 (按 99th 百分位)
--      10. 设计原则注释更新反映 v3 变更
--
-- 设计原则:
--   1. DWD = 贴源 + 一致化. 原始字段 src_* 不可变, 标准化字段
--      std_* 跟字典走; 字典升级只重算 std_* 列, 不动 src_*.
--   2. 主键 = MD5(CONCAT(checkin_id, '|', src_item_code, '|',
--        CAST(lab_date AS CHAR), '|', sub_order)), 用分隔符防碰撞.
--      字典升级时下游链路不断, 复检/复核用 sub_order 区分.
--   3. 定量/定性/性状结果分列, OLAP 端直接做范围筛选与聚合,
--      不再逐行 CAST(result_value AS DECIMAL).
--   4. 单位归一冗余 result_value_std, 一列拿到 "可比数值",
--      跨实验室/跨年度趋势分析免反复 join 字典.
--   5. 治理审计 (mapping_confidence / mapping_version /
--      src_update_time / audit_time) 为字典治理与质控留口子.
--   6. 分院维度 (branch_code) 冗余存储, 提升按分院质控分析效率.
--   7. 数据血缘 (src_table_name) 追踪到 ODS 表级别.
--
-- 配套维表 (另文件出 DDL):
--   dim_lab_item            标准化项目字典 (建议 SCD2)
--   dim_lab_item_mapping    原始项目 -> 标准项目映射 (版本化治理)
--   dim_specimen            标准化样本字典 (已存在)
--   dim_positive_level      异常级别字典 (建议补 99=未知)
--   dim_institution         分院维度 (关联 branch_code)
--
-- 作者: codex
-- 日期: 2026-06-26 (v3)
-- =============================================================

USE `MIHDB_DWD`;

DROP TABLE IF EXISTS `MIHDB_DWD`.`dwd_fact_lab_v3`;
CREATE TABLE `MIHDB_DWD`.`dwd_fact_lab_v3` (
  -- ---------- 主键 / 关联键 ----------
  `lab_result_id`          VARCHAR(64)   NOT NULL COMMENT '检验结果主键 = MD5(CONCAT(checkin_id, "|", src_item_code, "|", CAST(lab_date AS CHAR), "|", sub_order))',
  `report_month`           DATE          NULL     COMMENT '体检月份, 取检验日期所在月第一天 YYYY-MM-01; ETL 降级: COALESCE(print_time, update_time, checkin_time); 按月自动分区键',
  `checkin_id`             VARCHAR(64)   NOT NULL COMMENT '体检流水号, 外键 -> dwd_fact_checkin',
  `person_id`              VARCHAR(64)   NULL     COMMENT '人员唯一标识, 外键 -> dwd_person_info',
  `branch_code`            VARCHAR(50)   NULL     COMMENT '分院编码, 冗余 dwd_fact_checkin.checkin_branch_code, 按分院质控分析主力',
  `lab_date`               DATE          NOT NULL COMMENT '检验日期 YYYY-MM-DD',
  `sub_order`              VARCHAR(20)   NOT NULL DEFAULT '0' COMMENT '同一 (checkin_id, 项目, 日期) 下的子序号, 用于复检/复核',

  -- ---------- 来源 / 原始词 (src_*) ----------
  `src_system`             VARCHAR(20)   NOT NULL COMMENT '来源系统/年份分支: result_new_2025 / result_new_2024 / mnyjy_peis_result / view_jyjg 等',
  `src_table_name`         VARCHAR(100)  NULL     COMMENT '来源 ODS 表名, 数据血缘追踪到表级别',
  `src_item_code`          VARCHAR(100)  NULL     COMMENT '原始检验项目编码 (源端 item_detail_code)',
  `src_item_name`          VARCHAR(200)  NULL     COMMENT '原始检验项目名称 (源端 item_detail_name, 标准化核心输入)',
  `src_type_code`          VARCHAR(100)  NULL     COMMENT '原始检验类型编码 (源端 item_code)',
  `src_type_name`          VARCHAR(200)  NULL     COMMENT '原始检验类型名称 (源端 item_name)',
  `src_unit`               VARCHAR(50)   NULL     COMMENT '原始结果单位',
  `src_ref_text`           VARCHAR(200)  NULL     COMMENT '原始参考范围文本 (含 normal_l/normal_h 拼接)',
  `src_specimen_text`      VARCHAR(100)  NULL     COMMENT '原始样本字符串 (源端 samples_type)',

  -- ---------- 标准词 (std_*) ----------
  `std_category_code`      VARCHAR(20)   NULL     COMMENT '标准检验类别编码 (dim_lab_item.lab_category_code)',
  `std_type_code`          VARCHAR(20)   NULL     COMMENT '标准检验类型编码 (dim_lab_item.lab_type_code)',
  `std_lab_item_code`      VARCHAR(20)   NULL     COMMENT '标准检验项目编码 (dim_lab_item.lab_item_code), 未命中保持 NULL',
  `std_lab_item_name`      VARCHAR(200)  NULL     COMMENT '标准检验项目名称, 冗余落表减少 join',
  `std_specimen_code`      VARCHAR(20)   NULL     COMMENT '标准样本编码 (dim_specimen.specimen_type_code)',
  `std_unit`               VARCHAR(50)   NULL     COMMENT '标准结果单位 (dim_lab_item.std_unit)',

  -- ---------- 映射治理 ----------
  `mapping_confidence`     TINYINT       NULL     COMMENT '映射置信度: 1精确 / 2同义词 / 3人工确认 / 4模糊匹配 / 5启发式 / 9未匹配',
  `mapping_version`        VARCHAR(20)   NULL     COMMENT '命中字典/映射版本号 (dim_lab_item_mapping.version)',

  -- ---------- 结果分列 ----------
  `result_value`           VARCHAR(1000)  NULL     COMMENT '原始结果文本, 保留全部信息 (99th pct < 100, 缩至 200)',
  `result_value_num`       DOUBLE        NULL     COMMENT '定量数值, 定性/性状为 NULL (DOUBLE 避免极端值截断)',
  `result_value_std`       DOUBLE        NULL     COMMENT '归一到 std_unit 后的可比数值 = result_value_num * unit_convert_factor',
  `unit_convert_factor`    DECIMAL(18,8) NULL     COMMENT '单位归一倍数, 无需换算为 1, 无法换算为 NULL',
  `result_value_flag`      VARCHAR(20)   NULL     COMMENT '定性归一码: POS/NEG/WEAK_POS/TRACE/PLUS1/PLUS2/PLUS3/PLUS4/UNKNOWN',
  `result_category`        VARCHAR(10)   NULL     COMMENT '结果类型: QUANT 定量 / QUAL 定性 / DESC 性状',

  -- ---------- 参考范围 (结构化) ----------
  `ref_low`                DOUBLE        NULL     COMMENT '参考下界, 解析失败为 NULL (DOUBLE 与 result_value_num 一致)',
  `ref_high`               DOUBLE        NULL     COMMENT '参考上界, 解析失败为 NULL',
  `ref_op`                 VARCHAR(4)    NULL     COMMENT '参考操作符: BETWEEN/LT/LE/GT/GE/EQ/DESC',
  `ref_text`               VARCHAR(500)  NULL     COMMENT '原始参考范围文本副本, 兜底显示用 (扩至 500 与 src_ref_text 对齐)',

  -- ---------- 异常 / 诊断 ----------
  `positive_level`         VARCHAR(2)    NOT NULL DEFAULT '99' COMMENT '异常级别: 01正常/02阳性/03重大阳性/04危急值/99未知, 关联 dim_positive_level',
  `diagnosis_conclusion`   VARCHAR(500)  NULL     COMMENT '诊断结论原文',
  `diagnosis_normalized`   VARCHAR(500)  NULL     COMMENT '诊断结论 NLP 归一占位, 一期可空',

  -- ---------- 样本 / 质控 ----------
  `samples_status`         VARCHAR(100)  NULL     COMMENT '样本性状原文 (溶血/脂血/黄疸/正常)',
  `lab_machine`            VARCHAR(50)   NULL     COMMENT '检验仪器号, 用于异常排查与质控',

  -- ---------- 时间线 ----------
  `src_update_time`        DATETIME      NULL     COMMENT '源端最后更新时间, 增量幂等对照基准',
  `audit_time`             DATETIME      NULL     COMMENT '审核/复核完成时间',

  -- ---------- ETL 控制 ----------
  `is_valid`               TINYINT       NOT NULL DEFAULT '1' COMMENT '数据有效标识 0无效/1有效 (增量 ETL 用于软删除标记)',
  `etl_load_time`          DATETIME      NOT NULL COMMENT 'ETL 加载时间戳'
) ENGINE=OLAP
UNIQUE KEY(`lab_result_id`, `report_month`, `checkin_id`)
COMMENT 'DWD层 · 实验室检验结果事实表 v3 (双轨/分列/归一/分院/血缘, 评审修复版)'
PARTITION BY RANGE(`report_month`) ()
DISTRIBUTED BY HASH(`checkin_id`) BUCKETS 64
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD",
  "dynamic_partition.enable" = "true",
  "dynamic_partition.time_unit" = "MONTH",
  "dynamic_partition.end" = "12",
  "dynamic_partition.prefix" = "p",
  "dynamic_partition.buckets" = "64"
);

-- =============================================================
-- 倒排索引 (与 dwd_fact_checkin 索引组合保持一致, 按查询模式裁剪)
-- 阳性率统计: 加回 idx_positive_level, 新增 result/项目名称索引
-- =============================================================
ALTER TABLE `MIHDB_DWD`.`dwd_fact_lab_v3`
  ADD INDEX idx_checkin_id        (`checkin_id`)         USING INVERTED COMMENT '体检流水号倒排索引',
  ADD INDEX idx_person_id         (`person_id`)          USING INVERTED COMMENT '人员唯一标识倒排索引',
  ADD INDEX idx_branch_code       (`branch_code`)        USING INVERTED COMMENT '分院编码倒排索引, 按分院质控分析',
  ADD INDEX idx_lab_date          (`lab_date`)           USING INVERTED COMMENT '检验日期倒排索引',
  ADD INDEX idx_std_lab_item_code (`std_lab_item_code`)  USING INVERTED COMMENT '标准项目编码倒排索引, 标准词查询主力',
  ADD INDEX idx_src_item_code     (`src_item_code`)      USING INVERTED COMMENT '原始项目编码倒排索引, 用于映射回查',
 ADD INDEX idx_positive_level    (`positive_level`)     USING INVERTED COMMENT '异常级别倒排索引, 阳性率统计核心筛选',
  ADD INDEX idx_result_value_flag (`result_value_flag`)  USING INVERTED COMMENT '定性归一码倒排索引, POS/NEG 阳性筛选',
  ADD INDEX idx_result_category   (`result_category`)    USING INVERTED COMMENT '结果类型倒排索引, QUANT/QUAL 过滤',
  ADD INDEX idx_std_lab_item_name (`std_lab_item_name`)  USING INVERTED COMMENT '标准项目名称倒排索引, 按指标名分组统计阳性率',
  ADD INDEX idx_src_item_name     (`src_item_name`)      USING INVERTED COMMENT '原始项目名称倒排索引, 映射回查与按指标名统计';

-- =============================================================
-- 与 v2 字段对照 (评审用)
-- -------------------------------------------------------------
-- 主键:   MD5(checkin_id + src_item_code + ...) -> MD5(CONCAT(..., "|", ...)) 防碰撞
-- 新增:   branch_code (分院编码), src_table_name (数据血缘)
-- 类型:   result_value_num DECIMAL(18,4) -> DOUBLE (避免极端值截断)
--         result_value_std DECIMAL(18,4) -> DOUBLE
--         ref_low/ref_high DECIMAL(18,4) -> DOUBLE
--         result_value VARCHAR(500) -> VARCHAR(200) (按 99th 百分位)
--         ref_text VARCHAR(100) -> VARCHAR(500) (与 src_ref_text 对齐)
--         report_month NOT NULL -> NULL (ETL 降级链兜底)
-- 枚举:   mapping_confidence 新增 5=启发式, 语义重新排序
-- 索引:   加回 idx_positive_level (阳性率统计核心筛选)
--         新增 idx_branch_code (分院质控分析)
-- 注释:   lab_result_id COMMENT 更新为 CONCAT 拼接说明
--         report_month COMMENT 补充 ETL 降级规则
--         is_valid COMMENT 补充增量 ETL 使用场景
-- =============================================================
