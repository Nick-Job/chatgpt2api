<#
.SYNOPSIS
    一键构建 ChatGPT2API 的 Windows 桌面版（免安装压缩包 + Inno Setup 安装程序）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File packaging\build_windows.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File packaging\build_windows.ps1 -SkipWeb -SkipInstaller
#>

[CmdletBinding()]
param(
    # 版本号，默认读取仓库根目录的 VERSION 文件
    [string]$Version = "",
    # 跳过 Next.js 前端构建（复用已有的 web/out）
    [switch]$SkipWeb,
    # 跳过 Inno Setup 安装包，只产出免安装目录与 zip
    [switch]$SkipInstaller,
    # 指定 ISCC.exe 路径，默认自动探测
    [string]$InnoSetupPath = "",
    # 构建产物输出目录
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $Version) {
    $Version = (Get-Content (Join-Path $RepoRoot "VERSION") -Raw).Trim()
}
if (-not $OutputDir) {
    $OutputDir = Join-Path $RepoRoot "dist\windows"
}

$WebDir = Join-Path $RepoRoot "web"
$WebDist = Join-Path $RepoRoot "web_dist"
$PyInstallerDist = Join-Path $RepoRoot "build\pyinstaller-dist"
$PyInstallerWork = Join-Path $RepoRoot "build\pyinstaller-work"
$TiktokenCache = Join-Path $RepoRoot "build\tiktoken-cache"
$StageDir = Join-Path $OutputDir "ChatGPT2API"
$PortableZip = Join-Path $OutputDir "ChatGPT2API-$Version-windows-x64-portable.zip"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Assert-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "找不到命令 '$Name'。$Hint"
    }
}

function Remove-Directory([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

Write-Host "ChatGPT2API Windows 打包" -ForegroundColor Green
Write-Host "  仓库目录: $RepoRoot"
Write-Host "  版本号  : $Version"
Write-Host "  输出目录: $OutputDir"

Assert-Command "uv" "请先安装 uv：https://docs.astral.sh/uv/getting-started/installation/"
Assert-Command "node" "请先安装 Node.js 20 或更高版本：https://nodejs.org/"
Assert-Command "npm" "请先安装 Node.js（自带 npm）：https://nodejs.org/"

Push-Location $RepoRoot
try {
    # ---------------------------------------------------------------- 前端
    if (-not $SkipWeb) {
        Write-Step "构建 Next.js 前端"
        Push-Location $WebDir
        try {
            if (-not (Test-Path (Join-Path $WebDir "node_modules"))) {
                npm install
                if ($LASTEXITCODE -ne 0) { throw "npm install 失败" }
            }
            $env:NEXT_PUBLIC_APP_VERSION = $Version
            npm run build
            if ($LASTEXITCODE -ne 0) { throw "npm run build 失败" }
        }
        finally {
            Pop-Location
        }
    }

    $WebOut = Join-Path $WebDir "out"
    if (-not (Test-Path (Join-Path $WebOut "index.html"))) {
        throw "未找到 $WebOut\index.html，请先构建前端（不要使用 -SkipWeb）。"
    }
    Write-Step "同步静态前端到 web_dist"
    Remove-Directory $WebDist
    Copy-Item -LiteralPath $WebOut -Destination $WebDist -Recurse -Force

    # ---------------------------------------------------------------- 后端依赖
    Write-Step "安装后端依赖"
    uv sync --frozen --no-dev --no-install-project
    if ($LASTEXITCODE -ne 0) { throw "uv sync 失败" }
    uv pip install --quiet pyinstaller
    if ($LASTEXITCODE -ne 0) { throw "安装 PyInstaller 失败" }

    # ---------------------------------------------------------------- 分词词表
    Write-Step "预下载 tiktoken 词表"
    Remove-Directory $TiktokenCache
    New-Item -ItemType Directory -Path $TiktokenCache -Force | Out-Null
    $env:TIKTOKEN_CACHE_DIR = $TiktokenCache
    uv run --no-sync python -c "import tiktoken; [tiktoken.get_encoding(name) for name in ('o200k_base', 'cl100k_base')]"
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "tiktoken 词表下载失败，将跳过内置词表（首次分词需要联网）"
    }

    # ---------------------------------------------------------------- 打包 exe
    Write-Step "使用 PyInstaller 打包后端"
    Remove-Directory $PyInstallerDist
    Remove-Directory $PyInstallerWork
    uv run --no-sync pyinstaller (Join-Path $PSScriptRoot "chatgpt2api.spec") `
        --noconfirm `
        --distpath $PyInstallerDist `
        --workpath $PyInstallerWork
    if ($LASTEXITCODE -ne 0) { throw "PyInstaller 打包失败" }

    # ---------------------------------------------------------------- 组装目录
    Write-Step "组装免安装目录"
    Remove-Directory $StageDir
    New-Item -ItemType Directory -Path $StageDir -Force | Out-Null
    Copy-Item -Path (Join-Path (Join-Path $PyInstallerDist "ChatGPT2API") "*") -Destination $StageDir -Recurse -Force
    Copy-Item -LiteralPath $WebDist -Destination (Join-Path $StageDir "web_dist") -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot "config.json") -Destination $StageDir -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot "VERSION") -Destination $StageDir -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot "CHANGELOG.md") -Destination $StageDir -Force
    Copy-Item -Path (Join-Path (Join-Path $PSScriptRoot "extra") "*") -Destination $StageDir -Force

    # 免安装包不预置 data 目录，首次启动自动创建
    Remove-Directory (Join-Path $StageDir "data")

    # ---------------------------------------------------------------- 压缩包
    Write-Step "生成免安装压缩包"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $PortableZip) {
        Remove-Item -LiteralPath $PortableZip -Force
    }
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $StageDir,
        $PortableZip,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $true
    )
    Write-Host "  -> $PortableZip"

    # ---------------------------------------------------------------- 安装包
    if (-not $SkipInstaller) {
        Write-Step "生成 Inno Setup 安装程序"
        $Iscc = $InnoSetupPath
        if (-not $Iscc) {
            $candidates = @()
            foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
                if ($root) {
                    $candidates += (Join-Path $root "Inno Setup 6\ISCC.exe")
                    $candidates += (Join-Path $root "Inno Setup 5\ISCC.exe")
                }
            }
            $Iscc = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
        }
        if (-not $Iscc) {
            Write-Warning "未找到 ISCC.exe，跳过安装包。请安装 Inno Setup 6：https://jrsoftware.org/isdl.php"
        }
        else {
            $defines = @(
                "/DMyAppVersion=$Version",
                "/DSourceDir=$StageDir",
                "/DOutputDir=$OutputDir"
            )
            # Windows 文件属性只接受纯数字版本号，非数字版本（如 1.8.0-rc1）降级为 0.0.0
            $versionMatch = [regex]::Match($Version.TrimStart("v", "V"), "^\d+(\.\d+){0,3}")
            $versionInfo = if ($versionMatch.Success) { $versionMatch.Value } else { "0.0.0" }
            $defines += "/DVersionInfoVersion=$versionInfo"
            $chineseIsl = Join-Path (Split-Path -Parent $Iscc) "Languages\ChineseSimplified.isl"
            if (Test-Path -LiteralPath $chineseIsl) {
                $defines += "/DIncludeChinese=1"
            }
            else {
                Write-Host "  （未检测到中文语言包，安装界面将使用英文）"
            }
            & $Iscc @defines (Join-Path $PSScriptRoot "installer.iss")
            if ($LASTEXITCODE -ne 0) { throw "Inno Setup 编译失败" }
        }
    }

    Write-Step "完成"
    Write-Host "  免安装目录: $StageDir"
    Write-Host "  免安装压缩包: $PortableZip"
    Get-ChildItem -Path $OutputDir -Filter "*.exe" | ForEach-Object {
        Write-Host "  安装程序: $($_.FullName)"
    }
}
finally {
    Pop-Location
}
