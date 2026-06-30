from flask import Flask, render_template_string, request, session
import paramiko
import traceback

app = Flask(__name__)
app.secret_key = "local_ssh_db_tool_2026_v2"

# 数据库类型映射
DB_TYPE_MAP = {
    "doris": "Apache Doris",
    "mysql": "MySQL",
    "clickhouse": "ClickHouse"
}
# 全局超时：单位秒（大查询可调大）
EXEC_TIMEOUT = 600
# 默认查询条数
DEFAULT_LIMIT = 200

# 默认连接配置
DEFAULT_CFG = {
    # SSH 跳板机
    "ssh_host": "data-process",
    "ssh_port": 22,
    "ssh_user": "mnyjy",
    "ssh_pwd": "",
    # 目标数据库
    "db_type": "doris",
    "db_host": "192.168.77.38",
    "db_port": 9030,
    "db_user": "root",
    "db_pwd": "",
    "db_name": "MIHDB_DICT",
    # 库表浏览选中项
    "curr_db": "",
    "curr_table": ""
}

# ====================== 工具函数 ======================
def build_db_shell_cmd(cfg, sql):
    """拼接跳板机执行的数据库客户端命令，自动转义+反引号包裹标识符"""
    db_type = cfg["db_type"]
    db_host = cfg["db_host"]
    db_port = str(cfg["db_port"])
    db_user = cfg["db_user"]
    db_pwd = cfg["db_pwd"]
    db_name = cfg["db_name"]

    # Shell特殊字符转义
    safe_sql = sql.replace('"', '\\"')

    if db_type in ("doris", "mysql"):
        cmd_parts = [f"mysql -h{db_host} -P{db_port} -u{db_user}"]
        if db_pwd.strip():
            cmd_parts.append(f'-p{db_pwd}')
        cmd_parts.append(f'-D{db_name} -e "{safe_sql}" --default-character-set=utf8mb4')
        return " ".join(cmd_parts)

    elif db_type == "clickhouse":
        cmd_parts = [f"clickhouse-client -h {db_host} --port {db_port} -u {db_user}"]
        if db_pwd.strip():
            cmd_parts.append(f"--password {db_pwd}")
        cmd_parts.append(f"-d {db_name} -q \"{safe_sql}\"")
        return " ".join(cmd_parts)
    else:
        raise Exception("不支持的数据库类型")


def ssh_exec(ssh_cfg, cmd, timeout):
    """本地SSH连接跳板机执行命令"""
    ssh_client = paramiko.SSHClient()
    ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh_client.connect(
            hostname=ssh_cfg["ssh_host"],
            port=int(ssh_cfg["ssh_port"]),
            username=ssh_cfg["ssh_user"],
            password=ssh_cfg["ssh_pwd"],
            timeout=15
        )
        stdin, stdout, stderr = ssh_client.exec_command(cmd, timeout=timeout)
        out = stdout.read().decode("utf-8", errors="ignore")
        err = stderr.read().decode("utf-8", errors="ignore")
        return out, err
    finally:
        ssh_client.close()


def parse_result(output):
    """解析命令行输出为 表头 + 数据行"""
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if not lines:
        return [], []
    columns = []
    rows = []
    if len(lines) >= 2 and all(c in "-+" for c in lines[1]):
        columns = [col.strip() for col in lines[0].split("\t")]
        for line in lines[2:]:
            rows.append([cell.strip() for cell in line.split("\t")])
    else:
        col_cnt = len(lines[0].split("\t")) if lines else 0
        columns = [f"字段{i+1}" for i in range(col_cnt)]
        for line in lines:
            rows.append([cell.strip() for cell in line.split("\t")])
    return columns, rows


def get_meta_sql(db_type, action, target_db=""):
    """根据库类型，生成 查询库/查询表 的元数据SQL"""
    if action == "list_db":
        return "SHOW DATABASES;"
    elif action == "list_table":
        if db_type in ("doris", "mysql"):
            return f"USE `{target_db}`; SHOW TABLES;"
        elif db_type == "clickhouse":
            return f"SHOW TABLES FROM `{target_db}`;"
    return ""

# ====================== 前端页面模板 ======================
HTML_TPL = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title>SSH远程数据库查询工具(库表浏览版)</title>
    <style>
        body {margin: 20px; font-family: "Microsoft Yahei", sans-serif; font-size: 14px;}
        /* 顶部导航 */
        .nav {margin-bottom: 20px;}
        .nav button {
            padding: 8px 20px; margin-right: 8px;
            background: #e8e8e8; border: none; border-radius: 4px;
            cursor: pointer; font-size: 14px;
        }
        .nav button.active {background: #2d8cf0; color: #fff;}
        /* 功能区块 */
        .block {display: none;}
        .block.show {display: block;}
        /* 通用样式 */
        .box {border: 1px solid #ccc; padding: 15px; border-radius: 6px; margin-bottom: 15px;}
        .row {margin: 8px 0;}
        label {display: inline-block; width: 110px; text-align: right; margin-right: 8px;}
        input, select {padding: 5px; width: 220px; font-size: 14px;}
        textarea {width: 98%; height: 240px; padding: 8px; box-sizing: border-box; font-size: 14px;}
        .btn {padding: 6px 20px; cursor: pointer; background: #2d8cf0; color: #fff; border: none; border-radius: 4px; font-size: 14px;}
        .error {color: #f53f3f; margin: 10px 0; white-space: pre-wrap;}
        .tip {color: #666; font-size: 12px;}
        /* 库表布局 */
        .db-table-wrap {display: flex; gap: 30px;}
        .list-box {width: 300px; height: 400px; border: 1px solid #eee; padding: 10px; overflow-y: auto;}
        .list-item {padding: 4px 8px; margin: 2px 0; cursor: pointer; border-radius: 2px;}
        .list-item:hover {background: #f0f7ff;}
        .list-item.active {background: #2d8cf0; color: #fff;}
        /* 结果表格 */
        table {border-collapse: collapse; width: 100%; margin-top: 15px;}
        th, td {border: 1px solid #ccc; padding: 6px 10px; text-align: center;}
        th {background: #f2f3f5;}
        h3 {margin-top: 0; color: #333;}
    </style>
</head>
<body>
    <h2>SSH跳板数据库查询工具</h2>
    <!-- 顶部导航菜单 -->
    <div class="nav">
        <button class="{{'active' if tab=='config' else ''}}" onclick="switchTab('config')">连接配置</button>
        <button class="{{'active' if tab=='meta' else ''}}" onclick="switchTab('meta')">库表浏览</button>
        <button class="{{'active' if tab=='sql' else ''}}" onclick="switchTab('sql')">SQL查询</button>
    </div>

    <!-- 1. 连接配置区块 -->
    <div id="config" class="block {{'show' if tab=='config' else ''}}">
        <div class="box">
            <h3>SSH 跳板机配置</h3>
            <form method="post">
                <input type="hidden" name="action" value="save_config">
                <div class="row">
                    <label>跳板机地址：</label>
                    <input type="text" name="ssh_host" value="{{cfg.ssh_host}}" required>
                </div>
                <div class="row">
                    <label>SSH 端口：</label>
                    <input type="number" name="ssh_port" value="{{cfg.ssh_port}}" required>
                </div>
                <div class="row">
                    <label>SSH 用户名：</label>
                    <input type="text" name="ssh_user" value="{{cfg.ssh_user}}" required>
                </div>
                <div class="row">
                    <label>SSH 密码：</label>
                    <input type="password" name="ssh_pwd" value="{{cfg.ssh_pwd}}">
                </div>
                <hr>
                <h3>目标数据库配置</h3>
                <div class="row">
                    <label>数据库类型：</label>
                    <select name="db_type">
                        {% for k,v in DB_TYPE_MAP.items() %}
                        <option value="{{k}}" {% if cfg.db_type == k %}selected{% endif %}>{{v}}</option>
                        {% endfor %}
                    </select>
                </div>
                <div class="row">
                    <label>数据库IP：</label>
                    <input type="text" name="db_host" value="{{cfg.db_host}}" required>
                </div>
                <div class="row">
                    <label>数据库端口：</label>
                    <input type="number" name="db_port" value="{{cfg.db_port}}" required>
                </div>
                <div class="row">
                    <label>数据库账号：</label>
                    <input type="text" name="db_user" value="{{cfg.db_user}}">
                </div>
                <div class="row">
                    <label>数据库密码：</label>
                    <input type="password" name="db_pwd" value="{{cfg.db_pwd}}">
                </div>
                <div class="row">
                    <label>默认库名：</label>
                    <input type="text" name="db_name" value="{{cfg.db_name}}">
                </div>
                <div class="tip">端口参考：Doris=9030 | MySQL=3306 | ClickHouse=9000</div>
                <br>
                <button class="btn" type="submit">保存配置</button>
            </form>
        </div>
    </div>

    <!-- 2. 库表浏览区块 -->
    <div id="meta" class="block {{'show' if tab=='meta' else ''}}">
        <div class="box">
            <h3>数据库 & 数据表 浏览（点击表自动查询前{{DEFAULT_LIMIT}}条）</h3>
            <form method="post" style="margin-bottom:10px;">
                <input type="hidden" name="action" value="refresh_db">
                <button class="btn" type="submit">刷新数据库列表</button>
            </form>
            {% if meta_error %}
                <div class="error">{{meta_error}}</div>
            {% endif %}
            <div class="db-table-wrap">
                <!-- 数据库列表 -->
                <div>
                    <h4>数据库列表</h4>
                    <div class="list-box">
                        {% for db in db_list %}
                        <div class="list-item {{'active' if db == cfg.curr_db else ''}}" 
                             onclick="selectDb('{{db}}')">{{db}}</div>
                        {% endfor %}
                    </div>
                </div>
                <!-- 数据表列表 -->
                <div>
                    <h4>数据表列表（当前库：{{cfg.curr_db if cfg.curr_db else '未选择'}}）</h4>
                    <div class="list-box">
                        {% for tb in table_list %}
                        <div class="list-item" onclick="selectTable('{{tb}}')">{{tb}}</div>
                        {% endfor %}
                    </div>
                </div>
            </div>
            <!-- 隐藏表单：选中库/表 提交 -->
            <form id="dbForm" method="post">
                <input type="hidden" name="action" value="select_db">
                <input type="hidden" name="selected_db" id="selected_db">
            </form>
            <form id="tableForm" method="post">
                <input type="hidden" name="action" value="select_table">
                <input type="hidden" name="selected_table" id="selected_table">
            </form>
        </div>
    </div>

    <!-- 3. SQL查询区块 -->
    <div id="sql" class="block {{'show' if tab=='sql' else ''}}">
        <div class="box">
            <h3>自定义SQL执行</h3>
            <form method="post">
                <input type="hidden" name="action" value="run_sql">
                <textarea name="sql" placeholder="输入SQL语句，点击表会自动填充查询前{{DEFAULT_LIMIT}}条语句...">{{sql}}</textarea>
                <br><br>
                <button class="btn" type="submit">执行SQL</button>
            </form>
            {% if error %}
                <div class="error">{{error}}</div>
            {% endif %}
            {% if columns and rows %}
                <div class="tip">查询结果：共 {{rows|length}} 行</div>
                <table>
                    <tr>
                        {% for col in columns %}
                        <th>{{col}}</th>
                        {% endfor %}
                    </tr>
                    {% for r in rows %}
                    <tr>
                        {% for cell in r %}
                        <td>{{cell}}</td>
                        {% endfor %}
                    </tr>
                    {% endfor %}
                </table>
            {% endif %}
        </div>
    </div>

    <script>
        // 切换标签页
        function switchTab(tabName) {
            window.location.href = '?tab=' + tabName;
        }
        // 选中数据库，刷新表列表
        function selectDb(dbName) {
            document.getElementById('selected_db').value = dbName;
            document.getElementById('dbForm').submit();
        }
        // 选中数据表，自动生成 LIMIT 语句并填充到SQL框
        function selectTable(tbName) {
            let db = '{{cfg.curr_db}}';
            let limit = {{DEFAULT_LIMIT}};
            let sql = 'SELECT * FROM `' + db + '`.`' + tbName + '` LIMIT ' + limit + ';';
            // 跳转到SQL页并带入SQL
            let form = document.createElement('form');
            form.method = 'post';
            form.action = '?tab=sql';
            let act = document.createElement('input');
            act.type = 'hidden'; act.name = 'action'; act.value = 'fill_sql';
            let sqlInp = document.createElement('input');
            sqlInp.type = 'hidden'; sqlInp.name = 'sql'; sqlInp.value = sql;
            form.appendChild(act); form.appendChild(sqlInp);
            document.body.appendChild(form);
            form.submit();
        }
    </script>
</body>
</html>
"""

# ====================== 主路由 ======================
@app.route("/", methods=["GET", "POST"])
def index():
    # 读取会话数据
    cfg = session.get("full_cfg", DEFAULT_CFG.copy())
    tab = request.args.get("tab", "sql")  # 默认打开SQL查询页
    sql = ""
    error = ""
    meta_error = ""
    columns, rows = [], []
    db_list = []
    table_list = []

    # 拆分SSH配置
    ssh_cfg = {
        "ssh_host": cfg["ssh_host"],
        "ssh_port": cfg["ssh_port"],
        "ssh_user": cfg["ssh_user"],
        "ssh_pwd": cfg["ssh_pwd"]
    }

    if request.method == "POST":
        action = request.form.get("action", "")

        # 1. 保存连接配置
        if action == "save_config":
            cfg["ssh_host"] = request.form.get("ssh_host", "").strip()
            cfg["ssh_port"] = request.form.get("ssh_port", "").strip()
            cfg["ssh_user"] = request.form.get("ssh_user", "").strip()
            cfg["ssh_pwd"] = request.form.get("ssh_pwd", "")
            cfg["db_type"] = request.form.get("db_type", "doris")
            cfg["db_host"] = request.form.get("db_host", "").strip()
            cfg["db_port"] = request.form.get("db_port", "").strip()
            cfg["db_user"] = request.form.get("db_user", "").strip()
            cfg["db_pwd"] = request.form.get("db_pwd", "")
            cfg["db_name"] = request.form.get("db_name", "").strip()
            session["full_cfg"] = cfg
            tab = "config"

        # 2. 刷新数据库列表
        elif action == "refresh_db":
            tab = "meta"
            try:
                meta_sql = get_meta_sql(cfg["db_type"], "list_db")
                shell_cmd = build_db_shell_cmd(cfg, meta_sql)
                out, err = ssh_exec(ssh_cfg, shell_cmd, EXEC_TIMEOUT)
                if err:
                    meta_error = f"查询数据库失败：{err}"
                else:
                    _, db_raw = parse_result(out)
                    db_list = [item[0] for item in db_raw if item and item[0]]
            except Exception as e:
                meta_error = f"查询异常：{str(e)}\n{traceback.format_exc()}"

        # 3. 选中数据库，加载表列表
        elif action == "select_db":
            tab = "meta"
            selected_db = request.form.get("selected_db", "").strip()
            cfg["curr_db"] = selected_db
            session["full_cfg"] = cfg
            try:
                meta_sql = get_meta_sql(cfg["db_type"], "list_table", selected_db)
                shell_cmd = build_db_shell_cmd(cfg, meta_sql)
                out, err = ssh_exec(ssh_cfg, shell_cmd, EXEC_TIMEOUT)
                if err:
                    meta_error = f"查询数据表失败：{err}"
                else:
                    _, tb_raw = parse_result(out)
                    table_list = [item[0] for item in tb_raw if item and item[0]]
            except Exception as e:
                meta_error = f"查询异常：{str(e)}\n{traceback.format_exc()}"

        # 4. 点击表，自动填充查询SQL
        elif action == "fill_sql":
            tab = "sql"
            sql = request.form.get("sql", "").strip()

        # 5. 执行自定义SQL
        elif action == "run_sql":
            tab = "sql"
            sql = request.form.get("sql", "").strip()
            if not sql:
                error = "请输入SQL语句"
            else:
                try:
                    shell_cmd = build_db_shell_cmd(cfg, sql)
                    out, err = ssh_exec(ssh_cfg, shell_cmd, EXEC_TIMEOUT)
                    if err:
                        error = f"执行错误：{err}"
                    else:
                        columns, rows = parse_result(out)
                except Exception as e:
                    error = f"程序异常：{str(e)}\n{traceback.format_exc()}"

    return render_template_string(
        HTML_TPL,
        cfg=cfg,
        tab=tab,
        sql=sql,
        error=error,
        meta_error=meta_error,
        db_list=db_list,
        table_list=table_list,
        columns=columns,
        rows=rows,
        DB_TYPE_MAP=DB_TYPE_MAP,
        DEFAULT_LIMIT=DEFAULT_LIMIT
    )


if __name__ == "__main__":
    # 仅本地127.0.0.1访问
    app.run(host="127.0.0.1", port=8080, debug=False)