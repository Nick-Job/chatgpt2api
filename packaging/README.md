# Windows 桌面版打包说明

把 ChatGPT2API 打包成 **Windows 免安装压缩包 + 图形化安装程序（.exe）**，
双击安装即可使用，无需 Docker、无需自己装 Python。

## 产物

| 文件 | 说明 |
| --- | --- |
| `ChatGPT2API-<版本>-windows-x64-setup.exe` | 安装程序：当前用户安装、不弹 UAC、自带开始菜单/桌面快捷方式与卸载项 |
| `ChatGPT2API-<版本>-windows-x64-portable.zip` | 免安装版：解压后双击 `ChatGPT2API.exe` 即可运行 |

安装/运行后：

- Web 面板：`http://127.0.0.1:3000`
- API 地址：`http://127.0.0.1:3000/v1`
- 默认密钥：`chatgpt2api`（请在 `config.json` 或设置页中修改）

## 方式一：用 GitHub Actions 一键构建（推荐）

不需要 Windows 电脑，构建在 GitHub 的 Windows 机器上完成。

1. 把本仓库（含 `.github/workflows/build-windows.yml`）推送到你自己的 GitHub 仓库。
2. 打开仓库的 **Actions → Build Windows Installer → Run workflow**，直接运行。
3. 构建完成后在该次运行的 **Artifacts** 里下载 `ChatGPT2API-windows-x64-<版本>`。

打 tag 会自动发版：推送 `v1.8.0` 这类 tag 后，安装包与免安装包会作为附件
出现在 GitHub Release 页面，用户直接下载即可。

```bash
git tag v1.8.0
git push origin v1.8.0
```

## 方式二：在 Windows 上本地构建

前置条件：

- [Node.js](https://nodejs.org/) 20+
- [uv](https://docs.astral.sh/uv/getting-started/installation/)
- [Inno Setup 6](https://jrsoftware.org/isdl.php)（只需生成安装程序时需要）

在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File packaging\build_windows.ps1
```

常用参数：

```powershell
# 只做后端打包，复用已有的前端产物，跳过安装程序
powershell -ExecutionPolicy Bypass -File packaging\build_windows.ps1 -SkipWeb -SkipInstaller

# 指定版本号
powershell -ExecutionPolicy Bypass -File packaging\build_windows.ps1 -Version 1.8.0
```

产物输出到 `dist\windows\`。

## 目录结构

```
packaging/
  launcher.py           启动器（固定数据目录、自动开浏览器、端口占用顺延）
  chatgpt2api.spec      PyInstaller 打包配置
  build_windows.ps1     一键构建脚本
  installer.iss         Inno Setup 安装程序脚本
  extra/                随包分发的启动脚本与使用说明
  assets/app.ico        程序与安装包图标
```

安装后的目录：

```
%LOCALAPPDATA%\Programs\ChatGPT2API\
  ChatGPT2API.exe       启动器（内置 Python 运行时）
  _internal\            依赖
  web_dist\             Web 面板静态文件
  config.json           配置
  data\                 账号、日志、图片
  start.bat / start-lan.bat / README.txt
```

## 实现要点

- **数据目录跟随安装目录**：`utils/runtime_paths.py` 让 `services/config.py`、
  `api/support.py` 在打包运行时把根目录解析为 exe 所在目录，因此
  `config.json`、`data/`、`web_dist/` 都在安装目录内，备份/迁移只需复制该目录。
  源码运行与 Docker 行为保持不变（仍为项目根目录）。
- **前端不单独跑 Node**：Next.js 以 `output: 'export'` 静态导出，由 FastAPI
  同源托管，所以只需要一个进程、一个端口。
- **默认只监听 127.0.0.1**：不会触发防火墙弹窗；需要局域网访问时用
  `start-lan.bat` 或 `ChatGPT2API.exe --host 0.0.0.0`。
- **tiktoken 词表内置**：构建时预下载 `o200k_base` / `cl100k_base`，
  离线首次分词也能正常工作。

## 常见问题

**安装包没有中文界面？**
Inno Setup 官方未内置简体中文语言包，构建脚本检测到
`Languages\ChineseSimplified.isl` 时才会启用中文。CI 会自动下载该语言包；
本地构建想用中文，把语言包放到 Inno Setup 安装目录的 `Languages\` 下即可。

**为什么安装到 `%LOCALAPPDATA%` 而不是 `Program Files`？**
当前用户安装不需要管理员权限，安装后程序也能直接读写自己目录里的
`config.json` 与 `data`，避免权限问题。

**怎么升级？**
直接运行新版本安装程序覆盖安装，`config.json` 与 `data` 不会被删除。

**怎么彻底卸载？**
「设置 → 应用 → 已安装的应用」中卸载。卸载时会询问是否删除配置与账号数据。
