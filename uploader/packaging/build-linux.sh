#!/usr/bin/env bash
# Build the Linux one-file binary.  Usage: uploader/packaging/build-linux.sh [--with-tray]
#   --with-tray  also bundle pystray + Pillow (optional; the default build is stdlib-only)
# Output: packaging/dist/meta-uploader and packaging/dist/meta-uploader-<VERSION>-linux-<arch>.tar.gz
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
VENV="$HERE/.venv-linux"
DIST="$HERE/dist"
PY="${PYTHON:-python3}"

with_tray=0
for a in "$@"; do
  case "$a" in
    --with-tray) with_tray=1 ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 64 ;;
  esac
done

# VERSION lives only in meta_uploader.py.
VERSION="$(sed -n 's/^VERSION = "\(.*\)"$/\1/p' "$ROOT/meta_uploader.py")"
[[ -n "$VERSION" ]] || { echo "VERSION not found in meta_uploader.py" >&2; exit 1; }
ARCH="$(uname -m)"

"$PY" -m venv "$VENV"
"$VENV/bin/python" -m pip install --quiet --upgrade pip pyinstaller
if (( with_tray )); then
  "$VENV/bin/python" -m pip install --quiet -r "$ROOT/requirements-tray.txt"
else
  # A venv reused from a --with-tray build would silently bundle the tray; keep the default build stdlib-only.
  "$VENV/bin/python" -m pip uninstall --quiet -y pystray Pillow 2>/dev/null || true
fi

"$VENV/bin/python" -m PyInstaller --noconfirm --clean \
  --distpath "$DIST" --workpath "$HERE/build/work-linux" \
  "$HERE/meta_uploader_linux.spec"

BIN="$DIST/meta-uploader"
[[ -x "$BIN" ]] || { echo "missing $BIN after PyInstaller" >&2; exit 1; }
"$BIN" --help >/dev/null

STAGE="$HERE/build/meta-uploader-$VERSION-linux-$ARCH"
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp "$BIN" "$HERE/meta-uploader.desktop.in" "$HERE/install-linux.sh" "$STAGE/"
cp "$ROOT/README.md" "$STAGE/README-uploader.md"
cp "$HERE/README.md" "$STAGE/README-packaging.md"
[[ -f "$HERE/icon.png" ]] && cp "$HERE/icon.png" "$STAGE/"
tar -C "$HERE/build" -czf "$DIST/meta-uploader-$VERSION-linux-$ARCH.tar.gz" "$(basename "$STAGE")"

echo "Done: $BIN"
echo "      $DIST/meta-uploader-$VERSION-linux-$ARCH.tar.gz"
