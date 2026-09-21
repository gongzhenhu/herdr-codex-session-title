# Codex Session Title Plugin — Design

Date: 2026-09-21
Status: approved by user in chat, 2026-09-21

## Goal

Mirror the Codex CLI session title into the herdr pane display metadata,
behaviorally identical to the Claude-side `bcihanc.claude-session-title`
plugin: same architecture (herdr plugin + hook scripts + `report-metadata`),
same source token (`agent:title`), same fail-open guarantees. Scope is title
reporting only — no agent renaming, no watcher daemon.

## Background findings (verified on this machine)

- Codex CLI 0.155.1 with `features.hooks = true`; `~/.codex/hooks.json`
  already hosts third-party hooks (loongsuite, a1) — format matches Claude's
  `settings.json` hooks section.
- Codex hook events available: SessionStart, UserPromptSubmit, Stop,
  SubagentStart/Stop, PreToolUse, PostToolUse(Failure). **No SessionEnd.**
- Codex hook payloads carry `session_id`, `transcript_path`, `prompt`
  (confirmed via loongsuite's processor). No confirmed `hook_event_name`.
- Codex session titles live in `~/.codex/session_index.jsonl`:
  `{"id": <uuid>, "thread_name": ..., "updated_at": ...}`, append-only;
  `/rename` appends a new line, so the last line per id is current.
- Rollout file names embed the session uuid
  (`rollout-<ts>-<uuid>.jsonl`) — usable as an id fallback.
- herdr's built-in codex agent-state integration (v8) is already installed
  and registered; this plugin complements it.
- Current herdr `pane report-metadata` syntax: `--title <TEXT>` /
  `--clear-title` (the bcihanc plugin's `--token` form predates it).

## Architecture

```
codex-session-title/
├── herdr-plugin.toml                  # id=local.codex-session-title, actions: install/uninstall/status
├── scripts/
│   ├── herdr-codex-session-title.sh   # guard shell: env checks → exec python3 (event via $1)
│   ├── herdr-codex-session-title.py   # title extraction + herdr reporting (extract test entrypoint)
│   ├── install.sh                     # deploy to ~/.codex/hooks/ + idempotent hooks.json registration
│   ├── uninstall.sh                   # marker-based removal + delete scripts
│   └── status.sh                      # read-only install status
├── tests/
│   ├── fixtures/session_index.jsonl
│   └── run.sh                          # extract-mode unit tests
└── README.md
```

Runtime layout mirrors the Claude side: plugin source (git-managed,
`herdr plugin link`ed) deploys copies to `~/.codex/hooks/`, exactly as
bcihanc deploys to `~/.claude/hooks/`.

## Data flow

| Event | Registered command | Behavior |
|---|---|---|
| SessionStart | `sh '<hooks>/herdr-codex-session-title.sh' start` | clear stale title, then report indexed title if present (resume case) |
| UserPromptSubmit | `sh '<hooks>/herdr-codex-session-title.sh' prompt` | report indexed title; fallback: sanitized `prompt[:60]` |
| Stop | `sh '<hooks>/herdr-codex-session-title.sh' stop` | report indexed title |

Session id resolution order: payload `session_id` → env `CODEX_THREAD_ID` →
uuid parsed from `transcript_path` basename.

Report/clear commands (legacy token syntax — see "Post-deploy debug" below):

```
herdr pane report-metadata "$HERDR_PANE_ID" --source agent:title --agent codex --token title=<t>
herdr pane report-metadata "$HERDR_PANE_ID" --source agent:title --agent codex --clear-token title
```

Stop race: Codex writes `thread_name` to the session index ~3s AFTER the Stop
hook fires (measured on a live session). On a Stop-time index miss the script
spawns a detached poller (`poll` mode: retry every 300ms for up to 6s, report
when the title lands) so the hook returns instantly and Codex is never
delayed.

## Deliberate differences from the Claude plugin

1. Title source: `session_index.jsonl` `thread_name` (not transcript
   `ai-title`/`custom-title` records).
2. No SessionEnd hook in Codex → stale-title cleanup moves to SessionStart.
3. Event passed as wrapper argument (payload lacks `hook_event_name`).
4. ~~Current `--title`/`--clear-title` syntax~~ REVERTED to legacy
   `--token title=` (see debug findings below).
5. Dropped Claude-specific paths: sessions-index.json legacy fallback,
   Cursor env detection, subagent filtering (SubagentStart/Stop simply are
   not registered).

## Error handling

Fail-open everywhere: guards (`HERDR_ENV=1`, `HERDR_SOCKET_PATH`,
`HERDR_PANE_ID`, python3 present) exit 0 silently outside herdr panes; all
hook-mode exceptions are swallowed; the herdr subprocess has a 2s timeout.
The hook must never block, delay visibly, or write to stderr in Codex.

Registration safety: install/uninstall only touch entries whose command
contains the marker `herdr-codex-session-title.sh`; `hooks.json` is backed up
to `hooks.json.bak-codex-session-title` before modification; writes are
atomic (tempfile + `os.replace`).

## Testing

1. `tests/run.sh` — extract mode against fixtures: simple title, rename
   (last-line-wins), whitespace-only ignored, control-char normalization,
   unknown id, missing index file.
2. Pipe tests — synthesized hook payloads + fake `HERDR_*` env and a stub
   `HERDR_BIN_PATH` that logs arguments: verify per-event behavior
   (start clears; prompt falls back to prompt text; stop reports index title)
   and exit 0 on garbage input.
3. Live check — user opens a Codex session inside a herdr pane; title appears
   after the first turn; `/rename` updates it.

## Rollout path

Develop locally with `herdr plugin link`; later optionally publish to GitHub
and switch to `herdr plugin install <user>/herdr-codex-session-title` so both
title plugins sit side by side under `~/.config/herdr/plugins/github/`.

## Post-deploy debug (2026-09-21, first live session)

Symptom: pane title never appeared. Investigation (systematic, evidence
first) found:

1. Hooks fired and trust entries were written (config.toml
   `hooks.state` gained entries for our three commands during the session;
   loongsuite state files prove UserPromptSubmit ran).
2. **Primary root cause**: herdr 0.9.1 accepts `--title` at the CLI but the
   server silently drops it. Isolation matrix: `--title`+codex → no effect;
   `--token title=`+claude → works; `--token title=`+codex cross-pane →
   works. Fix: use the legacy `--token`/`--clear-token` syntax.
3. **Secondary**: Stop fires ~3s before `thread_name` lands in the index
   (rollout timeline: task_complete 04:46:39Z vs index updated_at
   04:46:42Z). Fix: detached 6s poller on Stop-time miss.
4. Docs confirm codex payloads DO include `prompt` (UserPromptSubmit) and
   `hook_event_name` (all events); the prompt fallback is valid.

Second live round (13:01–13:04): user restarted a session and saw the old
title persist. Reconstruction: the old session's Stop poller (6s lifetime)
outlived the session; the new session's SessionStart cleared the title, then
the old poller re-attached the old title. (The final title on the pane was
actually the NEW session's own thread_name — the user greeted again and
Codex named both sessions "回应问候".) Fix: `pane_still_ours()` — before a
late report the poller queries `herdr pane list` and aborts if the pane's
`agent_session` is now bound to a different session id. Fail-open when
herdr cannot be queried. Verified with stubbed pane-list responses: rebound
pane → no report; same-session pane → report lands.

Third round (13:09–13:12, fully autonomous repro via `herdr pane
split`/`run`/`wait-output`/`read` in a scratch pane): user still saw the
old title after reopening Codex. Root causes found:

1. **Codex sessions are lazy.** Opening the TUI does not create a session;
   SessionStart fires only when the first message is sent. The user's
   reopened Codex (rollouts 01a0c257/01a0c259 — both message-less, identical
   18KB sizes) never fired SessionStart, so the clear never ran. Fix:
   register **SessionEnd** (Codex DOES have it — confirmed in
   /etc/codex/hooks.json and official payload docs; the earlier assumption
   that it lacked SessionEnd was wrong) to clear the title on session exit.
   SessionStart clear stays as a crash backstop. Codex clamps SessionEnd
   hook timeouts to 3s.
2. **Codex fires UserPromptSubmit for its own internal title-generation
   request**, whose prompt is the template "Generate a concise,
   single-line task title of at most 36 characters..." — our prompt
   fallback displayed it as a 60-char garbage title mid-turn (this also
   explains the earlier mystery token on wP:p3). Fix: prefix filter
   INTERNAL_TITLE_PROMPT_PREFIX.

Happy path verified live in the scratch pane: UserPromptSubmit reported the
user's prompt as interim title; after the turn the poller replaced it with
the generated thread_name "列出项目文件" (~3s after Stop).

Fourth round (13:28, user report: prompt title flashes then vanishes
mid-turn): instrumented live repro on wP:p6. Codex fires SessionStart TWICE
around the first message of a lazy session (13:29:06.1 creation start,
13:29:09.6 second start ~3.5s later) with the UserPromptSubmit report
landing in between. The second start-time clear wiped the user's prompt
title, leaving a gap until the Stop poller reported the real title. Fix:
the start event no longer clears — it only re-reports a resumed session's
indexed title. SessionEnd owns cleanup; a kill-9'd session's stale title is
overwritten by the next session's first report. Verified after redeploy:
first-message prompt title persists through the turn.

Fifth round (13:33, poller instrumented live): the poller works end to end
(POLL_START → POLL_FOUND → PANE_CHECK → REPORT; prompt title "谢谢" replaced
by generated "致谢" mid-observation). Also confirmed: Codex's internal
title-generation session fires its own Stop, spawning a poller for a sid
that never appears in the index (times out harmlessly) or that the
pane-ownership guard rejects. Measured title-generation latency of 5.8s —
the 6s poll window was marginal, widened to 20s at 0.5s intervals. Turns
whose title lands later (or never — observed once) are covered by the next
hook event's index lookup.

Sixth round (13:42–13:44, user report: title appears, then vanishes after
the answer completes): instrumented live repro on wP:p7. Codex's internal
title-generation sub-session runs with its OWN session id and fires the
full hook lifecycle in the same pane: SessionStart(source=startup),
UserPromptSubmit(internal template prompt), Stop, and — ~60–80s later —
SessionEnd(reason=other). Our unconditional end-time clear wiped the live
session's title (observed 13:44:19 CLEAR(end) with the internal sid while
the real session was still working). Fix: sub-session guard — every event
now checks `pane_still_ours()` first; events whose session id is not the
pane's bound session (agent-state only binds the real one, protected by
its CODEX_THREAD_ID check) are ignored entirely, including end-time
clearing. Verified with stubbed pane-list: internal end → no clear; real
end → clear; internal prompt/stop → no report/no poller; real events
unaffected.
