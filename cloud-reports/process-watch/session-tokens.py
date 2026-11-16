#!/usr/bin/env python3
"""Sums the token usage a Claude Code session recorded in its own transcript.

    session-tokens.py [--since TIME] [--until TIME] [TRANSCRIPT.jsonl ...]

With no file it reads every transcript under ~/.claude/projects, subagents' too. Each assistant message carries a
`usage` object; a message written over several lines repeats it, so usage is counted once per message id. Times are
ISO 8601 in UTC, as in the transcript. A lane runs this at hand-back and reports the line it prints.
"""
import glob, json, os, sys

def main():
    arguments = sys.argv[1:]
    bounds = {}
    for flag in ("--since", "--until"):
        if flag in arguments:
            i = arguments.index(flag); bounds[flag] = arguments[i + 1]; del arguments[i:i + 2]
    files = arguments or glob.glob(os.path.expanduser("~/.claude/projects/**/*.jsonl"), recursive=True)
    seen = {}
    for file in files:
        with open(file, encoding="utf-8", errors="replace") as lines:
            for line in lines:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                message = entry.get("message") or {}
                usage = message.get("usage")
                time = entry.get("timestamp", "")
                if not usage or (bounds.get("--since") and time < bounds["--since"]) or (bounds.get("--until") and time >= bounds["--until"]):
                    continue
                seen[message.get("id") or (file, time)] = usage
    keys = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")
    total = {key: sum(usage.get(key) or 0 for usage in seen.values()) for key in keys}
    print(f"{len(seen)} messages: input {total['input_tokens']:,}, cache written {total['cache_creation_input_tokens']:,}, cache read {total['cache_read_input_tokens']:,}, output {total['output_tokens']:,}")

main()
