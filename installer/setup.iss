#define MyAppName "ERPNext Windows Installer"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "ERPNext Windows Installer"

[Setup]
AppId={{6B24B59C-123C-4B9D-9F1D-2F5ED53F257F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\ERPNextWindowsInstaller
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=..\artifacts\installer
OutputBaseFilename=ERPNextWindowsInstaller-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "scripts\*"; DestDir: "{app}\scripts"; Flags: ignoreversion recursesubdirs createallsubdirs

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\orchestrate.ps1"""; Flags: postinstall waituntilterminated
