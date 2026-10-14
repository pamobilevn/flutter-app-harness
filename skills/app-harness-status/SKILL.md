---
name: app-harness-status
description: Show the current app-harness pipeline state — app, phase, round, latest QA verdict, recent events — read-only.
argument-hint: ""
allowed-tools: [Read, Bash, Glob]
---

# app-harness-status

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

Read-only status reporter for the flutter-app-harness pipeline. Reads `state.md`,
`build-log.md`, and `pipeline-log.md` and prints a summary of the current pipeline state.

All file schemas (`state.md`, `build-log.md`, `pipeline-log.md`) are defined in
`docs/harness-protocol.md` — refer to that document as the single source of truth.
Do not redefine schemas here.

**This skill is strictly read-only. It must never modify state.md or any other harness file.**

Print the report in `config.md` `default_language` (labels may be translated; values stay verbatim).

---

## Input

`state.md` lives in one of two places (see **Locate the Harness** in `skills/app-harness/SKILL.md`):
`docs/harness/state.md` in the cwd (before the generator moves it, or when run from inside the app
project), or `<app_slug>/docs/harness/state.md` one level down (after the move). List both with
that skill's `find` snippet — only app-harness runs count (their `config.md` has `skip_monetize:`;
runs of the upstream `flutter-flame-harness` in the same directory are ignored):

```bash
find . -maxdepth 4 -path '*/docs/harness/state.md' 2>/dev/null | while read -r f; do
  grep -q '^skip_monetize:' "${f%state.md}config.md" 2>/dev/null && echo "$f"
done
```

- `./docs/harness/state.md` found → report that run only.
- Otherwise report **every** `<app_slug>/docs/harness/state.md` found (one report block each,
  headed by the slug) — this skill does not ask which one.

If nothing is found, print:

```
app-harness-status: no active pipeline found (no docs/harness/state.md here or in <app_slug>/).
Run /app-harness <idea> to start a new pipeline.
```

Then exit without error. Below, `docs/harness/` means the located harness directory.

---

## Procedure

### 1. Read state.md and config.md

Read `docs/harness/state.md` and extract the following fields per the schema in
`docs/harness-protocol.md` §2:

- `status` — `running` | `paused` | `completed`
- `current_phase` — name of the currently executing phase
- `current_round` — integer round counter
- `next_role` — skill role that runs next
- `pause_reason` — `""` | `rate_limit` | `manual_action` | `error`
- `updated_at` — ISO-8601 timestamp of last write
- `resume_attempts` — integer

From `docs/harness/config.md` (§1) read `app_name`, `app_slug`, `default_language`, `max_rounds`,
`mode`, and `project_path`. If it is unreadable, show `(unavailable)` for those values.

### 2. Read build-log.md (if present)

Read `docs/harness/build-log.md` per the schema in `docs/harness-protocol.md` §6. Extract the
latest row to obtain the most recent QA score (`PASS` | `FAIL` | `PARTIAL`) and the round number
it corresponds to. If the file is absent or has no data rows, set `latest_score` to `—`.

### 3. Read pipeline-log.md (if present)

Read `docs/harness/pipeline-log.md` per the schema in `docs/harness-protocol.md` §6. Extract the
last 3 rows to give a recent event summary. If the file is absent or empty, skip.

### 4. Print status report

Print the following formatted report (adapt spacing for readability):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 app-harness pipeline status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  App           : <app_name> (<app_slug>)
  Status        : <status>
  Mode          : <mode> (new | update — update shows project_path)
  Current phase : <current_phase>
  Round         : <current_round> / <max_rounds>
  Next role     : <next_role>
  Latest QA     : <latest_score>
  Last updated  : <updated_at>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If `status` is `paused`, append:

```
  ⚠  Paused — reason: <pause_reason>
  Resume attempts: <resume_attempts>
  Run /app-harness --resume (or /app-harness-resume) to continue.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If `status` is `completed`, append:

```
  Pipeline completed successfully.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If there are recent pipeline-log rows, append:

```
Recent events:
  <time>  <event>  <phase>  <details>
  <time>  <event>  <phase>  <details>
  <time>  <event>  <phase>  <details>
```

---

## Constraints

- **Read-only**: this skill must never call `Write`, `Edit`, or any Bash command that modifies a
  file. It reads `state.md`, `config.md`, `build-log.md`, and `pipeline-log.md` only.
- Do not modify `state.md` under any circumstances, including error paths.
- If any file is unreadable, skip it silently and note "(unavailable)" in the report.
