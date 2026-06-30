#!/usr/bin/env python3
"""macOS status bar app for managing SSH local forwards through a bastion host."""

from __future__ import annotations

import argparse
import os
import re
import signal
import shlex
import socket
import subprocess
import shutil
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

import pexpect
import yaml
import objc
from PyObjCTools import AppHelper

try:
    import rumps
except ModuleNotFoundError:  # pragma: no cover - depends on local macOS env
    rumps = None

try:  # pragma: no cover - depends on local macOS env
    from AppKit import (
        NSAlert,
        NSApplication,
        NSBackingStoreBuffered,
        NSBezelStyleRounded,
        NSButton,
        NSMakeRect,
        NSPopUpButton,
        NSTextField,
        NSWindow,
        NSWindowStyleMaskClosable,
        NSWindowStyleMaskMiniaturizable,
        NSWindowStyleMaskResizable,
        NSWindowStyleMaskTitled,
    )
    from Foundation import NSObject

    APPKIT_AVAILABLE = True
except Exception:  # pragma: no cover - depends on local macOS env
    NSObject = object
    APPKIT_AVAILABLE = False


STATUS_IDLE = "idle"
STATUS_CONNECTING = "connecting"
STATUS_CONNECTED = "connected"
STATUS_ERROR = "error"

DEFAULT_SSH_PASSWORD = "Mnjk@20252026"
NEW_TARGET_MENU_TITLE = "新建转发..."
AUTH_MAX_RETRIES = 3


@dataclass
class TargetConfig:
    key: str
    name: str
    ip: str
    port: int
    local_port: int
    description: str = ""
    bind_host: str = "127.0.0.1"


@dataclass
class BastionConfig:
    user: str
    host: str
    port: int


@dataclass
class JumpHostConfig:
    user: str
    host: str
    port: int


@dataclass
class AdvancedConfig:
    connect_timeout: int = 20
    bind_host: str = "127.0.0.1"
    strict_host_key_checking: str = "accept-new"
    check_interval: int = 5


@dataclass
class AppConfig:
    bastion: BastionConfig
    jump_host: JumpHostConfig
    targets: list[TargetConfig]
    advanced: AdvancedConfig
    config_path: Path


@dataclass
class ForwardSession:
    target: TargetConfig
    status: str = STATUS_IDLE
    message: str = "未连接"
    child: pexpect.spawn | None = None
    socat_proc: subprocess.Popen | None = None
    socat_path: str | None = None
    control_path: Path | None = None
    worker: threading.Thread | None = None
    stop_event: threading.Event = field(default_factory=threading.Event)


class ConfigError(RuntimeError):
    pass


APP_SUPPORT_DIR = Path.home() / ".ssh_forwarder"
DEFAULT_CONFIG_PATH = APP_SUPPORT_DIR / "config.yaml"
RUMPS_SUPPORT_DIR = APP_SUPPORT_DIR / "rumps"
LOG_PATH = APP_SUPPORT_DIR / "ssh_forward.log"
COMMON_EXECUTABLE_DIRS = (
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
)


def expand_path(raw_path: str) -> Path:
    return Path(os.path.expanduser(raw_path)).resolve()


def bundle_resource_path(filename: str) -> Path | None:
    try:
        from Foundation import NSBundle  # type: ignore

        bundle_path = NSBundle.mainBundle().resourcePath()
        if bundle_path:
            candidate = Path(str(bundle_path)) / filename
            if candidate.exists():
                return candidate
    except Exception:
        pass

    candidate = Path(__file__).resolve().with_name(filename)
    return candidate if candidate.exists() else None


def resolve_executable(name: str) -> str | None:
    bundled = bundle_resource_path(name)
    if bundled is not None and os.access(bundled, os.X_OK):
        return str(bundled)

    found = shutil.which(name)
    if found is not None:
        return found

    search_path = os.pathsep.join(COMMON_EXECUTABLE_DIRS)
    return shutil.which(name, path=search_path)


def ensure_default_config() -> Path:
    APP_SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
    if DEFAULT_CONFIG_PATH.exists():
        return DEFAULT_CONFIG_PATH

    template_path = bundle_resource_path("config.yaml")
    if template_path is None:
        raise ConfigError("未找到内置配置模板 config.yaml")

    shutil.copyfile(template_path, DEFAULT_CONFIG_PATH)
    return DEFAULT_CONFIG_PATH


def prepare_rumps_support_dir() -> str:
    RUMPS_SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
    return str(RUMPS_SUPPORT_DIR)


def config_to_dict(config: AppConfig) -> dict[str, Any]:
    targets: dict[str, dict[str, Any]] = {}
    for target in config.targets:
        target_data: dict[str, Any] = {
            "name": target.name,
            "ip": target.ip,
            "port": target.port,
            "local_port": target.local_port,
            "description": target.description,
        }
        if target.bind_host != config.advanced.bind_host:
            target_data["bind_host"] = target.bind_host
        targets[target.key] = target_data

    return {
        "bastion": {
            "user": config.bastion.user,
            "host": config.bastion.host,
            "port": config.bastion.port,
        },
        "jump_host": {
            "user": config.jump_host.user,
            "host": config.jump_host.host,
            "port": config.jump_host.port,
        },
        "targets": targets,
        "advanced": {
            "timeout": config.advanced.connect_timeout,
            "bind_host": config.advanced.bind_host,
            "strict_host_key_checking": config.advanced.strict_host_key_checking,
            "check_interval": config.advanced.check_interval,
        },
    }


def draft_from_target(target: TargetConfig) -> dict[str, str]:
    return {
        "key": target.key,
        "name": target.name,
        "ip": target.ip,
        "port": str(target.port),
        "local_port": str(target.local_port),
        "bind_host": target.bind_host,
        "description": target.description,
    }


def target_from_draft(draft: dict[str, str], default_bind_host: str) -> TargetConfig:
    key = draft["key"].strip()
    if not key:
        raise ConfigError("每个转发都需要一个标识")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", key):
        raise ConfigError(f"转发标识 `{key}` 只能包含字母、数字、_ 或 -")

    name = draft["name"].strip()
    if not name:
        raise ConfigError(f"转发 `{key}` 缺少名称")

    ip = draft["ip"].strip()
    if not ip:
        raise ConfigError(f"转发 `{key}` 缺少目标 IP")

    bind_host = draft["bind_host"].strip() or default_bind_host
    description = draft["description"].strip()

    try:
        port = int(draft["port"].strip())
    except ValueError as exc:
        raise ConfigError(f"转发 `{key}` 的目标端口必须是整数") from exc
    try:
        local_port = int(draft["local_port"].strip())
    except ValueError as exc:
        raise ConfigError(f"转发 `{key}` 的本地端口必须是整数") from exc

    if not (1 <= port <= 65535):
        raise ConfigError(f"转发 `{key}` 的目标端口必须在 1-65535 之间")
    if not (1 <= local_port <= 65535):
        raise ConfigError(f"转发 `{key}` 的本地端口必须在 1-65535 之间")

    return TargetConfig(
        key=key,
        name=name,
        ip=ip,
        port=port,
        local_port=local_port,
        description=description,
        bind_host=bind_host,
    )


def save_targets(config: AppConfig, targets: list[TargetConfig]) -> None:
    seen_keys: set[str] = set()
    seen_local_ports: set[tuple[str, int]] = set()
    for target in targets:
        if target.key in seen_keys:
            raise ConfigError(f"转发标识重复: {target.key}")
        seen_keys.add(target.key)

        port_signature = (target.bind_host, target.local_port)
        if port_signature in seen_local_ports:
            raise ConfigError(
                f"本地监听重复: {target.bind_host}:{target.local_port}"
            )
        seen_local_ports.add(port_signature)

    payload = config_to_dict(config)
    payload["targets"] = {}
    for target in targets:
        target_data: dict[str, Any] = {
            "name": target.name,
            "ip": target.ip,
            "port": target.port,
            "local_port": target.local_port,
            "description": target.description,
        }
        if target.bind_host != config.advanced.bind_host:
            target_data["bind_host"] = target.bind_host
        payload["targets"][target.key] = target_data

    with config.config_path.open("w", encoding="utf-8") as handle:
        yaml.safe_dump(payload, handle, allow_unicode=True, sort_keys=False)


def load_config(config_file: str) -> AppConfig:
    config_path = expand_path(config_file)
    if not config_path.exists():
        raise ConfigError(f"配置文件不存在: {config_path}")

    with config_path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}

    bastion_data = data.get("bastion") or {}
    if not bastion_data.get("user") or not bastion_data.get("host") or not bastion_data.get("port"):
        raise ConfigError("配置文件缺少 bastion.user / bastion.host / bastion.port")

    jump_data = data.get("jump_host") or {}
    jump_host = JumpHostConfig(
        user=str(jump_data.get("user", "mnyjy")),
        host=str(jump_data.get("host", "192.168.77.39")),
        port=int(jump_data.get("port", 22)),
    )

    advanced_data = data.get("advanced") or {}
    advanced = AdvancedConfig(
        connect_timeout=int(advanced_data.get("timeout", 20)),
        bind_host=str(advanced_data.get("bind_host", "127.0.0.1")),
        strict_host_key_checking=str(
            advanced_data.get("strict_host_key_checking", "accept-new")
        ),
        check_interval=max(2, int(advanced_data.get("check_interval", 5))),
    )

    targets_data = data.get("targets") or {}
    targets: list[TargetConfig] = []
    for key, raw_target in targets_data.items():
        local_port = raw_target.get("local_port") or raw_target.get("local")
        if local_port is None:
            continue
        targets.append(
            TargetConfig(
                key=str(key),
                name=str(raw_target.get("name", key)),
                ip=str(raw_target.get("ip")),
                port=int(raw_target.get("port")),
                local_port=int(local_port),
                description=str(raw_target.get("description", "")),
                bind_host=str(raw_target.get("bind_host", advanced.bind_host)),
            )
        )

    if not targets:
        raise ConfigError("配置文件中至少需要一个带 local_port 的 target")

    bastion = BastionConfig(
        user=str(bastion_data["user"]),
        host=str(bastion_data["host"]),
        port=int(bastion_data["port"]),
    )
    return AppConfig(
        bastion=bastion,
        jump_host=jump_host,
        targets=targets,
        advanced=advanced,
        config_path=config_path,
    )


def is_port_listening(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=1):
            return True
    except OSError:
        return False


def is_port_available(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind((host, port))
        except OSError:
            return False
    return True


def listening_pids(host: str, port: int) -> list[int]:
    lsof_path = resolve_executable("lsof") or "/usr/sbin/lsof"
    commands = [
        [lsof_path, "-nP", f"-iTCP@{host}:{port}", "-sTCP:LISTEN", "-t"],
        [lsof_path, "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-t"],
    ]
    pids: list[int] = []
    for command in commands:
        result = subprocess.run(command, check=False, capture_output=True, text=True)
        if result.returncode not in {0, 1}:
            continue
        for line in result.stdout.splitlines():
            try:
                pid = int(line.strip())
            except ValueError:
                continue
            if pid not in pids:
                pids.append(pid)
        if pids:
            break
    return pids


def process_command(pid: int) -> str:
    ps_path = resolve_executable("ps") or "/bin/ps"
    result = subprocess.run(
        [ps_path, "-p", str(pid), "-o", "command="],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def is_managed_socat_command(command: str, target: TargetConfig) -> bool:
    listen_arg = f"TCP-LISTEN:{target.local_port},bind={target.bind_host}"
    return (
        "socat" in command
        and listen_arg in command
        and "EXEC:ssh -S" in command
        and str(APP_SUPPORT_DIR) in command
    )


def stop_managed_socat_for_target(target: TargetConfig) -> int:
    stopped = 0
    for pid in listening_pids(target.bind_host, target.local_port):
        command = process_command(pid)
        if not is_managed_socat_command(command, target):
            continue
        try:
            os.kill(pid, signal.SIGTERM)
            stopped += 1
        except ProcessLookupError:
            pass
        except OSError as exc:
            append_log(f"[{target.key}] failed to stop stale socat pid {pid}: {exc}")

    if stopped:
        deadline = time.time() + 3
        while time.time() < deadline:
            if not any(
                is_managed_socat_command(process_command(pid), target)
                for pid in listening_pids(target.bind_host, target.local_port)
            ):
                break
            time.sleep(0.2)
    return stopped


def sanitize_error(message: str) -> str:
    compact = " ".join(part.strip() for part in message.splitlines() if part.strip())
    return compact[:180] if compact else "连接失败"


def append_log(message: str) -> None:
    APP_SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    with LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(f"[{timestamp}] {message}\n")


def summarize_ssh_output(*parts: Any) -> str:
    normalized: list[str] = []
    for part in parts:
        if part is None:
            continue
        text = part if isinstance(part, str) else str(part)
        text = text.strip()
        if text:
            normalized.append(text)
    text = " ".join(normalized)
    return sanitize_error(text)


def summarize_expect_state(child: pexpect.spawn) -> str:
    before = summarize_ssh_output(child.before)
    after = summarize_ssh_output(child.after)
    if before and after:
        return f"before={before!r} after={after!r}"
    if after:
        return f"after={after!r}"
    if before:
        return f"before={before!r}"
    return "before='' after=''"


def get_target_by_key(config: AppConfig, key: str) -> TargetConfig:
    for target in config.targets:
        if target.key == key:
            return target
    available = ", ".join(target.key for target in config.targets)
    raise ConfigError(f"未找到转发标识 `{key}`，可用项: {available}")


def run_on_main_thread(func: Callable[..., Any], *args: Any, **kwargs: Any) -> None:
    if threading.current_thread() is threading.main_thread():
        func(*args, **kwargs)
        return

    done = threading.Event()
    result: dict[str, Any] = {}

    def wrapper() -> None:
        try:
            result["value"] = func(*args, **kwargs)
        except Exception as exc:  # pragma: no cover - UI thread dispatch
            result["error"] = exc
        finally:
            done.set()

    AppHelper.callAfter(wrapper)
    done.wait()
    if "error" in result:
        raise result["error"]


def call_on_main_thread(func: Callable[..., Any], *args: Any, **kwargs: Any) -> Any:
    if threading.current_thread() is threading.main_thread():
        return func(*args, **kwargs)

    done = threading.Event()
    result: dict[str, Any] = {}

    def wrapper() -> None:
        try:
            result["value"] = func(*args, **kwargs)
        except Exception as exc:  # pragma: no cover - UI thread dispatch
            result["error"] = exc
        finally:
            done.set()

    AppHelper.callAfter(wrapper)
    done.wait()
    if "error" in result:
        raise result["error"]
    return result.get("value")


class SSHSessionManager:
    def __init__(self, config: AppConfig, notifier: Callable[[], None]):
        self.config = config
        self.notifier = notifier
        self.sessions = {target.key: ForwardSession(target=target) for target in config.targets}
        self._lock = threading.Lock()

    def _notify(self) -> None:
        run_on_main_thread(self.notifier)

    def _notify_error(self, title: str, message: str) -> None:
        def show() -> None:
            if rumps is not None:
                rumps.notification("SSH Forward Tool", title, message)

        run_on_main_thread(show)

    def list_sessions(self) -> list[ForwardSession]:
        return [self.sessions[target.key] for target in self.config.targets]

    def get(self, key: str) -> ForwardSession:
        return self.sessions[key]

    def start(self, key: str) -> tuple[bool, str]:
        session = self.get(key)
        with self._lock:
            if session.status in {STATUS_CONNECTING, STATUS_CONNECTED}:
                return False, "该转发已经在运行"
            socat_path = resolve_executable("socat")
            if socat_path is None:
                session.status = STATUS_ERROR
                session.message = "未找到 socat，请先安装: brew install socat"
                self._notify()
                return False, session.message
            session.socat_path = socat_path
            if not is_port_available(session.target.bind_host, session.target.local_port):
                stopped = stop_managed_socat_for_target(session.target)
                if stopped and is_port_available(
                    session.target.bind_host, session.target.local_port
                ):
                    append_log(
                        f"[{session.target.key}] stopped {stopped} stale socat listener(s)"
                    )
                else:
                    session.status = STATUS_ERROR
                    session.message = f"本地端口 {session.target.local_port} 已被占用"
                    self._notify()
                    return False, session.message
            if not is_port_available(session.target.bind_host, session.target.local_port):
                session.status = STATUS_ERROR
                session.message = f"本地端口 {session.target.local_port} 已被占用"
                self._notify()
                return False, session.message
            session.stop_event = threading.Event()
            session.status = STATUS_CONNECTING
            session.message = "正在建立连接"
            session.worker = threading.Thread(
                target=self._run_session,
                args=(session,),
                name=f"ssh-forward-{key}",
                daemon=True,
            )
            session.worker.start()
        self._notify()
        return True, "开始连接"

    def stop(self, key: str) -> tuple[bool, str]:
        session = self.get(key)
        with self._lock:
            if session.status == STATUS_IDLE:
                return False, "该转发未运行"
            session.stop_event.set()
            child = session.child
        if child is not None and child.isalive():
            try:
                child.close(force=True)
            except Exception:
                pass
        proc = session.socat_proc
        if proc is not None and proc.poll() is None:
            try:
                proc.terminate()
                proc.wait(timeout=3)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass
        self._remove_control_path(session)
        with self._lock:
            session.child = None
            session.socat_proc = None
            session.control_path = None
            session.status = STATUS_IDLE
            session.message = "已停止"
        self._notify()
        return True, "已停止转发"

    def stop_all(self) -> None:
        for key in list(self.sessions):
            self.stop(key)
        for session in self.list_sessions():
            stopped = stop_managed_socat_for_target(session.target)
            if stopped:
                append_log(
                    f"[{session.target.key}] stopped {stopped} stale socat listener(s)"
                )

    def _control_path_for(self, session: ForwardSession) -> Path:
        return APP_SUPPORT_DIR / f"control-{session.target.key}.sock"

    def _remove_control_path(self, session: ForwardSession) -> None:
        control_path = session.control_path
        if control_path is None:
            return
        try:
            control_path.unlink()
        except FileNotFoundError:
            pass
        except OSError as exc:
            append_log(f"[{session.target.key}] failed to remove control socket: {exc}")

    def _build_command(self, session: ForwardSession) -> list[str]:
        bastion = self.config.bastion
        jump = self.config.jump_host
        advanced = self.config.advanced
        APP_SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
        session.control_path = self._control_path_for(session)
        try:
            session.control_path.unlink()
        except FileNotFoundError:
            pass
        return [
            "ssh",
            "-N",
            "-J",
            f"{bastion.user}@{bastion.host}:{bastion.port}",
            "-o",
            f"ConnectTimeout={advanced.connect_timeout}",
            "-o",
            "ServerAliveInterval=30",
            "-o",
            "ServerAliveCountMax=3",
            "-o",
            f"StrictHostKeyChecking={advanced.strict_host_key_checking}",
            "-o",
            "PreferredAuthentications=password,keyboard-interactive",
            "-o",
            "PubkeyAuthentication=no",
            "-o",
            "ControlMaster=yes",
            "-o",
            f"ControlPath={session.control_path}",
            f"{jump.user}@{jump.host}",
            "-p",
            str(jump.port),
        ]

    def _build_socat_command(self, session: ForwardSession) -> list[str]:
        target = session.target
        jump = self.config.jump_host
        advanced = self.config.advanced
        if session.control_path is None:
            raise RuntimeError("ControlMaster socket 尚未初始化")
        socat_path = session.socat_path or resolve_executable("socat")
        if socat_path is None:
            raise RuntimeError("未找到 socat，请先安装: brew install socat")
        ssh_exec = " ".join(
            [
                "ssh",
                "-S",
                shlex.quote(str(session.control_path)),
                "-o",
                "ControlMaster=no",
                "-o",
                "ConnectTimeout=10",
                "-o",
                f"StrictHostKeyChecking={shlex.quote(advanced.strict_host_key_checking)}",
                f"{shlex.quote(jump.user)}@{shlex.quote(jump.host)}",
                "-p",
                str(jump.port),
                "nc",
                shlex.quote(target.ip),
                str(target.port),
            ]
        )
        return [
            socat_path,
            f"TCP-LISTEN:{target.local_port},bind={target.bind_host},reuseaddr,fork",
            f"EXEC:{ssh_exec}",
        ]

    def _run_session(self, session: ForwardSession) -> None:
        command = self._build_command(session)
        append_log(
            f"[{session.target.key}] start ControlMaster via "
            f"{self.config.bastion.user}@{self.config.bastion.host}:{self.config.bastion.port} "
            f"to {self.config.jump_host.user}@{self.config.jump_host.host}:{self.config.jump_host.port}; "
            f"target {session.target.ip}:{session.target.port}"
        )
        child = pexpect.spawn(command[0], command[1:], encoding="utf-8", timeout=120)
        child.delaybeforesend = 0.05
        with self._lock:
            session.child = child

        try:
            self._drive_auth(session, child)
            if session.stop_event.is_set():
                return

            deadline = time.time() + self.config.advanced.connect_timeout
            control_ready = False
            while time.time() < deadline:
                if session.stop_event.is_set():
                    return
                if session.control_path and session.control_path.exists():
                    control_ready = True
                    break
                if not child.isalive():
                    break
                time.sleep(0.2)

            if not control_ready:
                error_output = (child.before or "").strip()
                append_log(
                    f"[{session.target.key}] control master failed: "
                    f"{summarize_ssh_output(error_output)}"
                )
                raise RuntimeError(error_output or "ControlMaster 未建立成功")

            socat_command = self._build_socat_command(session)
            append_log(f"[{session.target.key}] start socat: {' '.join(socat_command)}")
            socat_proc = subprocess.Popen(
                socat_command,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
            with self._lock:
                session.socat_proc = socat_proc

            deadline = time.time() + self.config.advanced.connect_timeout
            while time.time() < deadline:
                if session.stop_event.is_set():
                    return
                if is_port_listening(session.target.bind_host, session.target.local_port):
                    with self._lock:
                        session.status = STATUS_CONNECTED
                        session.message = (
                            f"已连接 localhost:{session.target.local_port} -> "
                            f"{session.target.ip}:{session.target.port}"
                        )
                    self._notify()
                    self._wait_until_exit(session, child)
                    return
                if socat_proc.poll() is not None:
                    break
                if not child.isalive():
                    break
                time.sleep(0.2)

            error_output = (child.before or "").strip()
            socat_error = ""
            if session.socat_proc is not None and session.socat_proc.stderr is not None:
                try:
                    socat_error = session.socat_proc.stderr.read() or ""
                except Exception:
                    socat_error = ""
            output = summarize_ssh_output(error_output, socat_error)
            append_log(f"[{session.target.key}] connect failed: {output}")
            raise RuntimeError(output or "socat 本地监听未建立成功")
        except Exception as exc:
            if session.stop_event.is_set():
                with self._lock:
                    session.status = STATUS_IDLE
                    session.message = "已停止"
                append_log(f"[{session.target.key}] stopped by user")
            else:
                with self._lock:
                    session.status = STATUS_ERROR
                    session.message = sanitize_error(str(exc))
                append_log(f"[{session.target.key}] error: {session.message}")
                self._notify_error(session.target.name, session.message)
            self._notify()
        finally:
            proc = session.socat_proc
            if proc is not None and proc.poll() is None:
                try:
                    proc.terminate()
                    proc.wait(timeout=3)
                except Exception:
                    try:
                        proc.kill()
                    except Exception:
                        pass
            if child.isalive():
                try:
                    child.close(force=True)
                except Exception:
                    pass
            self._remove_control_path(session)
            with self._lock:
                session.child = None
                session.socat_proc = None
                session.control_path = None
                session.worker = None
                if session.status == STATUS_CONNECTING:
                    session.status = STATUS_ERROR
                    session.message = "连接中断"
            if session.status == STATUS_CONNECTED:
                append_log(f"[{session.target.key}] session disconnected")
            self._notify()

    def _drive_auth(self, session: ForwardSession, child: pexpect.spawn) -> None:
        prompts = [
            r"(?i)are you sure you want to continue connecting \(yes/no(/\[fingerprint\])?\)\?",
            r"(?i)(?:password|passphrase).*:",
            r"(?i)(?:verification code|verification|mfa|otp|token|duo passcode).*:",
            r"(?i)permission denied",
            r"(?i)connection (?:closed|refused|reset)",
            r"(?i)could not resolve hostname",
            pexpect.EOF,
            pexpect.TIMEOUT,
        ]
        mfa_supplied = False
        password_attempts = 0
        mfa_attempts = 0
        last_auth_error = ""
        prompt_names = {
            0: "hostkey_confirm",
            1: "password_prompt",
            2: "mfa_prompt",
            3: "permission_denied",
            4: "connection_closed",
            5: "resolve_error",
            6: "eof",
            7: "timeout",
        }

        while True:
            if session.stop_event.is_set():
                raise RuntimeError("连接已取消")
            if session.control_path and session.control_path.exists():
                append_log(f"[{session.target.key}] control socket ready")
                break
            index = child.expect(prompts, timeout=max(10, self.config.advanced.connect_timeout))
            append_log(
                f"[{session.target.key}] expect={index}:{prompt_names.get(index, 'unknown')} "
                f"{summarize_expect_state(child)}"
            )
            if index == 0:
                append_log(f"[{session.target.key}] send hostkey confirmation")
                child.sendline("yes")
                continue
            if index == 1:
                if password_attempts >= AUTH_MAX_RETRIES:
                    raise RuntimeError("SSH 密码重试次数过多")
                default_password = DEFAULT_SSH_PASSWORD if password_attempts == 0 else ""
                message = f"输入 {self.config.bastion.user}@{self.config.bastion.host} 的密码"
                if last_auth_error:
                    message = f"{last_auth_error}\n\n{message}"
                password = prompt_secret(
                    f"{session.target.name}: SSH 密码",
                    message,
                    default_value=default_password,
                )
                if password is None:
                    raise RuntimeError("已取消输入密码")
                password_attempts += 1
                last_auth_error = ""
                append_log(
                    f"[{session.target.key}] captured password attempt {password_attempts} "
                    f"len={len(password)}"
                )
                child.sendline(password)
                append_log(f"[{session.target.key}] sent password attempt {password_attempts}")
                continue
            if index == 2:
                if mfa_attempts >= AUTH_MAX_RETRIES:
                    raise RuntimeError("MFA 验证失败次数过多")
                message = "输入动态验证码或二次验证口令"
                if last_auth_error:
                    message = f"{last_auth_error}\n\n{message}"
                code = prompt_secret(
                    f"{session.target.name}: MFA 验证码",
                    message,
                )
                if code is None:
                    raise RuntimeError("已取消输入 MFA 验证码")
                mfa_supplied = True
                mfa_attempts += 1
                last_auth_error = ""
                append_log(
                    f"[{session.target.key}] captured mfa attempt {mfa_attempts} len={len(code)}"
                )
                child.sendline(code)
                append_log(f"[{session.target.key}] sent mfa attempt {mfa_attempts}")
                continue
            if index == 3:
                output = summarize_ssh_output(child.before, child.after)
                append_log(
                    f"[{session.target.key}] auth denied: {output} "
                    f"password_attempts={password_attempts} mfa_attempts={mfa_attempts} "
                    f"mfa_supplied={mfa_supplied}"
                )
                if child.isalive() and "please try again" in output.lower():
                    last_auth_error = (
                        "MFA 或密码错误，请重新输入"
                        if mfa_supplied
                        else "密码错误，请重新输入"
                    )
                    continue
                raise RuntimeError("SSH 认证失败，请检查账号、密码或 MFA 验证码")
            if index in {4, 5}:
                output = summarize_ssh_output(child.before, child.after)
                append_log(f"[{session.target.key}] ssh error: {output}")
                raise RuntimeError(output or "SSH 连接失败")
            if index == 6:
                if session.control_path and session.control_path.exists():
                    break
                break
            if index == 7:
                if session.control_path and session.control_path.exists():
                    break
                continue

    def _wait_until_exit(self, session: ForwardSession, child: pexpect.spawn) -> None:
        while not session.stop_event.is_set():
            if not child.isalive():
                if session.status == STATUS_CONNECTED:
                    raise RuntimeError("SSH 会话已断开")
                return
            time.sleep(self.config.advanced.check_interval)


def probe_auth_flow(
    config: AppConfig,
    target_key: str,
    password: str,
    timeout: int,
) -> int:
    target = get_target_by_key(config, target_key)
    session = ForwardSession(target=target)
    manager = SSHSessionManager(config, notifier=lambda: None)
    command = manager._build_command(session)

    print(f"开始测试认证链路: {target.key} ({target.name})")
    print("命中 OTP 提示后会立即退出，不会真正保持转发。")
    append_log(f"[{target.key}] debug auth probe start")

    child = pexpect.spawn(command[0], command[1:], encoding="utf-8", timeout=timeout)
    child.delaybeforesend = 0.05
    password_sent = False

    prompts = [
        r"(?i)are you sure you want to continue connecting \(yes/no(/\[fingerprint\])?\)\?",
        r"(?i)(?:password|passphrase).*:",
        r"(?i)(?:verification code|verification|mfa|otp|token|duo passcode).*:",
        r"(?i)permission denied",
        r"(?i)connection (?:closed|refused|reset)",
        r"(?i)could not resolve hostname",
        pexpect.EOF,
        pexpect.TIMEOUT,
    ]
    prompt_names = {
        0: "hostkey_confirm",
        1: "password_prompt",
        2: "mfa_prompt",
        3: "permission_denied",
        4: "connection_closed",
        5: "resolve_error",
        6: "eof",
        7: "timeout",
    }

    try:
        while True:
            index = child.expect(prompts, timeout=timeout)
            summary = summarize_expect_state(child)
            print(f"expect={prompt_names.get(index, index)} {summary}")
            append_log(f"[{target.key}] debug expect={index}:{prompt_names.get(index, 'unknown')} {summary}")

            if index == 0:
                child.sendline("yes")
                print("已自动确认 host key。")
                append_log(f"[{target.key}] debug sent hostkey confirmation")
                continue

            if index == 1:
                if password_sent:
                    print("结果: 密码被再次请求，认证未进入 OTP。")
                    append_log(f"[{target.key}] debug password requested again")
                    return 2
                child.sendline(password)
                password_sent = True
                print(f"已发送默认密码，长度={len(password)}。")
                append_log(f"[{target.key}] debug sent default password len={len(password)}")
                continue

            if index == 2:
                print("结果: 已进入二次口令 / OTP 验证阶段。")
                append_log(f"[{target.key}] debug reached mfa prompt")
                return 0

            if index == 3:
                output = summarize_ssh_output(child.before, child.after)
                print(f"结果: 认证被拒绝: {output}")
                append_log(f"[{target.key}] debug auth denied: {output}")
                return 1

            if index in {4, 5}:
                output = summarize_ssh_output(child.before, child.after)
                print(f"结果: SSH 错误: {output}")
                append_log(f"[{target.key}] debug ssh error: {output}")
                return 1

            if index == 6:
                output = summarize_ssh_output(child.before, child.after)
                print(f"结果: 会话提前结束: {output or 'EOF'}")
                append_log(f"[{target.key}] debug eof: {output or 'EOF'}")
                return 1

            output = summarize_ssh_output(child.before, child.after)
            print(f"结果: 等待超时: {output or 'no output'}")
            append_log(f"[{target.key}] debug timeout: {output or 'no output'}")
            return 1
    finally:
        if child.isalive():
            try:
                child.close(force=True)
            except Exception:
                pass


if APPKIT_AVAILABLE:  # pragma: no branch - UI wiring only exists on macOS env
    class ConfigWindowController(NSObject):
        def initWithApp_(self, app):
            self = self.init()
            if self is None:
                return None
            self.app = app
            self.window = None
            self.selector = None
            self.fields: dict[str, Any] = {}
            self.drafts: list[dict[str, str]] = []
            self.current_index = 0
            self._build_window()
            self.reload_from_config(app.config)
            return self

        @objc.python_method
        def _build_window(self) -> None:
            style_mask = (
                NSWindowStyleMaskTitled
                | NSWindowStyleMaskClosable
                | NSWindowStyleMaskResizable
                | NSWindowStyleMaskMiniaturizable
            )
            self.window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
                NSMakeRect(0, 0, 560, 340),
                style_mask,
                NSBackingStoreBuffered,
                False,
            )
            self.window.setTitle_("配置转发")
            self.window.center()
            content = self.window.contentView()

            selector_label = self._label("转发项", 24, 292, 60)
            content.addSubview_(selector_label)

            selector = NSPopUpButton.alloc().initWithFrame_(NSMakeRect(92, 288, 240, 28))
            selector.setTarget_(self)
            selector.setAction_("onTargetChanged:")
            content.addSubview_(selector)
            self.selector = selector

            add_button = self._button("新建", 344, 287, 72, "onAddTarget:")
            delete_button = self._button("删除", 424, 287, 72, "onDeleteTarget:")
            content.addSubview_(add_button)
            content.addSubview_(delete_button)

            field_specs = [
                ("key", "标识", 24, 240),
                ("name", "名称", 292, 240),
                ("ip", "目标IP", 24, 188),
                ("port", "目标端口", 292, 188),
                ("local_port", "本地端口", 24, 136),
                ("bind_host", "监听地址", 292, 136),
                ("description", "说明", 24, 84),
            ]
            for key, label, x, y in field_specs:
                content.addSubview_(self._label(label, x, y + 20, 80))
                width = 236 if key != "description" else 504
                height = 24 if key != "description" else 48
                field = self._text_field(x, y, width, height)
                content.addSubview_(field)
                self.fields[key] = field

            save_button = self._button("保存并重载", 332, 24, 164, "onSave:")
            close_button = self._button("关闭", 420, 24, 76, "onClose:")
            content.addSubview_(save_button)
            content.addSubview_(close_button)

        @objc.python_method
        def _label(self, text: str, x: float, y: float, width: float):
            label = NSTextField.alloc().initWithFrame_(NSMakeRect(x, y, width, 18))
            label.setStringValue_(text)
            label.setBezeled_(False)
            label.setDrawsBackground_(False)
            label.setEditable_(False)
            label.setSelectable_(False)
            return label

        @objc.python_method
        def _text_field(self, x: float, y: float, width: float, height: float):
            field = NSTextField.alloc().initWithFrame_(NSMakeRect(x, y, width, height))
            return field

        @objc.python_method
        def _button(self, title: str, x: float, y: float, width: float, action: str):
            button = NSButton.alloc().initWithFrame_(NSMakeRect(x, y, width, 30))
            button.setTitle_(title)
            button.setBezelStyle_(NSBezelStyleRounded)
            button.setTarget_(self)
            button.setAction_(action)
            return button

        @objc.python_method
        def show(self) -> None:
            self.reload_from_config(self.app.config)
            NSApplication.sharedApplication().activateIgnoringOtherApps_(True)
            self.window.makeKeyAndOrderFront_(None)

        @objc.python_method
        def reload_from_config(self, config: AppConfig) -> None:
            self.drafts = [draft_from_target(target) for target in config.targets]
            if not self.drafts:
                self.drafts = [self._new_draft()]
            self.current_index = 0
            self._refresh_selector()
            self._load_current_into_fields()

        @objc.python_method
        def _refresh_selector(self) -> None:
            self.selector.removeAllItems()
            for draft in self.drafts:
                title = draft["name"].strip() or draft["key"].strip() or "未命名转发"
                self.selector.addItemWithTitle_(title)
            self.selector.addItemWithTitle_(NEW_TARGET_MENU_TITLE)
            self.selector.selectItemAtIndex_(self.current_index)

        @objc.python_method
        def _new_draft(self) -> dict[str, str]:
            return {
                "key": "",
                "name": "",
                "ip": "",
                "port": "22",
                "local_port": "",
                "bind_host": self.app.config.advanced.bind_host,
                "description": "",
            }

        @objc.python_method
        def _persist_fields(self) -> None:
            if not self.drafts:
                return
            current = self.drafts[self.current_index]
            for key, field in self.fields.items():
                current[key] = str(field.stringValue())

        @objc.python_method
        def _load_current_into_fields(self) -> None:
            current = self.drafts[self.current_index]
            for key, field in self.fields.items():
                field.setStringValue_(current.get(key, ""))

        @objc.python_method
        def _show_error(self, message: str) -> None:
            alert = NSAlert.alloc().init()
            alert.setMessageText_("配置保存失败")
            alert.setInformativeText_(message)
            alert.addButtonWithTitle_("知道了")
            alert.runModal()

        @objc.python_method
        def _show_info(self, message: str) -> None:
            alert = NSAlert.alloc().init()
            alert.setMessageText_("配置已保存")
            alert.setInformativeText_(message)
            alert.addButtonWithTitle_("好的")
            alert.runModal()

        def onTargetChanged_(self, _sender) -> None:
            selected = self.selector.indexOfSelectedItem()
            self._persist_fields()
            if selected == len(self.drafts):
                self.drafts.append(self._new_draft())
                self.current_index = len(self.drafts) - 1
                self._refresh_selector()
            else:
                self.current_index = max(0, min(selected, len(self.drafts) - 1))
            self._load_current_into_fields()

        def onAddTarget_(self, _sender) -> None:
            self._persist_fields()
            self.drafts.append(self._new_draft())
            self.current_index = len(self.drafts) - 1
            self._refresh_selector()
            self._load_current_into_fields()

        def onDeleteTarget_(self, _sender) -> None:
            if len(self.drafts) <= 1:
                self._show_error("至少保留一个转发目标")
                return
            del self.drafts[self.current_index]
            self.current_index = max(0, min(self.current_index, len(self.drafts) - 1))
            self._refresh_selector()
            self._load_current_into_fields()

        def onSave_(self, _sender) -> None:
            self._persist_fields()
            try:
                targets = [
                    target_from_draft(draft, self.app.config.advanced.bind_host)
                    for draft in self.drafts
                ]
                save_targets(self.app.config, targets)
                self.app.reload_config_from_disk(notify_saved=True)
            except Exception as exc:
                self._show_error(str(exc))
                return

            self.reload_from_config(self.app.config)
            self._show_info(str(self.app.config.config_path))

        def onClose_(self, _sender) -> None:
            self.window.orderOut_(None)


def prompt_secret(title: str, message: str, default_value: str = "") -> str | None:
    if threading.current_thread() is not threading.main_thread():
        return call_on_main_thread(prompt_secret, title, message, default_value)

    def apple_quote(value: str) -> str:
        return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'

    script = (
        f"display dialog {apple_quote(message)} with title {apple_quote(title)} "
        f"default answer {apple_quote(default_value)} with hidden answer "
        'buttons {"取消", "确定"} default button "确定" cancel button "取消"'
    )
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            check=False,
            capture_output=True,
            text=True,
        )
    except Exception:
        result = None

    if result and result.returncode == 0:
        for line in result.stdout.splitlines():
            match = re.search(r"text returned:(.*?)(?:, button returned:|$)", line)
            if match:
                return match.group(1).strip()
        return ""
    if result and result.returncode != 0:
        stderr = result.stderr.lower()
        if "user canceled" in stderr:
            return None

    if rumps is None:
        return None

    window = rumps.Window(
        title=title,
        message=message,
        default_text=default_value,
        ok="确定",
        cancel="取消",
        dimensions=(320, 24),
    )
    response = window.run()
    if response.clicked != 1:
        return None
    return response.text.strip()


BaseApp = rumps.App if rumps is not None else object


class SSHForwardStatusBarApp(BaseApp):
    def __init__(self, config: AppConfig):
        if rumps is None:
            raise RuntimeError("缺少 rumps 依赖，请先安装 requirements.txt")
        rumps.rumps.application_support = lambda _name: prepare_rumps_support_dir()
        super().__init__("SSH Forward Tool", title="SSH:--", quit_button=None)
        self.config = config
        self.manager = SSHSessionManager(config, self.refresh_menu)
        self.refresh_timer = rumps.Timer(self.refresh_menu, 2)
        self._item_map: dict[str, rumps.MenuItem] = {}
        self._config_window = None
        self._build_menu()
        self.refresh_menu(None)
        self.refresh_timer.start()

    def _build_menu(self) -> None:
        self.menu.clear()
        status_header = rumps.MenuItem("状态")
        status_header.set_callback(None)
        self.menu.add(status_header)
        self.menu.add(None)

        for session in self.manager.list_sessions():
            item = rumps.MenuItem(self._target_title(session), callback=self._toggle_target)
            self.menu.add(item)
            self._item_map[session.target.key] = item

        self.menu.add(None)
        self.menu.add(rumps.MenuItem("配置转发...", callback=self._open_config_window))
        self.menu.add(rumps.MenuItem("重新加载配置", callback=self._reload_config))
        self.menu.add(rumps.MenuItem("停止全部转发", callback=self._stop_all))
        self.menu.add(rumps.MenuItem("退出", callback=self._quit_app))

    def refresh_menu(self, _sender=None) -> None:
        connected = 0
        connecting = 0
        for session in self.manager.list_sessions():
            item = self._item_map.get(session.target.key)
            if item is None:
                continue
            item.title = self._target_title(session)
            item.state = 1 if session.status == STATUS_CONNECTED else 0
            if session.status == STATUS_CONNECTED:
                connected += 1
            elif session.status == STATUS_CONNECTING:
                connecting += 1
        if connecting:
            self.title = f"SSH:{connected}+{connecting}"
        elif connected:
            self.title = f"SSH:{connected}"
        else:
            self.title = "SSH:--"

    def _target_title(self, session: ForwardSession) -> str:
        target = session.target
        prefix = {
            STATUS_IDLE: "🔴",
            STATUS_CONNECTING: "🟡",
            STATUS_CONNECTED: "🟢",
            STATUS_ERROR: "🔴",
        }[session.status]
        endpoint = f"localhost:{target.local_port} -> {target.ip}:{target.port}"
        return f"{prefix} {target.name} | {endpoint} | {session.message}"

    def _toggle_target(self, sender: Any) -> None:
        key = self._key_for_item(sender)
        if key is None:
            return
        session = self.manager.get(key)
        if session.status in {STATUS_CONNECTED, STATUS_CONNECTING}:
            ok, message = self.manager.stop(key)
        else:
            ok, message = self.manager.start(key)
        if not ok:
            rumps.notification("SSH Forward Tool", session.target.name, message)
        self.refresh_menu()

    def _reload_config(self, _sender: Any) -> None:
        self.reload_config_from_disk(notify_saved=False)

    def reload_config_from_disk(self, notify_saved: bool) -> None:
        try:
            new_config = load_config(str(self.config.config_path))
        except Exception as exc:
            rumps.alert(title="重新加载失败", message=str(exc), ok="知道了")
            return
        self.manager.stop_all()
        self.config = new_config
        self.manager = SSHSessionManager(new_config, self.refresh_menu)
        self._item_map = {}
        self._build_menu()
        self.refresh_menu()
        if self._config_window is not None:
            self._config_window.reload_from_config(new_config)
        subtitle = "配置已保存并重载" if notify_saved else "配置已重新加载"
        rumps.notification("SSH Forward Tool", subtitle, str(new_config.config_path))

    def _stop_all(self, _sender: Any) -> None:
        self.manager.stop_all()
        self.refresh_menu()

    def _open_config_window(self, _sender: Any) -> None:
        if not APPKIT_AVAILABLE:
            rumps.alert(
                title="当前环境不支持",
                message="未检测到 macOS 原生窗口依赖，无法打开配置窗口。",
                ok="知道了",
            )
            return
        if self._config_window is None:
            self._config_window = ConfigWindowController.alloc().initWithApp_(self)
        self._config_window.show()

    def _quit_app(self, _sender: Any) -> None:
        self.manager.stop_all()
        rumps.quit_application()

    def _key_for_item(self, item: Any) -> str | None:
        for key, current in self._item_map.items():
            if current is item:
                return key
        return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="SSH 转发状态栏工具")
    parser.add_argument(
        "-c",
        "--config",
        default=str(DEFAULT_CONFIG_PATH),
        help=f"配置文件路径 (默认: {DEFAULT_CONFIG_PATH})",
    )
    parser.add_argument(
        "--check-config",
        action="store_true",
        help="只校验配置文件，不启动状态栏应用",
    )
    parser.add_argument(
        "--debug-auth",
        metavar="TARGET_KEY",
        help="调试指定转发的认证流程，自动发送默认密码并在出现 OTP 提示后退出",
    )
    parser.add_argument(
        "--debug-timeout",
        type=int,
        default=30,
        help="调试认证流程时每次等待提示的超时时间，默认 30 秒",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.config == str(DEFAULT_CONFIG_PATH):
        try:
            ensure_default_config()
        except Exception as exc:
            print(f"初始化默认配置失败: {exc}")
            return 1
    try:
        config = load_config(args.config)
    except Exception as exc:
        print(f"配置错误: {exc}")
        return 1

    if args.check_config:
        print(f"配置文件可用: {config.config_path}")
        print(f"已加载 {len(config.targets)} 个转发目标")
        return 0

    if args.debug_auth:
        return probe_auth_flow(
            config,
            args.debug_auth,
            DEFAULT_SSH_PASSWORD,
            max(5, args.debug_timeout),
        )

    if rumps is None:
        print("缺少依赖: rumps。请先运行 `pip3 install -r requirements.txt`。")
        return 1

    app = SSHForwardStatusBarApp(config)

    def _handle_signal(_signum, _frame) -> None:
        app.manager.stop_all()
        rumps.quit_application()

    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)
    app.run(debug=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
