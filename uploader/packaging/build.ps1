# Build the Windows installer. Usage: powershell -File uploader\packaging\build.ps1
# The version comes only from VERSION in meta_uploader.py (same as build-linux.sh).
$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$Root = Split-Path $Here -Parent

$Match = Select-String -CaseSensitive -Path (Join-Path $Root "meta_uploader.py") -Pattern '^VERSION = "(\d+\.\d+\.\d+)"$' |
    Select-Object -First 1
if (-not $Match) { throw "VERSION not found in meta_uploader.py" }
$Version = $Match.Matches[0].Groups[1].Value
Write-Host "Building version $Version"
$Venv = Join-Path $Here ".venv"
$Bin = Join-Path $Here "build\bin"

function Run([string]$exe, [string[]]$argv) {
    & $exe @argv
    if ($LASTEXITCODE -ne 0) { throw "$exe failed with exit code $LASTEXITCODE" }
}

Run "python" @("-m", "venv", $Venv)
$Py = Join-Path $Venv "Scripts\python.exe"
Run $Py @("-m", "pip", "install", "--upgrade", "pip")
# Pinned PyInstaller, pystray and Pillow so CI builds are reproducible.
Run $Py @("-m", "pip", "install", "-r", (Join-Path $Here "requirements-build.txt"))
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
