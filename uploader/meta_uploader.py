#!/usr/bin/env python3
"""Meta Uploader: ships Elders / Bloodsports SavedVariables to World of Meta and writes the WorldOfMeta_Data addon.

It only reads the SavedVariables files the game wrote to disk (like the WarcraftLogs / Raider.IO uploaders). It never
reads game memory and never sends keystrokes or /reload. Python >= 3.10, standard library only.

  meta_uploader.py link [CODE]    exchange a site link code for an install token (asks when CODE is missing)
  meta_uploader.py once           one sync pass (upload new rows, refresh WorldOfMeta_Data) and exit
  meta_uploader.py daemon [--tray] keep syncing every 2 s until stopped (Ctrl+C, or Quit in the tray icon)
  meta_uploader.py run            same as daemon without the tray
  meta_uploader.py configure --mode {daemon,script} [--autostart {on,off}]
  meta_uploader.py autostart {on,off}   start the tray daemon with Windows (Windows only)
  meta_uploader.py status         show mode, autostart, running daemon, WoW folder, API, files found
  options: --wow-dir DIR  --api URL  --config FILE  --dry-run  (prints payloads, no network, no writes)
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import http.client
import json
import logging
import logging.handlers
import math
import ntpath
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from dataclasses import dataclass
from pathlib import Path

VERSION = "1.0.0"
DEFAULT_API = "https://worldofmeta.win/api"
ADDONS = ("Elders", "Bloodsports")
BATCH_ROWS = 200
POLL_SECONDS = 2.0
DATA_REFRESH_SECONDS = 600
TOC_INTERFACE = "16001, 120100"
DATA_ADDON = "WorldOfMeta_Data"
USER_AGENT = f"meta-uploader/{VERSION}"
DEFAULT_SITE = "https://worldofmeta.win"
APP_NAME = "WorldOfMetaUploader"  # mutex name and autostart registry value
RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
TRAY_EXE = "MetaUploaderTray.exe"
LOG_BYTES = 512 * 1024

_file_log: logging.Logger | None = None


def log(msg: str) -> None:
    if sys.stdout is not None:  # a windowed exe has no console
        try:
            print(time.strftime("%H:%M:%S"), msg, flush=True)
        except (OSError, ValueError):
            pass
    if _file_log is not None:
        _file_log.info(msg)


def open_file_log(path: Path) -> None:
    """Send log() lines to a small rotating file as well."""
    global _file_log
    close_file_log()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        h = logging.handlers.RotatingFileHandler(path, maxBytes=LOG_BYTES, backupCount=1, encoding="utf-8")
    except OSError:
        return
    h.setFormatter(logging.Formatter("%(asctime)s %(message)s", "%Y-%m-%d %H:%M:%S"))
    _file_log = logging.getLogger("meta-uploader")
    _file_log.setLevel(logging.INFO)
    _file_log.propagate = False
    _file_log.addHandler(h)


def close_file_log() -> None:
    global _file_log
    if _file_log is not None:
        for h in list(_file_log.handlers):
            h.close()
            _file_log.removeHandler(h)
        _file_log = None


# --------------------------------------------------------------------------------------------------------------------
# Lua table parser (the subset a SavedVariables file uses, plus the odd corner cases)

class LuaParseError(ValueError):
    pass


_WS = re.compile(r"(?:\s+|--(?!\[=*\[)[^\n]*|--\[(=*)\[.*?\]\1\])*", re.S)
_SPECIAL = re.compile(r"-?(?:1\.#(?:INF|IND|QNAN|SNAN)\w*|inf\b|nan\b)")
_NUM = re.compile(r"-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)")
_NAME = re.compile(r"[A-Za-z_]\w*")
_LONG_OPEN = re.compile(r"\[(=*)\[")
_RUN = {'"': re.compile(r'[^\\"\n]+'), "'": re.compile(r"[^\\'\n]+")}
_ESC = {"n": 10, "t": 9, "r": 13, "a": 7, "b": 8, "f": 12, "v": 11, "\\": 92, '"': 34, "'": 39}
_MAX_DEPTH = 200


class _Parser:
    def __init__(self, text: str):
        self.s = text
        self.n = len(text)
        self.i = 0

    def fail(self, msg: str):
        raise LuaParseError(f"{msg} at offset {self.i}")

    def ws(self) -> None:
        self.i = _WS.match(self.s, self.i).end()

    def peek(self) -> str:
        self.ws()
        return self.s[self.i] if self.i < self.n else ""

    def expect(self, ch: str) -> None:
        if self.peek() != ch:
            self.fail(f"expected {ch!r}")
        self.i += 1

    def long_string(self):
        m = _LONG_OPEN.match(self.s, self.i)
        if not m:
            return None
        close = "]" + m.group(1) + "]"
        end = self.s.find(close, m.end())
        if end < 0:
            self.fail("unterminated long string")
        body = self.s[m.end():end]
        if body.startswith("\r\n"):
            body = body[2:]
        elif body.startswith("\n"):
            body = body[1:]
        self.i = end + len(close)
        return body

    def string(self) -> str:
        s, n, q = self.s, self.n, self.s[self.i]
        run = _RUN[q]
        i = self.i + 1
        out = bytearray()
        while True:
            if i >= n:
                self.fail("unterminated string")
            c = s[i]
            if c == q:
                i += 1
                break
            if c == "\n":
                self.fail("newline in string")
            if c != "\\":
                m = run.match(s, i)
                out += m.group().encode("utf-8", "replace")
                i = m.end()
                continue
            i += 1
            if i >= n:
                self.fail("unterminated escape")
            e = s[i]
            if e in _ESC:
                out.append(_ESC[e])
                i += 1
            elif "0" <= e <= "9":
                j = i
                while j < n and j < i + 3 and "0" <= s[j] <= "9":
                    j += 1
                v = int(s[i:j])
                if v > 255:
                    self.fail("decimal escape too large")
                out.append(v)
                i = j
            elif e == "x" and re.fullmatch(r"[0-9a-fA-F]{2}", s[i + 1:i + 3]):
                out.append(int(s[i + 1:i + 3], 16))
                i += 3
            elif e == "z":
                i += 1
                while i < n and s[i].isspace():
                    i += 1
            elif e == "\n" or e == "\r":
                out.append(10)
                i += 1
                if e == "\r" and i < n and s[i] == "\n":
                    i += 1
            else:  # Lua 5.1 keeps the character of an unknown escape
                out += e.encode("utf-8", "replace")
                i += 1
        self.i = i
        return out.decode("utf-8", "replace")

    def number(self):
        m = _SPECIAL.match(self.s, self.i)
        if m:
            self.i = m.end()
            return None  # inf / nan have no JSON form
        m = _NUM.match(self.s, self.i)
        if not m:
            return self.fail("unexpected token")
        self.i = m.end()
        t = m.group()
        if "x" in t or "X" in t:
            return int(t, 16)
        if re.fullmatch(r"-?\d+", t):
            return int(t)
        f = float(t)
        if math.isfinite(f) and f == int(f) and abs(f) < 2 ** 53:
            return int(f)
        return f

    def value(self, depth: int):
        c = self.peek()
        if not c:
            self.fail("unexpected end of input")
        if c == "{":
            return self.table(depth + 1)
        if c in "\"'":
            return self.string()
        if c == "[":
            v = self.long_string()
            if v is None:
                self.fail("unexpected '['")
            return v
        if c == "-" or c == "." or c.isdigit():
            return self.number()
        m = _NAME.match(self.s, self.i)
        if m and m.group() in ("true", "false", "nil"):
            self.i = m.end()
            return {"true": True, "false": False, "nil": None}[m.group()]
        if m and _SPECIAL.match(self.s, self.i):
            return self.number()
        return self.fail("unexpected token")

    def table(self, depth: int) -> dict:
        if depth > _MAX_DEPTH:
            self.fail("nesting too deep")
        self.expect("{")
        d: dict = {}
        idx = 1
        while True:
            c = self.peek()
            if not c:
                self.fail("unterminated table")
            if c == "}":
                self.i += 1
                return d
            key, positional = None, False
            if c == "[" and not _LONG_OPEN.match(self.s, self.i):
                self.i += 1
                key = self.value(depth)
                self.expect("]")
                self.expect("=")
            else:
                m = _NAME.match(self.s, self.i) if (c.isalpha() or c == "_") else None
                if m:
                    j = _WS.match(self.s, m.end()).end()
                    if self.s[j:j + 1] == "=" and self.s[j + 1:j + 2] != "=":
                        key = m.group()
                        self.i = j + 1
                if key is None:
                    positional = True
            val = self.value(depth)
            if positional:
                key = idx
                idx += 1
            elif isinstance(key, float) and key == int(key):
                key = int(key)
            if key is None or isinstance(key, (dict, bool)):
                self.fail("invalid table key")
            if val is None:
                d.pop(key, None)
            else:
                d[key] = val
            c = self.peek()
            if c in (",", ";"):
                self.i += 1
            elif c != "}":
                self.fail("expected ',' or '}'")

    def chunk(self) -> dict:
        out: dict = {}
        while True:
            c = self.peek()
            if not c:
                return out
            if c == ";":
                self.i += 1
                continue
            m = _NAME.match(self.s, self.i)
            if not m:
                self.fail("expected variable name")
            self.i = m.end()
            self.expect("=")
            val = self.value(0)
            if val is None:
                out.pop(m.group(), None)
            else:
                out[m.group()] = val


def parse_lua(text: str) -> dict:
    """Parse `Name = value` assignments. Tables become dicts (int keys stay ints); nil values are dropped."""
    if text.startswith("﻿"):
        text = text[1:]
    return _Parser(text).chunk()


def seq(t) -> list:
    """Values of a Lua array-like table in key order (accepts list or dict with int keys)."""
    if isinstance(t, list):
        return t
    if isinstance(t, dict):
        return [v for k, v in sorted((k, v) for k, v in t.items() if isinstance(k, int) and not isinstance(k, bool))]
    return []


# Tables keyed by ids (levels, zones...) must stay objects even when their keys happen to be 1..n.
_KEYED = {"brackets", "levels", "zones", "dungeons", "prof", "venue"}


def jsonable(v, key: str | None = None):
    """Convert parsed Lua data to JSON-safe data: 1..n tables become arrays (except id-keyed tables)."""
    if isinstance(v, dict):
        if v and key not in _KEYED and all(isinstance(k, int) and not isinstance(k, bool) for k in v):
            n = len(v)
            if all(i in v for i in range(1, n + 1)):
                return [jsonable(v[i]) for i in range(1, n + 1)]
        return {str(k): jsonable(x, k if isinstance(k, str) else None) for k, x in sorted(v.items(), key=lambda kv: str(kv[0]))}
    if isinstance(v, list):
        return [jsonable(x) for x in v]
    if isinstance(v, float) and not math.isfinite(v):
        return None
    return v


def read_lua_file(path: Path, retries: int = 5, delay: float = 0.4):
    """Read + parse a SavedVariables file, retrying while the game is still writing it. Returns (data, signature)."""
    last = None
    for attempt in range(retries):
        try:
            before = path.stat()
            raw = path.read_bytes()
            after = path.stat()
            if (before.st_mtime_ns, before.st_size) != (after.st_mtime_ns, after.st_size):
                raise LuaParseError("file changed while reading")
            return parse_lua(raw.decode("utf-8", "replace")), (after.st_mtime_ns, after.st_size)
        except (LuaParseError, OSError) as e:
            last = e
            time.sleep(delay)
    raise LuaParseError(f"{path.name}: {last}")


# --------------------------------------------------------------------------------------------------------------------
# Lua serializer (Data.lua writer). Deterministic: sorted keys, tab indent.

_LUA_KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil",
                 "not", "or", "repeat", "return", "then", "true", "until", "while"}
_IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")


def lua_string(s: str) -> str:
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif o < 32 or o == 127:
            out.append("\\%03d" % o)  # always 3 digits so a following digit is not absorbed
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lua_number(v) -> str | None:
    if isinstance(v, int):
        return str(v)
    if not math.isfinite(v):
        return None
    if v == int(v) and abs(v) < 2 ** 53:
        return str(int(v))
    return repr(v)


def lua_value(v, indent: int = 0) -> str:
    if v is None:
        return "nil"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, (int, float)):
        return lua_number(v) or "nil"
    if isinstance(v, str):
        return lua_string(v)
    pad, pad1 = "\t" * indent, "\t" * (indent + 1)
    if isinstance(v, (list, tuple)):
        if not v:
            return "{}"
        return "{\n" + "".join(f"{pad1}{lua_value(x, indent + 1)},\n" for x in v) + pad + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        lines = []
        for k in sorted(v, key=lambda k: (isinstance(k, str), str(k) if isinstance(k, str) else k)):
            x = v[k]
            if x is None:
                continue
            if isinstance(k, bool) or not isinstance(k, (str, int, float)):
                raise TypeError(f"unsupported key {k!r}")
            if isinstance(k, str):
                ks = k if (_IDENT.match(k) and k not in _LUA_KEYWORDS) else f"[{lua_string(k)}]"
            else:
                ks = f"[{lua_number(k)}]"
            lines.append(f"{pad1}{ks} = {lua_value(x, indent + 1)},\n")
        return "{\n" + "".join(lines) + pad + "}" if lines else "{}"
    raise TypeError(f"cannot serialize {type(v).__name__}")


# --------------------------------------------------------------------------------------------------------------------
# Config

def default_config_path() -> Path:
    if os.name == "nt" and os.environ.get("APPDATA"):
        return Path(os.environ["APPDATA"]) / "meta-uploader" / "config.json"
    base = os.environ.get("XDG_CONFIG_HOME")
    return (Path(base) if base else Path.home() / ".config") / "meta-uploader" / "config.json"


class Config:
    def __init__(self, path: Path):
        self.path = path
        self.data: dict = {"wow_dir": "", "token": "", "api": DEFAULT_API, "acked": {},
                     "mode": "daemon", "autostart": "off"}
        try:
            loaded = json.loads(path.read_text("utf-8"))
            if isinstance(loaded, dict):
                self.data.update(loaded)
        except (OSError, ValueError):
            pass
        if not isinstance(self.data.get("acked"), dict):
            self.data["acked"] = {}

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_name(self.path.name + ".tmp")
        # Created 0600 from the start: the file holds the token, and chmod after write leaves a window.
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(self.data, indent=2, sort_keys=True))
        try:
            os.chmod(tmp, 0o600)
        except OSError:
            pass
        os.replace(tmp, self.path)

    def acked(self, addon: str, install: str) -> int:
        v = self.data["acked"].get(addon, {}).get(install, 0)
        return v if isinstance(v, int) else 0

    def set_acked(self, addon: str, install: str, n: int) -> None:
        bucket = self.data["acked"].setdefault(addon, {})
        if n > bucket.get(install, 0):
            bucket[install] = n

    def __getitem__(self, k):
        return self.data.get(k)

    def __setitem__(self, k, v):
        self.data[k] = v


# --------------------------------------------------------------------------------------------------------------------
# WoW directory discovery

_FLAVOR = re.compile(r"_.+_\Z")


def ci_child(parent: Path, name: str) -> Path | None:
    p = parent / name
    if p.exists():
        return p
    try:
        for c in parent.iterdir():
            if c.name.lower() == name.lower():
                return c
    except OSError:
        pass
    return None


def flavor_roots(wow_dir: Path) -> list[Path]:
    roots: list[Path] = []
    if ci_child(wow_dir, "WTF"):
        roots.append(wow_dir)
    try:
        for c in sorted(wow_dir.iterdir()):
            if c.is_dir() and _FLAVOR.match(c.name) and ci_child(c, "WTF"):
                roots.append(c)
    except OSError:
        pass
    if _FLAVOR.match(wow_dir.name) and ci_child(wow_dir, "WTF") and wow_dir not in roots:
        roots.append(wow_dir)
    return roots


def looks_like_wow(p: Path) -> bool:
    try:
        return p.is_dir() and bool(flavor_roots(p))
    except OSError:
        return False


def _normalize_install_path(p: str) -> Path:
    path = Path(p.strip().rstrip("\\/"))
    return path.parent if _FLAVOR.match(path.name) else path


def _registry_candidates() -> list[Path]:
    try:
        import winreg  # type: ignore
    except ImportError:
        return []
    out: list[Path] = []
    keys = [r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft", r"SOFTWARE\Blizzard Entertainment\World of Warcraft"]
    for hive in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
        for key in keys:
            try:
                with winreg.OpenKey(hive, key) as k:
                    for val in ("InstallPath", "GameDir"):
                        try:
                            out.append(_normalize_install_path(winreg.QueryValueEx(k, val)[0]))
                        except OSError:
                            pass
            except OSError:
                pass
    return out


_GAME_NAMES = ["World of Warcraft", "WoW Forever", "Forever", "World of Warcraft Forever", "WoW"]


def candidate_dirs() -> list[Path]:
    cands: list[Path] = []
    if os.environ.get("WOW_DIR"):
        cands.append(Path(os.environ["WOW_DIR"]))
    cands += _registry_candidates()
    home = Path.home()
    if os.name == "nt":
        roots = [f"{d}:\\" for d in "CDEFGH"]
        subs = ["Program Files (x86)", "Program Files", "Games", "Blizzard", ""]
        cands += [Path(r) / s / n for r in roots for s in subs for n in _GAME_NAMES]
    elif sys.platform == "darwin":
        cands += [Path("/Applications") / n for n in _GAME_NAMES] + [home / "Applications" / n for n in _GAME_NAMES]
        cands += [Path("/Users/Shared") / n for n in _GAME_NAMES]
    else:
        wine_roots = [home / ".wine" / "drive_c"]
        for pat in (str(home / "Games" / "*" / "drive_c"),
                    str(home / ".var/app/com.usebottles.bottles/data/bottles/bottles/*/drive_c"),
                    str(home / ".local/share/bottles/bottles/*/drive_c"),
                    str(home / ".local/share/lutris/runners/wine/*/drive_c"),
                    str(home / ".local/share/Steam/steamapps/compatdata/*/pfx/drive_c")):
            wine_roots += [Path(p) for p in glob.glob(pat)]
        for r in wine_roots:
            for s in ("Program Files (x86)", "Program Files", "Games", ""):
                cands += [r / s / n for n in _GAME_NAMES]
        cands += [home / "Games" / n for n in _GAME_NAMES]
    return cands


def detect_wow_dir() -> Path | None:
    seen = set()
    for c in candidate_dirs():
        if c in seen:
            continue
        seen.add(c)
        if looks_like_wow(c):
            return c
    return None


@dataclass(frozen=True)
class SVFile:
    addon: str
    path: Path
    flavor_root: Path  # holds Interface/AddOns and WTF


def discover(wow_dir: Path) -> list[SVFile]:
    found: list[SVFile] = []
    for root in flavor_roots(wow_dir):
        wtf = ci_child(root, "WTF")
        accounts = ci_child(wtf, "Account") if wtf else None
        if not accounts:
            continue
        try:
            acct_dirs = sorted(a for a in accounts.iterdir() if a.is_dir() and a.name.lower() != "savedvariables")
        except OSError:
            continue
        for acct in acct_dirs:
            sv = ci_child(acct, "SavedVariables")
            if not sv:
                continue
            for addon in ADDONS:
                f = ci_child(sv, addon + ".lua")
                if f and f.is_file():
                    found.append(SVFile(addon, f, root))
    return found


# --------------------------------------------------------------------------------------------------------------------
# Payloads

_ROW_KEYS = ("seq", "t", "kind", "char", "data")
_STRIP_BS = ("duels", "trades", "bets")  # duels travel as outbox rows; trades/bets as ring rows


def outbox_delta(db: dict, acked: int) -> list[dict]:
    """Outbox rows with seq > acked, ordered, unique by seq, JSON-safe."""
    box = db.get("outbox")
    rows: dict[int, dict] = {}
    for r in seq(box.get("rows") if isinstance(box, dict) else None):
        if not isinstance(r, dict) or not isinstance(r.get("seq"), int) or isinstance(r.get("seq"), bool):
            continue
        if r["seq"] <= acked or not isinstance(r.get("kind"), str):
            continue
        rows[r["seq"]] = {k: jsonable(r[k], k if k != "data" else None) for k in _ROW_KEYS if k in r}
    return [rows[k] for k in sorted(rows)]


def build_state(addon: str, db: dict) -> dict:
    chars = db.get("chars")
    out: dict = {}
    if not isinstance(chars, dict):
        return {"chars": out}
    for key, c in chars.items():
        if not isinstance(c, dict):
            continue
        c = dict(c)
        if addon == "Bloodsports":
            for k in _STRIP_BS:
                c.pop(k, None)
        out[str(key)] = jsonable(c)
    return {"chars": out}


def build_payloads(addon: str, db: dict, acked: int, include_state: bool = True, batch: int = BATCH_ROWS) -> list[dict]:
    install = db.get("installId")
    if not isinstance(install, str) or not (8 <= len(install) <= 64):
        return []
    rows = outbox_delta(db, acked)
    chunks = [rows[i:i + batch] for i in range(0, len(rows), batch)] or ([[]] if include_state else [])
    payloads = []
    for i, chunk in enumerate(chunks):
        p = {"v": 1, "install": install, "addon": addon, "rows": chunk, "uploader": VERSION}
        if include_state and i == len(chunks) - 1:
            p["state"] = build_state(addon, db)
        payloads.append(p)
    return payloads


def state_hash(state: dict) -> str:
    return hashlib.sha1(json.dumps(state, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


# --------------------------------------------------------------------------------------------------------------------
# HTTP

class ApiError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(f"HTTP {status}: {message}")
        self.status = status


class NetworkError(Exception):
    pass


class _RefuseRedirects(urllib.request.HTTPRedirectHandler):
    """urllib would repeat a POST as a GET and send the Authorization header to the new address. The API never redirects,
    so a redirect is treated as an error (the sync retries later) instead of being followed."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(req.full_url, code, "redirect refused", headers, fp)


# Process-wide: every request this module makes (/link, /ingest, /data) goes through the refusing opener.
urllib.request.install_opener(urllib.request.build_opener(_RefuseRedirects))


def http_json(method: str, url: str, body: dict | None = None, token: str = "", timeout: float = 20.0) -> dict:
    headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    data = None
    if body is not None:
        data = json.dumps(body, separators=(",", ":")).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        with e:  # close the response; the error body is only read for its message
            try:
                msg = json.loads(e.read().decode("utf-8", "replace")).get("error", e.reason)
            except Exception:
                msg = e.reason
        raise ApiError(e.code, str(msg)) from None
    except (urllib.error.URLError, http.client.HTTPException, OSError, TimeoutError) as e:
        raise NetworkError(str(e)) from None
    try:
        out = json.loads(raw.decode("utf-8"))
    except ValueError:
        raise NetworkError("server sent invalid JSON") from None
    return out if isinstance(out, dict) else {}


# --------------------------------------------------------------------------------------------------------------------
# WorldOfMeta_Data addon writer

def build_toc() -> str:
    return (f"## Interface: {TOC_INTERFACE}\n## Title: World of Meta Data\n"
            "## Notes: Data downloaded by the Meta Uploader. Do not edit; it is overwritten.\n"
            "## Author: World of Meta\n## Version: 1\n## DefaultState: enabled\nData.lua\n")


def merge_acked(*maps: dict) -> dict:
    out: dict = {}
    for m in maps:
        if not isinstance(m, dict):
            continue
        for addon, installs in m.items():
            if not isinstance(installs, dict):
                continue
            bucket = out.setdefault(addon, {})
            for inst, n in installs.items():
                if isinstance(n, (int, float)) and not isinstance(n, bool) and n > bucket.get(inst, -1):
                    bucket[inst] = int(n)
    return out


def build_data_lua(data: dict, local_acked: dict, now: int | None = None) -> str:
    wom = {k: v for k, v in data.items() if k not in ("acked", "generatedAt", "ok")}
    wom["acked"] = merge_acked(data.get("acked"), local_acked)
    gen = data.get("generatedAt")
    gen = int(gen) if isinstance(gen, (int, float)) and not isinstance(gen, bool) else int(now if now is not None else time.time())
    body = lua_value(wom)  # starts with "{" (always non-empty: acked present)
    body = "{\n\tgeneratedAt = %d,\n" % gen + body[2:] if body != "{}" else "{\n\tgeneratedAt = %d,\n}" % gen
    return "-- Generated by Meta Uploader. Do not edit.\nWorldOfMetaData = " + body + "\n"


def _strip_generated(text: str) -> str:
    return re.sub(r"\tgeneratedAt = \d+,\n", "", text, count=1)


def write_data_addon(flavor_root: Path, data: dict, local_acked: dict) -> bool:
    """Write Interface/AddOns/WorldOfMeta_Data/{toc,Data.lua}. Returns True when something changed on disk."""
    addons = ci_child(flavor_root, "Interface")
    addons = (ci_child(addons, "AddOns") if addons else None) or (flavor_root / "Interface" / "AddOns")
    target = addons / DATA_ADDON
    target.mkdir(parents=True, exist_ok=True)
    changed = False
    toc, lua = build_toc(), build_data_lua(data, local_acked)
    toc_path, lua_path = target / (DATA_ADDON + ".toc"), target / "Data.lua"
    for path, text, cmp in ((toc_path, toc, lambda s: s), (lua_path, lua, _strip_generated)):
        try:
            old = path.read_text("utf-8")
        except OSError:
            old = None
        if old is not None and cmp(old) == cmp(text):
            continue
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_text(text, "utf-8", newline="\n")
        os.replace(tmp, path)
        changed = True
    return changed


# --------------------------------------------------------------------------------------------------------------------
# Sync engine

class Uploader:
    def __init__(self, cfg: Config, dry_run: bool = False):
        self.cfg = cfg
        self.dry = dry_run
        self.api = (cfg["api"] or DEFAULT_API).rstrip("/")
        self.fstate: dict[Path, dict] = {}
        self.state_hashes: dict[tuple, str] = {}
        self.data_cache: dict = {}
        self.last_data_fetch = 0.0
        self.rejected_codes: set[str] = set()  # codes the server answered with a 4xx: never sent again
        self.server_acked: dict = {}
        self._data_dirty = False
        self._token_reported = False  # the revoked-or-expired message is logged once per token

    # -- network helpers
    def post(self, path: str, body: dict) -> dict:
        return http_json("POST", self.api + path, body, self.cfg["token"])

    def _token_dead(self) -> None:
        """A 401 on /ingest or /data: the server no longer accepts this token. Says so once; the token is kept."""
        if not self._token_reported:
            self._token_reported = True
            log("token revoked or expired: run the link flow again (`meta_uploader.py link CODE`, code from the World of Meta site)")

    def link(self, code: str) -> bool:
        """Exchange a site link code for a token. Logs one status line; never logs the token."""
        code = re.sub(r"\s", "", code).upper()
        body = {"code": code, "client": USER_AGENT}
        if self.dry:
            print(f"DRY-RUN POST {self.api}/link\n{json.dumps(body, indent=2)}")
            return True
        try:
            resp = http_json("POST", self.api + "/link", body)
        except ApiError as e:
            if 400 <= e.status < 500 and e.status != 429:
                self.rejected_codes.add(code)
                log(f"link failed: {e}. This code will not be retried; write a new one in game.")
            else:
                log(f"link failed: {e}. Will retry.")
            return False
        except NetworkError as e:
            log(f"link failed (World of Meta unreachable), will retry: {e}")
            return False
        token = resp.get("token")
        if not isinstance(token, str) or not token:
            log("link failed: server returned no token")
            return False
        self.cfg["token"] = token
        self.cfg.save()
        self._token_reported = False
        log("linked to World of Meta. Token saved to " + str(self.cfg.path))
        return True

    def acked(self, addon: str, install: str) -> int:
        server = self.server_acked.get(addon, {}).get(install, 0)
        return max(self.cfg.acked(addon, install), server if isinstance(server, int) else 0)

    # -- one SavedVariables file
    def upload_file(self, f: SVFile, sv: dict) -> bool:
        ok = True
        db = sv.get(f.addon + "DB")
        if not isinstance(db, dict):
            return True
        if not self.cfg["token"] and not self.dry:
            self.auto_link(db)
        install = db.get("installId")
        if not isinstance(install, str):
            return True
        acked = self.acked(f.addon, install)
        state = build_state(f.addon, db)
        h = state_hash(state)
        want_state = self.state_hashes.get((f.addon, install)) != h
        for p in build_payloads(f.addon, db, acked, include_state=want_state):
            if self.dry:
                print(f"DRY-RUN POST {self.api}/ingest  ({f.path})\n{json.dumps(p, indent=2, sort_keys=True)}")
                continue
            if not self.cfg["token"]:
                log("not linked yet: run `meta_uploader.py link CODE` (code from the World of Meta site)")
                return False
            try:
                resp = self.post("/ingest", p)
            except ApiError as e:
                log(f"{f.addon}: upload rejected: {e}")
                if e.status == 401:
                    self._token_dead()
                    return False
                if e.status == 403:
                    return False
                if 400 <= e.status < 500 and e.status != 429:
                    return True  # a payload the server will never take; do not hammer it
                return False
            except NetworkError as e:
                log(f"{f.addon}: network error, will retry: {e}")
                return False
            top = max([r["seq"] for r in p["rows"]], default=0)
            got = resp.get("acked")
            n = got if isinstance(got, int) and not isinstance(got, bool) else top
            self.cfg.set_acked(f.addon, install, max(n, top) if resp.get("ok") else n)
            self.cfg.save()
            if "state" in p:
                self.state_hashes[(f.addon, install)] = h
            log(f"{f.addon}: sent {len(p['rows'])} rows, acked={self.cfg.acked(f.addon, install)}")
        return ok

    def auto_link(self, db: dict) -> None:
        """The in-game `/elders link CODE` leaves a `link` outbox row; use it to get a token if we have none.
        Newest code first. A 4xx marks that code rejected and the next code is tried; any other failure
        (network, 5xx) stops the pass and the code is retried on a later one."""
        rows = seq(db.get("outbox", {}).get("rows") if isinstance(db.get("outbox"), dict) else None)
        codes = []
        for r in rows:
            if isinstance(r, dict) and r.get("kind") == "link" and isinstance(r.get("data"), dict):
                code = r["data"].get("code")
                if isinstance(code, str) and code and code not in codes:
                    codes.append(code)
        for code in reversed(codes):
            if code in self.rejected_codes:
                continue
            if self.link(code):
                return
            if code not in self.rejected_codes:
                return

    # -- one file, with retry-friendly bookkeeping
    def process(self, f: SVFile, force: bool = False) -> bool:
        st = self.fstate.setdefault(f.path, {"sig": None, "retry_at": 0.0, "fails": 0})
        try:
            sig_now = f.path.stat()
        except OSError:
            return True
        sig = (sig_now.st_mtime_ns, sig_now.st_size)
        now = time.time()
        if not force:
            if sig == st["sig"] or now < st["retry_at"]:
                return True
            if now - sig_now.st_mtime < 1.0:  # the client may still be writing; look again next poll
                return True
        try:
            data, sig = read_lua_file(f.path)
        except LuaParseError as e:
            log(f"{f.path.name}: unreadable right now ({e}); will retry")
            st["retry_at"] = now + 5
            return False
        db = data.get(f.addon + "DB")
        if isinstance(db, dict) and isinstance(db.get("installId"), str):
            st["install"] = db["installId"]
        ok = self.upload_file(f, data)
        if ok:
            st["sig"], st["fails"] = sig, 0
        else:
            st["fails"] += 1
            st["retry_at"] = now + min(300, 5 * 2 ** st["fails"])
        return ok

    # -- download direction
    def refresh_data(self, files: list[SVFile], installs_by_root: dict[Path, set[str]], force: bool = False) -> None:
        if not files:
            return
        now = time.time()
        if not force and now - self.last_data_fetch < DATA_REFRESH_SECONDS and not self._data_dirty:
            return
        installs = sorted({i for s in installs_by_root.values() for i in s})
        if self.dry:
            q = "&".join("install=" + urllib.parse.quote(i) for i in installs)
            print(f"DRY-RUN GET {self.api}/data?{q}\nDRY-RUN would write {DATA_ADDON} into: "
                  + ", ".join(str(r) for r in installs_by_root))
            return
        if self.cfg["token"] and installs:
            q = "&".join("install=" + urllib.parse.quote(i) for i in installs)
            try:
                self.data_cache = http_json("GET", f"{self.api}/data?{q}", None, self.cfg["token"])
                self.server_acked = merge_acked(self.data_cache.get("acked"))
                self.last_data_fetch = now
                self._data_dirty = False
            except (ApiError, NetworkError) as e:
                if isinstance(e, ApiError) and e.status == 401:
                    self._token_dead()
                else:
                    log(f"data download failed: {e}")
                self.last_data_fetch = now - DATA_REFRESH_SECONDS + 60  # retry in a minute
        if not self.data_cache and not self.cfg.data["acked"]:
            return
        for root in installs_by_root:
            try:
                if write_data_addon(root, self.data_cache, self.cfg.data["acked"]):
                    log(f"updated {DATA_ADDON} in {root}")
            except OSError as e:
                log(f"cannot write {DATA_ADDON} in {root}: {e}")

    # -- passes
    def cycle(self, wow_dir: Path, force: bool = False) -> bool:
        files = discover(wow_dir)
        uploaded = False
        before = json.dumps(self.cfg.data["acked"], sort_keys=True)
        had_token = bool(self.cfg["token"])
        failed = [f for f in files if not self.process(f, force)]
        if failed and not had_token and self.cfg["token"]:  # a link code found in a later file just gave us a token
            failed = [f for f in failed if not self.process(f, True)]
        all_ok = not failed
        if json.dumps(self.cfg.data["acked"], sort_keys=True) != before:
            uploaded = True
            self._data_dirty = True
        installs: dict[Path, set[str]] = {}
        for f in files:
            ids = installs.setdefault(f.flavor_root, set())
            iid = self.fstate.get(f.path, {}).get("install")
            if iid:
                ids.add(iid)
        self.refresh_data(files, installs, force=force or uploaded)
        return all_ok


# --------------------------------------------------------------------------------------------------------------------
# CLI

def resolve_wow_dir(args, cfg: Config) -> Path | None:
    for cand in (args.wow_dir, cfg["wow_dir"], os.environ.get("WOW_DIR")):
        if cand:
            p = Path(cand).expanduser()
            return p
    found = detect_wow_dir()
    if found:
        log(f"found WoW at {found}")
        if not args.dry_run:
            cfg["wow_dir"] = str(found)
            cfg.save()
    return found


def is_windows() -> bool:
    return sys.platform == "win32"


# -- autostart (Windows Run key)

def autostart_command() -> str:
    """Command line stored in the Run key: the tray launcher."""
    exe = sys.executable
    if getattr(sys, "frozen", False):
        return f'"{ntpath.join(ntpath.dirname(exe), TRAY_EXE)}" daemon --tray'
    if exe.lower().endswith("python.exe"):
        exe = exe[:-len("python.exe")] + "pythonw.exe"
    return f'"{exe}" "{os.path.abspath(__file__)}" daemon --tray'


def run_key_write(command: str | None) -> None:
    """Set the Run value, or delete it when command is None. Separate function so tests can mock it."""
    import winreg  # type: ignore
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as k:
        if command is None:
            try:
                winreg.DeleteValue(k, APP_NAME)
            except FileNotFoundError:
                pass
        else:
            winreg.SetValueEx(k, APP_NAME, 0, winreg.REG_SZ, command)


def run_key_read() -> str | None:
    try:
        import winreg  # type: ignore
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as k:
            return winreg.QueryValueEx(k, APP_NAME)[0]
    except (ImportError, OSError):
        return None


def cmd_autostart(state: str, dry: bool = False) -> int:
    if not is_windows():
        log("autostart is only supported on Windows")
        return 3
    command = autostart_command() if state == "on" else None
    if dry:
        log(f"DRY-RUN would {'set' if command else 'remove'} HKCU\\{RUN_KEY}\\{APP_NAME}" + (f" = {command}" if command else ""))
        return 0
    try:
        run_key_write(command)
    except OSError as e:
        log(f"autostart failed: {e}")
        return 1
    log(f"autostart {state}" + (f": {command}" if command else ""))
    return 0


# -- single instance

class SingleInstance:
    """Windows: named mutex. Elsewhere: exclusive lock file in the config directory."""

    def __init__(self, lock_path: Path):
        self.lock_path = lock_path
        self._handle = None

    def acquire(self) -> bool:
        if is_windows():
            return self._acquire_mutex()
        self._handle = lock_file_acquire(self.lock_path)
        return self._handle is not None

    def _acquire_mutex(self) -> bool:
        import ctypes
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)  # type: ignore[attr-defined]
        k32.CreateMutexW.restype = ctypes.c_void_p
        h = k32.CreateMutexW(None, False, APP_NAME)
        if h and ctypes.get_last_error() == 183:  # ERROR_ALREADY_EXISTS
            k32.CloseHandle(ctypes.c_void_p(h))
            return False
        self._handle = h or True  # keep it open for the life of the process
        return True

    def release(self) -> None:
        h, self._handle = self._handle, None
        if h is None or is_windows():
            return
        try:
            h.close()  # closing the file drops the lock
        except OSError:
            pass


def lock_file_acquire(path: Path):
    """Open path and take an exclusive non-blocking lock. Returns the open file, or None if someone else holds it."""
    try:
        import fcntl
        path.parent.mkdir(parents=True, exist_ok=True)
        f = open(path, "a+")
    except (ImportError, OSError):
        return None
    try:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        f.close()
        return None
    return f


def instance_running(lock_path: Path) -> bool:
    """Read-only check for a running daemon."""
    if is_windows():
        import ctypes
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)  # type: ignore[attr-defined]
        k32.OpenMutexW.restype = ctypes.c_void_p
        h = k32.OpenMutexW(0x00100000, False, APP_NAME)  # SYNCHRONIZE
        if h:
            k32.CloseHandle(ctypes.c_void_p(h))
        return bool(h)
    if not lock_path.exists():
        return False
    f = lock_file_acquire(lock_path)
    if f is None:
        return True
    f.close()
    return False


# -- daemon loop

def daemon_loop(cycle, interval: float, stop: threading.Event, wake: threading.Event,
                max_cycles: int | None = None, on_cycle=None) -> None:
    """Call cycle() every interval seconds until stop is set. wake cuts the wait short (Sync now)."""
    n = 0
    while not stop.is_set():
        try:
            ok = cycle()
        except Exception as e:  # keep the daemon alive whatever one pass hits
            log(f"sync pass failed: {e}")
            ok = False
        n += 1
        if on_cycle:
            on_cycle(ok)
        if max_cycles is not None and n >= max_cycles:
            return
        wake.wait(interval)
        wake.clear()


class DaemonState:
    def __init__(self):
        self.last_sync: float | None = None
        self.ok = True

    def record(self, ok: bool) -> None:
        self.ok = ok
        if ok:
            self.last_sync = time.time()

    def text(self) -> str:
        when = time.strftime("%H:%M:%S", time.localtime(self.last_sync)) if self.last_sync else "never"
        return f"Last sync: {when}" + ("" if self.ok else " (retrying)")


def tray_icon_image():
    from PIL import Image, ImageDraw  # type: ignore
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse((3, 3, 61, 61), fill=(24, 24, 32, 255), outline=(212, 160, 23, 255), width=6)
    return img


def run_tray(loop, state: DaemonState, stop: threading.Event, wake: threading.Event, site: str) -> bool:
    """Tray icon on the main thread, sync loop in a thread. Returns False when the tray cannot be used."""
    try:
        import pystray  # type: ignore
        image = tray_icon_image()
    except Exception as e:  # ImportError, or Pillow/pystray failing to load
        log(f"tray unavailable ({e}); using the console loop")
        return False
    thread = threading.Thread(target=loop, name="sync", daemon=True)

    def quit_(icon, item=None):
        stop.set()
        wake.set()
        icon.stop()

    menu = pystray.Menu(
        pystray.MenuItem(lambda item: state.text(), None, enabled=False),
        pystray.MenuItem("Sync now", lambda icon, item: wake.set()),
        pystray.MenuItem("Open World of Meta", lambda icon, item: webbrowser.open(site)),
        pystray.MenuItem("Quit", quit_))
    icon = pystray.Icon(APP_NAME, image, "World of Meta Uploader", menu)

    def setup(ic):
        ic.visible = True
        thread.start()

    try:
        icon.run(setup)
    except Exception as e:
        log(f"tray failed ({e}); using the console loop")
        if not thread.is_alive():
            return False
    stop.set()
    wake.set()
    thread.join(timeout=10)
    return True


def run_daemon(up: Uploader, wow: Path, interval: float, tray: bool = False, stop: threading.Event | None = None,
               max_cycles: int | None = None) -> None:
    stop, wake, state = stop or threading.Event(), threading.Event(), DaemonState()

    def loop():
        daemon_loop(lambda: up.cycle(wow), interval, stop, wake, max_cycles, state.record)

    if tray and run_tray(loop, state, stop, wake, up.cfg["site"] or DEFAULT_SITE):
        return
    log(f"watching {wow} every {interval:g}s (Ctrl+C to stop); api={up.api}")
    try:
        loop()
    except KeyboardInterrupt:
        log("stopped")


def cmd_daemon(up: Uploader, cfg: Config, args) -> int:
    lock_path = cfg.path.with_name("uploader.lock")
    inst = SingleInstance(lock_path)
    if not args.dry_run:
        if not inst.acquire():
            log("another World of Meta Uploader is already running; exiting")
            return 0
        open_file_log(cfg.path.with_name("uploader.log"))
    try:
        wow = find_wow(args, cfg)
        if not wow:
            return 2
        run_daemon(up, wow, args.interval, getattr(args, "tray", False))
        return 0
    finally:
        inst.release()
        close_file_log()


# -- configure / status

def cmd_configure(cfg: Config, args) -> int:
    mode = args.mode or cfg["mode"] or "daemon"
    if args.dry_run:
        log(f"DRY-RUN would save mode={mode}" + (f", autostart={args.autostart}" if args.autostart else ""))
    else:
        cfg["mode"] = mode
        cfg.save()
    rc = 0
    if args.autostart:
        rc = cmd_autostart(args.autostart, args.dry_run)
        if rc == 0 and not args.dry_run:
            cfg["autostart"] = args.autostart
            cfg.save()
    if not args.dry_run:
        log(f"saved to {cfg.path}: mode={cfg['mode']}, autostart={cfg['autostart']}")
    return rc


def cmd_status(cfg: Config, args) -> int:
    wow = next((Path(c).expanduser() for c in (args.wow_dir, cfg["wow_dir"], os.environ.get("WOW_DIR")) if c), None)
    wow = wow or detect_wow_dir()
    if is_windows():
        cmd = run_key_read()
        auto = f"on ({cmd})" if cmd else "off"
    else:
        auto = "n/a (Windows only)"
    running = instance_running(cfg.path.with_name("uploader.lock"))
    files = len(discover(wow)) if wow and wow.is_dir() else 0
    print(f"mode:       {cfg['mode'] or 'daemon'}")
    print(f"autostart:  {auto}")
    print(f"daemon:     {'running' if running else 'not running'}")
    print(f"WoW folder: {wow or 'not found'}")
    print(f"API:        {(cfg['api'] or DEFAULT_API)}")
    print(f"SavedVariables files found: {files}")
    return 0


def find_wow(args, cfg: Config) -> Path | None:
    wow = resolve_wow_dir(args, cfg)
    if not wow or not wow.is_dir():
        log("could not find World of Warcraft. Pass --wow-dir <folder containing _classic_ / _retail_ / ...>")
        return None
    if not discover(wow):
        log(f"no Elders/Bloodsports SavedVariables under {wow} yet (log in once with the addons, then /reload)")
    return wow


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    S = argparse.SUPPRESS
    common.add_argument("--wow-dir", default=S, help="World of Warcraft folder (holds the _*_ flavor folders)")
    common.add_argument("--api", default=S, help=f"ingest API base URL (default {DEFAULT_API})")
    common.add_argument("--config", default=S, help="config file (default ~/.config/meta-uploader/config.json)")
    common.add_argument("--dry-run", action="store_true", default=S, help="print payloads; no network, no writes")
    ap = argparse.ArgumentParser(prog="meta_uploader", description=__doc__.split("\n")[1], parents=[common])
    ap.set_defaults(wow_dir=None, api=None, config=None, dry_run=False)
    sub = ap.add_subparsers(dest="cmd", required=True)
    pl = sub.add_parser("link", parents=[common], help="exchange a site link code for a token (asks if no CODE)")
    pl.add_argument("code", nargs="?")
    pd = sub.add_parser("daemon", parents=[common], help="keep syncing until stopped (--tray for a tray icon)")
    pd.add_argument("--tray", action="store_true", help="show a tray icon (needs pystray and Pillow)")
    pd.add_argument("--interval", type=float, default=POLL_SECONDS)
    pr = sub.add_parser("run", parents=[common], help="same as daemon without the tray")
    pr.add_argument("--interval", type=float, default=POLL_SECONDS)
    sub.add_parser("once", parents=[common], help="sync once and exit")
    pc = sub.add_parser("configure", parents=[common], help="choose daemon or script mode, and autostart")
    pc.add_argument("--mode", choices=("daemon", "script"), help="daemon keeps syncing, script is manual (default: keep)")
    pc.add_argument("--autostart", choices=("on", "off"), help="start the tray daemon with Windows")
    pa = sub.add_parser("autostart", parents=[common], help="start the tray daemon with Windows (Windows only)")
    pa.add_argument("state", choices=("on", "off"))
    sub.add_parser("status", parents=[common], help="show mode, autostart, daemon, WoW folder, API, files")
    return ap


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    cfg = Config(Path(args.config).expanduser() if args.config else default_config_path())
    if args.api:
        cfg["api"] = args.api
        if not args.dry_run:
            cfg.save()
    up = Uploader(cfg, dry_run=args.dry_run)
    if args.cmd == "link":
        code = args.code or input("Link code from the site: ")
        return 0 if up.link(code) else 1
    if args.cmd == "configure":
        return cmd_configure(cfg, args)
    if args.cmd == "autostart":
        return cmd_autostart(args.state, args.dry_run)
    if args.cmd == "status":
        return cmd_status(cfg, args)
    if args.cmd in ("daemon", "run"):
        return cmd_daemon(up, cfg, args)
    wow = find_wow(args, cfg)
    if not wow:
        return 2
    return 0 if up.cycle(wow, force=True) else 1


if __name__ == "__main__":
    sys.exit(main())
