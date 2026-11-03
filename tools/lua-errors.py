#!/usr/bin/env python3
"""Group the Lua errors in a TFS log by script:line, with count and first/last occurrence.

Reads the container log (docker logs -t, so every line has a timestamp) or a log file / stdin.
Understands the engine's two error shapes:
  - runtime:  "Lua Script Error:" + interface + "file:callback" + message + "stack traceback:" ...
  - loading:  "> file.lua [error]" + "^ message"

Usage:
  tools/lua-errors.py                          # docker logs of rpg-dev-tfs-1
  tools/lua-errors.py --container NAME --since 2h
  tools/lua-errors.py --file data/logs/x.log   # or "-" for stdin
  tools/lua-errors.py --traceback              # also print one traceback per group
  tools/lua-errors.py --json
Exit status: 0 without errors, 1 when there are Lua errors.
"""
import argparse
import json
import re
import subprocess
import sys

DEFAULT_CONTAINER = "rpg-dev-tfs-1"

TIMESTAMP = re.compile(r"^(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})(?:[.,]\d+)?(Z|[+-]\d{2}:?\d{2})?\s?")
PREFIX = re.compile(r"^\S+\s+\|\s")  # docker compose "service-1  | "
LEVEL = re.compile(r"^\s*\[(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|CRITICAL|LUA)\s*\]\s?")
LOCATION = re.compile(r"((?:\.\.\.)?[\w./\- ']*?\.lua):(\d+):")
CALLBACK = re.compile(r"(\S+\.lua):(\S+)\s*$")
LOAD_ERROR = re.compile(r"^>\s+(\S+\.lua)\s+\[error\]")


def strip_line(raw: str):
    """-> (timestamp or None, level or None, text)."""
    line = raw.rstrip("\n")
    stamp = None
    match = TIMESTAMP.match(line)
    if match:
        stamp = match.group(1).replace(" ", "T")
        line = line[match.end():]
    line = PREFIX.sub("", line, count=1)
    level = None
    match = LEVEL.match(line)
    if match:
        level = match.group(1)
        line = line[match.end():]
    return stamp, level, line.rstrip()


def relative(path: str) -> str:
    """/srv/data/scripts/x.lua -> data/scripts/x.lua (the repo path)."""
    index = path.find("data/")
    return path[index:] if index >= 0 else path


def resolve(path: str, known: list[str]) -> str:
    """Expand a truncated "...ata/scripts/x.lua" with a full path seen in the same error."""
    if path.startswith("..."):
        tail = path[3:]
        for candidate in known:
            if candidate.endswith(tail):
                return relative(candidate)
        return path
    return relative(path)


def normalize(message: str) -> str:
    message = re.sub(r"0x[0-9a-fA-F]+", "0x?", message)
    message = re.sub(r"table: [0-9a-fA-F]+|userdata: [0-9a-fA-F]+", "<addr>", message)
    return message.strip()


def parse(lines):
    """Yields one dict per Lua error."""
    current = None
    line_no = 0

    def finish():
        nonlocal current
        if current and current["lines"]:
            yield_value = build(current)
            current = None
            return yield_value
        current = None
        return None

    def build(block):
        texts = block["lines"]
        known = []
        callback = None
        for text in texts:
            match = CALLBACK.search(text)
            if match and not LOCATION.search(text):
                known.append(match.group(1))
                callback = callback or text.strip()
        message = None
        location = None
        traceback = []
        in_traceback = False
        for text in texts:
            if text.startswith("stack traceback:"):
                in_traceback = True
                continue
            if in_traceback:
                traceback.append(text.strip())
                continue
            match = LOCATION.search(text)
            if match and message is None:
                message = text.strip()
                location = (resolve(match.group(1), known), int(match.group(2)))
        if message is None:
            # No file:line in the message (e.g. an error raised from C++): use the last text line.
            candidates = [t.strip() for t in texts if t.strip() and not t.startswith("stack traceback:")]
            message = candidates[-1] if candidates else "?"
        if location is None and block.get("file"):
            location = (relative(block["file"]), 0)
        if location is None:
            for entry in traceback:
                match = LOCATION.search(entry)
                if match:
                    location = (resolve(match.group(1), known), int(match.group(2)))
                    break
        if location is None and known:
            location = (relative(known[0]), 0)
        text = message
        if location:
            text = LOCATION.sub("", message, count=1).strip() if LOCATION.search(message) else message
        return {
            "script": location[0] if location else "?",
            "line": location[1] if location else 0,
            "message": normalize(text),
            "kind": block["kind"],
            "callback": callback,
            "time": block["time"],
            "log_line": block["log_line"],
            "traceback": traceback,
        }

    for raw in lines:
        line_no += 1
        stamp, level, text = strip_line(raw)
        if text.strip().startswith("Lua Script Error:"):
            done = finish()
            if done:
                yield done
            current = {"kind": "runtime", "lines": [], "time": stamp, "log_line": line_no}
            continue
        match = LOAD_ERROR.match(text.strip())
        if match:
            done = finish()
            if done:
                yield done
            current = {"kind": "load", "lines": [], "time": stamp, "log_line": line_no, "file": match.group(1)}
            continue
        if current is None:
            continue
        if current["kind"] == "load":
            if text.strip().startswith("^"):
                current["lines"].append(text.strip()[1:].strip())
                continue
            if current["lines"] and (level is None or level == "ERROR") and not text.strip().startswith(">"):
                current["lines"].append(text)
                continue
        elif level in (None, "ERROR"):
            # Error lines and the untagged traceback lines that follow them.
            if text.strip() or current["lines"]:
                current["lines"].append(text)
            continue
        done = finish()
        if done:
            yield done
    done = finish()
    if done:
        yield done


def read_source(args):
    if args.file == "-":
        return sys.stdin.readlines()
    if args.file:
        with open(args.file, encoding="utf-8", errors="replace") as handle:
            return handle.readlines()
    command = ["docker", "logs", "-t"]
    if args.since:
        command += ["--since", args.since]
    command.append(args.container)
    result = subprocess.run(command, capture_output=True, text=True, errors="replace")
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        sys.exit(2)
    # TFS writes to stdout and stderr; docker keeps them apart, the timestamps put them back in order.
    lines = result.stdout.splitlines(keepends=True) + result.stderr.splitlines(keepends=True)
    return sorted(lines, key=lambda line: line[:35]) if lines and TIMESTAMP.match(lines[0]) else lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--container", default=DEFAULT_CONTAINER)
    parser.add_argument("--since", help="docker logs --since (e.g. 30m, 2h, 2026-11-03T20:00)")
    parser.add_argument("--file", help="log file instead of docker ('-' = stdin)")
    parser.add_argument("--traceback", action="store_true", help="print one traceback per group")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    groups: dict[tuple, dict] = {}
    for error in parse(read_source(args)):
        key = (error["script"], error["line"], error["message"])
        group = groups.get(key)
        when = error["time"] or f"line {error['log_line']}"
        if group is None:
            group = groups[key] = {**error, "count": 0, "first": when, "last": when}
        group["count"] += 1
        group["last"] = when

    ordered = sorted(groups.values(), key=lambda g: (-g["count"], g["script"], g["line"]))
    if args.json:
        json.dump([{k: g[k] for k in ("script", "line", "message", "kind", "callback", "count", "first", "last", "traceback")} for g in ordered], sys.stdout, indent=2, ensure_ascii=False)
        print()
        return 1 if ordered else 0

    total = sum(g["count"] for g in ordered)
    for group in ordered:
        where = f"{group['script']}:{group['line']}" if group["line"] else group["script"]
        tag = " [carga]" if group["kind"] == "load" else ""
        print(f"{group['count']:>6}x  {where}{tag}")
        print(f"         {group['message']}")
        print(f"         primeira {group['first']}  ultima {group['last']}")
        if args.traceback and group["traceback"]:
            for entry in group["traceback"][:12]:
                print(f"           {entry}")
    print(f"\n{total} erros Lua em {len(ordered)} grupos")
    return 1 if ordered else 0


if __name__ == "__main__":
    sys.exit(main())
