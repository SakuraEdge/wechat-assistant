#ifndef AppVersion
 #error AppVersion is required
#endif
#ifndef PayloadDir
 #error PayloadDir is required
#endif
#ifndef OutputDir
 #error OutputDir is required
#endif
[Setup]
AppId={{F3D40C68-3D70-4972-95E5-2E4F902F0C6A}
AppName=ClawBot实例管理器
AppVersion={#AppVersion}
AppPublisher=SakuraEdge
AppPublisherURL=https://github.com/SakuraEdge/wechat-assistant
AppSupportURL=https://github.com/SakuraEdge/wechat-assistant/issues
AppUpdatesURL=https://github.com/SakuraEdge/wechat-assistant/releases
DefaultDirName={localappdata}\Programs\ClawBotInstanceManager
DefaultGroupName=ClawBot实例管理器
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
DisableProgramGroupPage=yes
DisableDirPage=auto
DisableWelcomePage=no
WizardStyle=modern
SetupIconFile={#PayloadDir}\assets\clawbot.ico
UninstallDisplayIcon={app}\ClawBot实例管理器.exe
OutputDir={#OutputDir}
OutputBaseFilename=ClawBot-Instance-Manager-Setup-{#AppVersion}-windows-x64
Compression=lzma2
SolidCompression=yes
CloseApplications=no
RestartApplications=no
Uninstallable=yes
SetupLogging=no
UninstallDisplayName=ClawBot实例管理器
InfoBeforeFile={#PayloadDir}\installer\INSTALL.txt
[Languages]
Name: "chinesesimp"; MessagesFile: "{#PayloadDir}\installer\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#PayloadDir}\installer\SetupGuard.exe"; Flags: dontcopy
[Icons]
Name: "{autoprograms}\ClawBot实例管理器"; Filename: "{app}\ClawBot实例管理器.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\ClawBot实例管理器"; Filename: "{app}\ClawBot实例管理器.exe"; WorkingDir: "{app}"
Name: "{autoprograms}\ClawBot实例管理器使用教程"; Filename: "{app}\README.md"
[Run]
Filename: "{app}\ClawBot实例管理器.exe"; Description: "打开管理器，完成客户端连接与微信扫码"; Flags: nowait postinstall skipifsilent
[Code]
function IsInstallDirectorySafe(Directory: String): Boolean;
begin
  Result := (Length(Directory) > 5) and (CompareText(Directory, GetEnv('USERPROFILE')) <> 0) and
    (CompareText(Directory, ExpandConstant('{localappdata}')) <> 0) and
    (Pos(Lowercase(AddBackslash(ExpandConstant('{localappdata}\Codex'))), Lowercase(AddBackslash(Directory))) <> 1) and
    (Pos(Lowercase(AddBackslash(AddBackslash(GetEnv('USERPROFILE')) + '.codex')), Lowercase(AddBackslash(Directory))) <> 1);
end;
function PrepareToInstall(var NeedsRestart: Boolean): String;
var Code, I: Integer; Details: TArrayOfString; ReportFile: String;
begin
  Result := '';
  if not IsInstallDirectorySafe(ExpandConstant('{app}')) then begin
    Result := '请选择独立的软件安装文件夹，不能直接使用用户目录或Codex数据目录。'; exit;
  end;
  ExtractTemporaryFile('SetupGuard.exe');
  ReportFile := ExpandConstant('{tmp}\clawbot-processes.txt');
  if not Exec(ExpandConstant('{tmp}\SetupGuard.exe'), '"' + ExpandConstant('{app}') + '" --details "' + ReportFile + '"', '', SW_HIDE, ewWaitUntilTerminated, Code) then Code := 43;
  if Code = 42 then begin
    Result := '安装目录仍被进程使用。请等待工作完成、停止服务并关闭对应管理窗口，再重试。安装器不会中断任务。';
    if LoadStringsFromFile(ReportFile, Details) then
      for I := 0 to GetArrayLength(Details) - 1 do Result := Result + #13#10 + Details[I];
  end else if Code <> 0 then Result := '无法核对安装目录的进程状态。请检查当前Windows用户的访问权限后重试（检查代码43）。';
end;
function InitializeUninstall(): Boolean;
var Code: Integer;
begin
  Result := False;
  if not Exec(ExpandConstant('{app}\installer\SetupGuard.exe'), '"' + ExpandConstant('{app}') + '"', '', SW_HIDE, ewWaitUntilTerminated, Code) then Code := 43;
  if Code <> 0 then begin
    if not UninstallSilent then MsgBox('请先停止此安装目录的服务并关闭管理器，再卸载。私人账号、设置与聊天数据会保留。', mbInformation, MB_OK);
    exit;
  end;
  Result := True;
end;
procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer;
begin
  if CurStep = ssPostInstall then begin
    if CompareText(GetSHA256OfFile(ExpandConstant('{app}\runtime\node\node.exe')), '{#NodeSHA256}') <> 0 then
      RaiseException('运行环境校验失败，请重新下载安装包。');
    if not Exec(ExpandConstant('{app}\runtime\node\node.exe'), '"' + ExpandConstant('{app}\installer\verify-payload.mjs') + '" "' + ExpandConstant('{app}') + '"', '', SW_HIDE, ewWaitUntilTerminated, Code) then Code := 1;
    if Code <> 0 then RaiseException('安装文件完整性校验失败，请重新下载安装包。');
  end;
end;
