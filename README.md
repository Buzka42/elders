# Elders

Elders is a World of Warcraft addon for **WoW: Forever**. It records leveling stats for each character, per level bracket
(1-10, 11-20, and so on up to 51-60). Every 10 levels it asks you to rate your class and to vote on other players'
insights. The Meta Uploader sends the data to World of Meta. The data is meant to feed the class tier list.

Status: in development. The addon is not released. The rank is not shown in the addon yet (see Ranks).

## Stats

Collected by `Elders/Collect/*.lua`, per bracket:

- **Pace**: time played, XP, quests, kills, XP from kills, solo elite kills.
- **Downtime**: activity time and rested time.
- **Combat**: fights, fight length, damage done and taken, healing, interrupts, dispels, crowd control and taunt casts.
- **Economy**: copper, vendor trips, time with full bags.
- **Dungeons**: clears, LFG time, group time.
- **Deaths**: deaths, time as a ghost, spirit healer releases.

The server keeps the same six sections.

## The ritual

After every 10th level, `Collect/Pace.lua` fires `RITUAL_DUE` and `UI/Ritual.lua` opens three steps for the bracket you
just finished:

1. Rate PvE and PvP from 1 to 5 stars.
2. Vote like or dislike on up to three insights for your class. The insights come from the uploader's data.
3. Optionally write one insight of up to 280 characters.

Skipping is allowed. The ritual waits while you are in combat or inside an instance. `/elders ritual` opens it on demand
for testing.

## Ranks

The planned ranks are 14 named levels, from Initiate to Ancient. The rim colour changes by tier: bronze for 1-6, silver for
7-9, gold for 10-12, emerald for 13-14. The names and rims are in the site data (`site/src/data/elders.json` in
`../world-of-meta`).

The server works out a rank for each main character from weekly progress, compared with everyone else's. The rules are
kept on the server, so the addon does not carry them. The addon does not receive a rank yet: `/data` returns an empty
`ranks` object.

## Repository layout

| Path | Contents |
|---|---|
| `Elders/` | The addon: `Core.lua`, `Collect/`, `Data/`, `UI/`, `Media.lua` (generated), `Elders.toc`. |
| `Elders/Libs/MetaKit/` | A copy of `MetaKit/`, written by `tools/build.py`. Edit `MetaKit/`, not this copy. |
| `MetaKit/` | The shared library used by Elders and Bloodsports: addon framework, UI kit, codec, comms and saved data. |
| `tests/` | Lua tests, run with Lua 5.1 and a WoW stub (`wow_stub.lua`). |
| *(server)* | The API runs on Cloudflare Workers and D1 in a separate private repository. Public endpoint: `https://worldofmeta.win/api`. |
| `uploader/` | Meta Uploader: a Python tool that sends SavedVariables to the API and writes the `WorldOfMeta_Data` addon. See `uploader/README.md`. |
| `tools/` | `build.py` (build and install) and `art/` (art conversion). |
| `.github/workflows/` | Windows build of the uploader. Manual trigger only. |

## Tests

```bash
tests/run.sh            # every tests/test_*.lua, each in its own lua5.1 process
tests/run.sh collect    # only the files whose name contains "collect"
```

Needs `lua5.1` on the PATH. The full run passed on 2026-10-22. The uploader has its own tests, described in
`uploader/README.md`. The server has its own tests in its private repository.

## Art

- `tools/art/manifest.json` lists the textures. Each entry names a source PNG under `../../world-of-meta/assets/final/`, a
  size and a keying mode. `tools/art/convert.py` (needs Pillow) writes them as TGA files into `Elders/Media/`.
- `tools/build.py` runs the conversion, then rewrites `Elders/Media.lua` to list the textures that exist. A missing texture
  falls back to a stock WoW texture.
- `Elders/Media/*.tga` is gitignored. Art waits until it is approved and tested in game. `Media.lua` is committed.
- The source PNGs are in `world-of-meta/assets/final/`, which is also gitignored. Regenerating the art needs that folder.
- `--no-art` skips the conversion. `Media.lua` is still regenerated.

## Build and install

```bash
python3 tools/build.py                                                # MetaKit into Libs/, art, Media.lua for both addons
python3 tools/build.py --install "<WoW>/_retail_/Interface/AddOns"    # also copies Elders and Bloodsports
python3 tools/build.py --zip                                          # writes dist/Elders.zip and dist/Bloodsports.zip
```

- `--install` deletes the existing `Elders` and `Bloodsports` folders in that AddOns folder, then copies
  new ones. Use your game flavour's folder (`_retail_`, `_classic_` and so on).
- `build.py` builds Bloodsports from `../bloodsports`, so keep that repo next to this one.

In game, `/elders` toggles the panel. The other commands are `/elders link CODE`, `/elders sync` (reloads the UI so the
client writes SavedVariables), `/elders export` (copies your stats as a string), `/elders ritual` and `/elders debug`.
The client writes SavedVariables on logout, on `/reload` and on exit.

## Related

- `../bloodsports`: the Bloodsports addon. It uses the same MetaKit framework.
- `../world-of-meta`: the site, with the tier lists and the account pages.
