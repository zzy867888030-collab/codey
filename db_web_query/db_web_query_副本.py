from flask import Flask, render_template_string, request, session
import paramiko
import traceback

app = Flask(__name__)
app.secret_key = "local_ssh_db_tool_2026"

# 数据库类型映射
DB_TYPE_MAP = {
    "doris": "Apache Doris",
    "mysql": "MySQL",
    "clickhouse": "ClickHouse"
}
# 命令执行超时（秒，大表查询建议调大）
EXEC_TIMEOUT = 600

# 默认配置（贴合你的现有环境）
DEFAULT_CFG = {
    # SSH 跳板机配置（本地要连的跳板机）
    "ssh_host": "data-process",
    "ssh_port": 22,
    "ssh_user": "mnyjy",
    "ssh_pwd": "",
    # 目标数据库配置（跳板机最终访问的库）
    "db_type": "doris",
    "db_host": "192.168.77.38",
    "db_port": 9030,
    "db_user": "root",
    "db_pwd": "",
    "db_name": "MIHDB_DICT"
}

# 前端页面模板
HTML_TPL = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title>本地SSH远程数据库查询工具</title>
    <style>
        body {margin: 20px; font-family: "Microsoft Yahei", sans-serif; font-size: 14px;}
        .container {display: flex; gap: 20px; flex-wrap: wrap;}
        .cfg-box {border: 1px solid #ccc; padding: 15px; border-radius: 6px; width: 420px;}
        .sql-box {flex: 1; min-width: 500px; border: 1px solid #ccc; padding: 15px; border-radius: 6px;}
        .row {margin: 8px 0;}
        label {display: inline-block; width: 100px; text-align: right; margin-right: 8px;}
        input, select {padding: 5px; width: 220px; font-size: 14px;}
        textarea {width: 100%; height: 240px; padding: 8px; box-sizing: border-box; font-size: 14px;}
        button {padding: 6px 20px; cursor: pointer; background: #2d8cf0; color: #fff; border: none; border-radius: 4px; font-size: 14px;}
        .error {color: #f53f3f; margin: 10px 0; white-space: pre-wrap;}
        .tip {color: #666; font-size: 12px;}
        table {border-collapse: collapse; width: 100%; margin-top: 15px;}
        th, td {border: 1px solid #ccc; padding: 6px 10px; text-align: center;}
        th {background: #f2f3f5;}
        h3 {margin-top: 0; color: #333;}
    </style>
</head>
<body>
    <h2>本地SSH跳板 · 数据库查询工具</h2>
    <div class="container">
        <!-- 左侧：连接配置区 -->
        <div class="cfg-box">
            <h3>连接参数配置</h3>
            <form method="post" id="cfgForm">
                <h4>1. SSH 跳板机信息</h4>
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
                <h4>2. 目标数据库信息</h4>
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
                <div class="tip">
                    端口参考：Doris=9030 | MySQL=3306 | ClickHouse=9000
                </div>
                <br>
                <button type="submit" name="save_cfg">保存配置</button>
            </form>
        </div>

        <!-- 右侧：SQL执行区 -->
        <div class="sql-box">
            <h3>SQL 执行区域</h3>
            <form method="post">
                <textarea name="sql" placeholder="请输入SQL语句...">{{sql}}</textarea>
                <br><br>
                <button type="submit" name="run_sql">执行SQL</button>
            </form>

            {% if error %}
                <div class="error">执行异常：{{error}}</div>
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
</body>
</html>
"""

def build_db_shell_cmd(cfg, sql):
    """拼接跳板机内执行的数据库命令（mysql/clickhouse-client）"""
    db_type = cfg["db_type"]
    db_host = cfg["db_host"]
    db_port = str(cfg["db_port"])
    db_user = cfg["db_user"]
    db_pwd = cfg["db_pwd"]
    db_name = cfg["db_name"]

    # 转义特殊字符，防止shell命令截断
    safe_sql = sql.replace('"', '\\"').replace("`", "\\`")

    if db_type in ("doris", "mysql"):
        cmd = [f"mysql -h{db_host} -P{db_port} -u{db_user}"]
        if db_pwd.strip():
            cmd.append(f"-p{db_pwd}")
        cmd.append(f"-D{db_name} -e \"{safe_sql}\" --default-character-set=utf8mb4")
        return " ".join(cmd)

    elif db_type == "clickhouse":
        cmd = [f"clickhouse-client -h {db_host} --port {db_port} -u {db_user}"]
        if db_pwd.strip():
            cmd.append(f"--password {db_pwd}")
        cmd.append(f"-d {db_name} -q \"{safe_sql}\"")
        return " ".join(cmd)
    else:
        raise Exception("暂不支持该数据库类型")

def ssh_exec(ssh_cfg, cmd, timeout):
    """本地创建SSH连接，远程执行命令，返回输出"""
    ssh_client = paramiko.SSHClient()
    ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        # 本地连接跳板机
        ssh_client.connect(
            hostname=ssh_cfg["ssh_host"],
            port=int(ssh_cfg["ssh_port"]),
            username=ssh_cfg["ssh_user"],
            password=ssh_cfg["ssh_pwd"],
            timeout=15
        )
        # 在跳板机执行数据库命令
        stdin, stdout, stderr = ssh_client.exec_command(cmd, timeout=timeout)
        out = stdout.read().decode("utf-8", errors="ignore")
        err = stderr.read().decode("utf-8", errors="ignore")
        return out, err
    finally:
        ssh_client.close()

def parse_result(output):
    """解析命令行输出，转为表头+数据行"""
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if not lines:
        return [], []
    columns = []
    rows = []
    # 适配 mysql 标准表格输出
    if len(lines) >= 2 and all(c in "-+" for c in lines[1]):
        columns = [col.strip() for col in lines[0].split("\t")]
        for line in lines[2:]:
            rows.append([cell.strip() for cell in line.split("\t")])
    else:
        # 适配 ClickHouse / 单行结果
        col_cnt = len(lines[0].split("\t")) if lines else 0
        columns = [f"字段{i+1}" for i in range(col_cnt)]
        for line in lines:
            rows.append([cell.strip() for cell in line.split("\t")])
    return columns, rows

@app.route("/", methods=["GET", "POST"])
def index():
    cfg = session.get("full_cfg", DEFAULT_CFG)
    sql = ""
    columns = []
    rows = []
    error = ""

    if request.method == "POST":
        # 保存配置
        if "save_cfg" in request.form:
            new_cfg = {
                "ssh_host": request.form.get("ssh_host", "").strip(),
                "ssh_port": request.form.get("ssh_port", "").strip(),
                "ssh_user": request.form.get("ssh_user", "").strip(),
                "ssh_pwd": request.form.get("ssh_pwd", ""),
                "db_type": request.form.get("db_type", "doris"),
                "db_host": request.form.get("db_host", "").strip(),
                "db_port": request.form.get("db_port", "").strip(),
                "db_user": request.form.get("db_user", "").strip(),
                "db_pwd": request.form.get("db_pwd", ""),
                "db_name": request.form.get("db_name", "").strip()
            }
            session["full_cfg"] = new_cfg
            cfg = new_cfg
        # 执行SQL
        elif "run_sql" in request.form:
            sql = request.form.get("sql", "").strip()
            if not sql:
                error = "请输入需要执行的SQL语句"
            else:
                try:
                    ssh_cfg = {
                        "ssh_host": cfg["ssh_host"],
                        "ssh_port": cfg["ssh_port"],
                        "ssh_user": cfg["ssh_user"],
                        "ssh_pwd": cfg["ssh_pwd"]
                    }
                    # 拼接远程命令
                    shell_cmd = build_db_shell_cmd(cfg, sql)
                    # SSH执行
                    out, err = ssh_exec(ssh_cfg, shell_cmd, EXEC_TIMEOUT)
                    if err:
                        error = f"命令执行错误：\n{err}"
                    else:
                        columns, rows = parse_result(out)
                except Exception as e:
                    error = f"程序异常：{str(e)}\n{traceback.format_exc()}"
    return render_template_string(HTML_TPL, cfg=cfg, sql=sql, columns=columns, rows=rows, error=error, DB_TYPE_MAP=DB_TYPE_MAP)

if __name__ == "__main__":
    # 本地监听，仅本机访问：127.0.0.1
    app.run(host="127.0.0.1", port=8080, debug=False)