# PyInstaller spec: two one-file exes from one script.
# Run from anywhere: pyinstaller packaging/meta_uploader.spec
import os

HERE = SPECPATH  # noqa: F821 (injected by PyInstaller)
SCRIPT = os.path.join(HERE, "..", "meta_uploader.py")
ICON = os.path.join(HERE, "icon.ico")

a = Analysis(  # noqa: F821
    [SCRIPT],
    pathex=[os.path.join(HERE, "..")],
    hiddenimports=["pystray", "pystray._win32", "PIL", "PIL.Image", "PIL.ImageDraw"],
)
pyz = PYZ(a.pure)  # noqa: F821


def make(name, console):
    return EXE(  # noqa: F821
        pyz, a.scripts, a.binaries, a.datas, [],
        name=name, console=console, icon=ICON, upx=False,
    )


exe_console = make("MetaUploader", True)
exe_tray = make("MetaUploaderTray", False)
