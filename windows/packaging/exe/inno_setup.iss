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
  HelperService = '{{HELPER_SERVICE}}';
  AdoptLegacy = {{ADOPT_LEGACY}};
  LegacyUninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\728B3532-C74B-4870-9068-BE70FE12A3E6_is1';
  LegacyHelperService = 'FlClashHelperService';

var
  IsUpgrade: Boolean;
  PreviousVersion: String;
  HelperHeld: Boolean;
  LegacyRoot: Integer;
  LegacyDir: String;

procedure SHChangeNotify(wEventId: Integer; uFlags: Integer; dwItem1: Integer; dwItem2: Integer); external 'SHChangeNotify@shell32.dll stdcall';

function RunHidden(const Filename, Params: String): Integer;
var
  ResultCode: Integer;
begin
  ResultCode := -1;
  Exec(Filename, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := ResultCode;
end;

procedure KillProcess(const Name: String);
begin
  RunHidden('taskkill.exe', '/f /t /im ' + Name);
end;

// The stable app and a pre-release run Cores of the same name, so only the
// one started from this install goes.
procedure KillCore;
var
  Dir: String;
begin
  Dir := AddBackslash(ExpandConstant('{app}'));
  StringChangeEx(Dir, '''', '''''', True);
  RunHidden('powershell.exe', '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Get-Process -Name FlClashCore -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith(''' + Dir + ''', [StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force"');
end;

// The client goes first so it cannot bring the Helper back, and the Helper is
// disabled before it stops because the SCM restarts a killed Helper in 5 s.
procedure ShutDownApp;
begin
  KillProcess('{{EXECUTABLE_NAME}}');
  HelperHeld := RunHidden('sc.exe', 'config "' + HelperService + '" start= disabled') = 0;
  RunHidden('net.exe', 'stop "' + HelperService + '"');
  KillProcess(HelperService + '.exe');
  KillCore;
  Sleep(1000);
end;

// Killing the app skips its exit path, which is what turns the system proxy
// off; the executable clears a proxy left on a port nothing listens on. The
// proxy is a per-user setting, so Setup runs it as the user who started it,
// which the uninstaller cannot.
procedure ClearStaleProxy;
var
  AppPath: String;
  ResultCode: Integer;
begin
  AppPath := ExpandConstant('{app}\{{EXECUTABLE_NAME}}');
  if not FileExists(AppPath) then
    Exit;
  if IsUninstaller then
    Exec(AppPath, '--clear-stale-proxy', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
  else
    ExecAsOriginalUser(AppPath, '--clear-stale-proxy', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

// The install may abort before any 0.5 executable is in place, and 0.4.x
// has no --clear-stale-proxy, so Setup clears the proxy without the app.
procedure ClearStaleProxyBeforeInstall;
var
  ResultCode: Integer;
begin
  ExtractTemporaryFile('clear_stale_proxy.ps1');
  ExecAsOriginalUser('powershell.exe', '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\clear_stale_proxy.ps1') + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure ReleaseHelper;
begin
  if not HelperHeld then
    Exit;
  HelperHeld := False;
  RunHidden('sc.exe', 'config "' + HelperService + '" start= auto');
  RunHidden('sc.exe', 'start "' + HelperService + '"');
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

// 0.4.x registered under upstream FlClash's AppId, so only an entry that
// names FlClashX is ours.
function FindLegacyInstall(Root: Integer): Boolean;
var
  Name: String;
begin
  Result := RegQueryStringValue(Root, LegacyUninstallKey, 'DisplayName', Name) and
            (Pos('FlClashX', Name) = 1) and
            RegQueryStringValue(Root, LegacyUninstallKey, 'InstallLocation', LegacyDir);
  if Result then
  begin
    LegacyRoot := Root;
    LegacyDir := RemoveBackslashUnlessRoot(LegacyDir);
  end;
end;

function HasLegacyInstall(): Boolean;
begin
  Result := LegacyDir <> '';
end;

// The old uninstaller would remove the new files and offer to delete the
// user data both versions share, so its entry goes without running it.
procedure RetireLegacyInstall;
var
  Uninstaller: String;
  ImagePath: String;
begin
  if not HasLegacyInstall or (CompareText(LegacyDir, ExpandConstant('{app}')) <> 0) then
    Exit;
  if RegQueryStringValue(LegacyRoot, LegacyUninstallKey, 'UninstallString', Uninstaller) then
  begin
    Uninstaller := RemoveQuotes(Uninstaller);
    if CompareText(Uninstaller, ExpandConstant('{uninstallexe}')) <> 0 then
    begin
      DeleteFile(Uninstaller);
      DeleteFile(ChangeFileExt(Uninstaller, '.dat'));
      DeleteFile(ChangeFileExt(Uninstaller, '.msg'));
    end;
  end;
  RegDeleteKeyIncludingSubkeys(LegacyRoot, LegacyUninstallKey);
  if RegQueryStringValue(HKEY_LOCAL_MACHINE, 'SYSTEM\CurrentControlSet\Services\' + LegacyHelperService, 'ImagePath', ImagePath) and
     (Pos(Lowercase(AddBackslash(LegacyDir)), Lowercase(ImagePath)) > 0) then
  begin
    RunHidden('net.exe', 'stop "' + LegacyHelperService + '"');
    RunHidden('sc.exe', 'delete "' + LegacyHelperService + '"');
    KillProcess(LegacyHelperService + '.exe');
    DeleteFile(AddBackslash(LegacyDir) + LegacyHelperService + '.exe');
  end;
end;

function InitializeSetup(): Boolean;
begin
  if AdoptLegacy and not FindLegacyInstall(HKEY_LOCAL_MACHINE) and not FindLegacyInstall(HKEY_LOCAL_MACHINE_32) then
    FindLegacyInstall(HKEY_CURRENT_USER);
  IsUpgrade := IsAppInstalled();
  if IsUpgrade then
    PreviousVersion := GetInstalledVersion()
  else if HasLegacyInstall then
  begin
    IsUpgrade := True;
    RegQueryStringValue(LegacyRoot, LegacyUninstallKey, 'DisplayVersion', PreviousVersion);
  end;
  Result := True;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  ShutDownApp;
  ClearStaleProxyBeforeInstall;
  Result := '';
end;

procedure DeinitializeSetup();
begin
  ReleaseHelper;
end;

procedure InitializeWizard();
begin
  if HasLegacyInstall and not IsAppInstalled() then
    WizardForm.DirEdit.Text := LegacyDir;
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
begin
  if CurStep = ssPostInstall then
  begin
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, 0, 0);
    ClearStaleProxy;
    RetireLegacyInstall;
    ReleaseHelper;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  case CurUninstallStep of
    usUninstall:
    begin
      ShutDownApp;
      ClearStaleProxy;
      RunHidden('sc.exe', 'delete "' + HelperService + '"');
    end;
    usPostUninstall:
    begin
      if DirExists(ExpandConstant('{userappdata}\{{USER_DATA_DIR}}')) then
      begin
        if MsgBox(CustomMessage('RemoveUserData'), mbConfirmation, MB_YESNO) = IDYES then
          DelTree(ExpandConstant('{userappdata}\{{USER_DATA_DIR}}'), True, True, True);
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
chineseSimplified.Upgrade=升级
chineseSimplified.FreshInstall=全新安装
chineseSimplified.InstalledVersion=已安装版本 %1。
chineseSimplified.InstalledUnknown=检测到已安装的版本。
chineseSimplified.WillInstall=安装程序将安装版本 %1。
chineseSimplified.ContinueHint=点击“下一步”继续升级，或点击“取消”退出。
chineseSimplified.CurrentVersion=当前版本：%1
chineseSimplified.NewVersion=新版本：%1
chineseSimplified.RemoveUserData=是否删除应用程序的用户数据？

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce; Check: not IsUpgradeInstallation

[Files]
Source: "{{SOURCE_DIR}}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{{CLEAR_PROXY_SCRIPT}}"; Flags: dontcopy

[Icons]
Name: "{autoprograms}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"; Tasks: desktopicon

[Run]
Filename: "{app}\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: {{RUN_FLAGS}} nowait postinstall skipifsilent
