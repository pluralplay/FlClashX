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
OutputDir=.
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
; Update mode settings
UsePreviousAppDir=yes
UsePreviousGroup=yes
UsePreviousTasks=yes

[Code]
const
  SHCNE_ASSOCCHANGED = $08000000;
  SHCNF_IDLIST = $0000;

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
  Processes := ['FlClashX.exe', 'FlClashCore.exe', 'FlClashHelperService.exe'];

  // First try graceful shutdown
  for i := 0 to GetArrayLength(Processes)-1 do
  begin
    Exec('taskkill', '/im ' + Processes[i], '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
  
  // Wait for processes to terminate gracefully
  Sleep(1000);

  // Force kill any remaining processes
  for i := 0 to GetArrayLength(Processes)-1 do
  begin
    Exec('taskkill', '/f /im ' + Processes[i], '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
  
  // Give time for cleanup
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
  // Check if app is already installed
  IsUpgrade := IsAppInstalled();
  if IsUpgrade then
    PreviousVersion := GetInstalledVersion();
  
  // Stop service if running
  Exec('sc.exe', 'stop "FlClashHelperService"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1000);
  
  // Kill all processes
  KillProcesses;
  
  Result := True;
end;

procedure InitializeWizard();
begin
  if IsUpgrade then
  begin
    WizardForm.Caption := '{{DISPLAY_NAME}} - Обновление';
    if PreviousVersion <> '' then
      WizardForm.WelcomeLabel2.Caption := 
        'Обнаружена установленная версия ' + PreviousVersion + '.' + #13#10 + #13#10 +
        'Программа установит версию {{APP_VERSION}}.' + #13#10 + #13#10 +
        'Нажмите «Далее», чтобы продолжить обновление, или «Отмена», чтобы выйти.'
    else
      WizardForm.WelcomeLabel2.Caption := 
        'Обнаружена установленная версия программы.' + #13#10 + #13#10 +
        'Программа установит версию {{APP_VERSION}}.' + #13#10 + #13#10 +
        'Нажмите «Далее», чтобы продолжить обновление, или «Отмена», чтобы выйти.';
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  if IsUpgrade then
  begin
    Result := 'Обновление' + NewLine;
    if PreviousVersion <> '' then
      Result := Result + 'Текущая версия: ' + PreviousVersion + NewLine;
    Result := Result + 'Новая версия: {{APP_VERSION}}' + NewLine + NewLine;
  end
  else
    Result := 'Новая установка' + NewLine + NewLine;
    
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
    // Refresh icon cache/associations
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, 0, 0);
    Sleep(500);
    // Ensure helper service is started after install/upgrade, independent of app
    try
      Exec('sc.exe', 'start "FlClashHelperService"', '', SW_HIDE, ewNoWait, ResultCode);
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
      // Stop service first
      Exec('sc.exe', 'stop "FlClashHelperService"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Sleep(1000);
      
      // Kill all processes
      KillProcesses;
      
      // Delete service
      Exec('sc.exe', 'delete "FlClashHelperService"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      Sleep(500);
    end;
    
    usPostUninstall:
    begin
      if DirExists(ExpandConstant('{userappdata}\com.follow\clashx')) then
      begin
        if MsgBox('Удалить пользовательские данные программы?', mbConfirmation, MB_YESNO) = IDYES then
        begin
          DelTree(ExpandConstant('{userappdata}\com.follow\clashx'), True, True, True);
        end;
      end;
    end;
  end;
end;
[Languages]
{% for locale in LOCALES %}
{% if locale.lang == 'en' %}Name: "english"; MessagesFile: "compiler:Default.isl"{% endif %}
{% if locale.lang == 'hy' %}Name: "armenian"; MessagesFile: "compiler:Languages\\Armenian.isl"{% endif %}
{% if locale.lang == 'bg' %}Name: "bulgarian"; MessagesFile: "compiler:Languages\\Bulgarian.isl"{% endif %}
{% if locale.lang == 'ca' %}Name: "catalan"; MessagesFile: "compiler:Languages\\Catalan.isl"{% endif %}
{% if locale.lang == 'zh' %}
Name: "chineseSimplified"; MessagesFile: {% if locale.file %}{{ locale.file }}{% else %}"compiler:Languages\\ChineseSimplified.isl"{% endif %}
{% endif %}
{% if locale.lang == 'co' %}Name: "corsican"; MessagesFile: "compiler:Languages\\Corsican.isl"{% endif %}
{% if locale.lang == 'cs' %}Name: "czech"; MessagesFile: "compiler:Languages\\Czech.isl"{% endif %}
{% if locale.lang == 'da' %}Name: "danish"; MessagesFile: "compiler:Languages\\Danish.isl"{% endif %}
{% if locale.lang == 'nl' %}Name: "dutch"; MessagesFile: "compiler:Languages\\Dutch.isl"{% endif %}
{% if locale.lang == 'fi' %}Name: "finnish"; MessagesFile: "compiler:Languages\\Finnish.isl"{% endif %}
{% if locale.lang == 'fr' %}Name: "french"; MessagesFile: "compiler:Languages\\French.isl"{% endif %}
{% if locale.lang == 'de' %}Name: "german"; MessagesFile: "compiler:Languages\\German.isl"{% endif %}
{% if locale.lang == 'he' %}Name: "hebrew"; MessagesFile: "compiler:Languages\\Hebrew.isl"{% endif %}
{% if locale.lang == 'is' %}Name: "icelandic"; MessagesFile: "compiler:Languages\\Icelandic.isl"{% endif %}
{% if locale.lang == 'it' %}Name: "italian"; MessagesFile: "compiler:Languages\\Italian.isl"{% endif %}
{% if locale.lang == 'ja' %}Name: "japanese"; MessagesFile: "compiler:Languages\\Japanese.isl"{% endif %}
{% if locale.lang == 'no' %}Name: "norwegian"; MessagesFile: "compiler:Languages\\Norwegian.isl"{% endif %}
{% if locale.lang == 'pl' %}Name: "polish"; MessagesFile: "compiler:Languages\\Polish.isl"{% endif %}
{% if locale.lang == 'pt' %}Name: "portuguese"; MessagesFile: "compiler:Languages\\Portuguese.isl"{% endif %}
{% if locale.lang == 'ru' %}Name: "russian"; MessagesFile: "compiler:Languages\\Russian.isl"{% endif %}
{% if locale.lang == 'sk' %}Name: "slovak"; MessagesFile: "compiler:Languages\\Slovak.isl"{% endif %}
{% if locale.lang == 'sl' %}Name: "slovenian"; MessagesFile: "compiler:Languages\\Slovenian.isl"{% endif %}
{% if locale.lang == 'es' %}Name: "spanish"; MessagesFile: "compiler:Languages\\Spanish.isl"{% endif %}
{% if locale.lang == 'tr' %}Name: "turkish"; MessagesFile: "compiler:Languages\\Turkish.isl"{% endif %}
{% if locale.lang == 'uk' %}Name: "ukrainian"; MessagesFile: "compiler:Languages\\Ukrainian.isl"{% endif %}
{% endfor %}

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce; Check: not IsUpgradeInstallation
[Files]
Source: "{{SOURCE_DIR}}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; Tasks: desktopicon
[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runascurrentuser{% endif %} nowait postinstall skipifsilent