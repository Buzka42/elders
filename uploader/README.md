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
`.github/workflows/uploader-windows.yml` (in the `elders` repo) runs the unit tests and builds the installer on every
push that touches `uploader/**`, or when started by hand.

## Linux build

`packaging/build-linux.sh` builds a one-file console binary with PyInstaller in a local venv:
`packaging/dist/meta-uploader`, plus `meta-uploader-<VERSION>-linux-<arch>.tar.gz`. The default build is stdlib-only, and
`--with-tray` also bundles pystray and Pillow. Install with `install-linux.sh [--autostart]` from the tarball. It puts the
binary in `~/.local/bin` and adds an app-menu launcher (and, with `--autostart`, an XDG autostart entry). The launcher
runs `daemon --tray`, which falls back to the console loop when there is no tray. Hyprland needs `exec-once` for
autostart. See `packaging/README.md`.

## Tests

`python3 -m unittest discover -s uploader` (from the `elders` folder). It includes a mock-server end-to-end run. The last run
passed 68 tests (2026-11-05).

## Is it safe? (read this before running a game-side binary)

Yes — and you don't have to take our word for it. The whole program is one file,
`uploader/meta_uploader.py` (MIT licensed, this repo), Python standard library only.
No compiled dependencies, no obfuscation, ~1400 lines you can read in one sitting.

**Where everything lives on your machine:**

| What | Windows | Linux / macOS |
|---|---|---|
| Config + install token | `%APPDATA%\meta-uploader\config.json` | `~/.config/meta-uploader/config.json` |
| Log | same folder, `uploader.log` (rotated at 512 KB) | same |
| Game data it reads | `...\World of Warcraft\_<flavor>_\WTF\Account\*\SavedVariables\{Elders,Bloodsports}.lua` | same layout under your Wine prefix / install |
| What it writes into the game | `Interface\AddOns\WorldOfMeta_Data\{WorldOfMeta_Data.toc,Data.lua}` | same |
| Autostart (only if you ask) | `HKCU\...\Run` value `WorldOfMetaUploader` | XDG autostart entry (Hyprland: `exec-once`) |

**Exactly what it does, in order:** reads the two SavedVariables files the game itself
wrote to disk → POSTs only new outbox rows plus per-character aggregates to
`https://worldofmeta.win/api/ingest` (bearer install token, `--api` overrides the host) →
GETs `/api/data` and rewrites the `WorldOfMeta_Data` addon so ranks flow back into the
game. Link codes go to `/api/link` once and are never stored. Every request the program
makes goes through one function, and `--dry-run` prints each payload instead of sending
it — run any command with `--dry-run` first and inspect everything before a byte leaves.

**What it never does:** no game-memory reading, no keystrokes, no mouse, no screenshots,
no overlay, no `/reload`, no chat. The only `ctypes` use is the Windows named mutex
(`WorldOfMetaUploader`) that keeps a second copy from running — that is all it is.
The optional tray (`pystray`) is just an icon with Quit; without it the same loop runs
in the console. The token file is created owner-only (`0600` on POSIX, asserted by test).

**Verify it yourself in 5 minutes:**

1. `python3 uploader/meta_uploader.py status` — shows what it found, sends nothing.
2. `... once --dry-run` — prints the exact JSON it would POST. Compare with the tables
   in `wom-backend/schema*.sql` (also MIT, public repo).
3. Run from source for a week: `python3 uploader/meta_uploader.py daemon`. The release
   binaries are built from this exact file (`packaging/*.spec`, CI builds attached to
   each GitHub release) — same input, same behavior, or file a bug.
