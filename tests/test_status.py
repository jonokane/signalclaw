"""Tests for write_status.py and run-with-status.sh. No network, no OpenClaw.

    python3 -m unittest discover -s tests
"""

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from write_status import build, main  # noqa: E402

START = "2026-11-12T05:30:00-08:00"


def results(run_at="2026-11-12T05:31:10-08:00"):
    rows = [
        {"id": "a", "company": "Acme", "title": "Staff Product Designer", "url": "https://example.com/1",
         "verdict": "GONE", "reason": "absent from the full board"},
        {"id": "b", "company": "Globex", "title": "Design Lead", "url": "https://example.com/2", "verdict": "LIVE"},
        {"id": "c", "company": "Initech", "title": "VP of Design", "url": "https://example.com/3", "verdict": "CHANGED"},
    ]
    return {"runAt": run_at, "counts": {"LIVE": 1, "GONE": 1, "CHANGED": 1, "CANT_TELL": 0}, "results": rows}


class Build(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name) / "latest.json"

    def tearDown(self):
        self.dir.cleanup()

    def save(self, doc):
        self.path.write_text(json.dumps(doc))

    def test_plain_job_ok(self):
        s = build(START, 0, "done")
        self.assertEqual((s["status"], s["error"]), ("ok", ""))
        self.assertNotIn("counts", s)

    def test_plain_job_failed(self):
        s = build(START, 3, "")
        self.assertEqual((s["status"], s["error"]), ("failed", "exited with code 3"))

    def test_signalcheck_results_ok(self):
        self.save(results())
        s = build(START, 0, "", self.path)
        self.assertEqual(s["status"], "ok")
        self.assertEqual(s["counts"], {"LIVE": 1, "GONE": 1, "CHANGED": 1, "CANT_TELL": 0})
        self.assertEqual(s["gone"], [{"company": "Acme", "title": "Staff Product Designer", "url": "https://example.com/1"}])
        self.assertEqual(s["checked"], 3)

    def test_later_step_failed_keeps_real_counts(self):
        self.save(results())
        s = build(START, 1, "git push failed", self.path)
        self.assertEqual((s["status"], s["counts"]["GONE"]), ("failed", 1))
        self.assertIn("note", s)

    def test_old_results_are_not_this_run(self):
        self.save(results(run_at="2026-11-11T05:31:10-08:00"))
        s = build(START, 1, "network down", self.path)
        self.assertEqual((s["status"], s["counts"], s["gone"]), ("failed", None, []))

    def test_exit_zero_without_results_is_failed(self):
        s = build(START, 0, "nothing to check", self.path)
        self.assertEqual(s["status"], "failed")
        self.assertIn("wrote no results: nothing to check", s["error"])

    def test_no_contact_details_in_error(self):
        s = build(START, 1, "send to someone@example.com or +1 (415) 555-0100 failed")
        self.assertNotIn("example.com", s["error"])
        self.assertNotIn("555", s["error"])

    def test_only_listed_fields_from_results(self):
        self.save(results())
        text = json.dumps(build(START, 0, "", self.path))
        self.assertNotIn("absent from the full board", text)
        self.assertNotIn('"id"', text)

    def test_overwrites_atomically(self):
        out = Path(self.dir.name) / "ws" / "status.json"
        main(["--start", START, "--rc", "0", "--out", str(out)])
        main(["--start", START, "--rc", "124", "--error", "too slow", "--out", str(out)])
        s = json.loads(out.read_text())
        self.assertEqual((s["status"], s["exitCode"]), ("failed", 124))
        self.assertEqual([p.name for p in out.parent.iterdir()], ["status.json"])


class Wrapper(unittest.TestCase):
    """The real run-with-status.sh around small fake jobs."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.status = Path(self.dir.name) / "status.json"
        self.env = dict(os.environ, SIGNALCLAW_STATUS_FILE=str(self.status), SIGNALCLAW_NO_ALERTS="1")

    def tearDown(self):
        self.dir.cleanup()

    def run_job(self, *cmd, **env):
        p = subprocess.run(["/bin/sh", str(SCRIPTS / "run-with-status.sh"), *cmd], env={**self.env, **env},
                           capture_output=True, text=True, timeout=60)
        return p.returncode, json.loads(self.status.read_text())

    def test_success(self):
        rc, s = self.run_job("/bin/sh", "-c", "echo all good")
        self.assertEqual((rc, s["status"]), (0, "ok"))

    def test_failure_quotes_the_failed_line(self):
        rc, s = self.run_job("/bin/sh", "-c", "echo working; echo 'FAILED: board would not load'; exit 1")
        self.assertEqual((rc, s["status"], s["error"]), (1, "failed", "board would not load"))

    def test_timeout(self):
        rc, s = self.run_job("/bin/sleep", "30", SIGNALCLAW_TIMEOUT="2")
        self.assertEqual((rc, s["status"]), (124, "failed"))
        self.assertIn("ran longer than 2 seconds", s["error"])

    def test_killed_wrapper_still_writes_failed(self):
        p = subprocess.Popen(["/bin/sh", str(SCRIPTS / "run-with-status.sh"), "/bin/sleep", "30"], env=self.env,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1.5)
        p.send_signal(signal.SIGTERM)
        self.assertEqual(p.wait(timeout=20), 143)
        s = json.loads(self.status.read_text())
        self.assertEqual(s["status"], "failed")
        self.assertIn("stopped before finishing", s["error"])

    def test_results_from_this_run(self):
        res = Path(self.dir.name) / "latest.json"
        job = ("python3 -c \"import json,datetime;d=" + repr(results()).replace('"', '\\"') +
               ";d['runAt']=datetime.datetime.now().astimezone().isoformat();"
               f"open('{res}','w').write(json.dumps(d))\"")
        rc, s = self.run_job("/bin/sh", "-c", job, SIGNALCLAW_RESULTS=str(res))
        self.assertEqual((rc, s["status"], s["counts"]["GONE"]), (0, "ok", 1))


class Installer(unittest.TestCase):
    def test_print_renders_valid_plists(self):
        p = subprocess.run(["/bin/sh", str(SCRIPTS / "install.sh"), "--print", "--at", "06:05", "--restart-alert",
                            "--lock-at-login", "--check", "cd ~/jobs && signalcheck run <list> & echo \"done\""],
                           capture_output=True, text=True, check=True)
        parts = [x for x in p.stdout.split("----- ") if x.strip()]
        self.assertEqual(len(parts), 3)
        for part in parts:
            body = part.split("\n", 1)[1]
            lint = subprocess.run(["plutil", "-lint", "-"], input=body, capture_output=True, text=True)
            self.assertEqual(lint.returncode, 0, lint.stdout + lint.stderr)
        self.assertIn("<integer>6</integer>", parts[0])
        self.assertIn("<integer>5</integer>", parts[0])
        self.assertIn("&lt;list&gt; &amp; echo &quot;done&quot;", parts[0])

    def test_bad_time_rejected(self):
        p = subprocess.run(["/bin/sh", str(SCRIPTS / "install.sh"), "--print", "--check", "true", "--at", "25:00"],
                           capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)


if __name__ == "__main__":
    unittest.main()
