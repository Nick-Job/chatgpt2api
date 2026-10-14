; ChatGPT2API Windows 安装程序（Inno Setup 6）
;
; 编译示例：
;   ISCC.exe /DMyAppVersion=1.8.0 /DSourceDir=..\dist\windows\ChatGPT2API installer.iss
;
; 说明：默认安装到 %LOCALAPPDATA%\Programs\ChatGPT2API，属于当前用户安装，
; 不弹 UAC、不需要管理员权限；配置与数据都保存在安装目录内，方便备份与迁移。

#define MyAppName "ChatGPT2API"
#define MyAppPublisher "basketikun"
#define MyAppURL "https://github.com/basketikun/chatgpt2api"
#define MyAppExeName "ChatGPT2API.exe"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\dist\windows\ChatGPT2API"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist\windows"
#endif
; 供 Windows 文件属性显示的纯数字版本号，由构建脚本传入
#ifndef VersionInfoVersion
  #define VersionInfoVersion "0.0.0"
#endif

[Setup]
; 固定 AppId，保证升级安装时能覆盖旧版本
AppId={{8E1B7C4A-2F63-4C8E-9B0D-7A5D2E9F1C33}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
VersionInfoVersion={#VersionInfoVersion}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#MyAppName}-{#MyAppVersion}-windows-x64-setup
SetupIconFile=assets\app.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName} {#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
CloseApplications=yes
RestartApplications=no
AllowNoIcons=yes
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
#ifdef IncludeChinese
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart"; Description: "开机自动启动（后台运行，不自动打开浏览器）"; GroupDescription: "启动选项："; Flags: unchecked

[Files]
; config.json 由程序首次启动时生成，卸载时不会被安装程序直接删除，
; 这样用户的配置和账号数据可以安全保留。
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "config.json"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Comment: "启动 ChatGPT2API 并打开 Web 面板"
Name: "{autoprograms}\{#MyAppName} 使用说明"; Filename: "{app}\README.txt"; WorkingDir: "{app}"
Name: "{autoprograms}\{#MyAppName} 数据目录"; Filename: "{app}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"" --no-browser"; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "立即启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\start-lan.bat"; Description: "以局域网模式启动（同一网络的其他设备可访问）"; Flags: nowait postinstall skipifsilent unchecked

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  TargetDir: String;
begin
  if CurUninstallStep <> usPostUninstall then
    Exit;

  TargetDir := ExpandConstant('{app}');
  if (not DirExists(TargetDir + '\data')) and (not FileExists(TargetDir + '\config.json')) then
    Exit;

  if MsgBox('是否同时删除配置、账号数据和日志？' + #13#10 + #13#10 +
            '选择“否”将保留这些文件（推荐，方便下次安装继续使用）。',
            mbConfirmation, MB_YESNO) = IDNO then
    Exit;

  DelTree(TargetDir + '\data', True, True, True);
  DeleteFile(TargetDir + '\config.json');
  DelTree(TargetDir + '\_internal', True, True, True);
  DelTree(TargetDir + '\web_dist', True, True, True);
  RemoveDir(TargetDir);
end;
