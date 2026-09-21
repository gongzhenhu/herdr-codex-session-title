#!/bin/sh
# herdr plugin action: registers the Codex hook for session title reporting
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
codex_dir="${CODEX_HOME:-$HOME/.codex}"
hooks_dir="$codex_dir/hooks"
hook_sh="$hooks_dir/herdr-codex-session-title.sh"
hook_py="$hooks_dir/herdr-codex-session-title.py"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

mkdir -p "$hooks_dir"
cp "$plugin_root/scripts/herdr-codex-session-title.sh" "$hook_sh"
cp "$plugin_root/scripts/herdr-codex-session-title.py" "$hook_py"
chmod +x "$hook_sh"

HOOK_SH="$hook_sh" SETTINGS_PATH="$codex_dir/hooks.json" python3 - <<'PY'
import json
import os
import tempfile

settings_path = os.environ["SETTINGS_PATH"]
hook_sh = os.environ["HOOK_SH"]
marker = "herdr-codex-session-title.sh"
# event -> (wrapper argument, timeout). Codex clamps SessionEnd hook
# timeouts to 3s. The wrapper argument doubles as the event name since
# payloads are not relied on for event detection.
events = {
    "SessionStart": ("start", 10),
    "UserPromptSubmit": ("prompt", 10),
    "Stop": ("stop", 10),
    "SessionEnd": ("end", 3),
}

settings = {}
if os.path.exists(settings_path):
    with open(settings_path, encoding="utf-8") as handle:
        settings = json.load(handle)
    backup = settings_path + ".bak-codex-session-title"
    with open(backup, "w", encoding="utf-8") as handle:
        json.dump(settings, handle, indent=2)
        handle.write("\n")

if not isinstance(settings, dict):
    raise SystemExit("error: hooks.json root is not a JSON object; refusing to modify")
hooks = settings.setdefault("hooks", {})
if not isinstance(hooks, dict):
    raise SystemExit("error: hooks.json 'hooks' is not a JSON object; refusing to modify")
for event, (arg, timeout) in events.items():
    entries = hooks.setdefault(event, [])
    if not isinstance(entries, list):
        raise SystemExit("error: hooks.json 'hooks.{}' is not a list; refusing to modify".format(event))
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
    new_entry = {
        "hooks": [
            {
                "type": "command",
                "command": "sh '{}' {}".format(hook_sh, arg),
                "timeout": timeout,
            }
        ],
        "matcher": "*",
    }
    kept.append(new_entry)
    hooks[event] = kept

fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(settings_path) or ".", prefix=".hooks-")
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
os.replace(tmp_path, settings_path)
print("registered hooks: " + ", ".join(events))
PY

echo "installed: $hook_sh"
echo "note: Codex may ask you to trust the new hooks once on next start;"
echo "      already-running Codex sessions pick up new hooks on restart."
