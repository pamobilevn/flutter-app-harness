---
name: app-harness
description: Orchestrator — bootstrap a production Flutter mobile app pipeline (idea→store-ready app, or --audit an existing app to fix and extend it) and dispatch each phase skill. Use when starting or continuing an app-harness run.
argument-hint: "[app idea | change hint] [--audit [path]] [--strict] [--rounds N] [--skip-research] [--skip-monetize] [--auto-idea] [--auto-deploy] [--resume]"
allowed-tools: [Agent, Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, Skill]
---

# app-harness Orchestrator

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

This harness builds mobile apps; for Flame games use the upstream `flutter-flame-harness` plugin instead.

This skill bootstraps and drives the full Flutter app pipeline from idea to a store-ready app —
or, in **update mode** (`--audit`), from an existing Flutter project to an improved release that
keeps the app's core idea while fixing and extending it.
All file schemas (`config.md`, `state.md`, `contract.md`, log tables) and the phase transition table
are defined in `docs/harness-protocol.md` — refer to that document as the single source of truth.
Do not redefine schemas here.

Every user-facing message is printed in `config.md` `default_language` (before `config.md` exists:
the language the user is writing in). The quoted messages below are the English source text.

---

## Argument Parsing

Parse the invocation arguments before doing anything else.

| Argument | Config key (in `config.md`) | Default |
|---|---|---|
| `[app idea]` | `app_idea` | optional — if omitted, research generates & recommends ideas from scratch |
| `--audit [path]` | `mode: update`, `project_path: <abs path>` | off (`mode: new`, `project_path: ""`); path defaults to the cwd |
| `--strict` | `strict_mode: true` | `false` |
| `--rounds N` | `max_rounds: N` | `3` |
| `--skip-research` | `skip_research: true` | `false` |
| `--skip-monetize` | `skip_monetize: true` | `false` |
| `--auto-idea` | `auto_idea: true` | `false` |
| `--auto-deploy` | `auto_deploy: true` | `false` |
| `--credentials-dir <path>` | `credentials_dir` | `<projects-dir>/credentials`, else `~/AndroidStudioProjects/credentials` |
| `--resume` | (delegates to resume handler; see Resume section) | — |

**Guard:** if `--skip-research` is set AND no idea is given, abort immediately with:
`app-harness: --skip-research needs an app idea (nothing to build without research or an idea).`

Key-to-file mapping follows the `config.md` schema in `docs/harness-protocol.md` Section 1.

- `--strict` → set `strict_mode: true` in `config.md`
- `--rounds N` → set `max_rounds: N` in `config.md`
- `--skip-research` → set `skip_research: true` in `config.md`. On first run `next_role` is still
  `research` (NOT `plan`): the research skill honors `skip_research` by skipping market discovery and
  idea generation, but it still runs the App Store 4.2 minimum-functionality and 4.3 spam/copycat
  checks on the provided idea and writes the research spec — so those checks are never silently
  skipped.
- `--skip-monetize` → set `skip_monetize: true` in `config.md`: no ads, no IAP. The monetize phase is
  skipped entirely and the evaluator's PASS hands off straight to `build` (protocol §7 rule 9).
- `--auto-idea` → set `auto_idea: true` in `config.md`. The research skill then auto-scores its
  generated concepts and selects the best WITHOUT asking the user. No effect with `--skip-research`
  (which already takes the idea verbatim — nothing to select).
- `--auto-deploy` → set `auto_deploy: true` in `config.md`. Skips the post-QA human-review pause:
  on QA PASS the pipeline continues straight to deploy (monetize→build→screenshot→submit) without
  stopping for the user to run/approve the app. Default `false` — by default the harness PAUSES
  after QA so the user can check the built app before deploy. (`--auto-idea --auto-deploy` together
  = fully hands-off idea→deploy; the monetize phase then resolves `monetization.iap` to `false`
  without asking, per protocol §1 Key Notes.)
- `--resume` → skip bootstrap entirely, delegate straight to `app-harness-resume` (see Resume)
- `--audit [path]` → **update mode** for an existing Flutter project (protocol §1 `mode`, §3
  update-mode overrides, §7). Resolve `path` (default `.`) to an absolute path, verify it has
  `pubspec.yaml` + `lib/`, then **`cd` into it** — in update mode the projects dir IS the app project,
  so `docs/harness/` is bootstrapped inside it and never moved. Set `mode: update`,
  `project_path: <abs path>`. `next_role` starts at `audit` (not `research`). A positional argument
  is a **change hint**, not an idea: write it to `app_idea` — audit reads it as the user's requested
  change, then replaces `app_idea` with the locked core concept. `--skip-research` has no effect.
  To continue later, run `/app-harness --resume` from the project directory.
  **Re-audit:** if the project already holds an app-harness run whose `status` is `completed` (a
  previous update cycle), archive it first — `mkdir -p docs/harness-archive && git mv docs/harness
  docs/harness-archive/<YYYYMMDD>` (plain `mv` if untracked) — then bootstrap fresh. A non-completed
  run is continued instead (say so); never archive an unfinished run without asking.

---

## Locate the Harness

The **projects dir** is the directory bootstrap ran in (the cwd of the first `/app-harness` call):
bootstrap writes `docs/harness/` there, and (new mode only) the generator later creates the Flutter project at
`<projects-dir>/<app_slug>` and **moves** `docs/harness/` into it. From then on the app project is
`<projects-dir>/<app_slug>` and the projects dir is its **parent** — even after the `cd` below. So
`state.md` lives in one of two places:

| Location | When |
|---|---|
| `docs/harness/state.md` | before the generator's move — or the cwd is already the app project |
| `<app_slug>/docs/harness/state.md` | after the generator's move (cwd is the projects dir) |

`app_slug` can't be read first (`config.md` moves too), so list both candidates with their status.
Only app-harness runs count — their `config.md` has `skip_monetize:` (protocol §1).
Runs of the upstream `flutter-flame-harness` in the same projects dir use the same paths and are skipped:

```bash
find . -maxdepth 4 -path '*/docs/harness/state.md' 2>/dev/null | while read -r f; do
  grep -q '^skip_monetize:' "${f%state.md}config.md" 2>/dev/null || continue
  echo "$f $(sed -n 's/^status:[[:space:]]*//p' "$f")"
done
```

Resolution:

1. `./docs/harness/state.md` is listed → use it (any status). The app root is `.`. (If
   `./docs/harness/` exists but is NOT listed, it belongs to another harness — abort rather than
   bootstrap over it: "docs/harness/ here is not an app-harness run — start from another directory.")
2. Otherwise consider the `./<dir>/docs/harness/state.md` matches, **ignoring `completed` ones**
   (finished sibling apps in the same projects dir must not block a new run). `<dir>` is the folder
   `find` returned — usually `<app_slug>`, but an update-mode project folder may be named anything:
   - exactly one → use it; the app root is `<dir>/`. `cd <dir>` before dispatching so every
     phase skill's `docs/harness/...` paths resolve (the generator itself `cd`s into the project after
     the move).
   - more than one → **AskUserQuestion** which app to continue (list slug + status for each).
3. Nothing usable → no active pipeline (bootstrap on a normal run; abort on `--resume`).

Re-run this resolution at the **start of every dispatch-loop iteration**: the generator moves
`docs/harness/` during its own dispatch, so a path resolved before that dispatch goes stale.

---

## Bootstrap (First Run)

Bootstrap runs only when Locate the Harness finds no usable `state.md`. It writes into the projects
dir (cwd).

### 1. Create directory tree

```
docs/harness/
docs/harness/handoff/
docs/harness/feedback/
docs/harness/specs/
docs/harness/plans/
```

### 2. Write `docs/harness/config.md`

Determine `credentials_dir`: use the `--credentials-dir <path>` flag if given, else a `credentials/`
directory in the projects dir (`<projects-dir>/credentials`), else `~/AndroidStudioProjects/credentials`.
Write the resolved absolute path. **Never hard-code a company, developer name, contact, or signing
identity into the schema or skills** — every such value is the *user's own* and must be sourced at
runtime.

Look for `<credentials_dir>/store-metadata.md` and read the `developer`, `ios`, and `android` blocks
from it. **If that file does not exist** (e.g. a new user who just installed the plugin), do NOT fall
back to any placeholder/sample identity — instead **ask the user** for their own values (company,
first/last name, support email, contact phone, privacy-policy URL, support/marketing URL, copyright;
and — only when a deploy is intended — Apple `team_id`/`asc_key_id`/`asc_issuer_id`/key path and the
Android keystore path/alias). Offer to save them to `<credentials_dir>/store-metadata.md` for reuse.
The signing/store-credential answers may be deferred (left blank) until the build/submit phase if the
user only wants to generate and run the app now.

Then write `docs/harness/config.md` with **every key** of the schema in `docs/harness-protocol.md`
Section 1, populated as follows:

- `mode` — `update` with `--audit`, else `new`. `project_path` — the absolute project path with `--audit`, else `""`.
- `architecture` — `riverpod` in new mode; in update mode write `""` (audit records the detected one).
- `baseline` — update mode only, all zero/blank; audit fills it.
- **Update mode:** leave `app_name`, `app_slug`, `bundle_id`, `locales`, `orientation`, `device_family`,
  `backend`, `app_category`, `play_category` blank/defaults — audit reads them from the existing
  project. Never derive a new bundle id for an existing app.
- `app_idea` — from the positional argument; if no positional argument was given, write `app_idea: ""` (blank is valid — research will generate and recommend concepts). Do NOT abort on an empty idea.
- `app_name` — derive a short display name from the idea (ask the user if ambiguous); if NO idea was given, write `app_name: ""` — the plan phase sets the name after research confirms the concept.
- `app_slug` — kebab-case of `app_name`; write `app_slug: ""` if `app_name` is blank.
- `bundle_id` — `com.<company>.<id>` where `<id>` is `app_slug` with hyphens/underscores removed, lowercase (bundle-id segments must be `[a-z0-9]+`; hyphens/underscores break signing). Blank if `app_slug` is blank.
- `default_language` — the ISO 639-1 code of the language the user is conversing in, detected from the user's request/messages (any language: a Vietnamese request → `vi`, Korean → `ko`, Japanese → `ja`, English → `en`). If there's no conversational signal yet (e.g. a bare `/app-harness` with no idea), **fall back to the OS locale** and take the 2-letter language of the first entry; only default to `en` if even that is unavailable:
  ```bash
  l=$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p | tr -d ' ",')  # e.g. vi-VN
  [ -n "$l" ] || l=$LANG                                                      # e.g. vi_VN.UTF-8
  l=$(printf %s "${l%%[-_.]*}" | tr 'A-Z' 'a-z')
  case $l in ""|c|posix) l=en;; esac; echo "$l"
  ```
  The whole pipeline (PRD, copy, primary ARB file) is authored in this language.
- `locales` — `[<default_language>]`; the plan phase finalizes it (adds `en` when `default_language` ≠ `en`, plus any PRD extras).
- `app_category: ""`, `play_category: ""` — blank; set by plan.
- `orientation: portrait`, `device_family: phone`, `backend: local` — defaults; plan may change them.
- `strict_mode`, `max_rounds`, `skip_research`, `skip_monetize`, `auto_idea`, `auto_deploy` — from flags (defaults per table above)
- `developer`, `ios`, `android` — from `<credentials_dir>/store-metadata.md` (or the user's answers)
- `credentials_dir` — the resolved path above
- `monetization` — `admob_enabled: true` (`false` when `skip_monetize`), `ios_app_id: ""`, `android_app_id: ""`, `ad_units: []`, `iap: ask` (`false` when `skip_monetize` — no phase will ask), `products: []`. The monetize phase fills it.

Do NOT hard-code credential values; always read them from `credentials_dir`.

### 3. Write `docs/harness/state.md`

Write `state.md` per the schema in `docs/harness-protocol.md` §2. Initial values: `status: running`, `current_phase: (init)`, `current_round: 1`, `next_role: research` in new mode or `next_role: audit` in update mode (new mode always starts at `research` — the research skill handles `skip_research` internally, still running the 4.2/4.3 checks and writing the spec), `pause_reason: ""`, `resume_attempts: 0`, `checkpoint: ""`, and `created_at`/`updated_at` set to the current ISO-8601 UTC timestamp.

### 4. Append INIT row to `docs/harness/pipeline-log.md`

Create `pipeline-log.md` if absent and append:

```
| <ISO-8601 UTC now> | start | bootstrap | config.md written |
```

Follow the `pipeline-log.md` schema in `docs/harness-protocol.md` Section 6.

---

## Dispatch Loop

After bootstrap (or when a usable `state.md` already exists and `--resume` was not passed), enter
the dispatch loop. If this session is not running on Sonnet, say once: "Tip: run the harness on
Sonnet (`/model`) — phases pull in Haiku and Opus for bounded steps (protocol §8)." Then continue;
never wait for a model change.

### Reading `next_role`

Locate the harness (see above), then read its `state.md` and extract `next_role` and `status`.

- If `status: completed` — print a completion summary and exit.
- If `status: paused` — print the `pause_reason` and any pending manual steps, then instruct the user to run with `--resume`. Do not continue automatically.

If an idea argument was given but an existing non-completed run was found, say which app is being
continued (`app_name` / `app_slug` from its `config.md`) — a new app starts from a projects dir with
no active run.

### Dispatch

For any `next_role` value in the known set, invoke the corresponding phase skill:

```
Skill("app-harness-<next_role>")
```

Valid `next_role` values and their skills (per transition table in `docs/harness-protocol.md`
Section 7):

| next_role | Skill invoked |
|---|---|
| `audit` | `app-harness-audit` |
| `research` | `app-harness-research` |
| `plan` | `app-harness-plan` |
| `design` | `app-harness-design` |
| `contract` | `app-harness-contract` |
| `generator` | `app-harness-generator` |
| `evaluator` | `app-harness-evaluator` |
| `monetize` | `app-harness-monetize` |
| `build` | `app-harness-build` |
| `screenshot` | `app-harness-screenshot` |
| `submit` | `app-harness-submit` |
| `retro` | `app-harness-retro` |

Each phase skill is responsible for updating `state.md` (including setting `next_role` to the
next phase) before returning, following the transition rules in `docs/harness-protocol.md` Section 7.

After each skill returns, **locate the harness again** (the generator may have moved it into
`<app_slug>/`), re-read `state.md`, and verify that `updated_at`, `next_role`, or `status` changed
compared to the values before dispatch (a phase that paused counts as progress). If none changed,
abort immediately with:
"orchestrator: phase skill `<role>` returned without updating state.md — halting to avoid a
redispatch loop."

When `status: paused` (e.g. after the evaluator's post-QA review gate, the monetize console steps, or
`submit` sets `pause_reason: manual_action`), print the pending manual steps from `state.md` and the
latest `pause` row of `pipeline-log.md`, instruct the user to complete them, then run with
`--resume`. Do not continue automatically.

Then repeat the dispatch check. Continue until:
- `status: completed` (set by `retro` — print a completion summary and exit)
- `status: paused` (print pause_reason and instruct user to run with `--resume`, then exit)

---

## Resume

If `--resume` is passed as an argument, first verify that a `state.md` exists in either location
from Locate the Harness. If none exists, abort with: "Nothing to resume — no state.md found. Run
without --resume to start a new pipeline."

Otherwise, skip all bootstrap and dispatch logic and delegate immediately to the resume skill:

```
Skill("app-harness-resume")
```

`app-harness-resume` is responsible for picking the run (same Locate the Harness rule), reading
`state.md`, incrementing `resume_attempts`, restoring `status: running`, and re-entering the
dispatch loop.

Do not modify `state.md` before delegating to the resume skill.

---

## Error Handling

- If `config.md` is missing next to a located `state.md` on a non-first run, abort with a clear error message.
- If an invoked phase skill exits with an error or sets `status: paused` with
  `pause_reason: error`, stop the loop and report the failure to the user.
- If `next_role` contains a value not in the known set (audit, research, plan, design, contract, generator, evaluator, monetize, build, screenshot, submit, retro), abort with an "unknown next_role" error so the user can investigate `state.md`.
