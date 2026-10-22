# Meta Uploader

Desktop helper for the Elders and Bloodsports addons. It reads the SavedVariables files the game already wrote to disk,
uploads new outbox rows to World of Meta, and writes the `WorldOfMeta_Data` addon (ranks, insights, champions, acked seqs)
back into your AddOns folder. It never reads game memory and never sends keystrokes or `/reload`.

Python 3.10+, standard library only: `python3 meta_uploader.py ...`

## Use

1. Get a link code. Create one on the World of Meta account page, or type `/elders link CODE` or `/bs link CODE` in game.
   A code is exactly 8 letters or digits; the addons refuse anything else. In game, the code is saved to SavedVariables
   and sent on logout or Sync.
2. `python3 meta_uploader.py link CODE` exchanges the code for an install token and stores it in
   `~/.config/meta-uploader/config.json` (`%APPDATA%\meta-uploader\config.json` on Windows). If no token exists yet, the
   uploader also tries the newest `link` code it finds in SavedVariables.
3. `python3 meta_uploader.py run` polls every 2 s. In game press the addon's Sync button (or `/reload`): the client only
   writes SavedVariables on logout, `/reload` and exit. `once` does a single pass.

Daemon and install options:

- `daemon [--tray]` keeps syncing until stopped (`run` is the same without the tray). `--tray` needs
  `pip install -r requirements-tray.txt`; without those packages it falls back to the console loop. One instance at a time.
  Logs go to `uploader.log` (rotated at 512 KB) next to the config.
- `configure --mode {daemon,script} [--autostart {on,off}]` saves the mode; `autostart on|off` (Windows) adds or removes the
  `WorldOfMetaUploader` value under `HKCU\...\Run`. `status` shows the current setup. `link` without a code asks for it.

Options (before or after the command): `--wow-dir DIR` (folder holding `_classic_`, `_retail_`, ...), `--api URL`
(default `https://worldofmeta.win/api`), `--config FILE`, `--dry-run` (print payloads; no network, no writes).

## What it does

- Finds WoW: `--wow-dir`, config, `$WOW_DIR`, Windows registry (winreg) and common Windows / macOS / Linux-Wine / Lutris /
  Bottles paths. Scans every `_*_` flavor folder and every account for `Elders.lua` and `Bloodsports.lua`.
- Parses the Lua table with a hand-written parser (escapes incl. `\ddd`, long strings, comments, hex/float/negative numbers,
  `nil`). A half-written file is retried; if it is still unreadable the pass is retried later.
- POSTs `{install, addon, rows (seq > acked), state}` to `{api}/ingest` with `Authorization: Bearer <token>`, 200 rows per
  request. Elders `state` = per-character aggregates; Bloodsports `state` = characters without `duels`, `trades`, `bets`
  (those travel as outbox rows). The acked seq is stored in the config and also comes back through `WorldOfMetaData.acked`,
  which is how the addon compacts its outbox.
- GETs `{api}/data?install=...` (after uploads and every 10 min) and rewrites
  `Interface/AddOns/WorldOfMeta_Data/{WorldOfMeta_Data.toc,Data.lua}` for each flavor, only when the content changed.

## Errors and retries

| Answer | Link (`POST /link`) | Upload (`POST /ingest`) |
|---|---|---|
| 4xx, except 429 | The code is dead. It is never retried, and the next-newest code is tried. Write a new code in game. | 401 or 403: "token invalid or expired"; run `link CODE` again. Other 4xx: that batch is skipped. The file is sent again only after it changes. |
| 429, 5xx, network error | Retried on a later pass. | Retried with backoff: 10 s, then 20 s, doubling, up to 5 min. |

A file that cannot be parsed (for example, the game is still writing it) is retried after 5 s.

## Windows build

`packaging/` has the PyInstaller spec, the Inno Setup script and `build.ps1`. See `packaging/README.md`. The GitHub workflow
`.github/workflows/uploader-windows.yml` (in the `elders` repo) runs only when started by hand.

## Tests

`python3 -m unittest discover -s uploader` (from the `elders` folder). It includes a mock-server end-to-end run. The last run
passed 62 tests (2026-10-22).
