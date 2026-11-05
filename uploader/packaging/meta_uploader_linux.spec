# PyInstaller spec, Linux: one one-file console binary (console kept so `once`, `status` and logs print).
# Run from anywhere: pyinstaller packaging/meta_uploader_linux.spec   (build-linux.sh does this in a venv)
# The runtime is stdlib-only. Tray support is bundled only when pystray + Pillow are importable at build time
# (build-linux.sh --with-tray); without them `daemon --tray` falls back to the console loop.
import importlib.util
import os

HERE = SPECPATH  # noqa: F821 (injected by PyInstaller)
SCRIPT = os.path.join(HERE, "..", "meta_uploader.py")

hidden = []
if importlib.util.find_spec("pystray") and importlib.util.find_spec("PIL"):
    hidden = ["pystray", "pystray._appindicator", "pystray._xorg", "PIL", "PIL.Image", "PIL.ImageDraw"]

a = Analysis(  # noqa: F821
    [SCRIPT],
    pathex=[os.path.join(HERE, "..")],
    hiddenimports=hidden,
    excludes=[] if hidden else ["tkinter", "PIL", "pystray"],
)
pyz = PYZ(a.pure)  # noqa: F821

exe = EXE(  # noqa: F821
    pyz, a.scripts, a.binaries, a.datas, [],
    name="meta-uploader", console=True, upx=False, strip=True,  # strip: drops debug symbols some Python builds ship in libpython
)
