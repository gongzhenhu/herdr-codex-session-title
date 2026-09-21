#!/bin/sh
# installed by the local.codex-session-title herdr plugin
# reinstalling the plugin overwrites this file; do not edit in place.
# Usage: herdr-codex-session-title.sh <start|prompt|stop>
set -eu

event="${1:-}"
case "$event" in
  start|prompt|stop) ;;
  *) exit 0 ;;
esac

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HERDR_TITLE_EVENT="$event" exec python3 "$script_dir/herdr-codex-session-title.py"
