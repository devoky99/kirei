#!/usr/bin/env python3
"""Macht Fehler, Warnungen und Testergebnisse aus einem Build-Log auf GitHub sichtbar.

Aufruf im Workflow:
    scripts/ci-annotate.py build.log
    scripts/ci-annotate.py --notice "Vision-Selbsttest" selbsttest.log

Erzeugt Workflow-Befehle (::error, ::warning, ::notice), die GitHub als
Anmerkungen am Commit anzeigt. Lokal ohne Wirkung.
"""

import os
import re
import sys

MAX_PER_KIND = 10

COMPILER = re.compile(r"^(/[^:\s][^:]*):(\d+):(\d+): (error|warning): (.*)$")
TEST_ISSUE = re.compile(r"recorded an issue at ([^\s:]+):(\d+):(\d+): (.*)$")
MACRO_ERROR = re.compile(r"^macro expansion [^:]+:\d+:\d+: error: (.*)$")
MACRO_ORIGIN = re.compile(r"(/[^:\s][^:]*):(\d+):(\d+): note: expanded code originates here")
TEST_SUMMARY = re.compile(r"Test run with (\d+) tests?(?: in \d+ suites?)? (passed|failed).*$")


def escape(text: str) -> str:
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def escape_property(text: str) -> str:
    return escape(text).replace(":", "%3A").replace(",", "%2C")


def relative(path: str) -> str:
    workspace = os.environ.get("GITHUB_WORKSPACE", "")
    if workspace and path.startswith(workspace + "/"):
        return path[len(workspace) + 1 :]
    return path


def is_own_file(path: str) -> bool:
    workspace = os.environ.get("GITHUB_WORKSPACE", "")
    own = not workspace or path.startswith(workspace + "/")
    return own and "/.build/" not in path and "/DerivedData/" not in path


def annotate(log_path: str) -> None:
    with open(log_path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()

    seen = set()
    counts = {"error": 0, "warning": 0}

    for number, line in enumerate(lines):
        macro = MACRO_ERROR.match(line.strip())
        if macro and counts["error"] < MAX_PER_KIND:
            origin = next((MACRO_ORIGIN.search(l) for l in lines[number + 1 : number + 4] if MACRO_ORIGIN.search(l)), None)
            if origin:
                path, row, col = origin.groups()
                key = (path, row, "error", macro.group(1))
                if key not in seen:
                    seen.add(key)
                    counts["error"] += 1
                    print(f"::error file={escape_property(relative(path))},line={row},col={col}::{escape(macro.group(1))}")
            continue

        match = COMPILER.match(line.strip())
        if match:
            path, row, col, kind, message = match.groups()
            if kind == "warning" and not is_own_file(path):
                continue
            key = (path, row, kind, message)
            if key in seen or counts[kind] >= MAX_PER_KIND:
                continue
            seen.add(key)
            counts[kind] += 1
            print(f"::{kind} file={escape_property(relative(path))},line={row},col={col}::{escape(message)}")
            continue

        match = TEST_ISSUE.search(line)
        if match and counts["error"] < MAX_PER_KIND:
            file, row, col, message = match.groups()
            key = (file, row, message)
            if key not in seen:
                seen.add(key)
                counts["error"] += 1
                print(f"::error title=Test {escape_property(file)}%3A{row}::{escape(message)}")

    summaries = [m.group(0) for m in (TEST_SUMMARY.search(l) for l in lines) if m]
    if summaries:
        print(f"::notice title=Tests::{escape(chr(10).join(summaries))}")

    failed = any("** BUILD FAILED **" in l or "error: fatalError" in l for l in lines)
    if counts["error"] == 0 and (failed or any(" error:" in l or l.startswith("error:") for l in lines)):
        tail = "\n".join(lines[-40:])
        print(f"::error title=Ende des Build-Logs::{escape(tail)}")


def notice(title: str, log_path: str) -> None:
    with open(log_path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    print(f"::notice title={escape_property(title)}::{escape(chr(10).join(lines[-120:]))}")


def main() -> int:
    args = sys.argv[1:]
    if len(args) == 3 and args[0] == "--notice":
        notice(args[1], args[2])
        return 0
    if len(args) == 1:
        annotate(args[0])
        return 0
    print(__doc__)
    return 64


if __name__ == "__main__":
    sys.exit(main())
