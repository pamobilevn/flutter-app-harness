---
name: app-harness-plan
description: Phase 2 — write the app PRD in the project's default_language (concept, primary user flows, features, screens & routes, data model, permissions, monetization intent, store compliance, scope guard, feature-first lib/ map) and assign app identity, store categories, orientation, device family, locales, and backend.
argument-hint: ""
allowed-tools: [Agent, Read, Write, Edit, Bash]
---

# app-harness-plan

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

Phase 2 of the flutter-app-harness pipeline. Reads the research spec and `config.md`, then
produces a comprehensive app PRD in the project's `default_language`, maps the feature-first `lib/`
directory structure, assigns the app identity and platform decisions (`app_name`, `app_slug`,
`bundle_id`, `orientation`, `device_family`, `app_category`, `play_category`, `locales`,
`backend`), and advances the pipeline state to `design`.

All file schemas (`config.md`, `state.md`, `pipeline-log.md`) are defined in
`docs/harness-protocol.md` — refer to that document as the single source of truth. Do not
redefine schemas here. Storage, permission, and store-review patterns live in
`docs/app-gotchas.md` — cite, do not restate.

---

## Input

### 1. Read `docs/harness/config.md`

Extract:

| Key | Use |
|---|---|
| `app_idea` | Refined concept tagline written by the research phase |
| `app_name` | Display name (may be blank — set it here if so) |
| `app_slug` | Kebab-case identifier (may be blank — derive it here if so) |
| `bundle_id` | App bundle ID (may be blank — set it here) |
| `default_language` | The user's conversation language (any ISO 639-1 code, set by the orchestrator); the PRD and all copy are written in it |
| `developer.company` | Middle segment of the bundle id |
| `skip_monetize` | `true` → PRD §7 is "none" |

If `config.md` does not exist, abort with:
`app-harness-plan: docs/harness/config.md not found — run the orchestrator to bootstrap first.`

### 2. Read the latest research spec

**Update mode (`config.mode: update`): skip this step** — there is no research spec; read the audit
spec and baseline PRD instead (see **Update mode** below).

Find the most recent file matching `docs/harness/specs/*-research.md` (sort by filename
descending, take the first). If no spec file exists, abort with:
`app-harness-plan: no research spec found in docs/harness/specs/ — run app-harness-research first.`

Extract from the spec's **Chosen Concept**:

- **Title, Tagline, Target user & job-to-be-done, Differentiator**
- **Primary user flows** — the 2-4 flows; they become PRD §2
- **Why native Flutter** — informs backend, storage, and permissions
- **Monetisation hook** — AdMob formats + IAP potential; becomes PRD §7
- **Suggested store category** — becomes `app_category` / `play_category`
- **App Store Review Check (4.2 + 4.3)** — the result must be `PASS` or `PASS (revised)` before
  proceeding; otherwise abort and send the pipeline back to research (see Error handling)

---

## Update mode (`config.mode: update`)

When the run audits an existing app (`/app-harness --audit`), plan writes a **delta PRD** instead of a
greenfield one. Differences from the steps below:

- **Inputs:** read `docs/harness/specs/*-audit.md` (core idea, gap report, change request) and
  `docs/harness/specs/*-baseline-prd.md` (the app as it is today) instead of a research spec. Abort with
  `app-harness-plan: no audit spec found — run app-harness-audit first.` if either is missing.
- **Core idea is locked:** §1 Product & concept is copied from the audit's confirmed core idea. Extensions
  may add flows and features but never change the concept, target user, or differentiator.
- **Identity is not reassigned:** keep `app_name`, `app_slug`, `bundle_id`, `orientation`,
  `device_family`, `locales`, `backend`, and categories exactly as audit recorded them. Change one only
  if the change request explicitly asks (e.g. "add Japanese" → `locales`, "support iPad" →
  `device_family`) — never change `bundle_id` (a new id is a new store app).
- **Every flow, feature, and screen carries a status tag:** `KEEP` (exists, must not regress), `CHANGE`
  (exists, modified by the change request), `NEW` (added), `REMOVE` (only when the user asked). Selected
  audit gap fixes are listed in a `### Fixes` subsection of §3 with their audit IDs.
- **§9 Scope Guard** additionally forbids: migrating state management, router, or storage (follow
  `config.architecture`); restyling KEEP screens; refactoring code the change request does not touch.
- **§10 lib/ structure** is the existing tree from the baseline PRD; NEW features go where the project's
  own conventions put them (new feature folder, or the existing layer folders), not into the default
  feature-first layout.
- **Output** is still `docs/harness/plans/<YYYY-MM-DD>-prd.md` (the baseline stays under `specs/`); the
  pipeline-log row reads `delta PRD written; <k> KEEP / <c> CHANGE / <n> NEW flows`.

---

## Identity assignment

Derive and assign the app identity **before** writing the PRD so that the PRD can reference the
final values.

### app_name

Use the working title from the research spec as the display name. Capitalise each word. Example:
`"habit loop"` → `"Habit Loop"`. Keep it **≤ 30 characters** (App Store name and Play title limit).

### app_slug

The `app_slug` is a **kebab-case** identifier derived from `app_name`:

1. Lowercase the display name.
2. Replace all spaces and special characters with hyphens.
3. Strip leading/trailing hyphens and collapse consecutive hyphens to one.
4. Example: `"Habit Loop!"` → `"habit-loop"`.

The slug is used as the last segment of the bundle ID and as the directory name in CI/CD paths.
Do not use underscores — kebab-case only.

### bundle_id

The bundle id is part of the app's identity and is decided **here, up front** (the user sees it in
the PRD). Format — reverse-DNS **`com.<company>.<appname>`**:
- `<company>` = `developer.company` from `config.md` (no built-in default — it comes from the user's
  own `credentials/store-metadata.md`, collected at bootstrap; never a hard-coded company name).
- `<appname>` = `app_slug` with **all hyphens/underscores removed, lowercase** (each segment must be
  `[a-z0-9]+`; hyphens/underscores/uppercase are INVALID and break iOS/Android signing).

So `bundle_id` = `com.<company>.<appname>`. Examples: `app_slug: habit-loop` →
**`com.<company>.habitloop`**; `app_slug: split-bill` → **`com.<company>.splitbill`** (NOT
`com.<company>.habit-loop`). State the chosen `bundle_id` explicitly in the PRD identity section. It must
be byte-identical on iOS and Android (`docs/harness-protocol.md` §1).

### orientation

Decide from the concept and record it in the PRD:
- `portrait` (default) — one-hand utility, tracker, list/form apps.
- `all` — content that benefits from rotation (reading, documents, photos, charts); every layout
  must then survive rotation.
- `landscape` — only when the app's job is inherently wide (e.g. a teleprompter or whiteboard).

The generator writes it natively (iOS `UISupportedInterfaceOrientations`, Android
`screenOrientation`) — no rotate-on-launch.

### device_family

- `phone` (default) — iPhone only on iOS.
- `universal` — only when the job clearly benefits from a large screen (note-taking, reading,
  planning boards, documents). It obliges iPad support regardless of `orientation`: all four iPad
  orientations (or `UIRequiresFullScreen`), iPad screenshots, and wide layouts (see
  `docs/app-gotchas.md`, *Build / platform → Device family*). Record that obligation in the PRD.

### app_category / play_category

Map the research spec's suggested category to valid ids for both stores (they differ):

| App Store `app_category` | Google Play `play_category` |
|---|---|
| `PRODUCTIVITY` | `PRODUCTIVITY` |
| `UTILITIES` | `TOOLS` |
| `HEALTH_AND_FITNESS` | `HEALTH_AND_FITNESS` |
| `FINANCE` | `FINANCE` |
| `EDUCATION` | `EDUCATION` |
| `LIFESTYLE` | `LIFESTYLE` |
| `FOOD_AND_DRINK` | `FOOD_AND_DRINK` |
| `TRAVEL` | `TRAVEL_AND_LOCAL` |
| `PHOTO_AND_VIDEO` | `PHOTOGRAPHY` |
| `REFERENCE` | `BOOKS_AND_REFERENCE` |
| `BUSINESS` | `BUSINESS` |
| `MEDICAL` | `MEDICAL` |
| `WEATHER` | `WEATHER` |

Pick from this table. The category must match what the app actually does (a mismatch draws review
scrutiny — `docs/app-gotchas.md`, *Store rejections*).

### locales

`locales` = `[default_language]`, plus `en` when `default_language` is not `en`, plus any extra
locale the PRD justifies by target market. The first entry is the template ARB. Example:
`default_language: vi` → `locales: [vi, en]`.

### backend

`local` (default) — all data on the device. Choose `rest` only when the job-to-be-done needs data
the device cannot produce (exchange rates, a public catalogue API); choose `firebase` only when
accounts or cross-device sync are part of the core job, not a nice-to-have. `rest`/`firebase` make
gate R2 apply and add compliance rows to PRD §8. Justify the choice in PRD §5.

### Write to `config.md`

Use `Edit` to update `config.md` with the identity and platform keys:

```yaml
app_name: "<display name>"
app_slug: "<kebab-case-slug>"
bundle_id: "com.<company>.<id>"   # <id> = app_slug with hyphens/underscores removed
orientation: portrait            # portrait | landscape | all
device_family: phone             # phone | universal
app_category: PRODUCTIVITY       # App Store category id (table above)
play_category: PRODUCTIVITY      # Google Play category id (table above)
locales: [<default_language>, en]  # just [en] when default_language is en
backend: local                   # local | rest | firebase
```

Make targeted edits — do not rewrite the entire file.

---

## PRD content

The template below is written in **English**. Write the PRD **entirely in `default_language`**:
translate every heading and all body text. When `default_language` is not `en`, keep the English
heading in parentheses after each translated section heading — e.g.
`## 2. Luồng người dùng chính (Primary user flows)` — so the design, contract, and evaluator phases
can locate sections in any language. Flow IDs (`F1`…) and feature IDs (`FT1`…) are never
translated. The only other
exceptions (kept in English as-is) are code identifiers, file paths, route names and paths, package
names, config keys, and store category ids.

Use the following structure verbatim. A fresh Claude must be able to fill every section from the
research spec and `config.md` alone — no guessing required.

### PRD structure (required sections)

````markdown
# Product Requirements (PRD) — <app_name>

> **Version:** 1.0
> **Date:** <YYYY-MM-DD>
> **Author:** app-harness-plan
> **Bundle ID:** com.<company>.<id> (app_slug with hyphens/underscores removed)
> **Slug:** <app_slug> · **Locales:** [<locales>] · **Backend:** <local | rest | firebase>
> **Orientation:** <portrait | landscape | all> · **Device family:** <phone | universal>
> **Store category:** App Store <app_category> / Google Play <play_category>

---

## 1. Product & concept

- **Category:** <store category and sub-niche, e.g. Productivity — habit tracker>
- **Tagline:** <from the research spec>
- **Target user:** <who, in one sentence>
- **Job-to-be-done:** When <situation>, I want to <motivation>, so I can <outcome>.
- **Differentiator:** <from the research spec — and the competitor complaint it answers>
- **Why native:** <offline / persistence / device features>

---

## 2. Primary user flows

The backbone of the app: the contract turns each flow into acceptance criteria and the evaluator
runs each one on a device. Flow IDs (F1…F4) are stable — later phases cite them. Every step is an
observable user action and system response. At least two flows save user data that survives an
app restart (App Store 4.2).

### F1 — <flow name>

- **Entry:** <route name> — <how the user gets here>
- **Steps:**
  1. <user action> → <what the app shows/does>
  2. <user action> → <what the app shows/does>
  3. …
- **Success state:** <what the user sees> + <what is saved and still there after a restart>
- **Edge states:** <empty input, cancel, invalid value, permission denied, storage error → what the user sees>

### F2 — <flow name>

…

---

## 3. Feature list

| ID | Feature | Priority | Flows | Screens (route names) |
|---|---|---|---|---|
| FT1 | <feature> | Must | F1 | <routeName> |
| FT2 | <feature> | Should | F2 | <routeName> |
| FTn | Settings | Must | — | settings |

- **Must** = a primary flow cannot pass without it. **Should** = in MVP scope, small, does not
  block a flow. Everything else goes to §9.
- Every feature maps to at least one screen in §4; every Must maps to at least one flow.

---

## 4. Screens & navigation

- **Navigation shell:** <bottom NavigationBar with tabs: <tab → routeName>, … (3-5 tabs) | single stack>
- **Onboarding:** <yes — ≤ 3 pages, shown once (flag persisted), skippable, explains the value | no>
- **Initial route:** <routeName>

| Route name | Path | Purpose | Params | Flows |
|---|---|---|---|---|
| home | `/` | <purpose> | — | F1, F2 |
| <detail> | `/<items>/:id` | <purpose> | `id` (path) | F2 |
| settings | `/settings` | App settings, privacy policy link, version | — | — |

Route names are lowerCamelCase (go_router `name:`); the screen file is the snake_case form
(`habitDetail` → `habit_detail_screen.dart`). Pass ids as path/query params, never objects via
`extra` (lost on restoration). Every route in this table gets exactly one screen spec in the
design phase.

---

## 5. Data model

| Entity | Fields (name: type, required?) | Relations | Notes (ordering, limits) |
|---|---|---|---|
| <Entity> | id: String, title: String (≤ 60 chars), createdAt: DateTime (UTC), … | <Entity> 1—n <Other> | <sorted by …> |

- **Storage:** <shared_preferences | drift | sqflite | JSON file via path_provider> — <why, by
  data shape and volume; see `docs/app-gotchas.md`, *Persistence & data safety*>. Schema version 1.
- **Backend:** <local | rest | firebase> — <justification; for rest: base URL + endpoints + offline
  behaviour; for firebase: which products and why local cannot serve the job>.
- **Survives reinstall:** <no — Android Auto Backup / iOS device backup only | yes — durable
  restore via `templates/save_repository.dart.template`>
- **Demo data (screenshot mode):** <3-8 realistic records per entity, written in default_language>

---

## 6. Settings & permissions

| Setting | Type | Default | Notes |
|---|---|---|---|
| Privacy policy | link | `developer.privacy` from config.md | always present |
| App version | read-only | from package info | always present |
| <app-specific setting> | <toggle / choice / number> | <default> | <notes> |

Theme follows the system (`ThemeMode.system`) and language follows the device unless a setting
above says otherwise.

| Permission | iOS key | Android permission | Needed by | Rationale (user benefit) | If denied |
|---|---|---|---|---|---|
| <camera> | `NSCameraUsageDescription` | `android.permission.CAMERA` | F2 step 1 | <benefit> | <fallback> |

Or: **Runtime permissions: none.** (Ad tracking consent/ATT is added by the monetize phase — do not
list it here.)

---

## 7. Monetization intent

<If skip_monetize: true → "None — skip_monetize: true.">

Candidate placements (the monetize phase makes the final decision):

| Format | Screen / moment | Why it fits |
|---|---|---|
| banner | <routeName> bottom | <reason> |
| native | <list routeName, after item N> | <reason> |
| interstitial | <natural break, e.g. after completing F1> | <reason> |
| app_open | cold start / return from background | <reason> |
| rewarded | <opt-in unlock, e.g. one premium export> | <reason> |

Never place ads inside a flow mid-step, on onboarding, or on permission rationale screens.

- **IAP candidate:** <remove ads (non_consumable) | pro unlock | subscription | none> — the monetize
  phase asks the user and records `monetization.iap`.

---

## 8. Store compliance checklist

| Item | Status | Evidence |
|---|---|---|
| 4.2 Minimum Functionality | PASS | F<n>, F<m> save data that survives restart; works offline |
| 4.3 Spam / copycat | PASS | <differentiator> (research spec) |
| 5.1.1(v) Account deletion | N/A (no accounts) / REQUIRED | <in-app delete-account flow> |
| 4.8 Sign in with Apple | N/A (no social login) / REQUIRED | <equivalent Apple sign-in> |
| Privacy policy URL | REQUIRED | `developer.privacy` in store metadata + Settings link |
| Age rating | <4+ / …> | <content notes; `advertising` = Yes when monetization is enabled> |
| Data collected | <Identifiers (AdMob) / Data Not Collected / …> | App Privacy label + Play Data Safety must match |
| Child-directed | No (default) / Yes | <only when the concept targets kids> |
| Permission strings | <N/A / localized for every locale> | §6 |

---

## 9. Scope Guard

The following are **out of MVP scope**. Do not plan, design, or build them. If scope must grow,
revise this PRD first.

**Out of scope (by default):**

- User accounts, sign-in, cloud sync — unless §5 chose `firebase` for the core job
- Push notifications
- Social features (feeds, comments, following, chat)
- Web and desktop builds
- Tablet-specific layouts — unless `device_family: universal`
- Locales beyond `locales`
- Payments outside in-app purchase (no external payment providers or purchase links)
- Backend server / API — unless §5 chose `rest` or `firebase`
- Any feature not listed in §3

---

## 10. lib/ structure

The design and generator phases follow this structure exactly. One `lib/features/<feature>/`
directory per feature group in §3 (snake_case); one screen file per route in §4.

```
lib/
├── main.dart                         # entry: bootstrap() → runApp(ProviderScope(child: App()))
├── app/
│   ├── app.dart                      # MaterialApp.router, theme + darkTheme, l10n delegates
│   ├── router.dart                   # the single GoRouter — routes = §4 table
│   └── bootstrap.dart                # error capture, storage init, provider overrides
├── core/
│   ├── config/app_config.dart        # tunable constants (limits, durations, defaults)
│   ├── theme/design_tokens.dart      # from the design phase
│   ├── theme/app_theme.dart          # ThemeData light + dark from the tokens
│   ├── services/                     # platform wrappers (storage, permissions, …)
│   ├── widgets/                      # AsyncValueView / EmptyView / ErrorView, shared widgets
│   └── utils/
├── features/
│   ├── <feature_a>/
│   │   ├── data/                     # models, <feature_a>_repository.dart, providers
│   │   └── presentation/             # <route_name>_screen.dart (snake_case), widgets, notifiers
│   ├── <feature_b>/
│   │   ├── data/
│   │   └── presentation/
│   └── settings/
│       ├── data/
│       └── presentation/             # settings_screen.dart
└── l10n/
    ├── app_<default_language>.arb    # template ARB
    └── app_<locale>.arb              # one per other entry in `locales`
```

> **Rules:** replace `<feature_a>`… with the real feature names from §3 and list every screen file.
> Widgets never touch storage or network — they go through a repository exposed by a provider
> (`lib/features/<feature>/data/`). Magic values live in `lib/core/config/app_config.dart` and
> `lib/core/theme/` (contract Hard Gates 4–5). Add `lib/features/<feature>/domain/` only when logic
> is shared across features.
````

---

## Output

### 1. Write the PRD

Create `docs/harness/plans/<YYYY-MM-DD>-prd.md` (use today's UTC date).

If `docs/harness/plans/` does not exist, create it before writing.

Write the full PRD in `default_language` using the structure defined in the **PRD content** section
above, filling every section from the research spec and `config.md`.

### 2. Update `config.md`

Apply the identity and platform keys (`app_name`, `app_slug`, `bundle_id`, `orientation`,
`device_family`, `app_category`, `play_category`, `locales`, `backend`) via `Edit` as described in
**Identity assignment** above.

### 3. Update `state.md`

Update `docs/harness/state.md` per the schema in `docs/harness-protocol.md` §2:

```yaml
status: running
current_phase: plan
next_role: design
updated_at: "<ISO-8601 UTC now>"
```

Leave all other keys unchanged. Use `Edit` for a targeted update.

### 4. Append to `pipeline-log.md`

Append one row to `docs/harness/pipeline-log.md` per the schema in `docs/harness-protocol.md` §6:

```
| <ISO-8601 UTC now> | complete | plan | PRD written; <N> flows, <M> routes; app_slug: <slug>; bundle_id: com.<company>.<id>; backend: <backend> |
```

---

## Error handling

- If the research spec (new mode) or the audit spec / baseline PRD (update mode) is missing or
  empty, abort with a clear message and set `state.md` to `status: paused`,
  `pause_reason: manual_action`, `next_role: research` (update mode: `next_role: audit`), so resume
  re-runs the phase that produces it.
- If the research spec's App Store Review Check is not `PASS` / `PASS (revised)`, abort and set
  `state.md` to `status: paused`, `pause_reason: manual_action`, **`next_role: research`** — resume
  then re-runs research so the concept gets revised (re-running plan would just abort again).
- Every pause appends a row to `pipeline-log.md`:
  `| <ISO-8601 UTC now> | pause | plan | manual_action: <what the user must decide> |`.
- If `config.md` cannot be read, abort immediately (do not write partial output).
- If any required PRD section cannot be filled from the spec, write a clearly marked placeholder
  (`<!-- TODO: fill in -->`) rather than omitting the section — downstream phases look sections up
  by their English heading term.
