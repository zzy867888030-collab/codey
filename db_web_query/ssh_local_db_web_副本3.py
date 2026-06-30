import json
import os
from flask import Flask, render_template_string, request
import paramiko
import traceback

# ====================== 全局常量 & 配置文件定义 ======================
CONFIG_FILE = "config.json"
DB_TYPE_MAP = {
    "doris": "Apache Doris",
    "mysql": "MySQL",
    "clickhouse": "ClickHouse"
}
EXEC_TIMEOUT = 600
DEFAULT_CFG = {
    "ssh_host": "data-process",
    "ssh_port": 22,
    "ssh_user": "mnyjy",
    "ssh_pwd": "",
    "db_type": "doris",
    "db_host": "192.168.77.38",
    "db_port": 9030,
    "db_user": "root",
    "db_pwd": "",
    "db_name": "MIHDB_DICT",
    "curr_db": "",
    "curr_table": "",
    "default_limit": 200
}

# ====================== 配置文件读写函数 ======================
def load_config():
    if not os.path.exists(CONFIG_FILE):
        save_config(DEFAULT_CFG)
        return DEFAULT_CFG.copy()
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        for k, v in DEFAULT_CFG.items():
            if k not in cfg:
                cfg[k] = v
        return cfg
    except Exception:
        save_config(DEFAULT_CFG)
        return DEFAULT_CFG.copy()

def save_config(cfg):
    try:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=4)
    except Exception as e:
        print(f"保存配置文件失败: {str(e)}")

LOCAL_CFG = load_config()

# ====================== Flask 初始化 ======================
app = Flask(__name__)
app.secret_key = "local_ssh_db_tool_2026_final"
app.config['TEMPLATES_AUTO_RELOAD'] = True

# ====================== 底层工具函数 ======================
def build_db_shell_cmd(cfg, sql):
    db_type = cfg["db_type"]
    db_host = cfg["db_host"]
    db_port = str(cfg["db_port"])
    db_user = cfg["db_user"]
    db_pwd = cfg["db_pwd"]
    db_name = cfg["db_name"]

    safe_sql = sql.replace('"', '\\"').replace('`', '\\`')

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
    if action == "list_db":
        return "SHOW DATABASES;"
    elif action == "list_table":
        if db_type in ("doris", "mysql", "clickhouse"):
            return f"SHOW TABLES FROM `{target_db}`;"
    return ""

# ====================== 前端页面模板（100% 语法修复版） ======================
HTML_TPL = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title>SSH跳板数据库查询工具</title>
    <style>
        body {margin: 20px; font-family: "Microsoft Yahei", sans-serif; font-size: 14px;}
        .nav {margin-bottom: 20px;}
        .nav button {
            padding: 8px 20px; margin-right: 8px;
            background: #e8e8e8; border: none; border-radius: 4px;
            cursor: pointer; font-size: 14px;
        }
        .nav button.active {background: #2d8cf0; color: #fff;}
        .block {display: none;}
        .block.active {display: block;}
        .box {border: 1px solid #ccc; padding: 15px; border-radius: 6px; margin-bottom: 15px;}
        .row {margin: 8px 0;}
        label {display: inline-block; width: 110px; text-align: right; margin-right: 8px;}
        input, select {padding: 5px; font-size: 14px;}
        .sql-input {width: 98%; height: 240px; padding: 8px; box-sizing: border-box; font-size: 14px;}
        .btn {padding: 6px 20px; cursor: pointer; background: #2d8cf0; color: #fff; border: none; border-radius: 4px; font-size: 14px; margin-right: 10px;}
        .btn-copy {background: #67c23a;}
        .error {color: #f53f3f; margin: 10px 0; white-space: pre-wrap;}
        .tip {color: #666; font-size: 12px;}
        .db-table-wrap {display: flex; gap: 30px;}
        .list-box {width: 300px; height: 400px; border: 1px solid #eee; padding: 10px; overflow-y: auto;}
        .list-item {padding: 4px 8px; margin: 2px 0; cursor: pointer; border-radius: 2px;}
        .list-item:hover {background: #f0f7ff;}
        .list-item.active {background: #2d8cf0; color: #fff;}
        table {border-collapse: collapse; width: 100%; margin-top: 10px;}
        th, td {border: 1px solid #ccc; padding: 6px 10px; text-align: center;}
        th {background: #f2f3f5;}
        h3 {margin-top: 0; color: #333;}
        .limit-input {width: 100px;}
        .copy-tip {color: #67c23a; margin-left: 10px;}
    </style>

    <!-- 【关键修复】JS 前置定义，确保函数在按钮渲染前加载 -->
    <script>
        // 全局变量，从后端传入配置（避免Jinja直接写在JS里导致语法错误）
        const GLOBAL_CFG = {
            curr_db: "{{cfg.curr_db}}",
            default_limit: {{cfg.default_limit}}
        };

        // 标签切换函数（无任何语法错误）
        function switchTab(tabName) {
            // 清空所有激活状态
            document.querySelectorAll('.nav button').forEach(btn => btn.classList.remove('active'));
            document.querySelectorAll('.block').forEach(block => block.classList.remove('active'));
            
            // 激活当前标签
            const btn = document.getElementById('btn-' + tabName);
            const block = document.getElementById(tabName);
            if (btn) btn.classList.add('active');
            if (block) block.classList.add('active');
        }

        // 选中数据库
        function selectDb(dbName) {
            document.getElementById('selected_db').value = dbName;
            document.getElementById('select-db-form').submit();
        }

        // 选中数据表，自动生成查询SQL
        function selectTable(tbName) {
            const db = GLOBAL_CFG.curr_db;
            const limit = GLOBAL_CFG.default_limit;
            const sql = 'SELECT * FROM `' + db + '`.`' + tbName + '` LIMIT ' + limit + ';';
            document.getElementById('auto-sql').value = sql;
            document.getElementById('select-table-form').submit();
        }

        // 复制全部结果
        function copyAllResult(){
            const table = document.getElementById("resultTable");
            if (!table) return;
            const rows = table.querySelectorAll("tr");
            let copyText = "";
            rows.forEach(function(tr){
                const tds = tr.querySelectorAll("th, td");
                let rowData = "";
                tds.forEach(function(td, index){
                    rowData += td.innerText.trim();
                    if(index < tds.length - 1){
                        rowData += "\t";
                    }
                });
                copyText += rowData + "\n";
            });
            navigator.clipboard.writeText(copyText).then(function(){
                const tip = document.getElementById("copyTip");
                if(tip) tip.innerText = "✅ 复制成功！";
                setTimeout(()=>{if(tip) tip.innerText = "";}, 2000);
            }).catch(function(err){
                const tip = document.getElementById("copyTip");
                if(tip) tip.innerText = "❌ 复制失败，请手动选中复制";
            });
        }

        // 页面加载完成后初始化
        window.onload = function(){
            const urlParams = new URLSearchParams(window.location.search);
            const tab = urlParams.get('tab') || 'sql';
            switchTab(tab);
        }
    </script>
</head>
<body>
    <h2>SSH跳板数据库查询工具</h2>
    <div class="nav">
        <button id="btn-config" onclick="switchTab('config')">连接配置</button>
        <button id="btn-meta" onclick="switchTab('meta')">库表浏览</button>
        <button id="btn-sql" onclick="switchTab('sql')">SQL查询</button>
    </div>

    <!-- 1. 连接配置 - 独立表单（无嵌套） -->
    <div id="config" class="block">
        <div class="box">
            <h3>SSH 跳板机配置</h3>
            <form id="config-form" method="post" action="/">
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
                <div class="row">
                    <label>默认查询条数：</label>
                    <input type="number" name="default_limit" value="{{cfg.default_limit}}" min="1" max="10000" class="limit-input">
                    <span class="tip">点击表自动生成 LIMIT 查询语句</span>
                </div>
                <div class="tip">端口参考：Doris=9030 | MySQL=3306 | ClickHouse=9000</div>
                <br>
                <button class="btn" type="submit">保存配置（自动写入配置文件）</button>
            </form>
        </div>
    </div>

    <!-- 2. 库表浏览 - 多个独立表单（无嵌套） -->
    <div id="meta" class="block">
        <div class="box">
            <h3>数据库 & 数据表 浏览（点击表自动查询前{{cfg.default_limit}}条）</h3>
            <form id="refresh-db-form" method="post" action="/" style="margin-bottom:10px;">
                <input type="hidden" name="action" value="refresh_db">
                <button class="btn" type="submit">刷新数据库列表</button>
            </form>
            {% if meta_error %}
                <div class="error">{{meta_error}}</div>
            {% endif %}
            <div class="db-table-wrap">
                <div>
                    <h4>数据库列表</h4>
                    <div class="list-box">
                        {% for db in db_list %}
                        <div class="list-item {{'active' if db == cfg.curr_db else ''}}" onclick="selectDb('{{db}}')">{{db}}</div>
                        {% endfor %}
                    </div>
                </div>
                <div>
                    <h4>数据表列表（当前库：{{cfg.curr_db if cfg.curr_db else '未选择'}}）</h4>
                    <div class="list-box">
                        {% for tb in table_list %}
                        <div class="list-item" onclick="selectTable('{{tb}}')">{{tb}}</div>
                        {% endfor %}
                    </div>
                </div>
            </div>
            <!-- 隐藏独立表单：选中数据库 -->
            <form id="select-db-form" method="post" action="/" style="display:none;">
                <input type="hidden" name="action" value="select_db">
                <input type="hidden" name="selected_db" id="selected_db">
            </form>
            <!-- 隐藏独立表单：选中数据表 -->
            <form id="select-table-form" method="post" action="/?tab=sql" style="display:none;">
                <input type="hidden" name="action" value="fill_sql">
                <input type="hidden" name="sql" id="auto-sql">
            </form>
        </div>
    </div>

    <!-- 3. SQL查询 - 独立表单（无嵌套） -->
    <div id="sql" class="block">
        <div class="box">
            <h3>自定义SQL执行</h3>
            <form id="sql-form" method="post" action="/">
                <input type="hidden" name="action" value="run_sql">
                <div class="row">
                    <label>当前默认条数：</label>
                    <input type="number" name="limit_rows" value="{{cfg.default_limit}}" min="1" max="10000" class="limit-input">
                    <span class="tip">点击表自动使用此条数生成查询语句</span>
                </div>
                <textarea name="sql" class="sql-input" placeholder="输入SQL语句，点击表会自动填充查询语句...">{{sql}}</textarea>
                <br><br>
                <button class="btn" type="submit">执行SQL</button>
                {% if columns and rows %}
                <button class="btn btn-copy" type="button" onclick="copyAllResult()">复制全部结果</button>
                <span id="copyTip" class="copy-tip"></span>
                {% endif %}
            </form>
            {% if error %}
                <div class="error">{{error}}</div>
            {% endif %}

            {% if columns and rows %}
                <div class="tip">查询结果：共 {{rows|length}} 行</div>
                <table id="resultTable">
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

</body>
</html>
"""

# ====================== 主路由 ======================
@app.route("/", methods=["GET", "POST"])
def index():
    global LOCAL_CFG
    cfg = LOCAL_CFG.copy()
    tab = request.args.get("tab", "sql")
    sql = ""
    error = ""
    meta_error = ""
    columns, rows = [], []
    db_list = []
    table_list = []

    ssh_cfg = {
        "ssh_host": cfg["ssh_host"],
        "ssh_port": cfg["ssh_port"],
        "ssh_user": cfg["ssh_user"],
        "ssh_pwd": cfg["ssh_pwd"]
    }

    if request.method == "POST":
        action = request.form.get("action", "")

        # 保存配置
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
            cfg["default_limit"] = int(request.form.get("default_limit", 200))
            LOCAL_CFG = cfg
            save_config(cfg)
            tab = "config"

        # 刷新数据库列表
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

        # 选中数据库
        elif action == "select_db":
            tab = "meta"
            selected_db = request.form.get("selected_db", "").strip()
            cfg["curr_db"] = selected_db
            LOCAL_CFG = cfg
            save_config(cfg)
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

        # 点击表自动填充SQL
        elif action == "fill_sql":
            tab = "sql"
            sql = request.form.get("sql", "").strip()

        # 执行SQL
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
        DB_TYPE_MAP=DB_TYPE_MAP
    )


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8080, debug=False)