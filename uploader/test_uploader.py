"""Tests for meta_uploader: parser, outbox delta, Data.lua round-trip, dry-run and a mock-server end-to-end pass."""
import contextlib
import http.client
import io
import json
import os
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest import mock

import meta_uploader as mu

parse = mu.parse_lua


# ---- WoW-style SavedVariables writer (independent of the uploader's own serializer) -----------------------------------
def wow_dump(v, ind=1):
    pad = "\t" * ind
    if isinstance(v, dict):
        items = []
        for k, x in v.items():
            ks = f'["{k}"]' if isinstance(k, str) else f"[{k}]"
            items.append(f"{pad}{ks} = {wow_dump(x, ind + 1)},\n")
        return "{\n" + "".join(items) + "\t" * (ind - 1) + "}"
    if isinstance(v, list):
        items = [f"{pad}{wow_dump(x, ind + 1)}, -- [{i}]\n" for i, x in enumerate(v, 1)]
        return "{\n" + "".join(items) + "\t" * (ind - 1) + "}"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    return repr(v)


def sv_text(name, db):
    return f"{name} = {wow_dump(db)}\n"


def elders_db(install="a1b2c3d4e5f60718", rows=3, acked_rows=0):
    char = "Thrall-Forever"
    return {
        "dbVersion": 1, "installId": install,
        "config": {"ritual": True, "toasts": True, "panel": {}, "minimap": {"angle": 200, "hide": False}},
        "votes": {"ins_9": 1},
        "outbox": {"seq": rows, "rows": [
            {"seq": i, "t": 1760000000 + i, "kind": "levelup" if i % 2 else "rating", "char": char,
             "data": {"level": 10 * i, "sec": 612.5, "deaths": 1, "bracket": i, "pve": 4, "pvp": 3}}
            for i in range(1, rows + 1)]},
        "chars": {char: {
            "id": "f" * 32, "created": 1759990000, "name": "Thrall", "realm": "Forever", "ruleset": "classic",
            "class": "SHAMAN", "race": "Orc", "faction": "Horde", "level": 23, "lastSeen": 1760000100,
            "played": {"total": 9000, "level": 120, "at": 1760000050},
            "brackets": {1: {"sec": 3600, "xp": 123456, "kills": 400, "act": {"combat": 900, "idle": 12},
                             "mobDelta": [0, 1, 2, 3, 4, 5, 6, 0, 0, 0, 1], "fightHist": [1, 2, 3, 4, 5, 6],
                             "zones": {14: {"sec": 100, "xp": 5000, "copper": 99}}, "ritual": {"pve": 4, "pvp": 3},
                             "dungeons": {389: {"runs": 1, "clears": 1, "clearSec": 1200.25}}},
                         3: {"sec": 10, "xp": -5, "ritual": {}}},
            "levels": {9: {"sec": 600, "deaths": 0, "talents": "05032/00/0"}, 10: {"sec": 640, "deaths": 2}},
        }},
    }


def bloodsports_db(install="9988776655443322"):
    char = "Garrosh-Forever"
    duel = {"id": "ab12cd34ef56ab12", "t": 1760000500, "dur": 41.5, "venue": "honor_road", "venueKind": "club",
            "map": {"mapID": 1454, "x": 0.52, "y": 0.41, "zone": "Orgrimmar", "sub": "Valley of Honor"},
            "me": {"class": "WARRIOR", "race": "Orc", "level": 24, "hpEnd": 31, "minHp": 12},
            "opp": {"name": "Jaina", "realm": "Forever", "class": "MAGE", "race": "Human", "level": 24, "hpEnd": 0, "minHp": 0},
            "result": "win", "how": "knockout", "firstBlood": "opp", "comeback": True, "confirmed": "both",
            "group": {"raid": False, "size": 1}, "v": 1}
    return {
        "dbVersion": 1, "installId": install, "config": {"ring": {"currency": "gold"}}, "peers": {}, "referees": {},
        "outbox": {"seq": 3, "rows": [
            {"seq": 1, "t": 1760000400, "kind": "link", "char": char, "data": {"code": "A7K2M9", "charId": "e" * 32}},
            {"seq": 2, "t": 1760000500, "kind": "duel", "char": char, "data": duel},
            {"seq": 3, "t": 1760000510, "kind": "duel_confirm", "char": char, "data": {"id": duel["id"], "confirmed": "both"}},
        ]},
        "chars": {char: {
            "id": "e" * 32, "name": "Garrosh", "realm": "Forever", "class": "WARRIOR", "faction": "Horde", "level": 24,
            "duels": [duel], "streak": {"cur": 3, "best": 7, "venue": {"honor_road": 3}},
            "challenges": {"c1": {"id": "c1", "venue": "honor_road", "champion": "Varian", "t": 1760000000, "status": "open"}},
            "bets": [], "trades": [{"partner": "Jaina", "copper": 50000}],
        }},
    }


def make_wow(root: Path, flavors=("_classic_", "_retail_"), with_bs=True):
    for fl in flavors:
        sv = root / fl / "WTF" / "Account" / "ACCT1" / "SavedVariables"
        sv.mkdir(parents=True)
        (sv / "Elders.lua").write_text(sv_text("EldersDB", elders_db(install=f"a1b2c3d4{fl.strip('_')[:4].ljust(4, 'x')}0718")), "utf-8")
        if with_bs:
            (sv / "Bloodsports.lua").write_text(sv_text("BloodsportsDB", bloodsports_db(install=f"99887766{fl.strip('_')[:4].ljust(4, 'x')}3322")), "utf-8")
        (root / fl / "Interface" / "AddOns").mkdir(parents=True)
    return root


# ---- parser ------------------------------------------------------------------------------------------------------------
class ParserTests(unittest.TestCase):
    def test_scalars(self):
        d = parse('A = 1\nB = -5\nC = 1.5e3\nD = 0x1F\nE = "x"\nF = true\nG = false\nH = nil\nI = -0.25\nJ = .5\n')
        self.assertEqual(d, {"A": 1, "B": -5, "C": 1500, "D": 31, "E": "x", "F": True, "G": False, "I": -0.25, "J": 0.5})
        self.assertIsInstance(d["C"], int)

    def test_string_escapes(self):
        d = parse(r'S = "a\"b\\c\nd\te\065\10\0z\x41\'"' + "\n")
        self.assertEqual(d["S"], "a\"b\\c\nd\te" + "A\n" + "\x00z" + "A'")

    def test_decimal_escape_utf8(self):
        d = parse(r'S = "\195\169 caf\195\169"')
        self.assertEqual(d["S"], "\u00e9 caf\u00e9")
        self.assertEqual(parse('S = "Zoë 名"')["S"], "Zoë 名")

    def test_single_quote_long_string_continuation(self):
        d = parse("A = 'it\\'s'\nB = [[line1\nline2]]\nC = [==[a]]b]==]\nD = \"x\\\ny\"\n")
        self.assertEqual(d["A"], "it's")
        self.assertEqual(d["B"], "line1\nline2")
        self.assertEqual(d["C"], "a]]b")
        self.assertEqual(d["D"], "x\ny")

    def test_nested_tables_and_keys(self):
        d = parse('T = { ["a"] = { 1, 2, { x = 3 } }, [5] = "five", [-2] = 1, name = "n", [ "with space" ] = 1; 9 }\n')
        t = d["T"]
        self.assertEqual(t["a"], {1: 1, 2: 2, 3: {"x": 3}})
        self.assertEqual((t[5], t[-2], t["name"], t["with space"], t[1]), ("five", 1, "n", 1, 9))

    def test_nil_values_and_positions(self):
        t = parse('T = { 1, nil, 3, ["k"] = nil }\n')["T"]
        self.assertEqual(t, {1: 1, 3: 3})
        self.assertEqual(mu.seq(t), [1, 3])

    def test_comments(self):
        src = '-- header\nA = { -- c\n 1, --[[ block\n comment ]] 2, --[==[ x ]] ]==] 3, -- [4]\n}\n--[[ trailing ]]\nB = 2 -- end\n'
        d = parse(src)
        self.assertEqual(d["A"], {1: 1, 2: 2, 3: 3})
        self.assertEqual(d["B"], 2)

    def test_array_comment_form_like_wow(self):
        d = parse('X = {\n\t{\n\t\t["seq"] = 1,\n\t}, -- [1]\n\t{\n\t\t["seq"] = 2,\n\t}, -- [2]\n}\n')
        self.assertEqual([r["seq"] for r in mu.seq(d["X"])], [1, 2])

    def test_float_integral_to_int_and_inf(self):
        d = parse("A = 3.0\nB = 1.#INF\nC = -1.#IND\nD = inf\nE = 2.50\n")
        self.assertEqual(d["A"], 3)
        self.assertIsNone(d.get("B"))
        self.assertEqual(d["E"], 2.5)

    def test_bom_and_empty(self):
        self.assertEqual(parse("\ufeffA = {}\n"), {"A": {}})
        self.assertEqual(parse(""), {})

    def test_truncated_inputs_raise(self):
        full = sv_text("EldersDB", elders_db())
        for cut in (len(full) // 2, len(full) - 3, len(full) // 3, 40):
            with self.assertRaises(mu.LuaParseError, msg=f"cut={cut}"):
                parse(full[:cut])
        for bad in ('A = "abc', "A = { 1, 2", "A = [[x", "A = --[[ open\n", "A = {1 2}", "A = ", "A = {[1] 2}"):
            with self.assertRaises(mu.LuaParseError, msg=bad):
                parse(bad)

    def test_deep_nesting_guard(self):
        with self.assertRaises(mu.LuaParseError):
            parse("A = " + "{" * 500 + "}" * 500)

    def test_realistic_files(self):
        d = parse(sv_text("EldersDB", elders_db()))["EldersDB"]
        self.assertEqual(d["installId"], "a1b2c3d4e5f60718")
        self.assertEqual(len(mu.seq(d["outbox"]["rows"])), 3)
        self.assertEqual(d["chars"]["Thrall-Forever"]["brackets"][1]["xp"], 123456)
        self.assertEqual(d["chars"]["Thrall-Forever"]["brackets"][3]["xp"], -5)

    def test_read_retries_half_written_file(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "Elders.lua"
            full = sv_text("EldersDB", elders_db())
            p.write_text(full[:200], "utf-8")

            def finish():
                import time
                time.sleep(0.25)
                p.write_text(full, "utf-8")
            t = threading.Thread(target=finish)
            t.start()
            data, _ = mu.read_lua_file(p, retries=10, delay=0.1)
            t.join()
            self.assertIn("EldersDB", data)
            p.write_text(full[:100], "utf-8")
            with self.assertRaises(mu.LuaParseError):
                mu.read_lua_file(p, retries=2, delay=0.01)


# ---- outbox / payloads -------------------------------------------------------------------------------------------------
class PayloadTests(unittest.TestCase):
    def test_outbox_delta(self):
        db = parse(sv_text("EldersDB", elders_db(rows=5)))["EldersDB"]
        self.assertEqual([r["seq"] for r in mu.outbox_delta(db, 0)], [1, 2, 3, 4, 5])
        self.assertEqual([r["seq"] for r in mu.outbox_delta(db, 3)], [4, 5])
        self.assertEqual(mu.outbox_delta(db, 5), [])
        row = mu.outbox_delta(db, 4)[0]
        self.assertEqual(set(row), {"seq", "t", "kind", "char", "data"})
        self.assertEqual(row["data"]["bracket"], 5)

    def test_outbox_delta_ignores_garbage_and_dupes(self):
        db = {"outbox": {"rows": {1: {"seq": 2, "kind": "x"}, 2: {"seq": 2, "kind": "y"}, 3: "junk", 4: {"seq": "5", "kind": "z"},
                                  5: {"kind": "k"}, 6: {"seq": 7}}}}
        self.assertEqual([(r["seq"], r["kind"]) for r in mu.outbox_delta(db, 0)], [(2, "y")])
        self.assertEqual(mu.outbox_delta({}, 0), [])

    def test_batches_and_state_on_last(self):
        db = parse(sv_text("EldersDB", elders_db(rows=5)))["EldersDB"]
        ps = mu.build_payloads("Elders", db, 0, batch=2)
        self.assertEqual([len(p["rows"]) for p in ps], [2, 2, 1])
        self.assertEqual(["state" in p for p in ps], [False, False, True])
        self.assertEqual(ps[0]["install"], "a1b2c3d4e5f60718")
        # nothing new and state unchanged -> nothing to send
        self.assertEqual(mu.build_payloads("Elders", db, 5, include_state=False), [])
        # nothing new but state wanted -> state only
        only = mu.build_payloads("Elders", db, 5)
        self.assertEqual(len(only), 1)
        self.assertEqual(only[0]["rows"], [])

    def test_elders_state_shape(self):
        db = parse(sv_text("EldersDB", elders_db()))["EldersDB"]
        st = mu.build_state("Elders", db)["chars"]["Thrall-Forever"]
        self.assertEqual(st["class"], "SHAMAN")
        self.assertEqual(st["brackets"]["1"]["mobDelta"], [0, 1, 2, 3, 4, 5, 6, 0, 0, 0, 1])
        self.assertEqual(st["brackets"]["1"]["zones"]["14"]["xp"], 5000)
        self.assertEqual(st["levels"]["10"]["deaths"], 2)
        json.dumps(st)

    def test_bloodsports_state_excludes_duels(self):
        db = parse(sv_text("BloodsportsDB", bloodsports_db()))["BloodsportsDB"]
        st = mu.build_state("Bloodsports", db)["chars"]["Garrosh-Forever"]
        for k in ("duels", "trades", "bets"):
            self.assertNotIn(k, st)
        self.assertEqual(st["streak"]["best"], 7)
        self.assertEqual(st["streak"]["venue"], {"honor_road": 3})
        self.assertEqual(st["challenges"]["c1"]["status"], "open")
        ps = mu.build_payloads("Bloodsports", db, 1)
        self.assertEqual([r["kind"] for r in ps[0]["rows"]], ["duel", "duel_confirm"])

    def test_missing_install_id(self):
        self.assertEqual(mu.build_payloads("Elders", {"outbox": {"rows": {}}}, 0), [])


# ---- Data.lua ----------------------------------------------------------------------------------------------------------
class DataLuaTests(unittest.TestCase):
    DATA = {
        "generatedAt": 1760001000,
        "ranks": {"f" * 32: 3},
        "elders": {"insights": {"SHAMAN": [{"id": "i1", "text": 'Quote " and \\ and \n newline\ttab \x01', "author": "Thrall", "votes": 7}]}},
        "bloodsports": {
            "champions": {"honor_road": {"Horde": {"WARRIOR": {"name": "Garrosh", "streak": 11, "since": 1759000000}}}},
            "badges": {"Garrosh": [{"venue": "honor_road"}]},
            "challenges": [{"id": "c1", "t": 1.5, "deadline": 1760600000}],
            "referees": {"Bob": {"rating": 4.5, "cap": 500000}},
        },
        "acked": {"Elders": {"a1b2c3d4e5f60718": 12}, "Bloodsports": {}},
        "flag": True, "neg": -3, "frac": 0.1, "unicode": "Zoë 名", "end": "ends with 1",
        "keyword": {"end": 1, "1abc": 2, "with space": 3, "if": 4},
    }

    def test_round_trip(self):
        lua = mu.build_data_lua(self.DATA, {})
        got = mu.jsonable(parse(lua)["WorldOfMetaData"])
        want = json.loads(json.dumps(self.DATA))
        self.assertEqual(got, want)

    def test_deterministic(self):
        a = mu.build_data_lua(self.DATA, {})
        shuffled = dict(reversed(list(self.DATA.items())))
        self.assertEqual(a, mu.build_data_lua(shuffled, {}))

    def test_acked_merge_takes_max(self):
        lua = mu.build_data_lua({"acked": {"Elders": {"i": 5}}}, {"Elders": {"i": 9, "j": 1}, "Bloodsports": {"k": 2}})
        acked = parse(lua)["WorldOfMetaData"]["acked"]
        self.assertEqual(acked, {"Elders": {"i": 9, "j": 1}, "Bloodsports": {"k": 2}})

    def test_generated_at_defaults(self):
        lua = mu.build_data_lua({}, {}, now=1234)
        self.assertEqual(parse(lua)["WorldOfMetaData"]["generatedAt"], 1234)

    def test_string_escapes_are_lua_safe(self):
        s = "a\x00" + "1b\x7f\r\n\\\"'"
        self.assertEqual(parse("X = " + mu.lua_string(s))["X"], s)
        self.assertNotIn("\n", mu.lua_string("a\nb"))

    def test_int_keys_and_nesting(self):
        v = {"t": {5: "five", 7: {1: "a"}, "x": [1, [2, 3], {}]}}
        out = parse("X = " + mu.lua_value(v))["X"]
        self.assertEqual(out["t"][5], "five")
        self.assertEqual(out["t"][7], {1: "a"})
        self.assertEqual(out["t"]["x"], {1: 1, 2: {1: 2, 2: 3}, 3: {}})

    def test_write_addon_files(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "_classic_"
            root.mkdir()
            self.assertTrue(mu.write_data_addon(root, self.DATA, {}))
            d = root / "Interface" / "AddOns" / "WorldOfMeta_Data"
            toc = (d / "WorldOfMeta_Data.toc").read_text()
            self.assertIn("## Interface: 16001, 120100", toc)
            self.assertTrue(toc.rstrip().endswith("Data.lua"))
            self.assertIn("WorldOfMetaData", (d / "Data.lua").read_text())
            self.assertFalse(mu.write_data_addon(root, self.DATA, {}))  # unchanged -> untouched
            changed = dict(self.DATA, generatedAt=1760009999)
            self.assertFalse(mu.write_data_addon(root, changed, {}))   # only the timestamp differs
            self.assertTrue(mu.write_data_addon(root, dict(self.DATA, ranks={}), {}))


# ---- discovery ---------------------------------------------------------------------------------------------------------
class DiscoveryTests(unittest.TestCase):
    def test_discover_all_flavors_and_accounts(self):
        with tempfile.TemporaryDirectory() as td:
            root = make_wow(Path(td))
            sv2 = root / "_retail_" / "WTF" / "Account" / "ACCT2" / "SavedVariables"
            sv2.mkdir(parents=True)
            (sv2 / "Elders.lua").write_text("EldersDB = {}", "utf-8")
            found = mu.discover(root)
            self.assertEqual(len(found), 5)
            self.assertEqual({f.addon for f in found}, {"Elders", "Bloodsports"})
            self.assertTrue(mu.looks_like_wow(root))
            self.assertFalse(mu.looks_like_wow(Path(td) / "nope"))
            self.assertEqual(len(mu.discover(root / "_classic_")), 2)  # flavor dir itself also works

    def test_install_path_normalisation(self):
        self.assertEqual(mu._normalize_install_path("C:/Games/World of Warcraft/_retail_/"), Path("C:/Games/World of Warcraft"))


# ---- end to end --------------------------------------------------------------------------------------------------------
class Mock(BaseHTTPRequestHandler):
    log: list = []
    seen: dict = {}
    fail_ingest = 0

    def _send(self, code, obj):
        raw = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])) or b"{}")
        if self.path == "/link":
            Mock.log.append(("link", body))
            return self._send(200, {"token": "tok123"}) if body.get("code") == "A7K2M9" else self._send(400, {"error": "bad code"})
        if self.headers.get("Authorization") != "Bearer tok123":
            return self._send(401, {"error": "unauthorized"})
        if Mock.fail_ingest:
            Mock.fail_ingest -= 1
            return self._send(503, {"error": "busy"})
        Mock.log.append(("ingest", body))
        key = (body["install"], body["addon"])
        top = max([r["seq"] for r in body["rows"]], default=Mock.seen.get(key, 0))
        Mock.seen[key] = max(Mock.seen.get(key, 0), top)
        self._send(200, {"ok": True, "acked": Mock.seen[key]})

    def do_GET(self):
        if self.headers.get("Authorization") != "Bearer tok123":
            return self._send(401, {"error": "unauthorized"})
        Mock.log.append(("data", self.path))
        acked = {}
        for (inst, addon), n in Mock.seen.items():
            acked.setdefault(addon, {})[inst] = n
        self._send(200, {"generatedAt": 1760002000, "acked": acked, "bloodsports": {"champions": {}}})

    def log_message(self, *a):
        pass


class EndToEndTests(unittest.TestCase):
    def setUp(self):
        Mock.log, Mock.seen, Mock.fail_ingest = [], {}, 0
        self.srv = HTTPServer(("127.0.0.1", 0), Mock)
        self.url = f"http://127.0.0.1:{self.srv.server_port}"
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.td = tempfile.TemporaryDirectory()
        self.root = make_wow(Path(self.td.name) / "wow", flavors=("_classic_",))
        self.cfgp = Path(self.td.name) / "cfg" / "config.json"

    def tearDown(self):
        self.srv.shutdown()
        self.td.cleanup()

    def run_main(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = mu.main(list(args) + ["--config", str(self.cfgp)])
        return rc, out.getvalue()

    def test_dry_run_prints_payloads_and_touches_nothing(self):
        with mock.patch("urllib.request.urlopen", side_effect=AssertionError("network used in dry run")):
            rc, out = self.run_main("once", "--dry-run", "--wow-dir", str(self.root), "--api", self.url)
        self.assertEqual(rc, 0)
        self.assertIn("DRY-RUN POST", out)
        self.assertFalse(self.cfgp.exists())
        self.assertFalse((self.root / "_classic_" / "Interface" / "AddOns" / "WorldOfMeta_Data").exists())
        blobs = [json.loads(b) for b in out.split("DRY-RUN POST")[1:] for b in [b[b.index("\n") + 1:].split("\nDRY-RUN")[0]]]
        by_addon = {b["addon"]: b for b in blobs}
        self.assertEqual(set(by_addon), {"Elders", "Bloodsports"})
        self.assertEqual(len(by_addon["Elders"]["rows"]), 3)
        self.assertEqual([r["kind"] for r in by_addon["Bloodsports"]["rows"]], ["link", "duel", "duel_confirm"])
        self.assertNotIn("duels", by_addon["Bloodsports"]["state"]["chars"]["Garrosh-Forever"])
        self.assertEqual(by_addon["Elders"]["state"]["chars"]["Thrall-Forever"]["brackets"]["1"]["xp"], 123456)

    def test_link_then_sync_and_ack(self):
        rc, _ = self.run_main("link", "a7k2m9", "--api", self.url)
        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(self.cfgp.read_text())["token"], "tok123")
        rc, _ = self.run_main("link", "WRONG1", "--api", self.url)
        self.assertEqual(rc, 1)
        rc, _ = self.run_main("once", "--wow-dir", str(self.root))
        self.assertEqual(rc, 0)
        posted = [b for k, b in Mock.log if k == "ingest"]
        self.assertEqual({(b["addon"], len(b["rows"])) for b in posted}, {("Elders", 3), ("Bloodsports", 3)})
        cfg = json.loads(self.cfgp.read_text())
        self.assertEqual(sorted(sum((list(v.values()) for v in cfg["acked"].values()), [])), [3, 3])
        # Data addon written, carries acked
        lua = (self.root / "_classic_" / "Interface" / "AddOns" / "WorldOfMeta_Data" / "Data.lua").read_text()
        wom = parse(lua)["WorldOfMetaData"]
        self.assertEqual(wom["generatedAt"], 1760002000)
        self.assertEqual(sorted(wom["acked"]), ["Bloodsports", "Elders"])
        # second pass: nothing new -> no more rows posted, and unchanged state is still resent only once per process
        n = len(posted)
        self.run_main("once", "--wow-dir", str(self.root))
        again = [b for k, b in Mock.log if k == "ingest"][n:]
        self.assertTrue(all(b["rows"] == [] for b in again))

    def test_retry_when_server_fails_then_resume(self):
        self.run_main("link", "A7K2M9", "--api", self.url)
        Mock.fail_ingest = 100
        rc, _ = self.run_main("once", "--wow-dir", str(self.root))
        self.assertEqual(rc, 1)
        self.assertEqual(json.loads(self.cfgp.read_text())["acked"], {})
        Mock.fail_ingest = 0
        rc, _ = self.run_main("once", "--wow-dir", str(self.root))
        self.assertEqual(rc, 0)
        self.assertEqual(sum(1 for k, _ in Mock.log if k == "ingest"), 2)

    def test_auto_link_from_ingame_code(self):
        rc, _ = self.run_main("once", "--wow-dir", str(self.root), "--api", self.url)
        self.assertEqual(rc, 0)
        self.assertEqual(Mock.log[0], ("link", {"code": "A7K2M9", "client": mu.USER_AGENT}))
        self.assertEqual(json.loads(self.cfgp.read_text())["token"], "tok123")

    def test_unlinked_without_code_does_not_post(self):
        for p in self.root.rglob("Bloodsports.lua"):
            p.unlink()
        rc, _ = self.run_main("once", "--wow-dir", str(self.root), "--api", self.url)
        self.assertEqual(rc, 1)  # elders has no link row -> cannot upload
        self.assertFalse([1 for k, _ in Mock.log if k == "ingest"])

    def test_missing_wow_dir(self):
        rc, _ = self.run_main("once", "--wow-dir", str(Path(self.td.name) / "nothing"))
        self.assertEqual(rc, 2)


class AutoLinkTests(unittest.TestCase):
    """auto_link retry rules: a 4xx code is never sent again; network/5xx codes are retried; no token in output."""

    SECRET = "SECRET-TOKEN-XYZ"

    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.dir = Path(self.td.name)
        self.cfg = mu.Config(self.dir / "cfg" / "config.json")
        self.up = mu.Uploader(self.cfg)

    def tearDown(self):
        self.td.cleanup()

    @staticmethod
    def db(*codes):
        return {"outbox": {"rows": [{"seq": i, "kind": "link", "data": {"code": c, "charId": "f" * 32}}
                                    for i, c in enumerate(codes, 1)]}}

    def test_4xx_code_is_not_retried(self):
        calls = []

        def fake(method, url, body=None, token="", timeout=20.0):
            calls.append(body["code"])
            raise mu.ApiError(400, "code invalid, used or expired")

        with mock.patch.object(mu, "http_json", side_effect=fake):
            with contextlib.redirect_stdout(io.StringIO()):
                self.up.auto_link(self.db("ABCD2345"))
                self.up.auto_link(self.db("ABCD2345"))
                self.up.auto_link(self.db("ABCD2345"))
        self.assertEqual(calls, ["ABCD2345"])
        self.assertEqual(self.cfg["token"], "")

    def test_newly_written_code_is_tried_after_a_4xx(self):
        seen = []

        def fake(method, url, body=None, token="", timeout=20.0):
            seen.append(body["code"])
            if body["code"] == "OLDCODE1":
                raise mu.ApiError(400, "code invalid, used or expired")
            return {"token": self.SECRET}

        with mock.patch.object(mu, "http_json", side_effect=fake):
            with contextlib.redirect_stdout(io.StringIO()):
                self.up.auto_link(self.db("OLDCODE1"))
                self.up.auto_link(self.db("OLDCODE1", "NEWCODE2"))
        self.assertEqual(seen, ["OLDCODE1", "NEWCODE2"])
        self.assertEqual(self.cfg["token"], self.SECRET)

    def test_network_failure_is_retried_later(self):
        seen = []

        def fake(method, url, body=None, token="", timeout=20.0):
            seen.append(body["code"])
            if len(seen) == 1:
                raise mu.NetworkError("connection refused")
            return {"token": self.SECRET}

        with mock.patch.object(mu, "http_json", side_effect=fake):
            with contextlib.redirect_stdout(io.StringIO()):
                self.up.auto_link(self.db("ABCD2345"))
                self.assertEqual(self.cfg["token"], "")
                self.assertNotIn("ABCD2345", self.up.rejected_codes)
                self.up.auto_link(self.db("ABCD2345"))
        self.assertEqual(seen, ["ABCD2345", "ABCD2345"])
        self.assertEqual(self.cfg["token"], self.SECRET)

    def test_5xx_is_retried_and_stops_the_pass(self):
        seen = []

        def fake(method, url, body=None, token="", timeout=20.0):
            seen.append(body["code"])
            raise mu.ApiError(503, "busy")

        with mock.patch.object(mu, "http_json", side_effect=fake):
            with contextlib.redirect_stdout(io.StringIO()):
                self.up.auto_link(self.db("OLDCODE1", "NEWCODE2"))
        self.assertEqual(seen, ["NEWCODE2"])  # newest tried, then the pass stops; OLDCODE1 is not given up on
        self.assertEqual(self.up.rejected_codes, set())

    def test_status_line_never_shows_the_token(self):
        def fake(method, url, body=None, token="", timeout=20.0):
            return {"token": self.SECRET}

        out = io.StringIO()
        with mock.patch.object(mu, "http_json", side_effect=fake), contextlib.redirect_stdout(out):
            self.up.auto_link(self.db("ABCD2345"))
        self.assertIn("linked to World of Meta", out.getvalue())
        self.assertNotIn(self.SECRET, out.getvalue())
        # the token goes only into the config file, which is the only file the uploader writes for it
        self.assertEqual(json.loads(self.cfg.path.read_text())["token"], self.SECRET)
        self.assertEqual(sorted(p.name for p in self.cfg.path.parent.iterdir()), ["config.json"])
        self.assertEqual(self.cfg.path.stat().st_mode & 0o777, 0o600)

    def test_unreachable_api_does_not_crash_a_watch_pass(self):
        root = make_wow(self.dir / "wow", flavors=("_classic_",))
        self.cfg["api"] = "http://127.0.0.1:9"
        self.cfg["token"] = ""
        self.cfg.data["mode"] = "daemon"
        with mock.patch.object(mu, "http_json", side_effect=mu.NetworkError("unreachable")):
            with contextlib.redirect_stdout(io.StringIO()) as out:
                ok = self.up.cycle(root, force=True)
        self.assertFalse(ok)
        self.assertIn("will retry", out.getvalue())

    def test_http_client_errors_map_to_network_error(self):
        with mock.patch("urllib.request.urlopen", side_effect=http.client.IncompleteRead(b"")):
            with self.assertRaises(mu.NetworkError):
                mu.http_json("POST", "http://127.0.0.1:9/link", {"code": "X"})



class RedirectHandler(BaseHTTPRequestHandler):
    """/redirect/* answers 302 to /landing (what a moved or hijacked address would do); /landing records what arrives."""
    seen: list = []

    def _answer(self, method):
        n = int(self.headers.get("Content-Length") or 0)
        if n:
            self.rfile.read(n)
        if self.path.startswith("/redirect/"):
            self.send_response(302)
            self.send_header("Location", "/landing")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        RedirectHandler.seen.append((method, self.path, self.headers.get("Authorization")))
        raw = b'{"ok": true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        self._answer("POST")

    def do_GET(self):
        self._answer("GET")

    def log_message(self, *a):
        pass


class RedirectTests(unittest.TestCase):
    """urllib would follow a 302 and resend a POST as GET with the bearer token. The uploader refuses every redirect."""

    TOKEN = "wom_redirect_test_token_0123456789"

    def setUp(self):
        RedirectHandler.seen = []
        self.srv = HTTPServer(("127.0.0.1", 0), RedirectHandler)
        self.base = f"http://127.0.0.1:{self.srv.server_port}"
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()

    def tearDown(self):
        self.srv.shutdown()
        self.srv.server_close()

    def test_redirects_are_refused_for_ingest_link_and_data(self):
        cases = [
            ("POST", "/redirect/ingest", {"install": "x", "rows": []}),
            ("POST", "/redirect/link", {"code": "ABCD2345"}),
            ("GET", "/redirect/data?install=x", None),
        ]
        for method, path, body in cases:
            with self.subTest(path=path):
                with self.assertRaises(mu.ApiError) as cm:
                    mu.http_json(method, self.base + path, body, self.TOKEN)
                self.assertEqual(cm.exception.status, 302)
        # the token never reached the redirect target, and no follow-up request was made
        self.assertEqual(RedirectHandler.seen, [])

    def test_a_direct_answer_still_works_and_carries_the_token_once(self):
        out = mu.http_json("POST", self.base + "/landing", {"rows": []}, self.TOKEN)
        self.assertEqual(out, {"ok": True})
        self.assertEqual(RedirectHandler.seen, [("POST", "/landing", "Bearer " + self.TOKEN)])


class TokenMessageTests(unittest.TestCase):
    """A 401 from /ingest or /data: the revoked-or-expired message, once per token, and again after a new link."""

    MSG = "token revoked or expired: run the link flow again"

    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.root = make_wow(Path(self.td.name) / "wow")   # two flavors: two files, same token
        self.cfg = mu.Config(Path(self.td.name) / "cfg" / "config.json")
        self.cfg["token"] = "wom_dead_token_0123456789abcdef"
        self.up = mu.Uploader(self.cfg)

    def tearDown(self):
        self.td.cleanup()

    @staticmethod
    def dead(method, url, body=None, token="", timeout=20.0):
        raise mu.ApiError(401, "invalid, expired or revoked token")

    def run_cycles(self, n, fake=None):
        out = io.StringIO()
        with mock.patch.object(mu, "http_json", side_effect=fake or self.dead), contextlib.redirect_stdout(out):
            for _ in range(n):
                self.up.cycle(self.root, force=True)
        return out.getvalue()

    def test_a_revoked_token_is_reported_once_across_files_and_passes(self):
        text = self.run_cycles(3)
        self.assertEqual(text.count(self.MSG), 1)
        self.assertNotIn("wom_dead_token", text)   # the token is never logged

    def test_a_new_link_resets_the_message(self):
        self.run_cycles(2)
        def linked(method, url, body=None, token="", timeout=20.0):
            return {"token": "wom_fresh_token_0123456789abcdef"}
        with mock.patch.object(mu, "http_json", side_effect=linked), contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(self.up.link("ABCD2345"))
        text = self.run_cycles(2)
        self.assertEqual(text.count(self.MSG), 1)

    def test_a_forbidden_install_is_not_reported_as_an_expired_token(self):
        def forbidden(method, url, body=None, token="", timeout=20.0):
            raise mu.ApiError(403, "install belongs to another account")
        text = self.run_cycles(1, forbidden)
        self.assertNotIn(self.MSG, text)
        self.assertIn("install belongs to another account", text)

    def test_a_data_download_401_gives_the_same_message(self):
        def data_only(method, url, body=None, token="", timeout=20.0):
            if method == "GET":
                raise mu.ApiError(401, "invalid, expired or revoked token")
            return {"ok": True, "acked": {}}
        text = self.run_cycles(2, data_only)
        self.assertEqual(text.count(self.MSG), 1)




if __name__ == "__main__":
    unittest.main()
