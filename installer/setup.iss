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
Source: "config\*"; DestDir: "{app}\config"; Flags: ignoreversion recursesubdirs createallsubdirs

[Code]
var
  RestartChoicePage: TInputOptionWizardPage;
  DockerInstallPage: TInputOptionWizardPage;

procedure InitializeWizard;
begin
  RestartChoicePage := CreateInputOptionPage(wpSelectDir,
    'Windows restart preference',
    'Choose what to do if Windows components must be enabled',
    'This choice is used only when Windows Subsystem for Linux or Virtual Machine Platform is missing. Save your work before choosing Restart Now.',
    True, True);
  RestartChoicePage.Add('Restart Windows now if required');
  RestartChoicePage.Add('Restart Windows later if required');

  DockerInstallPage := CreateInputOptionPage(RestartChoicePage.ID,
    'Docker Desktop setup',
    'Choose how to handle Docker Desktop if it is missing',
    'The installer can download the approved Docker Desktop release for all Windows users. Existing Docker Desktop installations are never upgraded automatically.',
    True, True);
  DockerInstallPage.Add('Use my existing Docker Desktop installation');
  DockerInstallPage.Add('Download and install the approved Docker Desktop release for all users');
end;

function GetRestartChoice(Param: String): String;
begin
  if RestartChoicePage.SelectedValueIndex = 0 then
    Result := 'RestartNow'
  else
    Result := 'RestartLater';
end;

function GetDockerInstallArgument(Param: String): String;
begin
  if DockerInstallPage.SelectedValueIndex = 1 then
    Result := '-InstallDocker'
  else
    Result := '';
end;

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\orchestrate.ps1"" -RestartChoice ""{code:GetRestartChoice}"" {code:GetDockerInstallArgument}"; Flags: postinstall waituntilterminated
