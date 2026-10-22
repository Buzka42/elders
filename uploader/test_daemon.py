"""Tests for the daemon, configure, autostart, single-instance and tray-fallback parts of meta_uploader."""
import contextlib
import io
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

import meta_uploader as mu


def run_main(cfgp, *args, stdin=None):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = mu.main(list(args) + ["--config", str(cfgp)])
    return rc, out.getvalue()


class ConfigureTests(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.addCleanup(self.td.cleanup)
        self.cfgp = Path(self.td.name) / "cfg" / "config.json"

    def test_configure_stores_mode_and_autostart(self):
        with mock.patch.object(mu, "is_windows", return_value=True), \
                mock.patch.object(mu, "run_key_write") as w:
            rc, out = run_main(self.cfgp, "configure", "--mode", "script", "--autostart", "on")
        self.assertEqual(rc, 0)
        data = json.loads(self.cfgp.read_text())
        self.assertEqual((data["mode"], data["autostart"]), ("script", "on"))
        w.assert_called_once_with(mu.autostart_command())
        self.assertIn("mode=script", out)

    def test_configure_defaults_and_no_autostart_flag(self):
        rc, _ = run_main(self.cfgp, "configure", "--mode", "daemon")
        data = json.loads(self.cfgp.read_text())
        self.assertEqual((rc, data["mode"], data["autostart"]), (0, "daemon", "off"))

    def test_configure_dry_run_writes_nothing(self):
        with mock.patch.object(mu, "is_windows", return_value=True), \
                mock.patch.object(mu, "run_key_write", side_effect=AssertionError("registry written")):
            rc, out = run_main(self.cfgp, "configure", "--mode", "script", "--autostart", "on", "--dry-run")
        self.assertEqual(rc, 0)
        self.assertIn("DRY-RUN", out)
        self.assertFalse(self.cfgp.exists())

    def test_configure_autostart_refused_off_windows(self):
        with mock.patch.object(mu, "is_windows", return_value=False):
            rc, _ = run_main(self.cfgp, "configure", "--mode", "daemon", "--autostart", "on")
        self.assertEqual(rc, 3)
        self.assertEqual(json.loads(self.cfgp.read_text())["autostart"], "off")


class AutostartTests(unittest.TestCase):
    def test_command_frozen(self):
        with mock.patch.object(sys, "frozen", True, create=True), \
                mock.patch.object(sys, "executable", r"C:\Apps\Meta\MetaUploader.exe"):
            self.assertEqual(mu.autostart_command(), r'"C:\Apps\Meta\MetaUploaderTray.exe" daemon --tray')

    def test_command_source_uses_pythonw(self):
        with mock.patch.object(sys, "executable", r"C:\Python312\python.exe"):
            cmd = mu.autostart_command()
        self.assertEqual(cmd, f'"C:\\Python312\\pythonw.exe" "{Path(mu.__file__).resolve()}" daemon --tray')

    def test_on_and_off_write_registry_value(self):
        with mock.patch.object(mu, "is_windows", return_value=True), mock.patch.object(mu, "run_key_write") as w:
            self.assertEqual(mu.cmd_autostart("on"), 0)
            self.assertEqual(mu.cmd_autostart("off"), 0)
        self.assertEqual([c.args[0] for c in w.call_args_list], [mu.autostart_command(), None])

    def test_run_key_write_with_fake_winreg(self):
        fake = mock.MagicMock()
        key = fake.OpenKey.return_value.__enter__.return_value
        with mock.patch.dict(sys.modules, {"winreg": fake}):
            mu.run_key_write("cmd")
            mu.run_key_write(None)
        fake.SetValueEx.assert_called_once_with(key, "WorldOfMetaUploader", 0, fake.REG_SZ, "cmd")
        fake.DeleteValue.assert_called_once_with(key, "WorldOfMetaUploader")
        self.assertEqual(fake.OpenKey.call_args.args[:2], (fake.HKEY_CURRENT_USER, mu.RUN_KEY))

    def test_refused_off_windows(self):
        with mock.patch.object(mu, "is_windows", return_value=False), \
                mock.patch.object(mu, "run_key_write", side_effect=AssertionError("no registry")):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rc = mu.cmd_autostart("on")
        self.assertEqual(rc, 3)
        self.assertIn("autostart is only supported on Windows", out.getvalue())


@unittest.skipIf(sys.platform == "win32", "lock-file fallback is the non-Windows path")
class SingleInstanceTests(unittest.TestCase):
    def test_second_holder_refused_until_release(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "sub" / "uploader.lock"
            a, b = mu.SingleInstance(path), mu.SingleInstance(path)
            self.assertTrue(a.acquire())
            self.assertFalse(b.acquire())
            self.assertTrue(mu.instance_running(path))
            a.release()
            self.assertTrue(b.acquire())
            b.release()
            self.assertFalse(mu.instance_running(path))

    def test_running_check_does_not_create_files(self):
        with tempfile.TemporaryDirectory() as td:
            self.assertFalse(mu.instance_running(Path(td) / "none" / "uploader.lock"))
            self.assertFalse((Path(td) / "none").exists())

    def test_daemon_exits_zero_when_another_instance_runs(self):
        with tempfile.TemporaryDirectory() as td:
            cfgp = Path(td) / "config.json"
            held = mu.SingleInstance(cfgp.with_name("uploader.lock"))
            self.assertTrue(held.acquire())
            self.addCleanup(held.release)
            with mock.patch.object(mu.Uploader, "cycle", side_effect=AssertionError("synced")):
                rc, _ = run_main(cfgp, "daemon", "--wow-dir", td)
            self.assertEqual(rc, 0)


class LoopTests(unittest.TestCase):
    def test_stops_on_stop_event(self):
        stop, wake, calls = threading.Event(), threading.Event(), []

        def cycle():
            calls.append(1)
            if len(calls) == 3:
                stop.set()
            return True

        mu.daemon_loop(cycle, 0.0, stop, wake)
        self.assertEqual(len(calls), 3)

    def test_max_cycles_and_error_survival(self):
        n = []

        def cycle():
            n.append(1)
            raise RuntimeError("boom")

        seen = []
        with contextlib.redirect_stdout(io.StringIO()):
            mu.daemon_loop(cycle, 0.0, threading.Event(), threading.Event(), max_cycles=2, on_cycle=seen.append)
        self.assertEqual((len(n), seen), (2, [False, False]))

    def test_wake_cuts_the_wait(self):
        stop, wake, calls = threading.Event(), threading.Event(), []

        def cycle():
            calls.append(1)
            if len(calls) >= 2:
                stop.set()
            wake.set()
            return True

        mu.daemon_loop(cycle, 60.0, stop, wake)  # would hang for 60 s if wake did not work
        self.assertEqual(len(calls), 2)

    def test_state_text(self):
        s = mu.DaemonState()
        self.assertEqual(s.text(), "Last sync: never")
        s.record(False)
        self.assertEqual(s.text(), "Last sync: never (retrying)")
        s.record(True)
        self.assertRegex(s.text(), r"Last sync: \d\d:\d\d:\d\d")


class TrayFallbackTests(unittest.TestCase):
    def test_tray_import_blocked_falls_back_to_console_loop(self):
        up = mock.Mock(api="http://x")
        up.cfg = {"site": None}
        up.cycle.return_value = True
        out = io.StringIO()
        with mock.patch.dict(sys.modules, {"pystray": None}), contextlib.redirect_stdout(out):
            mu.run_daemon(up, Path("."), 0.0, tray=True, max_cycles=2)
        self.assertEqual(up.cycle.call_count, 2)
        self.assertIn("tray unavailable", out.getvalue())

    def test_pillow_import_blocked_falls_back(self):
        up = mock.Mock(api="http://x")
        up.cfg = {"site": None}
        fake = mock.MagicMock()
        with mock.patch.dict(sys.modules, {"pystray": fake, "PIL": None}), contextlib.redirect_stdout(io.StringIO()):
            mu.run_daemon(up, Path("."), 0.0, tray=True, max_cycles=1)
        self.assertEqual(up.cycle.call_count, 1)
        fake.Icon.assert_not_called()


class LinkPromptTests(unittest.TestCase):
    def test_link_without_code_prompts(self):
        with tempfile.TemporaryDirectory() as td:
            cfgp = Path(td) / "config.json"
            with mock.patch("builtins.input", return_value=" a7k 2m9 ") as inp, \
                    mock.patch.object(mu.Uploader, "link", return_value=True) as link:
                rc, _ = run_main(cfgp, "link")
        self.assertEqual(rc, 0)
        inp.assert_called_once_with("Link code from the site: ")
        link.assert_called_once_with(" a7k 2m9 ")


class LogTests(unittest.TestCase):
    def test_log_writes_to_rotating_file(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "uploader.log"
            mu.open_file_log(path)
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    mu.log("hello file")
            finally:
                mu.close_file_log()
            self.assertIn("hello file", path.read_text())


if __name__ == "__main__":
    unittest.main()
