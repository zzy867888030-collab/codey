const fs = require("fs");

const specs = [
  { src: "/Users/zoyoe/.codex/attachments/2e933530-d012-41c7-9e84-26d13f96e34c/pasted-text.txt", out: "2.DDL脚本/jj_comm_jc_result_all_Encry_add_id_migration.sql" },
  { src: "/Users/zoyoe/.codex/attachments/9112bcf0-bdce-40b1-aee2-3c0d7108684d/pasted-text.txt", out: "2.DDL脚本/lis_test_result_all_Encry_add_id_migration.sql" },
];


function extractColumns(createSql) {
  const open = createSql.indexOf('(');
  const close = createSql.indexOf('\n) ENGINE=');
  const body = createSql.slice(open + 1, close);
  return body.split('\n')
    .map(line => line.trim())
    .filter(line => line.startsWith('`'))
    .map(line => line.match(/^`([^`]+)`/)[1]);
}

function extractMonths(createSql) {
  const months = [];
  for (const line of createSql.split('\n')) {
    const part = line.match(/PARTITION p(\d{6})/);
    if (!part) continue;
    const dates = [...line.matchAll(/'([^']+)'/g)].map(m => m[1]);
    if (dates.length >= 2) months.push({ part: part[1], start: dates[0], end: dates[1] });
  }
  return months;
}


for (const spec of specs) {
  const raw = fs.readFileSync(spec.src, 'utf8');
  const table = raw.match(/CREATE TABLE `([^`]+)`/)[1];
  let create = raw.slice(raw.indexOf('CREATE TABLE')).trim().replace(/;\s*$/, '');
  const columns = extractColumns(create);
  const colList = columns.map(col => '`' + col + '`').join(', ');
  const months = extractMonths(create);
  const oldKey = create.match(/DUPLICATE KEY\([^\n]+\)/)[0];

  create = create.replace('CREATE TABLE `' + table + '` (', 'CREATE TABLE IF NOT EXISTS MIHDB_ODS.' + table + '_new (');
  create = create.replace(/^  `/m, '  `id` bigint NOT NULL AUTO_INCREMENT(1) COMMENT "自增主键",\n  `');
  create = create.replace(oldKey, 'DUPLICATE KEY(`id`)');
  create = create.replace(/COMMENT '([^']*)'/, "COMMENT '$1 (带自增id)'");

  let sql = '';
  sql += `-- MIHDB_ODS.${table} add AUTO_INCREMENT id migration\n`;
  sql += `-- 新建 ${table}_new -> 按 part_month 月分区迁移 -> 校验 -> 手动换表。\n`;
  sql += `-- Doris 换表语法：ALTER TABLE db.table RENAME new_table_name; 不要写 RENAME TO。\n`;
  sql += `-- INSERT 不包含 id，Doris AUTO_INCREMENT 自动生成。\n\n`;
  sql += `SHOW TABLES FROM MIHDB_ODS LIKE '${table}%';\n\n`;
  sql += create + ';\n\n';
  sql += '-- Data migration by part_month. Execute month by month for safer recovery.\n';

  for (const month of months) {
    sql += `\n-- ${month.part}\n`;
    sql += `INSERT INTO MIHDB_ODS.${table}_new (${colList})\n`;
    sql += `SELECT ${colList}\n`;
    sql += `FROM MIHDB_ODS.${table}\n`;
    sql += `WHERE part_month >= '${month.start}' AND part_month < '${month.end}';\n`;
  }

  sql += `\n-- Verification: every diff should be 0.\n`;
  sql += `SELECT COALESCE(s.ym, d.ym) AS ym, s.cnt AS src_cnt, d.cnt AS dst_cnt, d.cnt - s.cnt AS diff\n`;
  sql += `FROM (SELECT DATE_FORMAT(part_month, '%Y%m') ym, COUNT(*) cnt FROM MIHDB_ODS.${table} GROUP BY 1) s\n`;
  sql += `LEFT JOIN (SELECT DATE_FORMAT(part_month, '%Y%m') ym, COUNT(*) cnt FROM MIHDB_ODS.${table}_new GROUP BY 1) d ON s.ym = d.ym\n`;
  sql += `ORDER BY ym;\n\n`;
  sql += `SELECT 'src_total', COUNT(*) FROM MIHDB_ODS.${table};\n`;
  sql += `SELECT 'dst_total', COUNT(*) FROM MIHDB_ODS.${table}_new;\n`;
  sql += `SELECT 'id_check', COUNT(*), COUNT(id), SUM(CASE WHEN id IS NULL THEN 1 ELSE 0 END), MIN(id), MAX(id) FROM MIHDB_ODS.${table}_new;\n\n`;
  sql += `-- Rename after verification passes. Keep backup table until business validation finishes.\n`;
  sql += `-- ALTER TABLE MIHDB_ODS.${table} RENAME ${table}_bak;\n`;
  sql += `-- ALTER TABLE MIHDB_ODS.${table}_new RENAME ${table};\n`;

  fs.writeFileSync(spec.out, sql);
  console.log(`${spec.out}: table=${table}, columns=${columns.length}, months=${months.length}`);
}
