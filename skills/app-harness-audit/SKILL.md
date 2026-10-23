---
name: app-harness-audit
description: Phase 1 (update mode) — audit an existing Flutter project, reverse-engineer its core idea and primary flows, record a baseline, report gaps against the gates, and capture the user's change request (fixes + extensions) before planning.
argument-hint: ""
allowed-tools: [Agent, Read, Write, Edit, Bash, Glob, Grep, WebFetch, WebSearch, AskUserQuestion]
---

# app-harness-audit

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

Entry phase of the flutter-app-harness pipeline in **update mode** (`config.mode: update`, started
with `/app-harness --audit [path]`). It replaces `research`: instead of inventing a concept it
**extracts** the existing app's core idea, records what already works (so later phases can prove
nothing regressed), finds gaps against the contract gates, and asks the user what to fix and how to
extend the app. Downstream phases keep the core idea locked and build only the requested delta.

All file schemas (`config.md`, `state.md`, `pipeline-log.md`), the update-mode gate overrides, and
the phase transition table are defined in `docs/harness-protocol.md` — the single source of truth
(§1 config, §3 update-mode overrides, §7 transitions). Robustness patterns live in
`docs/app-gotchas.md`. Cite them; do not redefine them here.

**Rule: audit is read-only on application code.** It runs `flutter pub get`, `flutter analyze`,
`flutter test`, and the app on a simulator, but changes no file outside `docs/harness/` and
`.maestro/` (the baseline device flows — test files, not app code).

---

## Input

Read `docs/harness/config.md` (inside the project — in update mode the orchestrator bootstraps
`docs/harness/` directly in `project_path`) and extract `project_path`, `default_language`,
`auto_idea`, `skip_monetize`, `strict_mode`, and `app_idea` — at this point it holds the user's
**change hint** from `/app-harness --audit "<hint>"` (or `""`). Keep it: step 7 pre-fills the change
request from it, and step 8 overwrites `app_idea` with the locked core concept.

If `config.md` does not exist, abort with:
`app-harness-audit: docs/harness/config.md not found — run /app-harness --audit to bootstrap first.`

If `mode` is not `update`, abort with:
`app-harness-audit: config.mode is not update — audit only runs for existing projects.`

---

## 1. Preflight

```bash
cd "<project_path>"
test -f pubspec.yaml && test -d lib || echo "NOT A FLUTTER PROJECT"
grep -q "sdk: flutter" pubspec.yaml || echo "NOT A FLUTTER APP (no flutter sdk dependency)"
git rev-parse --is-inside-work-tree 2>/dev/null || echo "NOT A GIT REPO"
git status --porcelain -- . ':!docs/harness'
```

- Not a Flutter app → abort (`status: paused`, `pause_reason: error`) with the reason.
- Not a git repository → ask (AskUserQuestion): "Initialize git and commit the current state as the
  baseline?" — the generator works on a branch, so a baseline commit is required. On no → pause
  `manual_action`.
- Uncommitted changes (outside `docs/harness/`) → ask: commit them as baseline / stash / abort.
  Never discard them.
- Then `flutter pub get`. A failing `pub get` is recorded as a finding (and a mandatory fix item),
  not an abort — unless nothing else can run, in which case pause `error` with the output.

---

## 2. Inventory

Collect facts, citing file paths. Prefer reading over guessing; mark anything inferred as
`(inferred)`.

| Area | How to find it |
|---|---|
| Name, version | `pubspec.yaml` `name`, `version` |
| iOS bundle id | `grep -oE 'PRODUCT_BUNDLE_IDENTIFIER = [^;]+' ios/Runner.xcodeproj/project.pbxproj \| sort -u` |
| Android id | `applicationId` / `namespace` in `android/app/build.gradle(.kts)` |
| Display name | `CFBundleDisplayName` in `ios/Runner/Info.plist`, `android:label` + `strings.xml` |
| Orientation / device family | `UISupportedInterfaceOrientations(~ipad)`, `TARGETED_DEVICE_FAMILY`, `android:screenOrientation` |
| Architecture | deps: `flutter_riverpod`/`hooks_riverpod` → riverpod, `flutter_bloc`/`bloc` → bloc, `provider` → provider, `get` → getx, `mobx` → mobx; none → setstate |
| Router | `go_router`, `auto_route`, `beamer`, or `Navigator` 1.0 |
| Storage | `shared_preferences`, `hive`, `isar`, `drift`, `sqflite`, `objectbox`, `flutter_secure_storage`; schema version / migrations if any |
| Backend | `dio`/`http` base URLs, `firebase_*`, `supabase_flutter`, GraphQL → `backend: rest \| firebase \| local` (Supabase/GraphQL → `rest`, note the real stack) |
| Monetization | `google_mobile_ads` (ad unit ids, formats used, consent/ATT), `in_app_purchase` / `purchases_flutter` (products) |
| Localization | `flutter_localizations`, `l10n.yaml`, `lib/l10n/*.arb` or `easy_localization` / `intl` usage → locales |
| Structure | `find lib -name '*.dart' \| sed 's#/[^/]*$##' \| sort \| uniq -c` — feature folders, layering |
| Screens / routes | route table (router config) or `Navigator.push` targets; one row per screen |
| Models | classes with `fromJson`/`toJson` or DB tables |
| Tests | counts of unit / widget (`testWidgets`) / `integration_test/` files |
| CI | `.github/workflows/*`, `codemagic.yaml`, `bitrise.yml` |
| Store listing | `ios/fastlane/metadata/**`, `android/fastlane/metadata/android/**` (descriptions, categories, locales), existing `Fastfile`s |
| Docs | `README.md`, any PRD/spec in the repo |

For a large codebase, delegate the inventory to parallel read-only sub-agents — one `Explore` agent
with `model: haiku` per area group (protocol §8) — and merge their findings, opening each cited
file path before it enters the audit spec. Keep the main context for judgment.

---

## 3. Baseline — run the app, then record

```bash
cd "<project_path>"
flutter analyze 2>&1 | tail -n 40      # record the issue count
flutter test 2>&1 | tail -n 40         # record passed / failed counts (and failing test names)
```

Then **see the app** — and write down what you see as Maestro flows, so the regression check is
re-runnable instead of a one-off walk (protocol §3 Device test suite; pitfalls:
`docs/app-gotchas.md` → Device flow tests (Maestro)). Once the primary flows are drafted in step 4
(F1, F2, …): boot a simulator, build and install the app (same commands as the evaluator's Step 7),
copy `${CLAUDE_PLUGIN_ROOT}/templates/maestro/` (`suite.sh.template` → `.maestro/suite.sh`, then
`chmod +x .maestro/suite.sh`; `ready.yaml.template` → `.maestro/subflows/ready.yaml`), and write one
`.maestro/flows/F<n>_<slug>.yaml` per flow from `flow.yaml.template`, asserting what the app does
today. An existing `.maestro/` is extended, never replaced — keep its flows and its own scripts.
The flows stay untracked here (audit commits nothing); the generator's first commit takes them.
Run `.maestro/suite.sh <udid> baseline` → `docs/harness/screenshots/baseline-F<n>-<screen>.png`.
These flows and screenshots are the regression references: the evaluator replays the same flows
against the new build. A flow that fails on the baseline build documents a bug — record it as a gap,
do not bend the flow to pass. If `maestro` is not installed, walk the flows by hand with
`flutter run` and capture the same file names. Note crashes, console errors, blank screens, broken flows. If the app
cannot launch, that is the first mandatory fix item.

Record the numbers into `config.md` → `baseline:` (`analyze_issues`, `tests_passed`, `tests_failed`,
`version`, and `commit` = `git rev-parse HEAD` after the preflight baseline commit).

---

## 4. Core idea — reverse-engineer and confirm

From code + README + store metadata, write:

- **Concept** — one sentence: what the app does, for whom.
- **Target user & job-to-be-done.**
- **Primary user flows** — numbered, step-by-step, each with its success state (these become the
  regression baseline the evaluator re-walks).
- **Data model** — entities, fields, storage, whether data must survive updates (always yes for
  existing users).
- **Differentiator** — what it does that look-alikes don't (from the store listing if present).

Branch on `auto_idea`:

- `false` (default) — AskUserQuestion: "Is this the core idea of the app?" with the concept + flows
  summarized; options: "Yes, correct", "Mostly — I'll correct it", plus free text via Other.
  Apply corrections and re-confirm (max 3 rounds; then pause `manual_action`).
- `true` — accept the reverse-engineered version and note `core idea: auto-accepted` in the spec.

The confirmed core idea is **locked**: downstream phases may extend it but never replace it.

---

## 5. Gap report

Check the current code against Hard Gates 1–8 and R1–R12 (`docs/harness-protocol.md` §3; patterns
in `docs/app-gotchas.md`). Reuse the evaluator's grep checks where they apply. For each finding:

| ID | Gate | Severity | Evidence (file:line / command) | Proposed fix |
|---|---|---|---|---|

Severity: **critical** (crash, data loss, store-rejection risk, security — e.g. tokens in
`shared_preferences`, missing `PrivacyInfo.xcprivacy`, ATT never shown, alpha icon), **major**
(missing error/empty states, no lifecycle flush, inaccessible controls, untested core logic),
**minor** (style, magic values, missing CI). Do not report the architecture itself as a gap — the
harness follows `architecture` as detected.

---

## 6. Extension candidates

Propose **2–4 extensions consistent with the core idea**:

1. Competitor scan (WebSearch/WebFetch): 3–5 apps solving the same job; note features they have that
   this app lacks, and recurring asks in their 1–3★ reviews.
2. Code-level opportunities found in the inventory (half-built features, TODO-marked plans, flows
   that dead-end).

Each candidate: title, user value (one line), flows added/changed, rough size (S/M/L), and a 4.2/4.3
sanity note (does it add real native depth; does it make the app more of a look-alike?).

---

## 7. Change request

Branch on `auto_idea`:

If a change hint was given, map it onto the options first (which fixes/extensions it implies, or a
new custom item) and show it pre-selected so the user only confirms.

**`auto_idea: false` (default)** — AskUserQuestion, up to 4 questions in one call:

1. "Which audit fixes should this run include?" (multiSelect) — options: "All critical", "All
   critical + major", "Let me pick" (then list them in a follow-up), "None".
2. "Which extensions should be built?" (multiSelect) — the 2–4 candidates (+ Other for the user's
   own changes).
3. "Anything else to change or fix?" — free text via Other; options "No", "Yes (describe)".
   If the baseline has failing tests, add them to question 1's fix list as their own items; the ones
   the user leaves unselected go on the `Accepted baseline failures (skip:)` line with a reason.
4. "Include monetization changes in this run?" — "No — keep current ads/IAP as is", "Yes — add or
   change ads / IAP". (Skip this question when `skip_monetize: true`.)

**`auto_idea: true`** — select all critical fixes + the change hint's items (or, with no hint, the
top-ranked extension by value/size), no monetization changes; record `change request: auto-selected`.

If the user selects nothing at all, there is nothing to build: write the spec, set
`status: paused`, `pause_reason: manual_action`, append
`| <ISO-8601 UTC now> | pause | audit | manual_action: audit report ready — nothing selected to build |`
to `pipeline-log.md`, and tell the user the audit report is ready.

Monetization answer "No" → set `skip_monetize: true` in config (existing monetization kept; the
`monetization` block still records what ships).

---

## Output

### 1. Audit spec — `docs/harness/specs/<YYYY-MM-DD>-audit.md`

```markdown
# Audit — <app_name>

## Core Idea (locked)
<concept, target user, JTBD, differentiator; "confirmed by user" | "auto-accepted">

## Inventory
<table from step 2>

## Baseline
- flutter analyze: <N> issues
- flutter test: <P> passed, <F> failed (<failing test names>)
- Launch: OK | CRASH (<detail>) — screenshots: docs/harness/screenshots/baseline-F<n>-*.png
- Accepted baseline failures (skip:): <failing test names the user chose to leave failing, each with a reason | none>
  (every other baseline failure is automatically a fix item)

## Gap Report
<table from step 5>

## Extension Candidates
<list from step 6>

## Change Request
- Fixes: <IDs>
- Extensions: <titles>
- Other changes: <free text or "none">
- Monetization in scope: yes | no
```

Write it in `default_language` (headings may keep the English term in parentheses).

### 2. Baseline PRD — `docs/harness/specs/<YYYY-MM-DD>-baseline-prd.md`

The reverse-engineered PRD of the app **as it is today**, using the same section layout as the plan
skill's PRD (product & concept, primary user flows, features, screens & navigation, data model,
settings & permissions, monetization, store compliance, scope guard, `lib/` map — the existing
structure, not the default one). The plan phase turns it into the delta PRD. It lives under
`specs/` on purpose: downstream phases read the latest `plans/*-prd.md`, which must be the delta PRD.

### 3. Update `config.md` (targeted `Edit`s)

`app_idea` (the locked concept sentence), `app_name`, `app_slug` (from pubspec `name`, kebab-case),
`bundle_id` (the **existing** iOS id) and `bundle_id_android` (the shipped Android `applicationId`
when it differs, else `""`). Divergent or non-lowercase shipped ids are an **accepted exception**,
recorded under Inventory — never a gap or fix item: changing a shipped id creates a new store app.
`architecture`, `backend`, `locales`, `orientation`, `device_family`, `app_category` /
`play_category` (from fastlane metadata, else ask once), `baseline`, `skip_monetize`, and the
`monetization` block **as the app ships today** (`docs/harness-protocol.md` §1 Key Notes): 
`admob_enabled: true|false` (is `google_mobile_ads` used?), `iap: true|false` (is a purchase plugin
used?), plus existing app ids, ad unit ids/formats, and product ids. Downstream phases read these
keys to decide privacy declarations, ATT, and R12 — `skip_monetize: true` here only means the
monetize phase does not run; existing ads/IAP stay exactly as they are.

### 4. Update `state.md`

```yaml
status: running
current_phase: audit
next_role: plan
updated_at: "<ISO-8601 UTC now>"
```

Leave all other keys unchanged.

### 5. Append to `pipeline-log.md`

```
| <ISO-8601 UTC now> | complete | audit | baseline analyze <N>/test <P>✓<F>✗; <k> gaps (<c> critical); change request: <n> fixes + <m> extensions |
```

---

## Error handling

- Every pause this skill sets (non-Flutter project, missing git baseline, unconfirmed core idea,
  empty change request) appends a `pause` row to `pipeline-log.md`
  (`| <time> | pause | audit | manual_action: <what> |` or `error: <reason>`).

- WebSearch/WebFetch failures in step 6 → log a warning, propose extensions from code-level
  opportunities only.
- Simulator unavailable → record "launch not verified" in the baseline, still write the
  `.maestro/` flows from the code (unrun), and add both as critical findings to verify in the
  evaluator; continue.
- Never modify application code, `pubspec.yaml`, or platform files during audit.
- If `docs/harness/specs/` is missing, create it before writing.
