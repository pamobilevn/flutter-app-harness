---
name: app-harness-contract
description: Phase 4 — turn the app PRD into a verifiable contract (8 hard gates, R1–R12 platform-robustness gates marked REQUIRED or N/A, PRD-derived functional criteria) and reach AGREED (1-pass default, second self-review pass in --strict).
argument-hint: ""
allowed-tools: [Agent, Read, Write, Edit, Bash]
---

# app-harness-contract

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

Phase 4 of the flutter-app-harness pipeline. Reads the PRD and design doc, proposes verifiable
completion criteria (Mandatory Hard Gates + Platform-Robustness Gates + Functional Criteria), and
marks the contract AGREED before handing off to the generator.

All file schemas (`config.md`, `state.md`, `contract.md`) are defined in
`docs/harness-protocol.md` — refer to that document as the single source of truth. Do not
redefine schemas here. The patterns behind the R-gates live in `docs/app-gotchas.md` — cite it,
do not restate it.

---

## Input

### 1. Read `docs/harness/config.md`

Extract:

| Key | Use |
|---|---|
| `app_name` | Contract title header |
| `app_slug` | Identifies the app |
| `bundle_id` | R6 — the exact string both platforms must carry |
| `orientation` | R6 — native orientation lock |
| `device_family` | R6 / R8 — phone vs universal (iPad) |
| `backend` | R2 — N/A when `local` and the PRD makes no network call |
| `default_language`, `locales` | Hard Gate 6, R5 display name, R12 usage strings |
| `monetization.admob_enabled` | R12 — ads bring ATT (never decided from `skip_monetize`) |
| `strict_mode` | If `true`, run `--strict` negotiation; if `false` (or absent), run default 1-pass |

### 2. Read the latest PRD

Find the most recent file matching `docs/harness/plans/*-prd.md` (sort by filename descending,
take the first). Abort with a clear message if none exists.

### 3. Read the design doc

Find the most recent file matching `docs/harness/plans/*-design.md` (sort by filename
descending, take the first). Abort if none exists.

---

## Mandatory Hard Gates

These 8 criteria are non-negotiable and must appear verbatim in every `contract.md`. A FAIL on
any one results in an immediate FAIL verdict, regardless of other passing criteria.

> **Source:** `docs/harness-protocol.md` §3 — Mandatory Hard Gates block. Always cite; never
> restate differently.

1. `flutter analyze` returns zero issues.
2. `flutter test` — all tests pass.
3. No TODO, stub, placeholder, or fake data in production code under `lib/` (grep-checkable).
4. No magic values — colors/spacing/typography come from `lib/core/theme/`, tunable constants from `lib/core/config/app_config.dart`.
5. Data is modeled — typed models behind repositories; widgets never touch storage/network directly; seed content is data, not widget literals.
6. Localization complete for all configured locales — no hard-coded user-visible strings, no missing l10n keys.
7. Every primary user flow in the PRD works end to end, and user data survives an app restart.
8. Runs on a simulator/emulator with zero crashes and zero console errors.

Copy these 8 lines verbatim into the `## Mandatory Hard Gates` section of `contract.md`. Do not
paraphrase, reorder, or omit any gate.

## Platform-Robustness Gates

In addition to the 8 core gates, every contract includes a `## Platform-Robustness Gates` section
covering R1–R12 (IDs and names fixed by `docs/harness-protocol.md` §3; patterns in
`docs/app-gotchas.md`). Each gate is marked **REQUIRED** or **N/A** with a one-line reason drawn
from the PRD + `config.md`. Only the gates whose "Applies" condition can be false may be N/A
(R2, R4, R12, and the optional durable-restore line of R9). A REQUIRED gate gets an app-specific
scope note so the generator knows exactly what it covers (e.g. which screens are data-backed,
which forms exist, which permissions are used).

### R1 Async UI states — always REQUIRED

- Every data-backed screen renders **loading**, **empty** (localized message + primary action), and
  **error** (localized message + **Retry**) via `AsyncValue.when(data:, loading:, error:)` or the
  shared `AsyncValueView` / `EmptyView` / `ErrorView` in `lib/core/widgets/`. Retry calls
  `ref.invalidate(provider)` (or the notifier's `refresh()`). No `.value!` / `.requireValue` in build.
- Global error capture: `FlutterError.onError` + `PlatformDispatcher.instance.onError` log instead of
  crash; release builds set `ErrorWidget.builder` to a friendly localized widget.
- Scope note: list every data-backed screen by name.

### R2 Network resilience — REQUIRED when `backend ≠ local` or the PRD makes any network call

- One injected HTTP client (`dio` or `http`) in `lib/core/services/`, provided via Riverpod; nothing
  else constructs a client.
- Timeouts on every request; retry with exponential backoff on idempotent requests only (never
  auto-retry a POST).
- Offline: an offline banner + cached data instead of an empty error screen.
- Requests cancelled on dispose (`ref.onDispose`).
- N/A when `backend: local` and the PRD makes no network calls — reason: "backend: local, no network calls".

### R3 Lifecycle — always REQUIRED

- An app-level `AppLifecycleListener` (or `WidgetsBindingObserver`) flushes pending writes on
  pause/inactive and refreshes time-sensitive data (dates, "today" views, tokens) on resume.
- `autoDispose` providers; every controller / subscription / timer disposed.
- No `BuildContext` across an async gap without a `context.mounted` check.

### R4 Forms & keyboard — REQUIRED when the app has text input

- `Form` + `TextFormField` validators returning **localized** messages.
- The focused field is never covered by the keyboard.
- Correct `keyboardType`, `textInputAction` (next → done), and `autofillHints` per field.
- Tapping outside dismisses the keyboard.
- No double-submit: the submit button is disabled while submitting and shows progress.
- Scope note: list every form/input screen. N/A when the app has no text input — reason: "no text input".

### R5 App branding — always REQUIRED

- A custom icon + native splash are generated (not Flutter defaults), including a **dark splash colour**.
- The iOS icon is opaque (no alpha).
- Android adaptive icon: a padded foreground (`adaptive_icon_foreground`, motif in the safe zone)
  over a solid background, plus a monochrome layer (`adaptive_icon_monochrome`) for Android 13+.
- The localized display name (`CFBundleDisplayName` per `<locale>.lproj/InfoPlist.strings`,
  Android `android:label` → per-locale `strings.xml`) equals `app_name` — never "Runner" or the slug.

### R6 Native config — always REQUIRED

- Orientation locked **natively** to `config.orientation` (`Info.plist`
  `UISupportedInterfaceOrientations` + Android `android:screenOrientation`); `all` leaves both open.
- Device family per `config.device_family`: `phone` → `TARGETED_DEVICE_FAMILY = 1` in every build
  configuration and no `UISupportedInterfaceOrientations~ipad` key; `universal` →
  `TARGETED_DEVICE_FAMILY = "1,2"` with all four iPad orientations (or `UIRequiresFullScreen`).
- `ITSAppUsesNonExemptEncryption = false` in `Info.plist`.
- Android back: nested routes pop; the root route shows a localized SnackBar and exits on a second
  back press (`PopScope(canPop: false)`).
- Bundle id **byte-identical** across iOS `PRODUCT_BUNDLE_IDENTIFIER`, Android `applicationId`
  (+ `namespace`), and `config.bundle_id` (lowercase `[a-z0-9.]`, no `_`/`-`).

### R7 Assets & CI — always REQUIRED

- No dangling asset references: every path in `pubspec.yaml` `assets:` and every `assets/...`
  string in `lib/` exists on disk (lowercase names).
- `.github/workflows` CI runs `flutter analyze` + `flutter test` on push/PR.

### R8 Store graphics — always REQUIRED

- Android Play listing: hi-res icon **512×512** and feature graphic **1024×500** (opaque) placed for
  `supply` at `android/fastlane/metadata/android/<locale>/images/icon.png` + `featureGraphic.png`.
- iOS: localized screenshots per locale (+ iPad screenshots when `device_family: universal`) —
  produced by the screenshot phase; the evaluator verifies the Play graphics only.

### R9 Persistence & data safety — always REQUIRED

- Storage only through repositories (`lib/features/<f>/data/*_repository.dart`) exposed via
  providers; widgets and notifiers never call `SharedPreferences` / DB / file APIs directly.
- User data survives an app restart (written on user action, or debounced ≤ 1 s and flushed on pause).
- Versioned schema (`schemaVersion` or a versioned key) + a migration path.
- Secrets/tokens in `flutter_secure_storage`, never in `shared_preferences`.
- Durable reinstall/device-transfer restore (`templates/save_repository.dart.template`) **only when
  the PRD requires it**; otherwise mark that line N/A — reason: "PRD does not require reinstall restore".

### R10 Accessibility — always REQUIRED

- Honors OS text scaling up to 200% without overflow — no `MediaQuery.withNoTextScaling` on content
  (a global `TextScaler.clamp(maxScaleFactor: 2.0)` is the only allowed clamp).
- `Semantics` label or `tooltip` on every icon-only button.
- Tap targets ≥ 48×48 dp.
- Text contrast ≥ 4.5:1 (3:1 for large text) in both light and dark theme.
- A dark theme (`theme` + `darkTheme`, `ThemeMode.system` by default).
- Reduce Motion respected (`MediaQuery.disableAnimations`).
- Nothing flashes faster than 3×/second.

### R11 Test depth — always REQUIRED

- ≥ 3 unit tests on notifiers/repositories with real logic, run through `ProviderContainer` with
  overrides.
- ≥ 1 widget test per primary screen (minimum 2).
- One Maestro flow per PRD primary flow — `.maestro/flows/F<n>_<slug>.yaml` (protocol §3 Device
  test suite) — driving it on a device from a fresh install (`clearState: true`), with an assert
  after every action and a kill + relaunch + assert for the data it created; at least one flow
  proves resume (`pressKey: home` → `launchApp: { stopApp: false }`). Main screens are tagged `ui`
  and replayed in dark mode and the largest text size. The suite passes via `.maestro/suite.sh`.
- Only when `maestro` is not installed: ≥ 1 integration test (`integration_test/`) driving the
  main PRD flow end to end, including persistence (data still present after the app is re-pumped
  from storage).
- Scope note: name the primary screens and the `F<n>` flows.

### R12 Permissions & privacy — REQUIRED when any runtime permission is used OR `monetization.admob_enabled: true`

- An in-context rationale before every system permission prompt (never cold at launch).
- Denied → graceful degradation with an explanation; permanently denied → `openAppSettings()`.
- Every `NS*UsageDescription` present and localized per configured locale
  (`ios/Runner/<locale>.lproj/InfoPlist.strings`), describing the concrete user benefit.
- `ios/Runner/PrivacyInfo.xcprivacy` present and registered in the Xcode project.
- Minimal data collection — no analytics/tracking SDK the PRD does not require.
- Ads (`monetization.admob_enabled: true` — the app ships or will ship AdMob) bring ATT: the ATT prompt, `NSUserTrackingUsageDescription`,
  and the UMP-before-ATT order are delivered by the monetize phase (it runs after QA) and verified
  there and at submit; the generator delivers everything else in this gate. (Update mode with
  existing ads: they already ship — the evaluator checks the existing order and strings.)
- Scope note: list each permission and the feature that needs it. N/A when no runtime permission is
  used and `monetization.admob_enabled: false` — reason: "no runtime permissions, no ads". Never decide
  this from `skip_monetize` (protocol §1 Key Notes).

---

## Update mode (`config.mode: update`)

When the run fixes/extends an existing app (`/app-harness --audit`):

- **Inputs:** also read `docs/harness/specs/*-audit.md` (gap report + change request) and
  `docs/harness/specs/*-baseline-prd.md`. The PRD is the delta PRD (flows tagged KEEP / CHANGE / NEW).
- **Hard Gates:** copy Gates 1–8 verbatim, then add a `### Update-mode overrides` block that copies the
  override table from `docs/harness-protocol.md` §3 and fills the numbers: `baseline.analyze_issues`,
  `baseline.tests_failed` (with the accepted `skip:` list), and `baseline.commit` as the diff base.
- **Robustness gates:** mark each R gate REQUIRED for **new/changed code** (or N/A with a reason); a
  legacy gap counts only when its audit ID is in the change request — list those IDs under the gate.
  Identity (bundle id, display name, icon) must stay unchanged unless the change request changes it.
- **Functional Criteria** have three groups:
  1. `### New & changed` — one criterion per step of each NEW/CHANGE flow (same verifiability rules).
  2. `### Regression` — one criterion per KEEP flow: "F<n> <name> completes exactly as in the baseline
     (the audit's `.maestro/flows/F<n>_*.yaml` passes; screenshots `baseline-F<n>-*.png`)", plus "data created by the baseline version loads after the
     update (upgrade install or migration test)".
  3. `### Fixes` — one criterion per selected audit gap ID, verifiable the same way the audit found it.
- **Anti-stub rule** applies to files the harness creates or modifies (`git diff --name-only
  <baseline.commit>...HEAD`), not to legacy files.

---

## Functional Criteria

Per-app acceptance criteria derived from the PRD. Each criterion must be verifiable by one of:

- **Command** — a shell command whose exit code or output proves the criterion (e.g.,
  `grep -rn "TODO" lib/` returns no matches).
- **Screenshot** — a labelled screenshot that visually confirms the criterion.
- **Code path** — a named file + method that implements the behaviour, plus a test that exercises it
  (e.g. `HabitsNotifier.toggleDone` in `lib/features/habits/presentation/habits_notifier.dart`,
  covered by `test/habits_notifier_test.dart`).

### Writing Functional Criteria

Read the PRD sections carefully (section names as written by `app-harness-plan`):

| PRD section | What to extract |
|---|---|
| Primary user flows | One criterion per flow step — each step must be observable on screen |
| Data model | One criterion per rule: required fields, validation limits, ordering, uniqueness, derived values |
| Settings | One criterion per setting: changing it has a visible effect **and** survives a restart |
| Design doc `## Screen specs` (empty / error states) | Per data-backed screen: the exact empty message + action, the error message + Retry |
| Data model → seed content and **Demo data** | Count targets (e.g. "≥ 20 tips defined in `assets/data/tips.json`"), demo records available in screenshot mode |
| Scope Guard | Nothing — out-of-scope items get no criterion |

Criteria that are NOT verifiable (e.g. "the app is easy to use") must be rewritten as observable
checks or removed. Every criterion that references a timing, count, or limit must cite a concrete
number (e.g. "the new item appears within 300 ms", "title is limited to 60 characters", "streak
increments by exactly 1 per calendar day"), not "quickly" or "several".

Aim for 6–15 Functional Criteria per app. More is not better — specificity is.

### Anti-stub rule

Before marking AGREED, run from the app root (`lib/` usually does not exist yet — the generator
runs `flutter create` — so the guard skips the check). **Update mode:** skip this check — legacy TODOs
are not the contract's to clean (the contract never edits app code); the evaluator applies the same
pattern to the harness's changed files only (`docs/harness-protocol.md` §3 overrides):

```bash
[ -d lib ] && grep -rnE "TODO|stub|placeholder|fake|[Ll]orem|mock data|스텁|미구현" lib/ --include="*.dart" | grep -v "placeholder:"
```

(`placeholder:` is excluded — a framework parameter of `FadeInImage` / `CachedNetworkImage`.)
If this command returns any output, the contract must NOT be marked AGREED. Remove or resolve
every stub before proceeding. The evaluator runs the same pattern (Step 3) — any hit there is an
automatic FAIL.

---

## Negotiation

### Default mode (1-pass)

When `strict_mode` is `false` or absent:

1. Generator reads the PRD, design doc, and `config.md`.
2. Generator writes `docs/harness/contract.md` with:
   - The 8 Mandatory Hard Gates verbatim (from `docs/harness-protocol.md` §3).
   - R1–R12, each marked REQUIRED (with scope note) or N/A (with one-line reason).
   - 6–15 Functional Criteria derived from the PRD.
3. Generator self-reviews each criterion for verifiability.
4. Generator marks the contract `## Status: AGREED` in the same pass.
5. Generator updates `state.md` and hands off to the generator phase.

### --strict mode (rigorous self-review)

When `strict_mode: true` in `config.md`, or when the skill is invoked with `--strict`:

1. Generator writes the initial `contract.md` (same as default, steps 1–3 above).
2. Generator performs a **second self-review pass** over every Functional Criterion, checking
   each one against all three of the following gates:
   - **Concrete verification method** — does the criterion name a specific shell command (with
     expected exit code or output), a labelled screenshot, or a named file + method + test?
     Vague language like "works correctly" or "looks good" must be rewritten with a measurable
     check.
   - **Concrete numbers** — every timing, count, or limit must cite a real value (e.g.
     "appears within 300 ms", "≥ 20 seed tips", "list paginates at 50 items").
     Relative terms ("quickly", "several", "enough") must be replaced.
   - **Full PRD coverage** — confirm that every primary-flow step, data-model rule, setting, and
     empty/error state from the PRD has at least one corresponding Functional Criterion, and that
     every N/A gate's reason still holds against the PRD.
3. If any criterion fails the second-pass check, revise it in-place before proceeding.
4. Generator self-marks `## Status: AGREED` and proceeds (same `state.md` write as default mode).

> **Phase B note:** Phase B may reintroduce Evaluator-side contract negotiation with a
> Generator↔Evaluator round-trip; Phase A uses rigorous self-review only.

In both modes the contract file must contain `## Status: AGREED` before the generator phase
begins coding.

---

## Output

### 1. Write `docs/harness/contract.md`

Use the layout defined in `docs/harness-protocol.md` §3:

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

Requirement text: `skills/app-harness-contract/SKILL.md`; patterns: `docs/app-gotchas.md`.

- **R1 Async UI states** — REQUIRED — data-backed screens: <Home list, Detail, Stats>
- **R2 Network resilience** — N/A — backend: local, no network calls
- **R3 Lifecycle** — REQUIRED — flush on pause; refresh "today" on resume
- **R4 Forms & keyboard** — REQUIRED — forms: <Add/Edit item>
- **R5 App branding** — REQUIRED
- **R6 Native config** — REQUIRED — orientation: <portrait>; device_family: <phone>; bundle id: <com.company.id>
- **R7 Assets & CI** — REQUIRED
- **R8 Store graphics** — REQUIRED
- **R9 Persistence & data safety** — REQUIRED — storage: <shared_preferences>; durable restore: N/A — PRD does not require reinstall restore
- **R10 Accessibility** — REQUIRED
- **R11 Test depth** — REQUIRED — primary screens: <Home, Edit>; device flows: <F1 create → complete → restart, F2 …>
- **R12 Permissions & privacy** — REQUIRED — <notifications for reminders>; ATT via monetize

## Functional Criteria (per app)

<!-- One line per criterion, each with its verification method (command / screenshot / file+method+test). -->

## Status: AGREED
```

The angle-bracket values in the R-gate lines are examples — replace them with this app's facts.
If `docs/harness/` does not exist, create it before writing.

### 2. Update `state.md`

Update `docs/harness/state.md` per the schema in `docs/harness-protocol.md` §2:

```yaml
status: running
current_phase: contract
next_role: generator
current_round: 1
updated_at: "<ISO-8601 UTC now>"
```

Leave all other keys unchanged. Use `Edit` for a targeted update.

Per `docs/harness-protocol.md` §7 (Phase Transition Table): the `contract → AGREED` event sets
`next_role: generator` and `current_round: 1`.

### 3. Append to `pipeline-log.md`

Append one row to `docs/harness/pipeline-log.md` per the schema in `docs/harness-protocol.md` §6:

```
| <ISO-8601 UTC now> | complete | contract | contract AGREED; <N> functional criteria; <K> R-gates N/A; next: generator |
```

---

## Error handling

- Every pause appends `| <ISO-8601 UTC now> | pause | contract | manual_action: <what is missing> |` to
  `pipeline-log.md` (protocol §7 rule 12), and leaves `next_role` on the phase that must produce the
  missing input (`plan` for a missing PRD, `design` for a missing design doc).
- If the PRD is missing, abort with a clear message and set `state.md` to `status: paused`,
  `pause_reason: manual_action`.
- If the design doc is missing, abort with a clear message and set `state.md` to
  `status: paused`, `pause_reason: manual_action`.
- If `config.md` cannot be read, abort immediately (do not write partial output).
- In `--strict` mode, the Generator self-marks AGREED after the rigorous second-pass review;
  there is no multi-round Evaluator loop in Phase A. `max_rounds` applies only to the
  generator→evaluator cycle (Phase 5–6), not to contract negotiation.
