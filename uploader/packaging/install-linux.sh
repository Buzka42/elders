#!/usr/bin/env bash
# Per-user install (no root): binary to ~/.local/bin, launcher to ~/.local/share/applications.
#   install-linux.sh [--autostart]   also start the tray daemon on login (XDG autostart)
#   install-linux.sh --uninstall     remove binary, launcher and autostart entry (config and token are kept)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS="$DATA/applications"
ICONS="$DATA/icons/hicolor/256x256/apps"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
NAME="world-of-meta-uploader"

if [[ "${1:-}" == "--uninstall" ]]; then
  pkill -x meta-uploader 2>/dev/null || true
  rm -f "$BIN_DIR/meta-uploader" "$APPS/$NAME.desktop" "$AUTOSTART/$NAME.desktop" "$ICONS/$NAME.png"
  echo "removed (config kept in ${XDG_CONFIG_HOME:-$HOME/.config}/meta-uploader)"
  exit 0
fi

SRC="$HERE/meta-uploader"
[[ -x "$SRC" ]] || SRC="$HERE/dist/meta-uploader"
[[ -x "$SRC" ]] || { echo "meta-uploader binary not found next to this script or in dist/" >&2; exit 1; }

install -Dm755 "$SRC" "$BIN_DIR/meta-uploader"
icon="utilities-terminal"
if [[ -f "$HERE/icon.png" ]]; then
  install -Dm644 "$HERE/icon.png" "$ICONS/$NAME.png"
  icon="$NAME"
fi
mkdir -p "$APPS"
sed -e "s|@BIN@|$BIN_DIR/meta-uploader|" -e "s|@ICON@|$icon|" "$HERE/meta-uploader.desktop.in" > "$APPS/$NAME.desktop"
echo "installed $BIN_DIR/meta-uploader and $APPS/$NAME.desktop"

if [[ "${1:-}" == "--autostart" ]]; then
  mkdir -p "$AUTOSTART"
  cp "$APPS/$NAME.desktop" "$AUTOSTART/$NAME.desktop"
  echo "autostart: $AUTOSTART/$NAME.desktop"
fi
echo "next: meta-uploader link CODE   then   meta-uploader status"
