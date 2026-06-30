from setuptools import setup


APP = ["ssh_forward.py"]
DATA_FILES = ["config.yaml", "app_icon.icns"]
OPTIONS = {
    "argv_emulation": False,
    "iconfile": "app_icon.icns",
    "excludes": ["tkinter", "_tkinter", "pydoc", "idlelib"],
    "packages": ["rumps", "yaml", "pexpect"],
    "plist": {
        "CFBundleName": "SSH Forward Tool",
        "CFBundleDisplayName": "SSH Forward Tool",
        "CFBundleIdentifier": "com.zoyoe.sshforwardtool",
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "1",
        "LSUIElement": True,
        "NSAppleEventsUsageDescription": "SSH Forward Tool uses AppleScript dialogs to securely prompt for SSH passwords and MFA codes.",
    },
}


setup(
    app=APP,
    data_files=DATA_FILES,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
