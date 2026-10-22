# World of Meta Uploader: Windows installer

## Install (users)
1. Run `MetaUploaderSetup-<version>.exe` (no admin needed).
2. Pick a mode: background tray daemon, or script only.
3. Optionally tick "Start the daemon when I sign in to Windows".
4. Start menu > World of Meta Uploader > Link account, and enter your code.
5. Type `/reload` in game; the first sync follows.

## Build (maintainers)
Needs Windows, Python 3.12, and Inno Setup 6 (`choco install innosetup -y`).

    powershell -File uploader\packaging\build.ps1 -Version 0.1.0

Output: `packaging\dist\MetaUploaderSetup-<version>.exe`. PyInstaller exes land in
`packaging\build\bin`. CI: `.github/workflows/uploader-windows.yml`.
Uninstall keeps the user's config (it holds the link token).

## Icon

`icon.ico` is not in the repo (artwork waits for approval). Build it once from the approved uploader icon before `build.ps1`:

    python make_icon.py path/to/uploader-icon.jpg
