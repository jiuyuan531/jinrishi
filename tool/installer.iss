; 今日事 Windows 安装程序（Inno Setup 6）
#define AppVersion GetEnv("APP_VERSION")

[Setup]
AppId={{8C2F6B1E-3D4A-4E5B-9F60-7A1B2C3D4E5F}
AppName=今日事
AppVersion={#AppVersion}
AppPublisher=沈
DefaultDirName={localappdata}\Programs\Jinrishi
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=jinrishi-setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\jinrishi.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=force

[Languages]
Name: "zh"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; Flags: unchecked
Name: "autostart"; Description: "开机自动启动（启动后只显示在托盘）"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\今日事"; Filename: "{app}\jinrishi.exe"
Name: "{autodesktop}\今日事"; Filename: "{app}\jinrishi.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "今日事"; ValueData: """{app}\jinrishi.exe"" --hidden"; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\jinrishi.exe"; Description: "立即打开今日事"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "taskkill"; Parameters: "/f /im jinrishi.exe"; Flags: runhidden; RunOnceId: "KillApp"
