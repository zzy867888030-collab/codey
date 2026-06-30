import json
import os
import shlex
import threading
import time
from flask import Flask, jsonify, render_template_string, request
import paramiko
import traceback

# ====================== 配置 & 工具函数 ======================
CONFIG_FILE = "config.json"
META_CACHE_FILE = "db_meta_cache.json"
RUNNING_QUERY_PID_FILE_TEMPLATE = "/tmp/ssh_local_db_web_query_{query_id}.pid"
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

def build_meta_cache_key(cfg):
    key_parts = [
        cfg.get("db_type", ""),
        cfg.get("db_host", ""),
        str(cfg.get("db_port", "")),
        cfg.get("db_user", "")
    ]
    return "|".join(key_parts)

def empty_meta_cache(cfg):
    return {
        "cache_key": build_meta_cache_key(cfg),
        "updated_at": "",
        "db_list": [],
        "tables": {}
    }

def load_meta_cache(cfg):
    cache = empty_meta_cache(cfg)
    if not os.path.exists(META_CACHE_FILE):
        return cache
    try:
        with open(META_CACHE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        if data.get("cache_key") != cache["cache_key"]:
            return cache
        cache["updated_at"] = data.get("updated_at", "")
        cache["db_list"] = data.get("db_list", []) if isinstance(data.get("db_list"), list) else []
        cache["tables"] = data.get("tables", {}) if isinstance(data.get("tables"), dict) else {}
        return cache
    except Exception as e:
        print(f"读取库表缓存失败: {str(e)}")
        return cache

def save_meta_cache(cfg, db_list, tables):
    cache = {
        "cache_key": build_meta_cache_key(cfg),
        "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "db_list": db_list,
        "tables": tables
    }
    try:
        with open(META_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(cache, f, ensure_ascii=False, indent=4)
    except Exception as e:
        print(f"保存库表缓存失败: {str(e)}")

def parse_meta_first_column(output, skip_exact=None, skip_prefixes=None):
    skip_exact = skip_exact or []
    skip_prefixes = skip_prefixes or []
    values = []
    for line in output.splitlines():
        first_col = line.strip().split("\t", 1)[0].strip()
        if not first_col:
            continue
        if first_col.startswith("-") or first_col.upper().startswith("SHOW "):
            continue
        if first_col in skip_exact:
            continue
        if any(first_col.startswith(prefix) for prefix in skip_prefixes):
            continue
        values.append(first_col)
    return values

def list_databases_from_remote(cfg, ssh_cfg):
    meta_sql = get_meta_sql(cfg["db_type"], "list_db")
    shell_cmd = build_db_shell_cmd(cfg, meta_sql)
    out, err = ssh_exec(ssh_cfg, shell_cmd, EXEC_TIMEOUT)
    if err:
        raise Exception(err)
    return parse_meta_first_column(out, skip_exact=["Database"])

def list_tables_from_remote(cfg, ssh_cfg, db_name):
    meta_sql = get_meta_sql(cfg["db_type"], "list_table", db_name)
    shell_cmd = build_db_shell_cmd(cfg, meta_sql)
    out, err = ssh_exec(ssh_cfg, shell_cmd, EXEC_TIMEOUT)
    if err:
        raise Exception(err)
    return parse_meta_first_column(out, skip_exact=["name"], skip_prefixes=["Tables_in_"])

LOCAL_CFG = load_config()
QUERY_STATES = {}
NEXT_QUERY_ID = 1
QUERY_LOCK = threading.Lock()

app = Flask(__name__)
app.secret_key = "local_ssh_db_tool_final"
app.config['TEMPLATES_AUTO_RELOAD'] = True

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

def get_running_query_pid_file(query_id):
    safe_query_id = str(query_id).replace("/", "_").replace(".", "_")
    return RUNNING_QUERY_PID_FILE_TEMPLATE.format(query_id=safe_query_id)

def new_query_state(query_id, title=None, sql=""):
    return {
        "id": query_id,
        "title": title or f"查询窗口 {query_id}",
        "running": False,
        "started_at": None,
        "finished_at": None,
        "sql": sql,
        "error": "",
        "columns": [],
        "rows": [],
        "message": ""
    }

def ensure_query_state(query_id=None):
    global NEXT_QUERY_ID
    with QUERY_LOCK:
        if not QUERY_STATES:
            QUERY_STATES[1] = new_query_state(1)
            NEXT_QUERY_ID = 2
        if query_id is None:
            query_id = min(QUERY_STATES.keys())
        else:
            try:
                query_id = int(query_id)
            except (TypeError, ValueError):
                query_id = min(QUERY_STATES.keys())
            if query_id not in QUERY_STATES:
                QUERY_STATES[query_id] = new_query_state(query_id)
                NEXT_QUERY_ID = max(NEXT_QUERY_ID, query_id + 1)
        return query_id

def create_query_window(sql=""):
    global NEXT_QUERY_ID
    with QUERY_LOCK:
        query_id = NEXT_QUERY_ID
        NEXT_QUERY_ID += 1
        QUERY_STATES[query_id] = new_query_state(query_id, sql=sql)
        return query_id

def ssh_exec_track_query(ssh_cfg, cmd, timeout, query_id):
    pid_file = get_running_query_pid_file(query_id)
    script = (
        f"{cmd} & "
        f"pid=$!; "
        f"echo $pid > {pid_file}; "
        f"wait $pid; "
        f"status=$?; "
        f"rm -f {pid_file}; "
        f"exit $status"
    )
    wrapped_cmd = f"sh -c {shlex.quote(script)}"
    return ssh_exec(ssh_cfg, wrapped_cmd, timeout)

def stop_running_query(ssh_cfg, query_id):
    pid_file = get_running_query_pid_file(query_id)
    stop_cmd = (
        f"if [ -f {pid_file} ]; then "
        f"pid=$(cat {pid_file}); "
        f"kill $pid 2>/dev/null; "
        f"rm -f {pid_file}; "
        f"echo stopped; "
        f"else echo no_running_query; fi"
    )
    out, err = ssh_exec(ssh_cfg, stop_cmd, 30)
    return out.strip(), err.strip()

def run_query_background(cfg, ssh_cfg, sql, query_id):
    try:
        shell_cmd = build_db_shell_cmd(cfg, sql)
        out, err = ssh_exec_track_query(ssh_cfg, shell_cmd, EXEC_TIMEOUT, query_id)
        if err:
            with QUERY_LOCK:
                state = QUERY_STATES.get(query_id)
                if state:
                    state["error"] = f"执行错误：{err}"
                    state["columns"] = []
                    state["rows"] = []
        else:
            columns, rows = parse_result(out)
            with QUERY_LOCK:
                state = QUERY_STATES.get(query_id)
                if state:
                    state["error"] = ""
                    state["columns"] = columns
                    state["rows"] = rows
                    state["message"] = f"查询完成，共 {len(rows)} 行"
    except Exception as e:
        with QUERY_LOCK:
            state = QUERY_STATES.get(query_id)
            if state:
                state["error"] = f"程序异常：{str(e)}\n{traceback.format_exc()}"
                state["columns"] = []
                state["rows"] = []
    finally:
        with QUERY_LOCK:
            state = QUERY_STATES.get(query_id)
            if state:
                state["running"] = False
                state["finished_at"] = time.time()

def normalize_query_state(state):
    state = state.copy()
    state["columns"] = list(state["columns"])
    state["rows"] = [list(row) for row in state["rows"]]
    now = time.time()
    if state["running"] and state["started_at"]:
        state["elapsed_seconds"] = int(now - state["started_at"])
    elif state["started_at"] and state["finished_at"]:
        state["elapsed_seconds"] = int(state["finished_at"] - state["started_at"])
    else:
        state["elapsed_seconds"] = 0
    return state

def get_query_state_snapshot(query_id=None):
    query_id = ensure_query_state(query_id)
    with QUERY_LOCK:
        state = QUERY_STATES[query_id].copy()
    return normalize_query_state(state)

def get_all_query_state_snapshots():
    ensure_query_state()
    with QUERY_LOCK:
        states = [QUERY_STATES[k].copy() for k in sorted(QUERY_STATES.keys())]
    return [normalize_query_state(state) for state in states]

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

# ====================== 极简HTML模板（无JS语法错误） ======================
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
        .btn-stop {background: #f56c6c;}
        .status-box {margin: 10px 0; padding: 10px; border: 1px solid #eee; background: #fafafa; border-radius: 4px;}
        .query-tabs {display: flex; align-items: center; gap: 8px; margin-bottom: 12px; flex-wrap: wrap;}
        .query-tab {padding: 6px 14px; border: 1px solid #dcdfe6; background: #fff; color: #333; border-radius: 4px; cursor: pointer;}
        .query-tab.active {background: #2d8cf0; border-color: #2d8cf0; color: #fff;}
        .query-panel {display: none;}
        .query-panel.active {display: block;}
        .inline-form {display: inline;}
    </style>

    <!-- 【关键修复】JS 完全前置，且无任何Jinja插值 -->
    <script>
        // 全局变量，从隐藏input读取配置（避免Jinja语法错误）
        let GLOBAL_CFG = {};

        // 标签切换函数（纯JS，无任何语法错误）
        function switchTab(tabName) {
            document.querySelectorAll('.nav button').forEach(btn => btn.classList.remove('active'));
            document.querySelectorAll('.block').forEach(block => block.classList.remove('active'));
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

        // 选中数据表（读取隐藏input的配置）
        function selectTable(tbName) {
            const db = document.getElementById('hidden_curr_db').value;
            const limit = document.getElementById('hidden_default_limit').value;
            const sql = 'SELECT * FROM `' + db + '`.`' + tbName + '` LIMIT ' + limit + ';';
            document.getElementById('auto-sql').value = sql;
            document.getElementById('auto-query-id').value = document.getElementById('active_query_id').value;
            document.getElementById('select-table-form').submit();
        }

        // 复制全部结果
        function copyAllResult(queryId){
            const table = document.getElementById("resultTable-" + queryId);
            if (!table) return;
            const rows = table.querySelectorAll("tr");
            let copyText = "";
            rows.forEach(function(tr){
                const tds = tr.querySelectorAll("th, td");
                let rowData = "";
                tds.forEach(function(td, index){
                    rowData += td.innerText.trim();
                    if(index < tds.length - 1){
                        rowData += "\\t";
                    }
                });
                copyText += rowData + "\\n";
            });
            navigator.clipboard.writeText(copyText).then(function(){
                const tip = document.getElementById("copyTip-" + queryId);
                if(tip) tip.innerText = "复制成功！";
                setTimeout(()=>{if(tip) tip.innerText = "";}, 2000);
            }).catch(function(err){
                const tip = document.getElementById("copyTip-" + queryId);
                if(tip) tip.innerText = "复制失败，请手动选中复制";
            });
        }

        function refreshQueryStatus(){
            fetch('/query_status')
                .then(resp => resp.json())
                .then(data => {
                    (data.queries || []).forEach(function(query){
                        let text = '查询状态：空闲';
                        if (query.running) {
                            window.__queryWasRunning = window.__queryWasRunning || {};
                            window.__queryWasRunning[query.id] = true;
                            text = '查询状态：运行中，已耗时 ' + query.elapsed_seconds + ' 秒';
                        } else if (query.message) {
                            text = '查询状态：' + query.message + '，耗时 ' + query.elapsed_seconds + ' 秒';
                        } else if (query.error) {
                            text = '查询状态：执行失败，耗时 ' + query.elapsed_seconds + ' 秒';
                        }
                        const statusBox = document.getElementById('query-status-' + query.id);
                        if (statusBox) statusBox.innerText = text;
                        const stopBtn = document.getElementById('stop-query-btn-' + query.id);
                        if (stopBtn) stopBtn.disabled = !query.running;
                        if (!query.running && query.finished_at && window.__queryWasRunning && window.__queryWasRunning[query.id] && !window.__queryFinishedReloaded) {
                            window.__queryFinishedReloaded = true;
                            window.location.href = '/?tab=sql&q=' + query.id;
                        }
                    });
                })
                .catch(() => {});
        }

        // 页面加载完成后初始化
        window.onload = function(){
            // 读取隐藏input的配置
            GLOBAL_CFG.curr_db = document.getElementById('hidden_curr_db').value;
            GLOBAL_CFG.default_limit = document.getElementById('hidden_default_limit').value;
            // 初始化标签页
            const urlParams = new URLSearchParams(window.location.search);
            const tab = urlParams.get('tab') || '{{tab}}' || 'sql';
            switchTab(tab);
            refreshQueryStatus();
            setInterval(refreshQueryStatus, 1000);
        }
    </script>
</head>
<body>
    <!-- 【关键修复】隐藏input传递配置，避免JS语法错误 -->
    <input type="hidden" id="hidden_curr_db" value="{{cfg.curr_db}}">
    <input type="hidden" id="hidden_default_limit" value="{{cfg.default_limit}}">

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
            <form id="refresh-db-form" method="post" action="/?tab=meta" style="margin-bottom:10px;">
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
                        <div class="list-item {{'active' if db == cfg.curr_db else ''}}" data-db="{{db|e}}" onclick="selectDb(this.dataset.db)">{{db}}</div>
                        {% endfor %}
                    </div>
                </div>
                <div>
                    <h4>数据表列表（当前库：{{cfg.curr_db if cfg.curr_db else '未选择'}}）</h4>
                    <div class="list-box">
                        {% for tb in table_list %}
                        <div class="list-item" data-table="{{tb|e}}" onclick="selectTable(this.dataset.table)">{{tb}}</div>
                        {% endfor %}
                    </div>
                </div>
            </div>
            <!-- 隐藏独立表单：选中数据库 -->
            <form id="select-db-form" method="post" action="/?tab=meta" style="display:none;">
                <input type="hidden" name="action" value="select_db">
                <input type="hidden" name="selected_db" id="selected_db">
            </form>
            <!-- 隐藏独立表单：选中数据表 -->
            <form id="select-table-form" method="post" action="/?tab=sql" style="display:none;">
                <input type="hidden" name="action" value="fill_sql">
                <input type="hidden" name="query_id" id="auto-query-id" value="{{active_query_id}}">
                <input type="hidden" name="sql" id="auto-sql">
            </form>
        </div>
    </div>

    <!-- 3. SQL查询 - 多窗口独立表单（无嵌套） -->
    <div id="sql" class="block">
        <div class="box">
            <h3>自定义SQL执行</h3>
            <input type="hidden" id="active_query_id" value="{{active_query_id}}">
            <div class="query-tabs">
                {% for q in query_states %}
                <form class="inline-form" method="get" action="/">
                    <input type="hidden" name="tab" value="sql">
                    <input type="hidden" name="q" value="{{q.id}}">
                    <button class="query-tab {{'active' if q.id == active_query_id else ''}}" type="submit">
                        {{q.title}}{% if q.running %}（运行中）{% endif %}
                    </button>
                </form>
                {% endfor %}
                <form class="inline-form" method="post" action="/?tab=sql">
                    <input type="hidden" name="action" value="new_query_window">
                    <button class="btn" type="submit">新建查询窗口</button>
                </form>
            </div>

            {% for q in query_states %}
            <div class="query-panel {{'active' if q.id == active_query_id else ''}}">
                <form id="sql-form-{{q.id}}" method="post" action="/?tab=sql&q={{q.id}}">
                    <input type="hidden" name="action" value="run_sql">
                    <input type="hidden" name="query_id" value="{{q.id}}">
                    <div class="row">
                        <label>当前默认条数：</label>
                        <input type="number" name="limit_rows" value="{{cfg.default_limit}}" min="1" max="10000" class="limit-input">
                        <span class="tip">点击表自动使用此条数生成查询语句</span>
                    </div>
                    <textarea name="sql" class="sql-input" placeholder="输入SQL语句，点击表会自动填充查询语句...">{{q.sql}}</textarea>
                    <br><br>
                    <button class="btn" type="submit">执行SQL</button>
                    {% if q.columns and q.rows %}
                    <button class="btn btn-copy" type="button" onclick="copyAllResult('{{q.id}}')">复制全部结果</button>
                    <span id="copyTip-{{q.id}}" class="copy-tip"></span>
                    {% endif %}
                </form>
                <form method="post" action="/?tab=sql&q={{q.id}}" style="margin-top:10px;">
                    <input type="hidden" name="action" value="stop_query">
                    <input type="hidden" name="query_id" value="{{q.id}}">
                    <button id="stop-query-btn-{{q.id}}" class="btn btn-stop" type="submit" {% if not q.running %}disabled{% endif %}>停止查询</button>
                </form>
                <div id="query-status-{{q.id}}" class="status-box">
                    {% if q.running %}
                        查询状态：运行中，已耗时 {{q.elapsed_seconds}} 秒
                    {% elif q.message %}
                        查询状态：{{q.message}}，耗时 {{q.elapsed_seconds}} 秒
                    {% elif q.error %}
                        查询状态：执行失败，耗时 {{q.elapsed_seconds}} 秒
                    {% else %}
                        查询状态：空闲
                    {% endif %}
                </div>
                {% if q.error %}
                    <div class="error">{{q.error}}</div>
                {% endif %}

                {% if q.columns and q.rows %}
                    <div class="tip">查询结果：共 {{q.rows|length}} 行</div>
                    <table id="resultTable-{{q.id}}">
                        <tr>
                            {% for col in q.columns %}
                            <th>{{col}}</th>
                            {% endfor %}
                        </tr>
                        {% for r in q.rows %}
                        <tr>
                            {% for cell in r %}
                            <td>{{cell}}</td>
                            {% endfor %}
                        </tr>
                        {% endfor %}
                    </table>
                {% endif %}
            </div>
            {% endfor %}
        </div>
    </div>

</body>
</html>
"""

@app.route("/", methods=["GET", "POST"])
def index():
    global LOCAL_CFG
    cfg = LOCAL_CFG.copy()
    tab = request.args.get("tab", "sql")
    meta_error = ""
    db_list = []
    table_list = []
    meta_cache = load_meta_cache(cfg)
    db_list = meta_cache["db_list"]
    if cfg.get("curr_db"):
        table_list = meta_cache["tables"].get(cfg["curr_db"], [])
    active_query_id = ensure_query_state(request.args.get("q"))

    ssh_cfg = {
        "ssh_host": cfg["ssh_host"],
        "ssh_port": cfg["ssh_port"],
        "ssh_user": cfg["ssh_user"],
        "ssh_pwd": cfg["ssh_pwd"]
    }

    if request.method == "POST":
        action = request.form.get("action", "")
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
        elif action == "refresh_db":
            tab = "meta"
            try:
                db_list = list_databases_from_remote(cfg, ssh_cfg)
                tables = {}
                table_errors = []
                for db_name in db_list:
                    try:
                        tables[db_name] = list_tables_from_remote(cfg, ssh_cfg, db_name)
                    except Exception as e:
                        tables[db_name] = []
                        table_errors.append(f"{db_name}: {str(e)}")
                save_meta_cache(cfg, db_list, tables)
                table_list = tables.get(cfg.get("curr_db", ""), [])
                if table_errors:
                    meta_error = "部分数据库表名刷新失败：\n" + "\n".join(table_errors)
            except Exception as e:
                meta_error = f"查询异常：{str(e)}\n{traceback.format_exc()}"
        elif action == "select_db":
            tab = "meta"
            selected_db = request.form.get("selected_db", "").strip()
            cfg["curr_db"] = selected_db
            LOCAL_CFG = cfg
            save_config(cfg)
            meta_cache = load_meta_cache(cfg)
            db_list = meta_cache["db_list"]
            table_list = meta_cache["tables"].get(selected_db, [])
        elif action == "fill_sql":
            tab = "sql"
            sql = request.form.get("sql", "").strip()
            active_query_id = ensure_query_state(request.form.get("query_id") or active_query_id)
            with QUERY_LOCK:
                QUERY_STATES[active_query_id]["sql"] = sql
        elif action == "run_sql":
            tab = "sql"
            active_query_id = ensure_query_state(request.form.get("query_id") or active_query_id)
            sql = request.form.get("sql", "").strip()
            if not sql:
                with QUERY_LOCK:
                    QUERY_STATES[active_query_id]["error"] = "请输入SQL语句"
            else:
                with QUERY_LOCK:
                    state = QUERY_STATES[active_query_id]
                    if state["running"]:
                        state["error"] = "当前查询窗口正在执行，请先停止或等待完成"
                    else:
                        state.update({
                            "running": True,
                            "started_at": time.time(),
                            "finished_at": None,
                            "sql": sql,
                            "error": "",
                            "columns": [],
                            "rows": [],
                            "message": "查询已开始"
                        })
                        threading.Thread(target=run_query_background, args=(cfg.copy(), ssh_cfg.copy(), sql, active_query_id), daemon=True).start()
        elif action == "stop_query":
            tab = "sql"
            active_query_id = ensure_query_state(request.form.get("query_id") or active_query_id)
            out, err = stop_running_query(ssh_cfg, active_query_id)
            with QUERY_LOCK:
                state = QUERY_STATES[active_query_id]
                state["running"] = False
                state["finished_at"] = time.time()
                state["message"] = "查询已停止" if out == "stopped" else "当前没有正在执行的查询"
                if err:
                    state["error"] = f"停止查询失败：{err}"
        elif action == "new_query_window":
            tab = "sql"
            active_query_id = create_query_window()

    query_states = get_all_query_state_snapshots()
    if active_query_id not in [q["id"] for q in query_states]:
        active_query_id = query_states[0]["id"]

    return render_template_string(
        HTML_TPL,
        cfg=cfg,
        tab=tab,
        meta_error=meta_error,
        db_list=db_list,
        table_list=table_list,
        active_query_id=active_query_id,
        query_states=query_states,
        DB_TYPE_MAP=DB_TYPE_MAP
    )

@app.route("/query_status", methods=["GET"])
def query_status():
    return jsonify({
        "queries": [
            {
                "id": state["id"],
                "running": state["running"],
                "started_at": state["started_at"],
                "finished_at": state["finished_at"],
                "elapsed_seconds": state["elapsed_seconds"],
                "message": state["message"],
                "error": state["error"],
                "row_count": len(state["rows"])
            }
            for state in get_all_query_state_snapshots()
        ]
    })

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8080, debug=False)
