# World of Meta Uploader: packaging

Windows installer and Linux binary. Both are built from `../meta_uploader.py`. The version comes only from its
`VERSION` constant.

## Windows

### Install (users)
The installer ships `README-user.txt` (installed as `README.txt`), not this file.

1. Run `MetaUploaderSetup-<version>.exe` (no admin needed).
2. Pick a mode: background tray daemon, or script only.
3. Optionally tick "Start the daemon when I sign in to Windows".
4. Start menu > World of Meta Uploader > Link account, and enter your code.
5. Type `/reload` in game; the first sync follows.

### Build (maintainers)
Needs Windows, Python 3.12, and Inno Setup 6 (`choco install innosetup -y`).

    powershell -File uploader\packaging\build.ps1

The version is read from `VERSION` in `meta_uploader.py`; there is no `-Version` flag. PyInstaller, pystray and Pillow
are pinned in `requirements-build.txt`. Output: `packaging\dist\MetaUploaderSetup-<version>.exe`. PyInstaller exes land
in `packaging\build\bin`. CI: `.github/workflows/uploader-windows.yml` runs the unit tests, then builds, on every push
that touches `uploader/**` (and by hand).

The installer's `AppId` GUID must never change: upgrades and uninstall find the existing install by it. Setup and
uninstall detect a running daemon through the `WorldOfMetaUploader` mutex. Uninstall stops both exes and keeps the
user's config (it holds the link token).

### Icon

`icon.ico` is approved for the repo (CI needs it). To regenerate it from the uploader icon:

    python make_icon.py path/to/uploader-icon.jpg

## Linux

### Build (maintainers)
Needs Python 3.10+ with `venv` and network access for pip. Run it from anywhere:

    uploader/packaging/build-linux.sh              # stdlib-only binary (default)
    uploader/packaging/build-linux.sh --with-tray  # also bundles pystray + Pillow (optional)

It creates `packaging/.venv-linux`, installs PyInstaller there, and builds `meta_uploader_linux.spec`. Output:

- `packaging/dist/meta-uploader`: one-file console binary (about 11 MB).
- `packaging/dist/meta-uploader-<VERSION>-linux-<arch>.tar.gz`: the binary, `install-linux.sh`,
  `meta-uploader.desktop.in` and both READMEs (plus `icon.png` if one is present in `packaging/`).

`PYTHON=/usr/bin/python3 build-linux.sh` picks the interpreter. The binary links against the build machine's glibc, so
build on the oldest distro you want to support.

### Install (users)
Unpack the tarball, then:

    ./install-linux.sh              # ~/.local/bin/meta-uploader + app-menu launcher
    ./install-linux.sh --autostart  # same, plus an XDG autostart entry (start on login)
    ./install-linux.sh --uninstall  # removes all three; config and token stay

    meta-uploader link CODE
    meta-uploader status

The launcher runs `meta-uploader daemon --tray`. If no tray can be used (the default build has no pystray, or the
desktop has no StatusNotifier tray), the daemon keeps syncing as a background loop. It runs as a single instance and
logs to `~/.config/meta-uploader/uploader.log`. To stop the background loop, run `pkill -x meta-uploader`.

XDG autostart: `--autostart` copies the launcher to `~/.config/autostart/world-of-meta-uploader.desktop`. GNOME, KDE,
XFCE, and sessions started through `uwsm` or `dex` read that folder. Plain Hyprland and sway do not. There, add
`exec-once = meta-uploader daemon --tray` to the compositor config instead. The uploader's own `autostart on|off`
command only works on Windows.

Proton or Wine WoW installs are found on their own under `~/Games/*/drive_c`, `~/.wine`, Lutris, Bottles and Steam
compatdata. If yours is somewhere else, pass `--wow-dir ".../drive_c/Program Files (x86)/World of Warcraft"` once; the
folder is then saved in the config.

Tray on Linux (only with `--with-tray`; experimental and not tested yet): the binary bundles only what is installed in
the build venv. pystray's AppIndicator backend, which Wayland bars such as waybar show, needs PyGObject in that venv
(`.venv-linux/bin/pip install PyGObject`, which needs the system gobject-introspection and
libayatana-appindicator). Without it, pystray uses the Xorg backend, and most Wayland bars do not show that.
