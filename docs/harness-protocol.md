# Harness Protocol Reference

This file is the single source of truth for all file schemas, state keys, and the phase transition
state machine used by every phase skill. Skills cite this document rather than redefining schemas
(DRY principle).

Companion source: [`docs/app-gotchas.md`](app-gotchas.md) — the required robustness patterns
(async states, network, lifecycle, forms, accessibility, persistence, build/platform, store review)
the generator emits and the contract/evaluator enforce. Cite it the same way; do not restate it.

Target: a production Flutter **mobile application**.
(Flame-engine titles belong to the upstream `flutter-flame-harness`.) Fixed stack defaults:

| Concern | Default | Notes |
|---|---|---|
| State management | **Riverpod** (`flutter_riverpod`, `Notifier` / `AsyncNotifier`) | no codegen required; `riverpod_generator` optional |
| Layout | **feature-first** (`lib/features/<feature>/{data,presentation}`) | `domain/` only when logic is shared across features |
| Navigation | **go_router** | one `GoRouter` in `lib/app/router.dart` |
| Backend | **local-first** (`backend: local`) | plan may opt into `rest` or `firebase` only when the PRD needs it |
| Monetization | **AdMob, all formats** (banner / native / interstitial / app-open / rewarded) | the monetize phase then **asks** whether to add IAP / subscriptions |
| Deploy | plugin's own **fastlane** templates | `templates/fastlane/*` |
| Device tests | **Maestro** flows committed in the app (`.maestro/`) | §3 Device test suite; `integration_test` only when `maestro` is not installed |

Two entry modes: **new** (`/app-harness "<idea>"` — research → … → a new app) and **update**
(`/app-harness --audit [path]` — audit an existing Flutter project, keep its core idea, fix and extend
it). In update mode the stack defaults above do not apply to existing code: the harness follows the
project's detected `architecture` and never migrates it unless the change request says so.

---

## 1. `config.md` Schema

Each app's `docs/harness/config.md` must be valid YAML containing the following keys:

```yaml
mode: new                 # new | update — bootstrap sets update for `--audit [path]`
project_path: ""          # update: absolute path of the existing project (docs/harness lives inside it from bootstrap)
architecture: riverpod    # new: riverpod. update: detected by audit — riverpod | bloc | provider | getx | mobx | setstate | other:<name>
baseline:                 # update only — written by audit, the "no worse than" reference for gates
  analyze_issues: 0
  tests_passed: 0
  tests_failed: 0
  version: ""           # pubspec version at audit time
  commit: ""            # git HEAD at audit time — base for "files created or modified by the harness"
app_idea: ""  # blank => research generates & recommends concepts; populated after research confirms choice
app_name: "<display name>"
app_slug: "<kebab-case identifier>"
bundle_id: "com.<company>.<id>"  # <id> = app_slug with hyphens/underscores stripped (segments must be [a-z0-9]+)
bundle_id_android: ""     # update mode only: the shipped Android applicationId when it differs from bundle_id
default_language: en      # ISO 639-1 code of the language the user converses in (en, ko, vi, ja, ...)
locales: [en]             # set by plan: default_language, plus en when default_language != en, plus any PRD extras
app_category: ""          # set by plan: App Store primary category id (e.g. PRODUCTIVITY, UTILITIES, HEALTH_AND_FITNESS)
play_category: ""         # set by plan: Google Play category (e.g. PRODUCTIVITY, TOOLS, HEALTH_AND_FITNESS)
orientation: portrait     # portrait | landscape | all — set by plan
device_family: phone      # phone | universal — set by plan; universal = iPad supported (all iPad orientations required)
backend: local            # local | rest | firebase — set by plan (default local)
strict_mode: false        # true => evaluator runs quality scoring + edge-case sweep
max_rounds: 3             # generator/evaluator loop limit
skip_research: false      # true => research takes app_idea verbatim (still runs the 4.2/4.3 check)
skip_monetize: false      # true => the monetize phase does not run (new: no ads/IAP; update: existing monetization kept as is)
auto_idea: false          # true => research auto-selects the best concept without asking
auto_deploy: false        # true => skip the post-QA human-review pause; PASS continues straight to deploy

# developer/ios/android below are PLACEHOLDERS. Every value is the USER'S OWN, sourced at
# bootstrap from <credentials_dir>/store-metadata.md (or asked interactively if that file is
# absent). Never commit real names, emails, phones, company names, or signing identities here.
developer:
  company: <company>      # reverse-DNS-safe, lowercase [a-z0-9] — used in the bundle id
  first_name: <first-name>     # App Review contact + Play contact
  last_name: <last-name>
  email: <support-email>
  phone: "<contact-phone>"
  privacy: <privacy-policy-url>   # privacy policy URL (both stores)
  homepage: <support-and-marketing-url>
  copyright: "Copyright <year>. <company> all rights reserved."

ios:
  team_id: <apple-team-id>
  asc_key_id: <asc-key-id>
  asc_issuer_id: <asc-issuer-id>
  asc_private_key_path: "<absolute path to AuthKey_<asc_key_id>.p8>"

android:
  keystore_path: "<absolute path to upload.jks>"
  key_alias: upload

credentials_dir: <projects-dir>/credentials

monetization:
  admob_enabled: true    # "this app ships AdMob ads" — the key every downstream check uses (new mode: false when skip_monetize; update: as audit detected)
  ios_app_id: ""         # ca-app-pub-XXXX~YYYY
  android_app_id: ""     # ca-app-pub-XXXX~ZZZZ
  ad_units: []           # list of { key, format, placement, ios_id, android_id }
                         #   format: banner | native | interstitial | app_open | rewarded
  iap: ask               # ask | true | false — "this app ships IAP"; monetize asks then records; update mode: audit records what ships
  products: []           # list of { id, type, entitlement, price_hint }
                         #   type: consumable | non_consumable | subscription
```

### Key Notes

- `bundle_id` must follow `com.<company>.<id>`, where `<id>` is `app_slug` with all hyphens and
  underscores removed, **lowercase** (each reverse-DNS segment must match `[a-z0-9]+`). E.g.
  `habit-tracker` → `com.<company>.habittracker`. It must be **byte-for-byte identical** on both
  platforms — iOS `PRODUCT_BUNDLE_IDENTIFIER` == Android `applicationId` (+ `namespace`) == this value.
- `default_language` is any ISO 639-1 code; the PRD, copy, and the primary ARB file are authored in it.
- `credentials_dir` is the shared directory for all credential files (keystores, p8 keys, etc.).
  Skills must not hard-code credential paths; they read `credentials_dir` from `config.md`.
- `device_family: universal` obliges iPad support: all four iPad orientations (or
  `UIRequiresFullScreen`), iPad screenshots, and layouts that adapt to wide screens.
- `backend: local` makes gate R2 (network resilience) N/A unless the app still calls the network.
- `monetization.iap: ask` is resolved to `true`/`false` by the monetize phase; with `auto_idea` +
  `auto_deploy` (fully hands-off) it resolves to `false` without asking.
- `max_rounds` controls how many generator→evaluator cycles are allowed before a forced judgment.
- `mode: update` — `app_idea` first holds the user's change hint, then audit replaces it with the locked
  core concept. Identity keys (`app_name`, `app_slug`, `bundle_id`, `orientation`, `device_family`,
  `locales`, `backend`, categories) are read from the existing project by audit and are never
  re-derived; `bundle_id` never changes (a new id is a new store app). If the shipped iOS and Android ids
  differ (or are not lowercase), audit records iOS in `bundle_id` and Android in `bundle_id_android`;
  that divergence is an accepted exception, never a fix item.
- **Monetization keys mean what ships.** Build (ATT / SKAdNetwork), submit (privacy declarations),
  contract/evaluator (R12, consent order), and screenshot gating read `monetization.admob_enabled` and
  `monetization.iap` — never `skip_monetize`, which only controls whether the monetize phase runs.

---

## 2. `state.md` Schema

Each app's `docs/harness/state.md` tracks live execution state. It must be valid YAML.

```yaml
status: running          # running | paused | completed
current_phase: research  # name of the phase currently executing
current_round: 1         # integer; increments each generator→evaluator cycle
next_role: evaluator     # role that runs next (skill name without the app-harness- prefix)
pause_reason: ""         # "" | rate_limit | manual_action | error
created_at: "2026-10-14T00:00:00Z"   # ISO-8601; set by bootstrap, never changed
updated_at: "2026-10-14T00:00:00Z"   # ISO-8601; updated by every skill on write
resume_attempts: 0       # integer; incremented each time the harness resumes after a pause
checkpoint: ""           # "" | 5a | 5b | 5c — last generator sub-phase whose HARD GATE passed
```

### Key Definitions

| Key | Type | Allowed Values | Written By |
|---|---|---|---|
| `status` | enum | `running` \| `paused` \| `completed` | every skill |
| `current_phase` | string | phase name (see transition table) | every skill |
| `current_round` | integer | ≥ 1 | contract, evaluator |
| `next_role` | string | skill role name | every skill |
| `pause_reason` | enum | `""` \| `rate_limit` \| `manual_action` \| `error` | every skill |
| `created_at` | ISO-8601 string | — | bootstrap only |
| `updated_at` | ISO-8601 string | — | every skill on write |
| `resume_attempts` | integer | ≥ 0 | resume handler |
| `checkpoint` | enum | `""` \| `5a` \| `5b` \| `5c` | generator (evaluator resets) |

**`checkpoint`** lets the generator re-enter safely after a mid-phase crash/pause: it records the last
sub-phase whose HARD GATE passed. On re-entry within the same round the generator skips sub-phases
`≤ checkpoint` and resumes at the next one. It is reset to `""` when a new round starts (evaluator
FAIL → generator round N+1 does a fresh feedback-driven pass).

**Note:** Timestamps are written by skills at runtime, not by scripts.

---

## 3. `contract.md` Layout

`docs/harness/contract.md` is written before coding begins.

```markdown
# Contract — <app_name>

## Mandatory Hard Gates

These criteria are non-negotiable. A FAIL on any one of these results in an immediate FAIL verdict,
regardless of other passing criteria.

1. `flutter analyze` returns zero issues.
2. `flutter test` — all tests pass.
3. No TODO, stub, placeholder, or fake data in production code under `lib/` (grep-checkable).
4. No magic values — colors/spacing/typography come from `lib/core/theme/`, tunable constants from `lib/core/config/app_config.dart`.
5. Data is modeled — typed models behind repositories; widgets never touch storage/network directly; seed content is data, not widget literals.
6. Localization complete for all configured locales — no hard-coded user-visible strings, no missing l10n keys.
7. Every primary user flow in the PRD works end to end, and user data survives an app restart.
8. Runs on a simulator/emulator with zero crashes and zero console errors.

## Platform-Robustness Gates

<!-- R1–R12 per docs/app-gotchas.md; each marked REQUIRED or N/A (with a one-line reason). -->

## Functional Criteria (per app)

<!-- Contract skill adds app-specific acceptance criteria here before marking AGREED. -->
<!-- Example:
- Adding a habit from the Home FAB shows it in the list within 300 ms and persists after restart.
- Marking a habit done increments its streak by exactly 1 per calendar day.
- Empty state shows the localized "No habits yet" message and a "Create habit" button.
-->

## Status: AGREED
```

### Platform-Robustness Gate IDs (fixed — skills cite these IDs, never renumber)

| ID | Name | Applies |
|---|---|---|
| R1 | Async UI states (loading / empty / error+retry) | always |
| R2 | Network resilience (timeout, retry/backoff, offline) | `backend ≠ local` or any network call |
| R3 | Lifecycle (persist on pause, refresh on resume, dispose) | always |
| R4 | Forms & keyboard (validation, insets, input actions) | app has text input |
| R5 | App branding (icon, splash, display name) | always |
| R6 | Native config (orientation, device family, export compliance, back nav, bundle id) | always |
| R7 | Assets & CI (no dangling assets, CI workflow) | always |
| R8 | Store graphics (Play hi-res icon + feature graphic, iOS screenshots) | always |
| R9 | Persistence & data safety (repositories, versioned schema, secrets in secure storage) | always |
| R10 | Accessibility (text scaling, Semantics, tap targets, contrast, reduce motion) | always |
| R11 | Test depth (unit + widget + Maestro device flows) | always |
| R12 | Permissions & privacy (in-context requests, denied handling, localized usage strings) | app uses any runtime permission, or `monetization.admob_enabled: true` (ATT) |

### Update-mode gate overrides (`mode: update`)

Legacy code is not held to greenfield gates; changed code is. Contract and evaluator apply:

| Gate | Update-mode rule |
|---|---|
| HG1 analyze | no NEW issues: total ≤ `baseline.analyze_issues`, and zero issues in files the harness created or modified |
| HG2 test | all tests pass; each baseline failure is a fix item unless listed on the audit spec's `Accepted baseline failures (skip:)` line |
| HG3 stub grep | files the harness created or modified |
| HG4 / HG5 | new and changed code |
| HG6 l10n | new strings follow the project's localization; N/A if the project has none and the change request does not add it |
| HG7 flows | every `KEEP` flow of the baseline PRD (regression — the audit's baseline Maestro flows pass against the new build) + every `CHANGE`/`NEW` flow works end to end; data created before the update still loads after it |
| HG8 | unchanged |
| R1–R12 | REQUIRED for new/changed code; audit gap findings apply only when the user selected them in the change request |

Files "created or modified by the harness" (one canonical command, empty set guarded by every consumer):

```bash
CHANGED=$({ git diff --name-only --diff-filter=d <baseline.commit>; git ls-files --others --exclude-standard; } | grep '\.dart$' | sort -u)
[ -z "$CHANGED" ] || flutter analyze $CHANGED
```

Baseline screenshots are named per flow: `docs/harness/screenshots/baseline-F<n>-<screen>.png`.

### Device test suite (`.maestro/`)

Every on-device check a verdict rests on is a Maestro flow committed in the app repo, so each round
re-runs the same checks and they outlive the session. Ad-hoc simulator taps are for exploring only:
a finding that decides a verdict is written down as a flow. Templates: `templates/maestro/`;
pitfalls: `docs/app-gotchas.md` → Device flow tests (Maestro).

```
.maestro/
  suite.sh                         one flow at a time; screenshots + device log → docs/harness/screenshots/
  subflows/ready.yaml              closes ATT / consent / ad / StoreKit interruptions, waits for the first screen
  flows/F<n>_<slug>.yaml           one per PRD primary flow (F<n> = PRD flow id) — tags: flow [, ui]
  flows/regress_r<N>_<slug>.yaml   a device-visible bug found in round N, reproduced — never weakened or deleted
```

| Who | Writes / runs |
|---|---|
| generator | 5c.8 writes one `F<n>` flow per primary flow; every round leaves the whole suite green |
| evaluator | Step 7 runs the suite (`light`, then `ui` flows in `dark` and `xxxl`); writes a `regress_r<N>` flow per device-visible bug |
| audit (update) | writes `F<n>` flows for the baseline flows and runs them (`baseline`); an existing `.maestro/` is extended, never replaced |

Screenshot `takeScreenshot: F<n>-<screen>` lands as `docs/harness/screenshots/<prefix>-F<n>-<screen>.png`,
the device log as `<prefix>-device.log`. Prefixes: `baseline` (audit),
`round-<N>-<ios|android|ipad>[-dark|-xxxl]` (evaluator).

Full requirement text for each gate lives in `skills/app-harness-contract/SKILL.md`; the patterns
behind them live in `docs/app-gotchas.md`.

---

## 4. `handoff/round-N-gen.md` Layout

After each generator round, the generator writes `docs/harness/handoff/round-<N>-gen.md`.

```markdown
# Generator Handoff — Round <N>

## What Was Built / Fixed

<!-- Bullet list of features implemented or bugs fixed in this round. -->

## Contract Self-Assessment

| Criterion | Status | Notes |
|---|---|---|
| Hard Gate 1–8 (one row each) | DONE / PARTIAL / FAIL | … |
| R1–R12 (one row each) | DONE / N/A / PARTIAL / FAIL | … |
| <app-specific functional criterion> | DONE / PARTIAL / FAIL | … |

## Test Results

```
flutter analyze output (truncated to last 20 lines)
```

```
flutter test output (truncated to last 20 lines)
```

```
.maestro/suite.sh summary line (flows passed / total) and any FAIL lines
```

## Environment Detection

- Flutter version: <output of `flutter --version`>
- Dart version: <from above>
- Device/emulator used for smoke test: <name>

## Known Issues

<!-- List any known issues, limitations, or deferred items. State "none" if clean. -->
```

---

## 5. `feedback/round-N-qa.md` Layout

After each evaluator round, the evaluator writes `docs/harness/feedback/round-<N>-qa.md`.

```markdown
# QA Feedback — Round <N>

## Verdict

**PASS** / **FAIL**

## Evidence

| Command / Check | Result | Screenshot / Log Path |
|---|---|---|
| `flutter analyze` | 0 issues | — |
| `flutter test` | 0 failures | — |
| Cold-start iOS | OK / CRASH | screenshots/round-<N>-ios-home.png |
| Primary flow: <name> | OK / FAIL | screenshots/round-<N>-ios-<flow>.png |
| Restart persistence | OK / FAIL | — |
| Commit evaluated | `<git rev-parse HEAD>` | — |
| Independent review (Step 8) | 3 findings, 2 reproduced | — |
| `.maestro/suite.sh` light / dark / xxxl | 6/6 · 4/4 · 4/4 flows | screenshots/round-<N>-ios-F1-result.png, round-<N>-ios-device.log |
| <app-specific check> | … | … |

## Failed Criteria

<!-- If verdict is FAIL, list each failing criterion with a specific, reproducible fix. -->
<!-- Example:
- **R1 error state**: `lib/features/habits/presentation/habit_list_screen.dart:58` — AsyncValue.error renders nothing. Fix: render ErrorView with a retry that calls ref.invalidate(habitsProvider).
-->

<!-- If verdict is PASS, write "none". -->
```

---

## 6. Log Table Schemas

### `build-log.md`

`docs/harness/build-log.md` accumulates one row per evaluator round.

```markdown
# Build Log

| Round | Phase | Score | Duration | Notes |
|---|---|---|---|---|
| 1 | evaluator | FAIL | 12 m | R1 error state missing on list screen |
| 2 | evaluator | PASS | 8 m | all gates green |
```

| Column | Content |
|---|---|
| Round | Integer round number |
| Phase | Skill that produced the row (`generator` \| `evaluator`) |
| Score | `PASS` \| `FAIL` \| `PARTIAL` |
| Duration | Wall-clock time (human-readable, e.g. `5 m`) |
| Notes | One-line summary of the most significant change or failure |

### `pipeline-log.md`

`docs/harness/pipeline-log.md` appends one row per significant harness event.

```markdown
# Pipeline Log

| Time | Event | Phase | Details |
|---|---|---|---|
| 2026-10-14T10:00Z | start | bootstrap | config.md written |
| 2026-10-14T10:05Z | complete | research | 4 competitors analysed |
| 2026-10-14T10:30Z | pause | generator | rate_limit hit |
```

| Column | Content |
|---|---|
| Time | ISO-8601 timestamp (UTC) |
| Event | `start` \| `complete` \| `pause` \| `resume` \| `error` \| `handoff` \| `PASS` \| `FAIL` |
| Phase | Current phase name at the time of the event |
| Details | Free-text one-liner |

---

## 7. Phase Transition Table

The state machine governing `current_phase`, `next_role`, and `status` transitions:

| current_phase | event | → next_role / next_phase |
|---|---|---|
| (init) | bootstrap, `mode: update` | audit |
| audit | complete | plan (delta PRD) |
| (init) | bootstrap, `mode: new` | research (always — research honors `skip_research` internally: skips discovery, still runs the 4.2/4.3 check + writes the spec) |
| research | complete | plan |
| plan | complete | design |
| design | complete | contract |
| contract | AGREED | generator (current_round=1) |
| generator | handoff | evaluator |
| evaluator | PASS | paused (manual_action, human review) unless `auto_deploy: true` → resume dispatches monetize (or `build` if `skip_monetize: true`) |
| evaluator | FAIL | generator (current_round+1) |
| evaluator | max_rounds | forced judgment, then the same human-review gate as PASS (paused unless `auto_deploy: true`) → monetize/build |
| monetize   | complete       | build                                    |
| build      | complete       | screenshot                               |
| screenshot | complete       | submit                                   |
| submit     | metadata-done  | status=paused, pause_reason=manual_action|
| (paused)   | resume         | retro                                    |
| retro      | complete       | status=completed                         |
| any | rate_limit | status=paused, pause_reason=rate_limit |

Valid `next_role` values: `audit`, `research`, `plan`, `design`, `contract`, `generator`, `evaluator`,
`monetize`, `build`, `screenshot`, `submit`, `retro`. Each maps to skill `app-harness-<next_role>`.

### State Transition Rules

1. A skill must update `state.md` atomically before exiting (write then rename/overwrite).
2. When a phase skill completes successfully and advances the pipeline, it sets `status: running` together with `current_phase` and `next_role` in the same `state.md` update. Only the rate-limit hook, an error, or a pause sets `status: paused`.
3. When `status` is set to `paused`, `pause_reason` must be one of `rate_limit`, `manual_action`, or `error` (never empty).
4. When `status` is set to `running` after a pause, `resume_attempts` must be incremented.
5. `current_round` starts at 1 when the contract is AGREED and increments each time the evaluator returns FAIL (i.e., at the start of each new generator round).
6. When `current_round` reaches `max_rounds` the evaluator triggers the `max_rounds` event, writes a forced judgment, and then follows the same PASS path — pausing for human review before deploy unless `auto_deploy: true` (see rule 10) — before transitioning to `monetize`/`build`.
7. `completed` status is set only after the final phase (`retro`) exits cleanly.
8. `pause_reason` is set by the rate-limit hook, the error path, or a forward-flow skill that intentionally pauses for a `manual_action` (the `submit` store steps, the `monetize` console steps, the `audit` questions, and the `evaluator` post-QA review gate). It is cleared (set to `""`) by `app-harness-resume` when it returns `status` to `running`. Forward-flow skills that do NOT pause leave `pause_reason` unchanged.
9. If `config.md` `skip_monetize: true`, the evaluator's PASS sets `next_role: build` (monetize is skipped).
10. By default a PASS PAUSES for human review before deploy: the evaluator sets `status: paused`, `pause_reason: manual_action`, and the deploy `next_role` (monetize/build). The user runs and approves the built app, then `--resume` dispatches that `next_role`. If `config.md` `auto_deploy: true`, PASS instead sets `status: running` and continues straight to deploy with no pause.
11. In update mode `research` never runs; `audit` is the entry phase and writes `docs/harness/specs/<date>-audit.md` + `docs/harness/specs/<date>-baseline-prd.md`. The generator works on a branch (`harness/<YYYYMMDD>-update`) in the existing repository and never runs `flutter create`, moves `docs/harness/`, or resets `version:`. A new `--audit` on a project whose run is `completed` archives the old `docs/harness/` to `docs/harness-archive/<YYYYMMDD>/` and bootstraps fresh.
12. Every phase that sets `status: paused` appends a `pause` row to `pipeline-log.md`: `| <ISO-8601 UTC now> | pause | <phase> | manual_action: <what the user must do> |` (or `error: <reason>`). Resume shows the latest one.

---

## 8. Model Routing (tiered)

Phases run in the main session (they ask the user and own `state.md`); a skill cannot change that
session's model. Run the harness session on **Sonnet** — implementation and integration — and let
the phases pull in cheaper or stronger models only for the bounded sub-steps below, through the
`Agent` tool's `model` alias (`haiku` / `sonnet` / `opus`) on the built-in `Explore` /
`general-purpose` agent types. Never pin a model id; if a `model` override is refused, run the same
step without it rather than block the phase.

| Phase | Sub-step | Agent · model | Returns |
|---|---|---|---|
| research | fetch one competitor's store data + mine its 1–3★ reviews (one agent per competitor, parallel) | `general-purpose` · haiku | complaint counts + short verbatim quotes |
| audit | inventory of one area group (large codebase, parallel) | `Explore` · haiku | facts with file paths |
| generator | root cause of a criterion that failed two rounds in a row (escalation) | `general-purpose` · opus, read-only | diagnosis, no edits |
| evaluator | independent review of the round diff against the contract | `general-purpose` · sonnet (round 1) / haiku (round N > 1) | findings with file:line |
| evaluator `--strict` 6.3 | device roles · gap finder · store-policy / security review | sonnet · haiku · opus | PASS/FAIL + evidence |

Rules:

1. **One owner.** The phase skill integrates every result and alone writes app code, `state.md`,
   and verdicts. Delegated agents are read-only unless the table says otherwise.
2. **No shared targets.** No two agents edit the same files, and no two agents drive the same
   device — device work runs one agent after another on one UDID, or each on its own device.
3. **Verify before it counts.** A claimed command result, finding, or root cause is re-checked by
   the owner (re-run the command, open the file:line, reproduce on the device) before it enters a
   spec, a verdict, or a fix.
4. **No agent for trivial work** — greps, single commands, and anything the owner already has in
   context stay in the session. A delegated step never needs user input.
5. **Escalate on evidence, not by default:** the same criterion ID failing in two consecutive
   rounds, a root cause still unclear, or a security / payments / data-integrity decision.
