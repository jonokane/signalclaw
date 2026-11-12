#!/usr/bin/env python3
"""Write a status file that a sandboxed OpenClaw agent can read.

Called by run-with-status.sh at the end of every scheduled run, success or
failure. Standard library only, so it runs on the macOS system Python
(/usr/bin/python3) even when the job's own environment is broken.

    write_status.py --start ISO --rc N [--name TEXT] [--error TEXT]
                    [--results PATH] [--out PATH]

--results (optional) is a signalcheck results file (results/latest.json). When
it was written during this run, its verdict counts and GONE rows are included.

The status is "ok" only when the job exited 0 and, if --results was given,
that file was written during this run. Anything else is "failed".

The error text is scrubbed of anything that looks like an email address or a
phone number, because the agent may quote it back over chat.
"""

import argparse
import json
import os
import re
import sys
import tempfile
from datetime import datetime
from pathlib import Path

DEFAULT_OUT = Path.home() / ".openclaw" / "workspace" / "checker-status.json"
VERDICTS = ("LIVE", "GONE", "CHANGED", "CANT_TELL")
EMAIL = re.compile(r"[\w.%+-]+@[\w-]+(\.[\w-]+)+")
PHONE = re.compile(r"\+?\d[\d ().-]{8,}\d")


def now_iso():
    return datetime.now().astimezone().isoformat(timespec="seconds")


def parse_time(s):
    try:
        t = datetime.fromisoformat(s)
    except (TypeError, ValueError):
        return None
    return t if t.tzinfo else t.astimezone()


def scrub(text, limit=500):
    text = " ".join(str(text or "").split())
    text = EMAIL.sub("[address removed]", text)
    text = PHONE.sub("[number removed]", text)
    return text[:limit]


def fresh_results(path, start):
    """The results doc if it was written during this run, else None."""
    if not path:
        return None
    try:
        doc = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None
    run_at, started = parse_time(doc.get("runAt")), parse_time(start)
    if not (run_at and started and run_at >= started):
        return None
    return doc


def build(start, rc, error="", results_path=None, name="scheduled job", end=None):
    doc = fresh_results(results_path, start)
    error = scrub(error)
    missing = bool(results_path) and doc is None
    ok = rc == 0 and not missing
    if rc == 0 and missing:
        error = f"the run finished but wrote no results: {error}" if error else "the run finished but wrote no results"
    elif rc != 0 and not error:
        error = f"exited with code {rc}"

    status = {
        "about": f"Status of the {name}, a macOS LaunchAgent (not an OpenClaw automation). "
                 "Overwritten at the end of every scheduled run. If finishedAt is not today, the run did not happen.",
        "startedAt": start,
        "finishedAt": end or now_iso(),
        "status": "ok" if ok else "failed",
        "exitCode": rc,
        "error": "" if ok else error,
    }
    if results_path:
        status.update({"counts": None, "checked": None, "gone": []})
    if doc is not None:
        c = doc.get("counts") or {}
        rows = doc.get("results") or []
        status["counts"] = {v: int(c.get(v, 0)) for v in VERDICTS}
        status["checked"] = len(rows)
        status["resultsRunAt"] = doc.get("runAt", "")
        status["gone"] = [
            {"company": r.get("company", ""), "title": r.get("title", ""), "url": r.get("url", "")}
            for r in rows if r.get("verdict") == "GONE"
        ]
        if not ok:
            status["note"] = "The check itself finished and these counts are real; a later step failed."
    return status


def write(status, out=DEFAULT_OUT):
    out = Path(out).expanduser()
    out.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out.parent, prefix=f".{out.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(status, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, out)  # atomic: the agent never reads a half-written file
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--start", required=True, help="ISO-8601 start time of the run")
    p.add_argument("--rc", type=int, required=True, help="the job's exit code")
    p.add_argument("--name", default=os.environ.get("SIGNALCLAW_JOB_NAME") or "scheduled job")
    p.add_argument("--error", default="")
    p.add_argument("--results", default=os.environ.get("SIGNALCLAW_RESULTS") or None)
    p.add_argument("--out", default=os.environ.get("SIGNALCLAW_STATUS_FILE") or str(DEFAULT_OUT))
    a = p.parse_args(argv)
    status = build(a.start, a.rc, a.error, a.results, a.name)
    write(status, a.out)
    print(f"wrote {a.out}: {status['status']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
