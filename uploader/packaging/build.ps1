# Build the Windows installer. Usage: powershell -File packaging\build.ps1 [-Version 0.1.0]
param([string]$Version = "0.1.0")
$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$Root = Split-Path $Here -Parent
$Venv = Join-Path $Here ".venv"
$Bin = Join-Path $Here "build\bin"

function Run([string]$exe, [string[]]$argv) {
    & $exe @argv
    if ($LASTEXITCODE -ne 0) { throw "$exe failed with exit code $LASTEXITCODE" }
}

Run "python" @("-m", "venv", $Venv)
$Py = Join-Path $Venv "Scripts\python.exe"
Run $Py @("-m", "pip", "install", "--upgrade", "pip", "pyinstaller")
Run $Py @("-m", "pip", "install", "-r", (Join-Path $Root "requirements-tray.txt"))
# icon.ico is built once from the approved uploader icon: make_icon.py SOURCE.png
if (-not (Test-Path (Join-Path $Here "icon.ico"))) {
    throw "icon.ico missing: run  $Py make_icon.py <path to the uploader icon>  first"
}

Run $Py @("-m", "PyInstaller", "--noconfirm", "--clean",
    "--distpath", $Bin, "--workpath", (Join-Path $Here "build\work"),
    (Join-Path $Here "meta_uploader.spec"))
foreach ($n in "MetaUploader.exe", "MetaUploaderTray.exe") {
    if (-not (Test-Path (Join-Path $Bin $n))) { throw "missing $n after PyInstaller" }
}

$Iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
if (-not $Iscc) { $Iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" }
if (-not (Test-Path $Iscc)) { throw "ISCC.exe not found; install Inno Setup 6" }
Run $Iscc @("/DAppVersion=$Version", (Join-Path $Here "MetaUploader.iss"))

Write-Host "Done: $(Join-Path $Here 'dist')"
