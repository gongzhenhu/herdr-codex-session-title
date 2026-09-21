#!/usr/bin/env python3
"""Reports the Codex CLI session title to herdr as pane metadata title.

Modes:
  (no args)                              hook mode: Codex hook input JSON on stdin
  extract <index_path> <session_id>      print extracted title (test entrypoint)

Hook mode reads the event name from HERDR_TITLE_EVENT (start|prompt|stop),
set by the shell wrapper from its first argument. Codex hook payloads carry
no hook_event_name field, so the event is passed explicitly at registration
time (see install.sh).
"""
import json
import os
import re
import subprocess
import sys

SOURCE = "agent:title"
AGENT = "codex"
MAX_TITLE_CHARS = 120
MAX_PROMPT_CHARS = 60

# Codex rollout file names embed the session uuid:
#   rollout-2026-09-20T17-59-15-01a0be41-7223-7212-9ede-70e2d73580db.jsonl
ROLLOUT_UUID_RE = re.compile(
    r"rollout-.*?-"
    r"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}"
    r"-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$"
)


def sanitize(title):
    if not isinstance(title, str):
        return None
    cleaned = "".join(
        " " if (ch < " " or ch == "\x7f" or "\x80" <= ch <= "\x9f") else ch
        for ch in title
    )
    cleaned = " ".join(cleaned.split())
    if not cleaned:
        return None
    return cleaned[:MAX_TITLE_CHARS]


def codex_home():
    home = os.environ.get("CODEX_HOME")
    if home:
        return home
    return os.path.join(os.path.expanduser("~"), ".codex")


def session_index_path():
    return os.path.join(codex_home(), "session_index.jsonl")


def title_from_index(index_path, session_id):
    # session_index.jsonl is an append-only log of
    #   {"id": <session uuid>, "thread_name": ..., "updated_at": ...}
    # The LAST line for a session id holds its current name (/rename appends
    # a fresh line), so we scan the whole file and keep overwriting.
    title = None
    try:
        with open(index_path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if session_id not in line:
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(record, dict):
                    continue
                if record.get("id") != session_id:
                    continue
                candidate = sanitize(record.get("thread_name"))
                if candidate:
                    title = candidate
    except OSError:
        return None
    return title


def session_id_from_input(hook_input):
    session_id = hook_input.get("session_id")
    if isinstance(session_id, str) and session_id:
        return session_id
    # Codex also exposes the thread id to hook processes via env, and the
    # rollout file name embeds the session uuid as a last resort.
    thread_id = os.environ.get("CODEX_THREAD_ID")
    if isinstance(thread_id, str) and thread_id:
        return thread_id
    transcript_path = hook_input.get("transcript_path")
    if isinstance(transcript_path, str):
        match = ROLLOUT_UUID_RE.search(os.path.basename(transcript_path))
        if match:
            return match.group(1)
    return None


def extract_title(index_path, session_id):
    return title_from_index(index_path, session_id)


def report(pane_id, title):
    _report_metadata(pane_id, ["--title", title])


def clear_reported_title(pane_id):
    _report_metadata(pane_id, ["--clear-title"])


def _report_metadata(pane_id, extra):
    herdr_bin = os.environ.get("HERDR_BIN_PATH") or "herdr"
    cmd = [
        herdr_bin, "pane", "report-metadata", pane_id,
        "--source", SOURCE,
        "--agent", AGENT,
    ] + extra
    try:
        subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
    except Exception:
        pass


def hook_mode():
    event = os.environ.get("HERDR_TITLE_EVENT", "")
    pane_id = os.environ.get("HERDR_PANE_ID")
    socket_path = os.environ.get("HERDR_SOCKET_PATH")
    if not pane_id or not socket_path:
        return
    try:
        hook_input = json.load(sys.stdin)
    except ValueError:
        hook_input = {}
    if not isinstance(hook_input, dict):
        hook_input = {}

    if event == "start":
        # Codex has no SessionEnd hook: drop the stale title when a new
        # session takes over the pane, then report the resumed session's
        # title below if the index already knows one.
        clear_reported_title(pane_id)

    session_id = session_id_from_input(hook_input)
    if not session_id:
        return
    title = extract_title(session_index_path(), session_id)
    if not title and event == "prompt":
        prompt = hook_input.get("prompt")
        if isinstance(prompt, str):
            cleaned = sanitize(prompt)
            if cleaned:
                title = cleaned[:MAX_PROMPT_CHARS]
    if not title:
        return
    report(pane_id, title)


def main():
    args = sys.argv[1:]
    if args[:1] == ["extract"] and len(args) == 3:
        title = extract_title(args[1], args[2])
        if not title:
            return 1
        print(title)
        return 0
    try:
        hook_mode()
    except Exception:
        # a hook must never disturb Codex
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
