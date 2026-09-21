#!/bin/sh
# herdr plugin action: prints hook installation status (read-only)
set -eu

codex_dir="${CODEX_HOME:-$HOME/.codex}"
hook_sh="$codex_dir/hooks/herdr-codex-session-title.sh"
settings_path="$codex_dir/hooks.json"

if [ -x "$hook_sh" ]; then
  echo "hook script: installed ($hook_sh)"
else
  echo "hook script: NOT installed"
fi

if [ -f "$settings_path" ] && command -v python3 >/dev/null 2>&1; then
  SETTINGS_PATH="$settings_path" python3 - <<'PY'
import json
import os

marker = "herdr-codex-session-title.sh"
try:
    with open(os.environ["SETTINGS_PATH"], encoding="utf-8") as handle:
        settings = json.load(handle)
    hooks = settings.get("hooks", {}) if isinstance(settings, dict) else {}
    if not isinstance(hooks, dict):
        hooks = {}
    for event in ["SessionStart", "UserPromptSubmit", "Stop"]:
        entries = hooks.get(event, [])
        if not isinstance(entries, list):
            entries = []
        count = sum(
            1
            for entry in entries
            if isinstance(entry, dict) and isinstance(entry.get("hooks"), list)
            for h in entry["hooks"]
            if isinstance(h, dict) and marker in str(h.get("command", ""))
        )
        status = "registered" if count == 1 else "{} entries".format(count)
        print("{}: {}".format(event, status))
except Exception:
    print("hooks.json: unreadable or malformed")
PY
else
  echo "hooks.json: not found or python3 missing"
fi

if [ -f "$codex_dir/session_index.jsonl" ]; then
  echo "session index: present ($codex_dir/session_index.jsonl)"
else
  echo "session index: not found (titles appear once Codex writes it)"
fi

if [ -n "${HERDR_SOCKET_PATH:-}" ] && [ -S "$HERDR_SOCKET_PATH" ]; then
  echo "herdr socket: reachable ($HERDR_SOCKET_PATH)"
else
  echo "herdr socket: not available in this environment"
fi
