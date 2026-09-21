#!/bin/sh
# herdr plugin action: removes the Codex hook registrations and copies
set -eu

codex_dir="${CODEX_HOME:-$HOME/.codex}"
hooks_dir="$codex_dir/hooks"
settings_path="$codex_dir/hooks.json"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

if [ -f "$settings_path" ]; then
  SETTINGS_PATH="$settings_path" python3 - <<'PY'
import json
import os
import tempfile

settings_path = os.environ["SETTINGS_PATH"]
marker = "herdr-codex-session-title.sh"

with open(settings_path, encoding="utf-8") as handle:
    settings = json.load(handle)

backup = settings_path + ".bak-codex-session-title"
with open(backup, "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")

hooks = settings.get("hooks")
if isinstance(hooks, dict):
    for event in list(hooks.keys()):
        entries = hooks.get(event)
        if not isinstance(entries, list):
            continue
        kept = []
        for entry in entries:
            if isinstance(entry, dict) and isinstance(entry.get("hooks"), list):
                had_marker = any(
                    isinstance(h, dict) and marker in str(h.get("command", ""))
                    for h in entry["hooks"]
                )
                if had_marker:
                    entry["hooks"] = [
                        h for h in entry["hooks"]
                        if not (isinstance(h, dict) and marker in str(h.get("command", "")))
                    ]
                    if not entry["hooks"]:
                        continue
            kept.append(entry)
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]

fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(settings_path) or ".", prefix=".hooks-")
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
os.replace(tmp_path, settings_path)
print("hook registrations removed")
PY
fi

rm -f "$hooks_dir/herdr-codex-session-title.sh" "$hooks_dir/herdr-codex-session-title.py"
echo "uninstalled"
