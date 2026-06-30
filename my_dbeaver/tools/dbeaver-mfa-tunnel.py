#!/usr/bin/env python3
"""
DBeaver MFA SSH Tunnel Launcher

Architecture:
  1. ControlMaster SSH to jump host (via -J bastion, handles MFA auth)
  2. socat listens on 127.0.0.1:3307
  3. Each connection: socat forks and runs:
       ssh -S control_socket jump_host "nc db:3306"
     Uses SSH exec channel (session channel), NOT direct-tcpip.
     socat handles bidirectional I/O correctly.

Usage:
  python3 dbeaver-mfa-tunnel.py --password 'xxx'
"""

import argparse
import atexit
import os
import signal
import socket
import subprocess
import sys
import threading
import time

try:
    import pexpect
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pexpect"])
    import pexpect

# ── Config ────────────────────────────────────────────────────────────────
BASTION_USER = "zhangzhiyu"
BASTION_HOST = "192.168.31.88"
BASTION_PORT = 60022

JUMP_USER = "mnyjy"
JUMP_HOST = "192.168.77.38"
JUMP_PORT = 22

DB_HOST = "192.168.77.39"
DB_PORT = 3306

LOCAL_BIND = "127.0.0.1"
LOCAL_PORT = 3307
CTRL_SOCK = "/tmp/dbeaver-mfa-ssh-master.sock"

AUTH_MAX_RETRIES = 3


def port_listening(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex((host, port)) == 0


def prompt_secret(title: str, msg: str, default: str = "") -> str | None:
    script = (
        f'display dialog "{msg}" with title "{title}" '
        f'default answer "{default}" hidden answer true '
        'buttons {"取消", "确定"} default button "确定"'
    )
    try:
        r = subprocess.run(["osascript", "-e", script],
                           capture_output=True, text=True, timeout=120)
        if r.returncode == 0:
            for part in r.stdout.split(","):
                if "text returned:" in part:
                    return part.split(":", 1)[1].strip()
    except Exception:
        pass
    try:
        import getpass
        return getpass.getpass(f"{title}: {msg} ")
    except Exception:
        return None


# ── ControlMaster ─────────────────────────────────────────────────────────

class ControlMaster:
    def __init__(self, password: str = "", mfa: str = ""):
        self.password = password
        self.mfa = mfa
        self.child: pexpect.spawn | None = None
        self.stop = threading.Event()

    def cmd(self) -> list[str]:
        return [
            "ssh",
            "-J", f"{BASTION_USER}@{BASTION_HOST}:{BASTION_PORT}",
            "-o", "ConnectTimeout=20",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "PreferredAuthentications=password,keyboard-interactive",
            "-o", "PubkeyAuthentication=no",
            "-o", "ControlMaster=yes",
            "-o", f"ControlPath={CTRL_SOCK}",
            "-N",
            f"{JUMP_USER}@{JUMP_HOST}",
            "-p", str(JUMP_PORT),
        ]

    def start(self) -> bool:
        c = self.cmd()
        print(f"[ssh] ControlMaster: {' '.join(c)}")
        self.child = pexpect.spawn(c[0], c[1:], encoding="utf-8", timeout=120)
        self.child.delaybeforesend = 0.05
        try:
            self._auth()
            if self.stop.is_set():
                return False
            for _ in range(10):
                if os.path.exists(CTRL_SOCK):
                    print(f"[ssh] Control socket: {CTRL_SOCK}")
                    return True
                time.sleep(0.5)
            return False
        except Exception as e:
            print(f"[ssh] Error: {e}")
            return False

    def _auth(self):
        prompts = [
            r"(?i)are you sure.*\(yes/no.*\)\?",
            r"(?i)(?:password|passphrase).*:",
            r"(?i)(?:verification code|verification|mfa|otp|token|duo passcode).*:",
            r"(?i)permission denied",
            r"(?i)connection (?:closed|refused|reset)",
            pexpect.EOF,
            pexpect.TIMEOUT,
        ]
        pw_attempts = 0
        mfa_attempts = 0
        mfa_done = False
        last_err = ""

        while True:
            if self.stop.is_set():
                raise RuntimeError("Cancelled")

            before = (self.child.before or "").strip()
            if before:
                for line in before.splitlines()[-3:]:
                    if line.strip():
                        print(f"  {line.strip()}")

            idx = self.child.expect(prompts, timeout=120)

            if idx == 0:
                self.child.sendline("yes")
                continue
            if idx == 1:
                if pw_attempts >= AUTH_MAX_RETRIES:
                    raise RuntimeError("Too many password attempts")
                if self.password:
                    pw = self.password
                else:
                    dflt = "Mnjk@20252026" if pw_attempts == 0 else ""
                    msg = f"输入 {BASTION_USER}@{BASTION_HOST} 的密码"
                    if last_err:
                        msg = f"{last_err}\n\n{msg}"
                    pw = prompt_secret("SSH 密码", msg, dflt)
                    if pw is None:
                        raise RuntimeError("Cancelled")
                pw_attempts += 1
                last_err = ""
                self.child.sendline(pw)
                continue
            if idx == 2:
                if mfa_attempts >= AUTH_MAX_RETRIES:
                    raise RuntimeError("Too many MFA attempts")
                if self.mfa:
                    code = self.mfa
                else:
                    msg = "输入动态验证码"
                    if last_err:
                        msg = f"{last_err}\n\n{msg}"
                    code = prompt_secret("MFA 验证码", msg)
                    if code is None:
                        raise RuntimeError("Cancelled")
                mfa_done = True
                mfa_attempts += 1
                last_err = ""
                self.child.sendline(code)
                continue
            if idx == 3:
                out = (self.child.before or "") + (self.child.after or "")
                if "please try again" in out.lower():
                    last_err = "MFA 或密码错误" if mfa_done else "密码错误"
                    self.password = ""
                    self.mfa = ""
                    continue
                raise RuntimeError("Auth failed")
            if idx in (4, 5):
                raise RuntimeError("SSH connection failed")
            if idx == 6:
                if os.path.exists(CTRL_SOCK):
                    return
                continue

    def close(self):
        self.stop.set()
        if self.child and self.child.isalive():
            self.child.close(force=True)
        for _ in range(5):
            try:
                os.unlink(CTRL_SOCK)
                break
            except (FileNotFoundError, OSError):
                time.sleep(0.5)


# ── Main ──────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--local-port", type=int, default=LOCAL_PORT)
    parser.add_argument("--password", type=str, default="")
    parser.add_argument("--mfa-code", type=str, default="")
    parser.add_argument("--dbeaver", action="store_true")
    args = parser.parse_args()

    try:
        os.unlink(CTRL_SOCK)
    except FileNotFoundError:
        pass

    master = ControlMaster(args.password, args.mfa_code)
    socat_proc = None

    def cleanup():
        nonlocal socat_proc
        if socat_proc:
            socat_proc.terminate()
        master.close()

    atexit.register(cleanup)
    signal.signal(signal.SIGINT, lambda s, f: (cleanup(), sys.exit(0)))
    signal.signal(signal.SIGTERM, lambda s, f: (cleanup(), sys.exit(0)))

    print("=" * 60)
    print("DBeaver MFA SSH Tunnel (socat + exec nc)")
    print("=" * 60)
    print(f"  {BASTION_USER}@{BASTION_HOST}:{BASTION_PORT}")
    print(f"  -> {JUMP_USER}@{JUMP_HOST}:{JUMP_PORT}")
    print(f"     -> {DB_HOST}:{DB_PORT} (via nc on jump host)")
    print(f"  Local: {LOCAL_BIND}:{args.local_port}")
    print("=" * 60)
    print()

    print("[1/2] Establishing ControlMaster SSH connection...")
    if not master.start():
        print("[!] Failed")
        sys.exit(1)

    print("[2/2] Starting socat proxy...")

    # socat EXEC address: the command is split by socat internally
    # No quotes needed - socat handles spaces in EXEC by splitting on spaces
    ssh_exec = (
        f"ssh -S {CTRL_SOCK} "
        f"-o ControlMaster=no "
        f"-o ConnectTimeout=10 "
        f"-o StrictHostKeyChecking=accept-new "
        f"{JUMP_USER}@{JUMP_HOST} -p {JUMP_PORT} "
        f"nc {DB_HOST} {DB_PORT}"
    )

    socat_cmd = [
        "socat",
        f"TCP-LISTEN:{args.local_port},reuseaddr,fork",
        f"EXEC:{ssh_exec}"
    ]

    print(f"[socat] {' '.join(socat_cmd)}")
    socat_proc = subprocess.Popen(socat_cmd)

    # Wait for port
    for i in range(20):
        if port_listening(LOCAL_BIND, args.local_port):
            break
        time.sleep(0.5)

    if not port_listening(LOCAL_BIND, args.local_port):
        print("[!] socat failed to bind")
        cleanup()
        sys.exit(1)

    print()
    print("=" * 60)
    print("Tunnel is active!")
    print(f"  Host: {LOCAL_BIND}")
    print(f"  Port: {args.local_port}")
    print("  SSH Tunnel: Disabled (in DBeaver)")
    print("=" * 60)
    print()

    if args.dbeaver:
        subprocess.Popen([
            "open", "-n", "-a",
            "/Users/zoyoe/codex/my_dbeaver/tools/DBeaver-MFA.app",
            "--args", "-data",
            "/Users/zoyoe/codex/my_dbeaver/tools/dbeaver-mfa-workspace"
        ])

    print("Press Ctrl+C to stop")
    try:
        socat_proc.wait()
    except KeyboardInterrupt:
        pass
    finally:
        cleanup()
        print("[tunnel] Stopped")


if __name__ == "__main__":
    main()
