; Rendered by setup.dart from make_config.yaml: every {{NAME}} is filled there.
[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={{INSTALL_DIR_NAME}}
DisableProgramGroupPage=yes
OutputDir={{OUTPUT_DIR}}
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed={{ARCH}}
ArchitecturesInstallIn64BitMode={{ARCH}}
UninstallDisplayIcon={uninstallexe}
ChangesAssociations=yes
UsePreviousAppDir=yes
UsePreviousGroup=yes
UsePreviousTasks=yes

[Code]
const
  SHCNE_ASSOCCHANGED = $08000000;
  SHCNF_IDLIST = $0000;
  HelperService = 'FlClashXHelperService';

var
  IsUpgrade: Boolean;
  PreviousVersion: String;

procedure SHChangeNotify(wEventId: Integer; uFlags: Integer; dwItem1: Integer; dwItem2: Integer); external 'SHChangeNotify@shell32.dll stdcall';

procedure KillProcesses;
var
  Processes: TArrayOfString;
  i: Integer;
  ResultCode: Integer;
begin
  Processes := ['{{EXECUTABLE_NAME}}', 'FlClashCore.exe', HelperService + '.exe'];
  for i := 0 to GetArrayLength(Processes)-1 do
    Exec('taskkill', '/im ' + Processes[i], '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1000);
  for i := 0 to GetArrayLength(Processes)-1 do
    Exec('taskkill', '/f /im ' + Processes[i], '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1000);
end;

function IsAppInstalled(): Boolean;
var
  UninstallKey: String;
begin
  UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{{APP_ID}}_is1';
  Result := RegKeyExists(HKEY_LOCAL_MACHINE, UninstallKey) or
            RegKeyExists(HKEY_CURRENT_USER, UninstallKey);
end;

function IsUpgradeInstallation(): Boolean;
begin
  Result := IsUpgrade;
end;

function GetInstalledVersion(): String;
var
  UninstallKey: String;
  Version: String;
begin
  Result := '';
  UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{{APP_ID}}_is1';
  if RegQueryStringValue(HKEY_LOCAL_MACHINE, UninstallKey, 'DisplayVersion', Version) then
    Result := Version
  else if RegQueryStringValue(HKEY_CURRENT_USER, UninstallKey, 'DisplayVersion', Version) then
    Result := Version;
end;

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  IsUpgrade := IsAppInstalled();
  if IsUpgrade then
    PreviousVersion := GetInstalledVersion();
  Exec('sc.exe', 'stop "' + HelperService + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1000);
  KillProcesses;
  Result := True;
end;

procedure InitializeWizard();
begin
  if IsUpgrade then
  begin
    WizardForm.Caption := '{{DISPLAY_NAME}} - ' + CustomMessage('Upgrade');
    if PreviousVersion <> '' then
      WizardForm.WelcomeLabel2.Caption :=
        FmtMessage(CustomMessage('InstalledVersion'), [PreviousVersion]) + #13#10 + #13#10 +
        FmtMessage(CustomMessage('WillInstall'), ['{{APP_VERSION}}']) + #13#10 + #13#10 +
        CustomMessage('ContinueHint')
    else
      WizardForm.WelcomeLabel2.Caption :=
        CustomMessage('InstalledUnknown') + #13#10 + #13#10 +
        FmtMessage(CustomMessage('WillInstall'), ['{{APP_VERSION}}']) + #13#10 + #13#10 +
        CustomMessage('ContinueHint');
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  if IsUpgrade then
  begin
    Result := CustomMessage('Upgrade') + NewLine;
    if PreviousVersion <> '' then
      Result := Result + FmtMessage(CustomMessage('CurrentVersion'), [PreviousVersion]) + NewLine;
    Result := Result + FmtMessage(CustomMessage('NewVersion'), ['{{APP_VERSION}}']) + NewLine + NewLine;
  end
  else
    Result := CustomMessage('FreshInstall') + NewLine + NewLine;
  if MemoDirInfo <> '' then
    Result := Result + MemoDirInfo + NewLine + NewLine;
  if MemoGroupInfo <> '' then
    Result := Result + MemoGroupInfo + NewLine + NewLine;
  if MemoTasksInfo <> '' then
    Result := Result + MemoTasksInfo + NewLine;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, 0, 0);
    Sleep(500);
    try
      Exec('sc.exe', 'start "' + HelperService + '"', '', SW_HIDE, ewNoWait, ResultCode);
    except
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  case CurUninstallStep of
    usUninstall:
    begin
      Exec('sc.exe', 'stop "' + HelperService + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Sleep(1000);
      KillProcesses;
      Exec('sc.exe', 'delete "' + HelperService + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Sleep(500);
    end;
    usPostUninstall:
    begin
      if DirExists(ExpandConstant('{userappdata}\com.follow\clashx')) then
      begin
        if MsgBox(CustomMessage('RemoveUserData'), mbConfirmation, MB_YESNO) = IDYES then
          DelTree(ExpandConstant('{userappdata}\com.follow\clashx'), True, True, True);
      end;
    end;
  end;
end;

[Languages]
{{LANGUAGES}}

[CustomMessages]
english.Upgrade=Upgrade
english.FreshInstall=New installation
english.InstalledVersion=Version %1 is installed.
english.InstalledUnknown=An installed version was found.
english.WillInstall=Setup will install version %1.
english.ContinueHint=Click Next to continue the upgrade, or Cancel to exit.
english.CurrentVersion=Current version: %1
english.NewVersion=New version: %1
english.RemoveUserData=Remove the application's user data?
russian.Upgrade=Обновление
russian.FreshInstall=Новая установка
russian.InstalledVersion=Обнаружена установленная версия %1.
russian.InstalledUnknown=Обнаружена установленная версия программы.
russian.WillInstall=Программа установит версию %1.
russian.ContinueHint=Нажмите «Далее», чтобы продолжить обновление, или «Отмена», чтобы выйти.
russian.CurrentVersion=Текущая версия: %1
russian.NewVersion=Новая версия: %1
russian.RemoveUserData=Удалить пользовательские данные программы?

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce; Check: not IsUpgradeInstallation

[Files]
Source: "{{SOURCE_DIR}}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"; Tasks: desktopicon

[Run]
Filename: "{app}\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: {{RUN_FLAGS}} nowait postinstall skipifsilent
