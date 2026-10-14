"""ChatGPT2API 桌面版启动器（Windows / macOS / Linux 通用）。

职责：
- 把应用根目录固定为可执行文件所在目录，保证 config.json / data / web_dist 都落在安装目录内；
- 打印中文启动信息，并把默认浏览器指向 Web 面板；
- 端口被占用时自动顺延，避免"双击没反应"。
"""

from __future__ import annotations

import argparse
import os
import shutil
import socket
import sys
import threading
import time
import webbrowser
from pathlib import Path

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 3000
PORT_SCAN_RANGE = 50


def _app_dir() -> Path:
    override = os.getenv("CHATGPT2API_BASE_DIR", "").strip()
    if override:
        return Path(override).expanduser().resolve()
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[1]


def _bundle_dir() -> Path | None:
    """PyInstaller 解包目录，仅打包运行时存在。"""
    bundle = getattr(sys, "_MEIPASS", None)
    return Path(bundle) if bundle else None


def _configure_console() -> None:
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")
    os.environ.setdefault("PYTHONUTF8", "1")
    if os.name != "nt":
        return
    try:
        os.system("chcp 65001 > nul")
    except Exception:
        pass
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass


def _seed_runtime_files(base_dir: Path) -> None:
    """首次运行时补齐 config.json / VERSION，避免用户误删后无法启动。"""
    bundle = _bundle_dir()
    if bundle is None:
        return
    for name in ("config.json", "VERSION"):
        target = base_dir / name
        source = bundle / name
        if target.exists() or not source.is_file():
            continue
        try:
            shutil.copyfile(source, target)
            print(f"[launcher] 已生成默认 {name}")
        except OSError as exc:
            print(f"[launcher] 生成 {name} 失败: {exc}")


def _configure_tiktoken_cache() -> None:
    """优先使用打包内置的 BPE 词表，避免离线环境首次分词失败。"""
    bundle = _bundle_dir()
    if bundle is None:
        return
    cache_dir = bundle / "tiktoken_cache"
    if cache_dir.is_dir() and any(cache_dir.iterdir()):
        os.environ.setdefault("TIKTOKEN_CACHE_DIR", str(cache_dir))


def _read_version(base_dir: Path) -> str:
    try:
        return (base_dir / "VERSION").read_text(encoding="utf-8").strip() or "unknown"
    except OSError:
        return "unknown"


def _port_available(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind((host, port))
        except OSError:
            return False
    return True


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _pick_port(host: str, preferred: int) -> int:
    for port in range(preferred, preferred + PORT_SCAN_RANGE):
        if _port_available(host, port):
            return port
    return preferred


def _open_browser_when_ready(url: str, port: int, timeout: float = 120.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.5)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                break
        time.sleep(0.25)
    else:
        return
    time.sleep(0.5)
    try:
        webbrowser.open(url)
    except Exception:
        pass


def _print_banner(version: str, url: str, base_dir: Path) -> None:
    line = "=" * 58
    print(line)
    print("  ChatGPT2API 桌面版")
    print(f"  版本: {version}")
    print(f"  面板: {url}")
    print(f"  API : {url}/v1")
    print(f"  目录: {base_dir}")
    print(line)
    print("  关闭本窗口即停止服务（Ctrl+C 也可退出）。")
    print()


def _fatal(message: str) -> int:
    print()
    print(f"[启动失败] {message}")
    if os.name == "nt":
        try:
            input("按回车键关闭窗口...")
        except EOFError:
            pass
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ChatGPT2API", description="ChatGPT2API 桌面版启动器")
    parser.add_argument("--host", default=os.getenv("CHATGPT2API_HOST", DEFAULT_HOST), help="监听地址，默认 127.0.0.1")
    parser.add_argument("--port", type=int, default=_env_int("CHATGPT2API_PORT", DEFAULT_PORT), help="监听端口，默认 3000")
    parser.add_argument("--no-browser", action="store_true", help="启动后不自动打开浏览器")
    parser.add_argument("--no-pick-port", action="store_true", help="端口被占用时直接报错，而不是自动顺延")
    args = parser.parse_args(argv)

    _configure_console()

    base_dir = _app_dir()
    os.environ["CHATGPT2API_BASE_DIR"] = str(base_dir)
    os.chdir(base_dir)
    if str(base_dir) not in sys.path:
        sys.path.insert(0, str(base_dir))

    _seed_runtime_files(base_dir)
    _configure_tiktoken_cache()

    if not (base_dir / "web_dist").is_dir():
        return _fatal(
            "缺少 web_dist 目录，安装包可能不完整。\n"
            f"请确认 {base_dir} 下存在 web_dist 文件夹（内含 index.html）。"
        )

    host = args.host
    port = args.port if args.no_pick_port else _pick_port(host, args.port)
    if port != args.port:
        print(f"[launcher] 端口 {args.port} 已被占用，改用 {port}")

    display_host = "127.0.0.1" if host in ("0.0.0.0", "::", "") else host
    url = f"http://{display_host}:{port}"
    version = _read_version(base_dir)
    _print_banner(version, url, base_dir)

    if not args.no_browser:
        threading.Thread(
            target=_open_browser_when_ready,
            args=(url, port),
            name="browser-opener",
            daemon=True,
        ).start()

    try:
        import uvicorn

        from api import create_app
    except Exception as exc:  # pragma: no cover - 打包环境异常兜底
        return _fatal(f"加载程序模块失败：{exc}")

    try:
        app = create_app()
    except Exception as exc:
        return _fatal(str(exc))

    try:
        uvicorn.run(app, host=host, port=port, access_log=False, log_level="info")
    except KeyboardInterrupt:
        print("\n[launcher] 已停止")
    except OSError as exc:
        return _fatal(f"端口 {port} 监听失败：{exc}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
