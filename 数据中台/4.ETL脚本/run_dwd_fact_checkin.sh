#!/usr/bin/env bash
# =============================================================
# 文件: run_dwd_fact_checkin.sh
# 用途: DolphinScheduler 任务调用入口
#       1. 拷 4.ETL 脚本到 /tmp
#       2. (可选) TRUNCATE 目标表
#       3. 串行执行 4 段 INSERT
#       4. 输出每段后行数 + person_id 命中率，便于 DS 日志监控
#
# DS Shell 任务配置示例:
#   命令:
#     bash ${BIZDATE_BASEDIR:-/opt/dolphinscheduler/resources/default/resources/dwd-etl}/run_dwd_fact_checkin.sh [--truncate]
#   或直接在任务里把 SCRIPT_DIR 写死
#
# 参数:
#   --truncate  灌入前先 TRUNCATE 目标表 (全量模式)
#   (不带参数默认不清表, 依赖 Unique Key + MoW 自动覆盖)
#
# 作者: codex
# 日期: 2026-06-24
# =============================================================
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-/opt/dolphinscheduler/resources/default/resources/dwd-etl}"
SQL_FILE="dwd_fact_checkin_from_ods.sql"

DORIS_HOST="${DORIS_HOST:-192.168.77.38}"
DORIS_PORT="${DORIS_PORT:-9030}"
DORIS_USER="${DORIS_USER:-root}"
DORIS_DB="${DORIS_DB:-MIHDB_DWD}"

MYSQL_CMD="mysql -h ${DORIS_HOST} -P ${DORIS_PORT} -u ${DORIS_USER} --skip-password --database ${DORIS_DB}"

TRUNCATE=false
for arg in "$@"; do
  case "$arg" in
    --truncate) TRUNCATE=true ;;
    *) echo "[WARN] unknown arg: $arg" ;;
  esac
done

echo "==============================================="
echo "DWD ETL: dwd_fact_checkin"
echo "start_time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "SCRIPT_DIR: ${SCRIPT_DIR}"
echo "TRUNCATE  : ${TRUNCATE}"
echo "==============================================="

if [[ ! -f "${SCRIPT_DIR}/${SQL_FILE}" ]]; then
  echo "[FATAL] not found: ${SCRIPT_DIR}/${SQL_FILE}"
  exit 1
fi

if [[ "$TRUNCATE" == "true" ]]; then
  echo "[STEP 0] TRUNCATE dwd_fact_checkin ..."
  ${MYSQL_CMD} -e "TRUNCATE TABLE dwd_fact_checkin;"
fi

# 按 "-- 第 N 段:" 把 SQL 拆 4 份, 全部走变量, 不落盘
SQL_FULL=$(cat "${SCRIPT_DIR}/${SQL_FILE}")

extract_segment() {
  # $1 = 段号 (1~4)
  # 用 sed 从 "-- 第 N 段:" 到下一段标题之前 (不含) 截一段
  local n="$1"
  printf '%s\n' "$SQL_FULL" | sed -n "/^-- 第 ${n} 段:/,/^-- 第 [0-9]\\+ 段:/ {
    /^-- 第 [0-9]\\+ 段:/ { /^-- 第 ${n} 段:/!d; }
    p
  }"
}

for i in 1 2 3 4; do
  echo
  echo "----- 第 ${i} 段 INSERT -----"
  SEG_SQL=$(extract_segment "$i")
  if [[ -z "${SEG_SQL//[[:space:]]/}" ]]; then
    echo "[WARN] 第 ${i} 段为空, 跳过"
    continue
  fi
  t0=$(date +%s)
  echo "$SEG_SQL" | ${MYSQL_CMD}
  t1=$(date +%s)
  rows=$(${MYSQL_CMD} -N -e "SELECT COUNT(*) FROM dwd_fact_checkin;")
  echo "[OK] 第 ${i} 段耗时 $((t1 - t0)) 秒, 当前 dwd_fact_checkin 行数: ${rows}"
done

echo
echo "----- 完成后质控（按年份命中率） -----"
${MYSQL_CMD} -t -e "
SELECT SUBSTR(report_month,1,4) AS yr, COUNT(*) AS cnt
FROM dwd_fact_checkin GROUP BY 1 ORDER BY 1;
SELECT
  SUBSTR(f.report_month,1,4) AS yr,
  COUNT(*) AS total,
  SUM(CASE WHEN p.person_id IS NULL THEN 1 ELSE 0 END) AS orphan
FROM dwd_fact_checkin f
LEFT JOIN dwd_person_info p ON f.person_id = p.person_id
GROUP BY 1 ORDER BY 1;
"

echo "end_time: $(date '+%Y-%m-%d %H:%M:%S')"
