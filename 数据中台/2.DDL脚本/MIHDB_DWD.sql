-- Auto-generated from 《DWD_体检数据仓库表结构设计_V1.2》.xlsx
-- Database: MIHDB_DWD, replication=2

CREATE DATABASE IF NOT EXISTS `MIHDB_DWD`;
USE `MIHDB_DWD`;

-- ==================== FACT TABLES ====================

-- ----- DWD_人员信息: dwd_person_info -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dwd_person_info`;
CREATE TABLE `MIHDB_DWD`.`dwd_person_info` (
  `person_id` VARCHAR(64) NOT NULL COMMENT '人员唯一标识',
  `person_name` VARCHAR(100) NULL COMMENT '姓名',
  `idcard` VARCHAR(20) NULL COMMENT '身份证号',
  `sex_code` VARCHAR(2) NOT NULL DEFAULT '99' COMMENT '性别',
  `birthday` DATE NOT NULL COMMENT '出生日期',
  `blood_type` VARCHAR(2) NULL COMMENT '血型',
  `nation_code` VARCHAR(2) NOT NULL DEFAULT '99' COMMENT '民族',
  `is_valid` TINYINT NOT NULL DEFAULT '1' COMMENT '数据有效标识',
  `etl_load_time` DATETIME NOT NULL COMMENT 'ETL加载时间'
) ENGINE=OLAP
UNIQUE KEY(`person_id`)
COMMENT 'DWD层 · 人员信息表（dwd_person_info）'
DISTRIBUTED BY HASH(`person_id`) BUCKETS 32
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- DWD_体检登记: dwd_fact_checkin -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dwd_fact_checkin`;
CREATE TABLE `MIHDB_DWD`.`dwd_fact_checkin` (
  `checkin_id` VARCHAR(64) NOT NULL COMMENT '体检流水号',
  `person_id` VARCHAR(64) NOT NULL COMMENT '人员唯一标识',
  `checkin_branch_code` VARCHAR(50) NULL COMMENT '到检分院编码',
  `health_check_code` VARCHAR(2) NULL COMMENT '体检类别',
  `personnel_unit_code` VARCHAR(100) NULL COMMENT '体检人员单位',
  `age` TINYINT NULL COMMENT '年龄（体检时）',
  `marital_code` VARCHAR(2) NOT NULL DEFAULT '99' COMMENT '婚姻状况',
  `fertility_code` VARCHAR(2) NOT NULL DEFAULT '99' COMMENT '生育情况',
  `mobile` VARCHAR(128) NULL COMMENT '手机号码（密文，2026-06-24 由 20 扩到 128）',
  `member_code` VARCHAR(2) NULL DEFAULT '02' COMMENT '会员类型',
  `external_inspection_code` VARCHAR(2) NULL DEFAULT 'N' COMMENT '是否外送检验（2026-06-24 由 VARCHAR(1) 扩到 VARCHAR(2)，与 dim_external_inspection 字典 01/02/99 对齐）',
  `report_query_code` VARCHAR(2) NULL DEFAULT '01' COMMENT '报告查询方式',
  `report_collection_code` VARCHAR(2) NULL DEFAULT '01' COMMENT '报告领取方式',
  `book_optime` DATETIME NULL COMMENT '预约时间',
  `checkin_date` DATE NULL COMMENT '体检日期',
  `report_date` DATE NULL COMMENT '出报告日期',
  `is_valid` TINYINT NOT NULL DEFAULT '1' COMMENT '数据有效标识',
  `report_month` VARCHAR(7) NOT NULL COMMENT '数据月份分区',
  `etl_load_time` DATETIME NOT NULL COMMENT 'ETL加载时间'
) ENGINE=OLAP
UNIQUE KEY(`checkin_id`)
COMMENT 'DWD层 · 体检登记事实表（dwd_fact_checkin）'
DISTRIBUTED BY HASH(`checkin_id`) BUCKETS 32
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- DWD_实验室检验结果: dwd_fact_lab -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dwd_fact_lab`;
CREATE TABLE `MIHDB_DWD`.`dwd_fact_lab` (
  `lab_result_id` VARCHAR(64) NOT NULL COMMENT '检验结果主键',
  `checkin_id` VARCHAR(64) NOT NULL COMMENT '体检流水号',
  `person_id` VARCHAR(64) NULL COMMENT '人员唯一标识',
  `lab_date` DATE NOT NULL COMMENT '检验日期',
  `lab_type_code` VARCHAR(100) NULL COMMENT '检项编码',
  `lab_item_code` VARCHAR(100) NULL COMMENT '细项编码',
  `result_value` VARCHAR(500) NULL COMMENT '检验结果值',
  `result_category` VARCHAR(50) NULL COMMENT '检验结果值类型',
  `unit` VARCHAR(50) NULL COMMENT '结果单位',
  `result_ref` VARCHAR(100) NULL COMMENT '参考范围',
  `positive_level` TINYINT NULL DEFAULT '01' COMMENT '异常级别',
  `diagnosis_conclusion` VARCHAR(500) NULL COMMENT '诊断结论',
  `specimen_type_code` VARCHAR(100) NULL COMMENT '样本类型',
  `samples_status` VARCHAR(100) NULL COMMENT '样本性状',
  `is_valid` TINYINT NOT NULL DEFAULT '1' COMMENT '数据有效标识',
  `report_month` VARCHAR(7) NOT NULL COMMENT '数据月份分区',
  `etl_load_time` DATETIME NOT NULL COMMENT 'ETL加载时间'
) ENGINE=OLAP
UNIQUE KEY(`lab_result_id`)
COMMENT 'DWD层 · 实验室检验结果事实表（dwd_fact_lab）'
DISTRIBUTED BY HASH(`lab_result_id`) BUCKETS 32
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- DWD_体格、影像与功能检查: dwd_fact_exam -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dwd_fact_exam`;
CREATE TABLE `MIHDB_DWD`.`dwd_fact_exam` (
  `exam_result_id` VARCHAR(64) NOT NULL COMMENT '检查结果主键',
  `checkin_id` VARCHAR(64) NOT NULL COMMENT '体检流水号',
  `person_id` VARCHAR(64) NULL COMMENT '人员唯一标识',
  `exam_date` DATE NOT NULL COMMENT '检查日期',
  `exam_type_code` VARCHAR(100) NULL COMMENT '检项编码',
  `exam_item_code` VARCHAR(100) NULL COMMENT '细项编码',
  `result_text` STRING NULL COMMENT '检查描述',
  `result_value` VARCHAR(100) NULL COMMENT '检查结果',
  `unit` VARCHAR(50) NULL COMMENT '结果单位',
  `result_ref` VARCHAR(100) NULL COMMENT '参考范围',
  `positive_level` TINYINT NULL DEFAULT '01' COMMENT '异常级别',
  `diagnosis_conclusion` VARCHAR(500) NULL COMMENT '诊断结论',
  `lis_report_id` VARCHAR(100) NULL COMMENT '图文报告ID',
  `is_valid` TINYINT NOT NULL DEFAULT '1' COMMENT '数据有效标识',
  `report_month` VARCHAR(7) NOT NULL COMMENT '数据月份分区',
  `etl_load_time` DATETIME NOT NULL COMMENT 'ETL加载时间'
) ENGINE=OLAP
UNIQUE KEY(`exam_result_id`)
COMMENT 'DWD层 · 体格、影像与功能检查结果事实表（dwd_fact_exam）'
DISTRIBUTED BY HASH(`exam_result_id`) BUCKETS 32
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- DWD_问卷信息: dwd_fact_questionnaire -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dwd_fact_questionnaire`;
CREATE TABLE `MIHDB_DWD`.`dwd_fact_questionnaire` (
  `questionnaire_result_id` VARCHAR(64) NOT NULL COMMENT '问卷结果主键',
  `checkin_id` VARCHAR(64) NOT NULL COMMENT '体检流水号',
  `questionnaire_code` VARCHAR(100) NULL COMMENT '问卷编码',
  `asq_code` VARCHAR(100) NULL COMMENT '问题编码',
  `asq_name` VARCHAR(200) NULL COMMENT '问题名称',
  `asq_type` VARCHAR(50) NULL COMMENT '问题类型',
  `asq_group` VARCHAR(100) NULL COMMENT '问题分组',
  `option_code` VARCHAR(100) NULL COMMENT '选项编码',
  `option_name` VARCHAR(200) NULL COMMENT '选项名称',
  `text_value` VARCHAR(300) NULL COMMENT '文本填写值',
  `numeric_value` DECIMAL(18,4) NULL COMMENT '数值答案',
  `create_at` DATETIME NULL COMMENT '创建时间',
  `update_at` DATETIME NULL COMMENT '更新时间',
  `is_valid` TINYINT NOT NULL DEFAULT '1' COMMENT '数据有效标识',
  `etl_load_time` DATETIME NOT NULL COMMENT 'ETL加载时间'
) ENGINE=OLAP
UNIQUE KEY(`questionnaire_result_id`)
COMMENT 'DWD层 · 问卷结果事实表（dwd_fact_questionnaire）'
DISTRIBUTED BY HASH(`questionnaire_result_id`) BUCKETS 32
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- DWD_随访信息: dwd_fact_followup -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dwd_fact_followup`;
CREATE TABLE `MIHDB_DWD`.`dwd_fact_followup` (
  `followup_id` VARCHAR(64) NOT NULL COMMENT '随访记录主键',
  `checkin_id` VARCHAR(64) NOT NULL COMMENT '体检流水号',
  `person_id` VARCHAR(64) NULL COMMENT '人员唯一标识',
  `visit_time` DATETIME NULL COMMENT '随访时间',
  `next_visit_time` DATETIME NULL COMMENT '下次随访时间',
  `status` TINYINT NULL DEFAULT '0' COMMENT '随访状态',
  `visit_record` VARCHAR(3000) NULL COMMENT '随访记录内容',
  `complete_flag` TINYINT NULL DEFAULT '0' COMMENT '完成标识',
  `call_status` VARCHAR(50) NULL COMMENT '回访状态',
  `major_visit_uid` VARCHAR(100) NULL COMMENT '主随访人ID',
  `diagnosis_name` VARCHAR(300) NULL COMMENT '诊断名称',
  `remark` VARCHAR(300) NULL COMMENT '备注',
  `is_valid` TINYINT NOT NULL DEFAULT '1' COMMENT '数据有效标识',
  `etl_load_time` DATETIME NOT NULL COMMENT 'ETL加载时间'
) ENGINE=OLAP
UNIQUE KEY(`followup_id`)
COMMENT 'DWD层 · 随访记录事实表（dwd_fact_followup）'
DISTRIBUTED BY HASH(`followup_id`) BUCKETS 32
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- DWD_计算指标: dwd_calc_indicator -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dwd_calc_indicator`;
CREATE TABLE `MIHDB_DWD`.`dwd_calc_indicator` (
  `calc_indicator_id` VARCHAR(64) NOT NULL COMMENT '计算指标主键',
  `checkin_id` VARCHAR(64) NOT NULL COMMENT '体检流水号',
  `person_id` VARCHAR(64) NULL COMMENT '人员唯一标识',
  `checkin_date` DATE NOT NULL COMMENT '体检日期',
  `indicator_type_code` VARCHAR(100) NULL COMMENT '指标类型编码',
  `indicator_item_code` VARCHAR(100) NULL COMMENT '指标编码',
  `result_ref` VARCHAR(100) NULL COMMENT '参考范围',
  `result_value` VARCHAR(100) NULL COMMENT '计算结果',
  `unit` VARCHAR(50) NULL COMMENT '结果单位',
  `positive_level` TINYINT NULL DEFAULT '01' COMMENT '异常级别',
  `diagnosis_conclusion` VARCHAR(500) NULL COMMENT '诊断结论',
  `is_valid` TINYINT NOT NULL DEFAULT '1' COMMENT '数据有效标识',
  `report_month` VARCHAR(7) NOT NULL COMMENT '数据月份分区',
  `etl_load_time` DATETIME NOT NULL COMMENT 'ETL加载时间'
) ENGINE=OLAP
UNIQUE KEY(`calc_indicator_id`)
COMMENT 'DWD层 · 计算指标表（dwd_calc_indicator）'
DISTRIBUTED BY HASH(`calc_indicator_id`) BUCKETS 32
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- DWD_明细标签: dwd_calc_label -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dwd_calc_label`;
CREATE TABLE `MIHDB_DWD`.`dwd_calc_label` (
  `label_id` VARCHAR(64) NOT NULL COMMENT '标签主键',
  `checkin_id` VARCHAR(64) NOT NULL COMMENT '体检流水号',
  `person_id` VARCHAR(64) NULL COMMENT '人员唯一标识',
  `checkin_date` DATE NOT NULL COMMENT '体检日期',
  `label_type_code` VARCHAR(100) NULL COMMENT '标签类型编码',
  `label_item_code` VARCHAR(100) NULL COMMENT '标签编码',
  `result_value` TINYINT NULL DEFAULT '0' COMMENT '标签结果',
  `is_valid` TINYINT NOT NULL DEFAULT '1' COMMENT '数据有效标识',
  `report_month` VARCHAR(7) NOT NULL COMMENT '数据月份分区',
  `etl_load_time` DATETIME NOT NULL COMMENT 'ETL加载时间'
) ENGINE=OLAP
UNIQUE KEY(`label_id`)
COMMENT 'DWD层 · 人员体检标签表（dwd_calc_label）'
DISTRIBUTED BY HASH(`label_id`) BUCKETS 32
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ==================== DIM TABLES ====================

-- ----- 维度表_日期: dim_date -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_date`;
CREATE TABLE `MIHDB_DWD`.`dim_date` (
  `date_id` INT NOT NULL COMMENT '日期ID，主键（YYYYMMDD）',
  `date_value` DATE NOT NULL COMMENT '日期值（yyyy-MM-dd）',
  `year_num` INT NOT NULL COMMENT '年份（2025）',
  `month_num` INT NOT NULL COMMENT '月份（1-12）',
  `day_num` INT NOT NULL COMMENT '日期（1-31）',
  `quarter_num` INT NOT NULL COMMENT '季度（1-4）',
  `week_num` INT NOT NULL COMMENT '一年中第几周',
  `week_day_num` INT NOT NULL COMMENT '星期几（1=周一，7=周日）',
  `year_month` VARCHAR(7) NOT NULL COMMENT '年月（2025-03）',
  `year_quarter` VARCHAR(8) NOT NULL COMMENT '年季度（2025-Q1）',
  `is_weekend` TINYINT NOT NULL COMMENT '是否周末（1=是，0=否）',
  `is_holiday` TINYINT NOT NULL COMMENT '是否法定节假日（1=是）',
  `holiday_name` VARCHAR(60) NOT NULL COMMENT '节假日名称',
  `date_desc` VARCHAR(60) NOT NULL COMMENT '日期描述（2025年03月30日）',
  `week_day_name` VARCHAR(30) NOT NULL COMMENT '星期名称（星期一、星期日）'
) ENGINE=OLAP
UNIQUE KEY(`date_id`)
COMMENT 'dim_date · 日期字典'
DISTRIBUTED BY HASH(`date_id`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_性别: dim_sex -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_sex`;
CREATE TABLE `MIHDB_DWD`.`dim_sex` (
  `sex_code` VARCHAR(64) NOT NULL COMMENT '代码值(sex_code)',
  `sex_name` VARCHAR(200) NULL COMMENT '代码含义(sex_name)',
  `sex_desc` VARCHAR(500) NULL COMMENT '说明(sex_desc)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`sex_code`)
COMMENT 'dim_sex · 性别字典'
DISTRIBUTED BY HASH(`sex_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_婚姻: dim_marital -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_marital`;
CREATE TABLE `MIHDB_DWD`.`dim_marital` (
  `marital_code` VARCHAR(64) NOT NULL COMMENT '代码值(marital_code)',
  `marital_name` VARCHAR(200) NULL COMMENT '代码含义(marital_name)',
  `marital_desc` VARCHAR(500) NULL COMMENT '说明(marital_desc)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`marital_code`)
COMMENT 'dim_marital · 婚姻状况字典'
DISTRIBUTED BY HASH(`marital_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_生育: dim_fertility -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_fertility`;
CREATE TABLE `MIHDB_DWD`.`dim_fertility` (
  `fertility_code` VARCHAR(64) NOT NULL COMMENT '代码值(fertility_code)',
  `fertility_name` VARCHAR(200) NULL COMMENT '代码含义(fertility_name)',
  `fertility_desc` VARCHAR(500) NULL COMMENT '说明(fertility_desc)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`fertility_code`)
COMMENT 'dim_fertility · 生育情况字典'
DISTRIBUTED BY HASH(`fertility_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_民族: dim_nation -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_nation`;
CREATE TABLE `MIHDB_DWD`.`dim_nation` (
  `nation_code` VARCHAR(64) NOT NULL COMMENT '代码值(nation_code)',
  `nation_name` VARCHAR(200) NULL COMMENT '代码含义(nation_name)',
  `nation_abbreviation` VARCHAR(64) NULL COMMENT '字母代码(nation_abbreviation)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`nation_code`)
COMMENT 'dim_nation · 民族字典（GB 3304-1991）'
DISTRIBUTED BY HASH(`nation_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_年龄段: dim_age -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_age`;
CREATE TABLE `MIHDB_DWD`.`dim_age` (
  `age` VARCHAR(64) NOT NULL COMMENT '年龄值(age)',
  `age_desc` VARCHAR(500) NULL COMMENT '年龄描述(age_desc)',
  `age_group_code` VARCHAR(64) NULL COMMENT '分组代码(age_group_code)',
  `age_group_name` VARCHAR(200) NULL COMMENT '分组名称(age_group_name)',
  `age_interval` VARCHAR(64) NULL COMMENT '区间(age_interval)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`age`)
COMMENT 'dim_age · 年龄段字典'
DISTRIBUTED BY HASH(`age`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_体检机构: dim_institution -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_institution`;
CREATE TABLE `MIHDB_DWD`.`dim_institution` (
  `institution_code` VARCHAR(64) NOT NULL COMMENT '代码值(institution_code)',
  `institution_name` VARCHAR(200) NULL COMMENT '代码含义(institution_name)',
  `institution_region` VARCHAR(64) NULL COMMENT '区域(institution_region)',
  `institution_province` VARCHAR(64) NULL COMMENT '省份(institution_province)',
  `institution_city` VARCHAR(64) NULL COMMENT '城市(institution_city)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`institution_code`)
COMMENT 'dim_institution · 体检机构字典（示例数据，需根据实际机构补全）'
DISTRIBUTED BY HASH(`institution_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_体检类别: dim_health_check_type -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_health_check_type`;
CREATE TABLE `MIHDB_DWD`.`dim_health_check_type` (
  `health_check_code` VARCHAR(64) NOT NULL COMMENT '代码值(health_check_code)',
  `health_check_name` VARCHAR(200) NULL COMMENT '代码含义(health_check_name)',
  `health_check_desc` VARCHAR(500) NULL COMMENT '说明(health_check_desc)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`health_check_code`)
COMMENT 'dim_health_check_type · 体检类别字典'
DISTRIBUTED BY HASH(`health_check_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_体检人员单位: dim_personnel_unit -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_personnel_unit`;
CREATE TABLE `MIHDB_DWD`.`dim_personnel_unit` (
  `personnel_unit_code` VARCHAR(64) NOT NULL COMMENT '代码值(personnel_unit_code)',
  `personnel_unit_name` VARCHAR(200) NULL COMMENT '代码含义(personnel_unit_name)',
  `profession` VARCHAR(64) NULL COMMENT '职业(profession)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`personnel_unit_code`)
COMMENT 'dim_personnel_unit · 体检人员单位字典（示例数据，需根据实际补全）'
DISTRIBUTED BY HASH(`personnel_unit_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_外送检验: dim_external_inspection -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_external_inspection`;
CREATE TABLE `MIHDB_DWD`.`dim_external_inspection` (
  `external_inspection_code` VARCHAR(64) NOT NULL COMMENT '代码值(external_inspection_code)',
  `external_inspection_name` VARCHAR(200) NULL COMMENT '代码含义(external_inspection_name)',
  `external_inspection_desc` VARCHAR(500) NULL COMMENT '说明(external_inspection_desc)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`external_inspection_code`)
COMMENT 'dim_external_inspection · 外送检验字典'
DISTRIBUTED BY HASH(`external_inspection_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_会员类型: dim_member -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_member`;
CREATE TABLE `MIHDB_DWD`.`dim_member` (
  `member_code` VARCHAR(64) NOT NULL COMMENT '代码值(member_code)',
  `member_name` VARCHAR(200) NULL COMMENT '代码含义(member_name)',
  `member_desc` VARCHAR(500) NULL COMMENT '说明(member_desc)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`member_code`)
COMMENT 'dim_member · 体检会员字典'
DISTRIBUTED BY HASH(`member_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_报告查询: dim_report_query -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_report_query`;
CREATE TABLE `MIHDB_DWD`.`dim_report_query` (
  `report_query_code` VARCHAR(64) NOT NULL COMMENT '代码值(report_query_code)',
  `report_query_name` VARCHAR(200) NULL COMMENT '代码含义(report_query_name)',
  `report_query_desc` VARCHAR(500) NULL COMMENT '说明(report_query_desc)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`report_query_code`)
COMMENT 'dim_report_query · 报告网络查询类型字典'
DISTRIBUTED BY HASH(`report_query_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_报告领取: dim_report_collection -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_report_collection`;
CREATE TABLE `MIHDB_DWD`.`dim_report_collection` (
  `report_collection_code` VARCHAR(64) NOT NULL COMMENT '代码值(report_collection_code)',
  `report_collection_name` VARCHAR(200) NULL COMMENT '代码含义(report_collection_name)',
  `report_collection_desc` VARCHAR(500) NULL COMMENT '说明(report_collection_desc)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`report_collection_code`)
COMMENT 'dim_report_collection · 报告领取方式字典'
DISTRIBUTED BY HASH(`report_collection_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_检验项目: dim_lab_item (原始词->标化词映射, 见 2.DDL脚本/dim_lab_item.sql) -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_lab_item`;
CREATE TABLE `MIHDB_DWD`.`dim_lab_item` (
  `mapping_id` VARCHAR(32) NOT NULL COMMENT '映射主键, MD5(原始三元组)',
  `raw_item_name` VARCHAR(128) NOT NULL COMMENT '原始大项名称',
  `raw_item_detail_name` VARCHAR(128) NULL COMMENT '原始细项名称',
  `raw_specimen_name` VARCHAR(32) NULL COMMENT '原始标本名称',
  `lab_level1_category` VARCHAR(64) NULL COMMENT '一级分类',
  `lab_level2_category` VARCHAR(64) NULL COMMENT '二级分类',
  `standard_name` VARCHAR(128) NULL COMMENT '归一标化名称',
  `item_detail_code` VARCHAR(32) NULL COMMENT '细项标化编码',
  `lab_level1_code` VARCHAR(16) NULL COMMENT '一级分类编码',
  `lab_level2_code` VARCHAR(32) NULL COMMENT '二级分类编码',
  `related_diseases` VARCHAR(256) NULL COMMENT '主要相关疾病',
  `related_disease_systems` VARCHAR(128) NULL COMMENT '疾病系统',
  `is_effective` VARCHAR(1) NULL DEFAULT '0' COMMENT '是否有效: 0有效/1无效',
  `etl_load_time` DATETIME NOT NULL COMMENT 'ETL加载时间'
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


-- ----- 维度表_检验样本: dim_specimen_item -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_specimen_item`;
CREATE TABLE `MIHDB_DWD`.`dim_specimen_item` (
  `specimen_item_code` VARCHAR(64) NOT NULL COMMENT '样本子项名称',
  `specimen_category_code` VARCHAR(64) NULL COMMENT '标本类别代码',
  `specimen_category_name` VARCHAR(200) NULL COMMENT '样本类别名称',
  `specimen_type_code` VARCHAR(64) NULL COMMENT '样本类型代码',
  `specimen_type_name` VARCHAR(200) NULL COMMENT '样本类型名称',
  `specimen_item_name` VARCHAR(200) NULL COMMENT '样本子项名称',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效'
) ENGINE=OLAP
UNIQUE KEY(`specimen_item_code`)
COMMENT 'dim_specimen_item· 检验样本字典（以下数据为示例数据，需根据标准进行完善）'
DISTRIBUTED BY HASH(`specimen_item_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_检查项目: dim_exam_item -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_exam_item`;
CREATE TABLE `MIHDB_DWD`.`dim_exam_item` (
  `exam_item_code` VARCHAR(64) NOT NULL COMMENT '检查项目代码',
  `exam_category_code` VARCHAR(64) NULL COMMENT '检查类别代码',
  `exam_category_name` VARCHAR(200) NULL COMMENT '检查类别名称',
  `exam_type_code` VARCHAR(64) NULL COMMENT '检查类型代码',
  `exam_type_name` VARCHAR(200) NULL COMMENT '检查类型名称',
  `exam_item_name` VARCHAR(200) NULL COMMENT '检查项目名称',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`exam_item_code`)
COMMENT 'dim_exam_item · 检查项目字典（以下数据为示例数据，需根据标准进行完善）'
DISTRIBUTED BY HASH(`exam_item_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_异常级别: dim_positive_level -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_positive_level`;
CREATE TABLE `MIHDB_DWD`.`dim_positive_level` (
  `positive_level_code` VARCHAR(64) NOT NULL COMMENT '代码值(positive_level_code)',
  `positive_level_name` VARCHAR(200) NULL COMMENT '代码含义(positive_level_name)',
  `positive_level_desc` VARCHAR(500) NULL COMMENT '说明(positive_level_desc)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`positive_level_code`)
COMMENT 'dim_positive_level · 结果异常级别字典'
DISTRIBUTED BY HASH(`positive_level_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);


-- ----- 维度表_随访状态: dim_visit_status -----
DROP TABLE IF EXISTS `MIHDB_DWD`.`dim_visit_status`;
CREATE TABLE `MIHDB_DWD`.`dim_visit_status` (
  `visit_status_code` VARCHAR(64) NOT NULL COMMENT '代码值(visit_status_code)',
  `visit_status_name` VARCHAR(200) NULL COMMENT '代码含义(visit_status_name)',
  `visit_status_desc` VARCHAR(500) NULL COMMENT '说明(visit_status_desc)',
  `is_effective` VARCHAR(1) NULL COMMENT '是否有效(is_effective)'
) ENGINE=OLAP
UNIQUE KEY(`visit_status_code`)
COMMENT 'dim_visit_status · 随访状态字典'
DISTRIBUTED BY HASH(`visit_status_code`) BUCKETS 4
PROPERTIES (
  "replication_num" = "2",
  "enable_unique_key_merge_on_write" = "true",
  "compression" = "ZSTD"
);
