# Contributing

Elders, Bloodsports and MetaKit are MIT licensed (`LICENSE`). Bloodsports lives in the sibling repo `../bloodsports`
and the build expects the two repos side by side.

## Build, test, install

```bash
tests/run.sh                 # every tests/test_*.lua in its own lua5.1 process (needs lua5.1 on PATH)
tests/run.sh ext             # only files whose name contains "ext"
(cd ../bloodsports && tests/run.sh)    # the Bloodsports suite; it reuses this repo's tests/wow_stub.lua
luac5.1 -p MetaKit/*.lua MetaKit/UI/*.lua   # syntax check (luac -p if that is your name for it)

python3 tools/build.py --no-art        # copy MetaKit/ into both addons' Libs/, rewrite Media.lua
python3 tools/build.py                 # same, plus art conversion
python3 tools/build.py --install "<WoW>/_retail_/Interface/AddOns"   # copy the addons into the game
python3 tools/build.py --zip           # dist/<Addon>.zip
```

Tests run against a WoW stub, not the game. Say so in a pull request when a change needs a live check, and what you
checked in game.

## Rules

- **`Libs/` is generated.** `Elders/Libs/MetaKit/` and `../bloodsports/Bloodsports/Libs/MetaKit/` are copies written by
  `tools/build.py`. Edit `MetaKit/` and rebuild; never edit a `Libs/` file by hand. A new MetaKit file also needs a line
  in both TOCs, and a MetaKit change that other addons must see needs a `MINOR` bump in `MetaKit/MetaKit.lua`
  (the newest embedded copy wins).
- **Lua 5.1 only.** No `goto`, no integer division, no `//`, no bit operators. Retail APIs that may be missing get a guard.
- **The addon never moves gold.** Betting code computes, records and prints instructions; the human trades.
- A new module gets a test in `tests/` (or `../bloodsports/tests/`). Keep tests free of real time and game state; use the stub.
- Do not add a dependency on Ace or other libraries; the point of MetaKit is that each addon is self-contained.

## Contracts and docs

| Doc | Covers |
|---|---|
| `docs/ADDON_API.md` | public extension API (`MK.Ext`): markets, sections, rows, narrators, versioning |
| `docs/BETTING_CONTRACT.md` | Ring v2 data model, settlement maths, wire messages |
| `docs/BLOODSPORTS_V2_PLAN.md` | v2 decisions and architecture |
| `README.md` | repository layout, uploader, art pipeline |
| `examples/WomExampleMarket/` | smallest working extension addon |

Changing something listed as stable in `docs/ADDON_API.md` section 3 is a breaking change: bump `MK.Ext.VERSION`, update the
doc and `tests/test_ext.lua` in the same change.
