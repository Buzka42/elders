; World of Meta Uploader installer (Inno Setup 6). Build with build.ps1, which passes /DAppVersion from
; VERSION in meta_uploader.py. There is no default so a stale version can never ship.
#ifndef AppVersion
  #error AppVersion is not set: build with build.ps1, or pass ISCC /DAppVersion=x.y.z
#endif
#define AppName "World of Meta Uploader"
#define Bin "build\bin"

[Setup]
; Fixed forever: upgrades and uninstall find the existing install by this id, not by the name. The doubled
; opening brace is Inno's escape for a literal "{".
AppId={{D3786131-74B3-4E3E-B73D-E987B358E4F0}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=World of Meta
DefaultDirName={localappdata}\Programs\WorldOfMetaUploader
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
OutputDir=dist
OutputBaseFilename=MetaUploaderSetup-{#AppVersion}
SetupIconFile=icon.ico
UninstallDisplayIcon={app}\icon.ico
Compression=lzma2
SolidCompression=yes
DisableProgramGroupPage=yes
; Same name as APP_NAME in meta_uploader.py: every running daemon (tray or console) holds this mutex, so setup and
; uninstall ask the user to quit it instead of failing on "file in use".
AppMutex=WorldOfMetaUploader

[Tasks]
; Same GroupDescription + exclusive flag renders as radio buttons.
Name: mode_daemon; Description: "Keep syncing in the background (tray icon; quit from its menu)"; GroupDescription: "Sync mode:"; Flags: exclusive
Name: mode_script; Description: "Script only: I will run a sync myself from the Start menu"; GroupDescription: "Sync mode:"; Flags: exclusive unchecked
; Always shown (task visibility is fixed at wizard start); ignored in script mode by AutostartArg below.
Name: autostart; Description: "Start the daemon when I sign in to Windows (background mode only)"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "{#Bin}\MetaUploader.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Bin}\MetaUploaderTray.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "icon.ico"; DestDir: "{app}"; Flags: ignoreversion
; Short user-only readme; packaging/README.md is maintainer docs and is not shipped.
Source: "README-user.txt"; DestDir: "{app}"; DestName: "README.txt"; Flags: ignoreversion isreadme

[Icons]
; The CLI requires a subcommand; without one the windowless tray exe would exit silently.
Name: "{group}\World of Meta Uploader"; Filename: "{app}\MetaUploaderTray.exe"; Parameters: "daemon --tray"; IconFilename: "{app}\icon.ico"
; cmd /k keeps the console open so the output stays visible.
; TODO verify on Windows: quoting of the cmd /k parameter string.
Name: "{group}\Sync now"; Filename: "{cmd}"; Parameters: "/k """"{app}\MetaUploader.exe"" once"""; IconFilename: "{app}\icon.ico"
Name: "{group}\Link account"; Filename: "{cmd}"; Parameters: "/k """"{app}\MetaUploader.exe"" link"""; IconFilename: "{app}\icon.ico"
Name: "{group}\Status"; Filename: "{cmd}"; Parameters: "/k """"{app}\MetaUploader.exe"" status"""; IconFilename: "{app}\icon.ico"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\MetaUploader.exe"; Parameters: "configure --mode {code:ModeArg} --autostart {code:AutostartArg}"; Flags: runhidden waituntilterminated; StatusMsg: "Saving your choices..."
; TODO verify on Windows: nowait postinstall launches the tray at the end of setup (not under /SILENT).
Filename: "{app}\MetaUploaderTray.exe"; Parameters: "daemon --tray"; Flags: nowait postinstall skipifsilent; Description: "Start the uploader now"; Check: IsDaemon

[UninstallRun]
; The user's config (holds the link token) is deliberately NOT removed.
; Stop both the tray and any console daemon/sync so no exe is locked while files are removed.
Filename: "{sys}\taskkill.exe"; Parameters: "/IM MetaUploaderTray.exe /F"; Flags: runhidden; RunOnceId: "KillTray"
Filename: "{sys}\taskkill.exe"; Parameters: "/IM MetaUploader.exe /F"; Flags: runhidden; RunOnceId: "KillConsole"
Filename: "{app}\MetaUploader.exe"; Parameters: "autostart off"; Flags: runhidden; RunOnceId: "AutostartOff"

[Code]
// Setup finishes with the chosen mode already stored by `configure`; no runtime text is shown.
function IsDaemon: Boolean;
begin
  Result := WizardIsTaskSelected('mode_daemon');
end;

function ModeArg(Param: String): String;
begin
  if IsDaemon then Result := 'daemon' else Result := 'script';
end;

function AutostartArg(Param: String): String;
begin
  if IsDaemon and WizardIsTaskSelected('autostart') then Result := 'on' else Result := 'off';
end;
