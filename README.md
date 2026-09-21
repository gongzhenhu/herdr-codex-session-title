# Herdr Codex Session Title

Herdr plugin that mirrors the current **Codex CLI** chat title into the herdr
pane display metadata — the Codex sibling of
[`bcihanc/herdr-claude-session-title`](https://github.com/bcihanc/herdr-claude-session-title).

A `/rename`-chosen name wins automatically (Codex appends a fresh line to its
session index); otherwise the generated `thread_name` is used, and until one
exists the first 60 characters of the user's prompt serve as a fallback title.

## How it works

- Registers three Codex CLI hooks (`features.hooks`) in `~/.codex/hooks.json`:
  - `SessionStart` — clears the stale pane title (Codex has **no SessionEnd
    hook**, so cleanup happens when the next session takes over the pane),
    then reports the resumed session's title if the index already knows one
  - `UserPromptSubmit` — reports the indexed title, falling back to the
    prompt's first 60 characters
  - `Stop` — reports the indexed title; Codex writes `thread_name` a few
    seconds *after* the turn ends, so on a miss a detached poller retries
    for up to 6s (the hook itself returns instantly). Before a late report
    the poller re-checks `herdr pane list`: if the pane has been taken over
    by a different session meanwhile, the stale title is dropped instead of
    resurrected.
- Titles are read **locally and read-only** from `~/.codex/session_index.jsonl`
  (`{"id": ..., "thread_name": ..., "updated_at": ...}`, append-only; the last
  line per session id wins).
- Reporting goes through
  `herdr pane report-metadata <pane> --source agent:title --agent codex --token title=...`
  — display-only pane metadata, same source token and same (legacy) syntax as
  the Claude plugin. Note: herdr 0.9.x's newer `--title` flag is accepted by
  the CLI but silently dropped by the server; `--token` is the syntax that
  actually works.
- Fully fail-open: every error path exits 0 silently so a title lookup or
  herdr outage can never disturb Codex. Outside a herdr-managed pane
  (`HERDR_ENV` / `HERDR_SOCKET_PATH` / `HERDR_PANE_ID` unset) the hook is a
  no-op.

Requires `python3`. No watcher process, no network, nothing leaves the machine.

## Install (development, from a local checkout)

```sh
herdr plugin link /path/to/codex-session-title
herdr plugin action invoke install --plugin local.codex-session-title
```

Restart already-running Codex sessions; Codex may ask you to trust the new
hooks once.

## Status / uninstall

```sh
herdr plugin action invoke status --plugin local.codex-session-title
herdr plugin action invoke uninstall --plugin local.codex-session-title
herdr plugin unlink local.codex-session-title
```

`install`/`uninstall` are idempotent: they replace only their own entries in
`hooks.json` (matched by script name) and back the file up to
`hooks.json.bak-codex-session-title` before touching it. Other hooks
(loongsuite, a1, ...) are never modified.

## Differences from the Claude sibling (all deliberate)

| | Claude plugin | this plugin |
|---|---|---|
| Title source | `ai-title`/`custom-title` records in the transcript JSONL | `thread_name` in `session_index.jsonl` |
| Stale-title cleanup | on `SessionEnd` | on `SessionStart` (Codex has no SessionEnd hook) |
| Event detection | `hook_event_name` in the payload | explicit wrapper argument (`start`/`prompt`/`stop`) — Codex payloads don't carry the event name |
| Report syntax | `--token title=...` | same (`--title` silently dropped by herdr 0.9.x server) |
| Late title after Stop | n/a (Claude writes ai-title before Stop) | detached 6s poller covers Codex's ~3s index-write delay |

## Development

```sh
sh tests/run.sh
```
