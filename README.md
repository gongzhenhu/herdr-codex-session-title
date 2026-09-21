# Herdr Codex Session Title

Herdr plugin that mirrors the current **Codex CLI** chat title into the herdr
pane display metadata — the Codex sibling of
[`bcihanc/herdr-claude-session-title`](https://github.com/bcihanc/herdr-claude-session-title).

A `/rename`-chosen name wins automatically (Codex appends a fresh line to its
session index); otherwise the generated `thread_name` is used, and until one
exists the first 60 characters of the user's prompt serve as a fallback title.

## How it works

- Registers four Codex CLI hooks (`features.hooks`) in `~/.codex/hooks.json`:
  - `SessionEnd` — clears the pane title the moment a session exits.
    Important because **Codex sessions start lazily**: the TUI alone is not
    a session; SessionStart only fires when the first message is sent.
    Without SessionEnd, reopening Codex would keep showing the previous
    session's title until a message is typed.
  - `SessionStart` — reports the resumed session's title if the index
    already knows one. It deliberately never clears: Codex fires
    SessionStart **twice** around the first message of a session, with a
    UserPromptSubmit report in between — clearing there would wipe the
    user's own prompt title mid-turn. SessionEnd does the clearing; a
    session killed without one is cleaned up by the next session's first
    report.
  - `UserPromptSubmit` — reports the indexed title, falling back to the
    prompt's first 60 characters. Codex's own internal title-generation
    request also fires this event with a template prompt; that is filtered
    out and never shown.
  - `Stop` — reports the indexed title; Codex writes `thread_name` a few
    seconds *after* the turn ends (measured up to ~6s), so on a miss a
    detached poller retries for up to 20s (the hook itself returns
    instantly). Before a late report the poller re-checks `herdr pane
    list`: if the pane has been taken over by a different session
    meanwhile, the stale title is dropped instead of resurrected. Note
    that Codex's internal title-generation session fires Stop too; the
    guard drops its reports, since the pane is bound to the real session.
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

## Install

```sh
herdr plugin install gongzhenhu/herdr-codex-session-title
herdr plugin action invoke install --plugin gongzhenhu.herdr-codex-session-title
```

(Development alternative: `herdr plugin link <checkout>` and invoke the
`install` action the same way.)

Restart already-running Codex sessions; Codex may ask you to trust the new
hooks once.

## Status / uninstall

```sh
herdr plugin action invoke status --plugin gongzhenhu.herdr-codex-session-title
herdr plugin action invoke uninstall --plugin gongzhenhu.herdr-codex-session-title
herdr plugin uninstall gongzhenhu.herdr-codex-session-title
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
