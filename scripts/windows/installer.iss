#define AppName "YoruMimizuku"
#ifndef AppVersion
#define AppVersion "0.0.0"
#endif
#ifndef SourceDir
#define SourceDir "..\..\build\YoruMimizuku-win-x64-" + AppVersion
#endif
#ifndef OutputDir
#define OutputDir "..\..\build"
#endif

[Setup]
AppId={{C62E26E9-F3F1-4E73-A1BB-79D782568A83}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=asonas
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#AppName}-win-x64-{#AppVersion}-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
CloseApplications=yes
RestartApplications=no

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\YoruMimizuku.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\YoruMimizuku.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "デスクトップにショートカットを作成"; GroupDescription: "追加アイコン:"; Flags: unchecked

[Run]
Filename: "{app}\YoruMimizuku.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
