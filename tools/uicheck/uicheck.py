#!/usr/bin/env python3
"""uicheck — capture the WoW window and measure it, so a UI loop can judge pixels instead of prose.

Why: the client lives on its own monitor under Hyprland/XWayland. Screenshots taken "however" drift
with window geometry, and a moved window reads as a layout bug. Every capture through this tool pins
the window to its monitor first and records the rect next to the file.

Usage:
  uicheck.py geo                       # window rect, monitor, scale (JSON)
  uicheck.py shot --out FILE [--no-pin] # capture the window rect at 1:1
  uicheck.py diff A.png B.png          # RMSE + per-band deltas between two captures
  uicheck.py reload [--windows N]      # /reload in game (Enter first), wait, then shot
  uicheck.py say "/bs" [--wait S]      # type one chat command into the client

Safety: `reload` and `say` drive the game's chat box. Never run them while the owner is typing in
game — keystrokes interleave into one box and the mix goes out as public SAY. Capture (`geo`, `shot`,
`diff`) is read-only and always safe.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

TITLE_MATCH = ("world of warcraft", "wow.exe")


def runtime_env() -> dict:
    env = dict(os.environ)
    env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    sig = sorted(Path(env["XDG_RUNTIME_DIR"], "hypr").glob("*"))
    if sig:
        env["HYPRLAND_INSTANCE_SIGNATURE"] = sig[-1].name
    for cand in sorted(Path(env["XDG_RUNTIME_DIR"]).glob("wayland-*")):
        if not cand.name.endswith(".lock"):
            env.setdefault("WAYLAND_DISPLAY", cand.name)
            break
    env.setdefault("DISPLAY", ":0")
    return env


ENV = runtime_env()


def run(cmd: list[str], **kw) -> str:
    out = subprocess.run(cmd, env=ENV, capture_output=True, text=True, **kw)
    if out.returncode != 0:
        raise SystemExit(f"{cmd[0]} failed ({out.returncode}): {out.stderr.strip()[:400]}")
    return out.stdout


def clients() -> list[dict]:
    data = json.loads(run(["hyprctl", "-j", "clients"]))
    hits = []
    for c in data:
        blob = f"{c.get('class','')} {c.get('title','')} {c.get('initialClass','')}".lower()
        if any(m in blob for m in TITLE_MATCH):
            hits.append(c)
    return hits


def monitors() -> list[dict]:
    return json.loads(run(["hyprctl", "-j", "monitors"]))


def find_game() -> dict:
    hits = clients()
    if not hits:
        raise SystemExit("WoW window not found: is the client running?")
    # the game window is the biggest one; Battle.net's launcher shares the class
    game = max(hits, key=lambda c: c["size"][0] * c["size"][1])
    return game


def x11_game_window() -> str:
    """Hex X window id from wmctrl (xdotool needs this, not the Hyprland address)."""
    for line in run(["wmctrl", "-l"]).splitlines():
        parts = line.split(None, 3)
        if len(parts) == 4 and parts[3].strip().lower().startswith("world of warcraft"):
            return parts[0]
    raise SystemExit("WoW X window not found via wmctrl: is the client running?")


def monitor_of(rect: dict) -> dict:
    x, y = rect["at"]
    for m in monitors():
        if m["x"] <= x < m["x"] + m["width"] and m["y"] <= y < m["y"] + m["height"]:
            return m
    return monitors()[0]


def geo() -> dict:
    g = find_game()
    m = monitor_of(g)
    return {
        "address": g["address"],
        "class": g.get("class"),
        "title": g.get("title"),
        "at": g["at"],
        "size": g["size"],
        "monitor": m["name"],
        "monitor_at": [m["x"], m["y"]],
        "monitor_size": [m["width"], m["height"]],
        "scale": g.get("scale", 1.0),
        "drift": [g["at"][0] - m["x"], g["at"][1] - m["y"]],
    }


def pin() -> dict:
    """Move the game to its monitor's top-left at full monitor size; move AFTER resize (resize re-centres)."""
    g = find_game()
    m = monitor_of(g)
    addr = g["address"]
    want_w, want_h = m["width"], m["height"]
    if g["size"] != [want_w, want_h]:
        run(["hyprctl", "eval", f'hl.dispatch(hl.dsp.window.resize({{ x = {want_w}, y = {want_h} }}, "{addr}"))'])
        time.sleep(0.25)
    if g["at"] != [m["x"], m["y"]]:
        run(["hyprctl", "eval", f'hl.dispatch(hl.dsp.window.move({{ x = {m["x"]}, y = {m["y"]} }}, "{addr}"))'])
        time.sleep(0.25)
    return geo()


def shot(out: Path, do_pin: bool = True) -> dict:
    g = pin() if do_pin else geo()
    m = g["monitor_at"]
    out.parent.mkdir(parents=True, exist_ok=True)
    run(["grim", "-g", f"{m[0]},{m[1]} {g['size'][0]}x{g['size'][1]}", str(out)])
    meta = {"file": str(out), "bytes": out.stat().st_size, "geometry": g["size"], "at": g["at"],
            "monitor": g["monitor"], "taken_at": time.strftime("%Y-%m-%dT%H:%M:%S")}
    out.with_suffix(out.suffix + ".json").write_text(json.dumps(meta, indent=1))
    return meta


def diff(a: Path, b: Path) -> dict:
    try:
        from PIL import Image, ImageChops, ImageStat
    except ImportError:
        raise SystemExit("Pillow missing: run with the interpreter that owns it (Hermes venv python)")
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        return {"error": "size mismatch", "a": ia.size, "b": ib.size}
    d = ImageChops.difference(ia, ib)
    stat = ImageStat.Stat(d)
    rmse = (sum(v * v for v in stat.rms) / 3) ** 0.5
    w, h = ia.size
    bands = {}
    for name, box in {"top": (0, 0, w, h // 4), "middle": (0, h // 4, w, 3 * h // 4),
                      "bottom": (0, 3 * h // 4, w, h)}.items():
        bands[name] = round(ImageStat.Stat(d.crop(box)).rms[0], 2)
    return {"size": [w, h], "rmse": round(rmse, 2), "rms_per_channel": [round(v, 2) for v in stat.rms],
            "bands_r": bands, "identical": rmse < 0.5}


def focus() -> None:
    run(["wmctrl", "-a", "World of Warcraft"])


def keyseq(*keys: str, delay: float = 0.12) -> None:
    win = x11_game_window()
    for k in keys:
        run(["xdotool", "key", "--window", win, "--clearmodifiers", k])
        time.sleep(delay)


def say(text: str, wait: float = 1.5) -> None:
    focus()
    time.sleep(0.3)
    keyseq("Return")            # chat box opens first; a slash typed into closed chat does nothing
    run(["xdotool", "type", "--window", x11_game_window(), "--delay", "12", text])
    time.sleep(0.2)
    keyseq("Return")
    time.sleep(wait)


def click(x: int, y: int, wait: float = 1.2) -> None:
    # x/y are game-screen pixels (the 1920x1080 capture); xdotool wants desktop
    # coordinates and the game monitor is offset (e.g. +1920,0) on this box.
    g = geo()
    run(["xdotool", "mousemove", str(x + g["monitor_at"][0]), str(y + g["monitor_at"][1]), "click", "1"])
    time.sleep(wait)


# Sidebar rows / tabs relative to a centred 960x600 window on the 1920x1080 game screen.
# Estimates only: every tour step saves a shot so the judge can see which page actually opened.
# Calibrated on the it5 tour (960x600 window centred): first sidebar row ~y330, rows ~28px apart,
# tabs on the title band (Bloodsports ~770, Elders ~885). First tour run was ~30px too low.
TOUR_STEPS = [
    ("stats", 620, 358),
    ("clubs", 620, 386),
    ("finder", 620, 414),
    ("duels", 620, 442),
    ("elders_tab", 885, 300),
    ("elders_s2", 620, 358),
    ("elders_s3", 620, 386),
    ("elders_s1", 620, 330),
    ("back_bloodsports", 770, 300),
    ("back_ring", 620, 330),
]


def tour(outdir: Path) -> list[dict]:
    out = []
    for name, x, y in TOUR_STEPS:
        click(x, y)
        out.append(shot(outdir / f"tour_{name}.png", do_pin=False))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("geo")
    p_shot = sub.add_parser("shot")
    p_shot.add_argument("--out", required=True)
    p_shot.add_argument("--no-pin", action="store_true")
    p_diff = sub.add_parser("diff")
    p_diff.add_argument("a")
    p_diff.add_argument("b")
    p_say = sub.add_parser("say")
    p_say.add_argument("text")
    p_say.add_argument("--wait", type=float, default=1.5)
    p_reload = sub.add_parser("reload")
    p_reload.add_argument("--wait", type=float, default=12.0)
    p_reload.add_argument("--out", default=str(Path.home() / "Projects/elders/docs/baseline/reload.png"))
    p_tour = sub.add_parser("tour")
    p_tour.add_argument("--outdir", default=str(Path.home() / "Projects/elders/docs/baseline"))

    a = ap.parse_args()
    if a.cmd == "geo":
        print(json.dumps(geo(), indent=1))
    elif a.cmd == "shot":
        print(json.dumps(shot(Path(a.out), do_pin=not a.no_pin), indent=1))
    elif a.cmd == "diff":
        print(json.dumps(diff(Path(a.a), Path(a.b)), indent=1))
    elif a.cmd == "say":
        say(a.text, a.wait)
        print(json.dumps({"sent": a.text}))
    elif a.cmd == "reload":
        say("/reload", wait=a.wait)
        print(json.dumps(shot(Path(a.out)), indent=1))
    elif a.cmd == "tour":
        print(json.dumps(tour(Path(a.outdir)), indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
