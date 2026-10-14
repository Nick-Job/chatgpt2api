# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller 打包配置：把 ChatGPT2API 后端封装成单目录桌面程序。

产物结构（安装目录）：

    ChatGPT2API.exe          启动器（内置 Python 运行时）
    _internal/               依赖与标准库
    web_dist/                Next.js 静态前端
    config.json              配置
    VERSION                  版本号

web_dist / config.json / VERSION 作为普通文件随安装包分发，方便用户直接修改配置。
"""

import sys
from pathlib import Path

from PyInstaller.utils.hooks import (
    collect_all,
    collect_submodules,
    copy_metadata,
)

ROOT = Path(SPECPATH).resolve().parent

datas = []
binaries = []
hiddenimports = []


def _collect_all(package: str) -> None:
    """收集带二进制/数据文件的依赖，缺失时静默跳过。"""
    try:
        package_datas, package_binaries, package_hiddenimports = collect_all(package)
    except Exception:
        return
    datas.extend(package_datas)
    binaries.extend(package_binaries)
    hiddenimports.extend(package_hiddenimports)


def _collect_submodules(package: str) -> None:
    try:
        hiddenimports.extend(collect_submodules(package))
    except Exception:
        return


def _copy_metadata(distribution: str) -> None:
    try:
        datas.extend(copy_metadata(distribution))
    except Exception:
        return


# 带本地扩展 / 证书 / 编码文件的依赖
for _package in ("curl_cffi", "tiktoken", "tiktoken_ext", "psycopg2", "pybase64", "certifi"):
    _collect_all(_package)

# 依赖动态导入的模块（ASGI 协议、数据库方言、Git 后端等）
for _package in (
    "uvicorn",
    "sqlalchemy",
    "gitdb",
    "smmap",
    "anyio",
    "h11",
    "websockets",
    "multipart",
):
    _collect_submodules(_package)

hiddenimports += [
    "uvicorn.logging",
    "uvicorn.loops",
    "uvicorn.loops.auto",
    "uvicorn.loops.asyncio",
    "uvicorn.protocols",
    "uvicorn.protocols.http",
    "uvicorn.protocols.http.auto",
    "uvicorn.protocols.http.h11_impl",
    "uvicorn.protocols.websockets",
    "uvicorn.protocols.websockets.auto",
    "uvicorn.lifespan",
    "uvicorn.lifespan.on",
    "sqlalchemy.dialects.sqlite",
    "sqlalchemy.dialects.postgresql",
    "sqlalchemy.dialects.postgresql.psycopg2",
    "tiktoken_ext.openai_public",
]

# 需要 importlib.metadata 读取版本号的依赖
for _distribution in (
    "tiktoken",
    "curl_cffi",
    "certifi",
    "pybase64",
    "sqlalchemy",
    "fastapi",
    "starlette",
    "pydantic",
    "uvicorn",
    "gitpython",
    "python-multipart",
):
    _copy_metadata(_distribution)

# 首次启动时补齐配置文件的模板
for _name in ("config.json", "VERSION"):
    _source = ROOT / _name
    if _source.is_file():
        datas.append((str(_source), "."))

# 预下载的 tiktoken BPE 词表（由构建脚本生成，缺失时跳过）
_tiktoken_cache = ROOT / "build" / "tiktoken-cache"
if _tiktoken_cache.is_dir():
    datas.append((str(_tiktoken_cache), "tiktoken_cache"))

excludes = [
    "tkinter",
    "unittest",
    "pydoc_data",
    "test",
    "matplotlib",
    "numpy",
    "pandas",
    "PIL.ImageQt",
    "PyQt5",
    "PyQt6",
    "PySide2",
    "PySide6",
]

block_cipher = None

a = Analysis(
    [str(ROOT / "packaging" / "launcher.py")],
    pathex=[str(ROOT)],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=excludes,
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

_icon = ROOT / "packaging" / "assets" / "app.ico"

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="ChatGPT2API",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    icon=str(_icon) if sys.platform == "win32" and _icon.is_file() else None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="ChatGPT2API",
)
