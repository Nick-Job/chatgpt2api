from __future__ import annotations

import os
import sys
from pathlib import Path


def resolve_base_dir(fallback: Path) -> Path:
    """解析应用根目录，兼容源码运行与 PyInstaller 打包后的桌面版。

    优先级：
    1. `CHATGPT2API_BASE_DIR` 环境变量（便携部署 / 自定义数据目录）
    2. 冻结后的可执行文件所在目录（PyInstaller 打包，配置与数据跟随安装目录）
    3. 调用方源码位置推导出的项目根目录（Docker / 源码运行）
    """
    override = os.getenv("CHATGPT2API_BASE_DIR", "").strip()
    if override:
        return Path(override).expanduser().resolve()
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return fallback
