---
name: app-harness-resume
description: Resume a paused app-harness run based on pause_reason (rate_limit waits; manual_action confirms the user finished the console/review/store step; error reports), then re-dispatch the stored next_role.
argument-hint: ""
allowed-tools: [Read, Write, Edit, Bash, AskUserQuestion, Skill]
---

# app-harness-resume

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

Resume handler for the flutter-app-harness pipeline. Reads `state.md`, branches on
`pause_reason`, and re-dispatches the next phase skill when ready to continue.

All file schemas (`state.md`, `pipeline-log.md`) and state transition rules (including the
requirement that `pause_reason` is cleared to `""` when `status` is restored to `running`) are
defined in `docs/harness-protocol.md` — refer to §2 (state.md schema) and §7 (state transition
rules) as the single source of truth. Do not redefine schemas here.

Print every user-facing message in `config.md` `default_language`; the quoted messages below are
the English source text.

---

## Input

Locate the run with the **Locate the Harness** rule (and its `find` snippet) in
`skills/app-harness/SKILL.md` — only app-harness runs count (their `config.md` has `skip_monetize:`):
use `docs/harness/state.md` if it exists in the cwd (before the generator's move, or when run from
inside the app project); otherwise the non-`completed` `<dir>/docs/harness/state.md` one level
down (after the move, or an update-mode project run from its parent — then `cd <dir>`, the folder
`find` returned, which may differ from `app_slug`, so `docs/harness/...` paths resolve). If more than one
non-completed run matches, use **AskUserQuestion** to pick the app. If none exists, abort with:

```
app-harness-resume: nothing to resume — no docs/harness/state.md found here or in <app_slug>/.
Run /app-harness <idea> to start a new pipeline.
```

Read `state.md` per the schema in `docs/harness-protocol.md` §2 and extract:

- `status` — expected `paused`; if `running` or `completed`, print a note and exit (nothing to resume).
- `pause_reason` — `rate_limit` | `manual_action` | `error`
- `next_role` — role to dispatch after resuming
- `resume_attempts` — integer; will be incremented on successful resume
- `current_phase`, `updated_at` — for logging

If `status` is `running`:

```
app-harness-resume: pipeline is already running (status: running, next_role: <next_role>).
No resume needed.
```

If `status` is `completed`:

```
app-harness-resume: pipeline is already completed. Nothing to resume.
```

---

## Branch on pause_reason

### rate_limit

`pause_reason: rate_limit` means the pipeline hit an API rate limit and paused automatically.

**Procedure:**

1. Print:
   ```
   Pipeline paused due to rate limit (rate_limit).
   Checking whether the rate-limit window has passed...
   ```
2. Read `updated_at` from `state.md`. Calculate elapsed time since that timestamp using Bash
   (`date` command). If elapsed time is less than 60 seconds, print a warning:
   ```
   Warning: only <N> seconds have elapsed since the pause. The rate-limit window may not
   have passed yet. Proceeding anyway — if another rate limit is hit, the pipeline will
   pause again.
   ```
3. Proceed to **Resume execution** below.

### manual_action

`pause_reason: manual_action` means the pipeline requires a manual step from the user before
it can continue. The specific action is recorded in the `pause` event row of `pipeline-log.md`.
The pausing skill already stored the role to run next — resume never changes `next_role`:

| Paused by | Manual step | Stored `next_role` → what resume dispatches |
|---|---|---|
| `evaluator` (post-QA human-review gate, `auto_deploy: false`) | run and approve the built app (`flutter run` in the app project; QA screenshots + `feedback/round-<N>-qa.md`) | `monetize` (or `build` when `skip_monetize: true`) |
| `monetize` (console steps) | create the AdMob apps / ad units, or the IAP products in App Store Connect + Play Console, and have the IDs ready | `monetize` — re-dispatched so it continues where it paused |
| `submit` (`metadata-done`) | finish the console-only store steps and press Submit for Review | `retro` |
| `audit` (update mode: nothing selected, dirty git tree, or core idea unconfirmed) | answer the audit's question / commit or stash changes | `audit` — re-dispatched to finish the change request (or `plan` if it already completed) |
| any other phase (user deferred a question) | answer what the phase asked | that phase's stored `next_role` |

**Procedure:**

1. Read `docs/harness/pipeline-log.md` per `docs/harness-protocol.md` §6. Find the most recent
   `pause` event row to extract the details string describing what manual action was needed.
   If the log is unavailable, use a generic prompt.

2. Use **AskUserQuestion** to confirm the user has completed the required steps:
   ```
   The pipeline was paused for a manual action.
   Last recorded reason: <details from pipeline-log, or "see docs/harness/pipeline-log.md">

   Have you completed the required steps? (yes / no / describe what's pending)
   ```

3. If the user answers `no` or describes pending work:
   - Print a summary of what they said.
   - Abort: do NOT resume. Exit with:
     ```
     app-harness-resume: manual action not yet complete. Run /app-harness-resume again
     when ready.
     ```

4. If the user answers `yes`:
   - Proceed to **Resume execution** below.

### error

`pause_reason: error` means the pipeline encountered an unrecoverable error in a phase skill.

**Procedure:**

1. Read `docs/harness/pipeline-log.md` per `docs/harness-protocol.md` §6. Find the most recent
   `error` event row to extract the error details.

2. Print a clear error report:
   ```
   Pipeline paused due to an error.
   Phase     : <current_phase>
   Next role : <next_role>
   Error     : <details from pipeline-log, or "see docs/harness/pipeline-log.md">

   You must investigate and fix the error before resuming.
   Common fixes:
     - If it is a Flutter/Dart compile error, fix the code and run `flutter analyze`.
     - If it is a missing file, create or restore it.
     - If it is a credential error, check docs/harness/config.md and the credentials_dir.
   ```

3. Use **AskUserQuestion**:
   ```
   Have you resolved the error and are ready to retry? (yes / no)
   ```

4. If the user answers `no`:
   - Abort: do NOT resume. Exit with:
     ```
     app-harness-resume: error not yet resolved. Run /app-harness-resume again when fixed.
     ```

5. If the user answers `yes`:
   - Proceed to **Resume execution** below.

### Unknown pause_reason

If `pause_reason` is empty or an unrecognised value, print:

```
app-harness-resume: unexpected pause_reason "<value>" in state.md.
Expected one of: rate_limit, manual_action, error.
Please inspect docs/harness/state.md manually and correct it before resuming.
```

Then abort without modifying any files.

---

## Resume execution

Reached only after the appropriate branch above confirms it is safe to continue.

Per `docs/harness-protocol.md` §7 rule 4: when `status` is set back to `running`,
`resume_attempts` must be incremented, and per §7 rule 8: `pause_reason` must be cleared
to `""` by this skill.

### 1. Update state.md

Use **Edit** to update `docs/harness/state.md` with the following field changes (leave all other
keys — including `next_role` — unchanged):

```yaml
status: running
pause_reason: ""
resume_attempts: <previous_value + 1>
updated_at: "<ISO-8601 UTC now>"
```

Both `status: running` and `pause_reason: ""` must be written in the same Edit call (atomic per
`docs/harness-protocol.md` §7 rule 1).

### 2. Append to pipeline-log.md

Append one row to `docs/harness/pipeline-log.md` per the schema in `docs/harness-protocol.md` §6:

```
| <ISO-8601 UTC now> | resume | <current_phase> | resume_attempts=<new_value>; was paused for <pause_reason> |
```

### 3. Dispatch next_role

Read `next_role` from the (now-updated) `state.md` and dispatch:

```
Skill("app-harness-<next_role>")
```

Valid `next_role` values are listed in the transition table in
`docs/harness-protocol.md` §7. In update mode (`config.mode: update`) the run lives in the existing
project (`project_path`) and may resume at `audit`; dispatch it like any other role. `monetize` is a normal dispatchable role and is handled like any
other `next_role` — dispatch `Skill("app-harness-monetize")` without any special boundary check.

If `next_role` is `generator`, the generator resumes safely on its own: it reads `checkpoint` from
`state.md` (§2) and skips the sub-phases whose HARD GATE already passed, so resume needs no special
handling here — just dispatch it.

After the dispatched skill returns, **re-enter the orchestrator's Dispatch Loop**
(`skills/app-harness/SKILL.md`): locate the harness again, re-read `state.md`, and keep
dispatching `next_role` until `status` is `paused` or `completed` — e.g. a resume after the
review gate runs monetize → build → screenshot → submit, not monetize alone.

If `next_role` is empty or unknown, abort with:

```
app-harness-resume: cannot dispatch — next_role is "<value>".
Inspect docs/harness/state.md and set a valid next_role before retrying.
```

---

## Error handling

- If `state.md` becomes unreadable mid-execution (e.g. concurrent write), abort immediately
  and do not write partial state changes.
- Never dispatch `Skill(...)` before `state.md` has been successfully updated to
  `status: running` with `pause_reason: ""`. Dispatch always follows the state write.
