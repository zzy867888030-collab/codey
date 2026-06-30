# -*- mode: python ; coding: utf-8 -*-

import os

from PyInstaller.utils.hooks import collect_submodules


os.environ.setdefault("PYINSTALLER_CONFIG_DIR", os.path.abspath("build/pyinstaller-cache"))


hiddenimports = collect_submodules("rumps") + collect_submodules("Foundation")


a = Analysis(
    ["ssh_forward.py"],
    pathex=[],
    binaries=[],
    datas=[("config.yaml", ".")],
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tkinter", "_tkinter", "turtle", "matplotlib"],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="SSH Forward Tool",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="SSH Forward Tool",
)

app = BUNDLE(
    coll,
    name="SSH Forward Tool.app",
    icon="app_icon.icns",
    bundle_identifier="com.zoyoe.sshforwardtool",
    info_plist={
        "CFBundleName": "SSH Forward Tool",
        "CFBundleDisplayName": "SSH Forward Tool",
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "1",
        "LSUIElement": True,
        "NSAppleEventsUsageDescription": "SSH Forward Tool uses AppleScript dialogs to securely prompt for SSH passwords and MFA codes.",
    },
)
