# flutter-app-harness

A Claude Code plugin that takes a Flutter **mobile app** from raw idea to the app stores — or takes an
**existing** Flutter app, audits it, keeps its core idea, and fixes/extends it through the same
pipeline. The harness orchestrates research, planning, design, a contract, and a generator–evaluator
build loop so every stage produces a verified, hand-off-ready artifact before the next one begins.

Forked from [tjdrhs90/flutter-flame-harness](https://github.com/tjdrhs90/flutter-flame-harness)
(Flutter/Flame games). Use the upstream plugin for Flame games; use this one for apps.

## Why

AI coding tools usually skip the boring parts — they code before pinning requirements, skip tests,
and stop while it's half-done. This harness **delegates the process, not just the code**: guardrails →
plan → a generator↔evaluator build loop with a *skeptical QA that runs the app before judging* → human
review. The store/build fixes earned shipping real apps (consent order, ATT, alpha-free icons,
screenshot de-duplication, review-submission API, age-rating declarations) are baked in.

## Stack defaults

| Concern | Default |
|---|---|
| State management | Riverpod (`Notifier` / `AsyncNotifier`), feature-first `lib/features/<feature>/{data,presentation}` |
| Navigation | go_router |
| Backend | local-first; plan may opt into REST or Firebase when the PRD needs it |
| Monetization | AdMob, all formats (banner / native / interstitial / app-open / rewarded), then asks about IAP / subscriptions |
| Deploy | fastlane (TestFlight + Play internal track), templates included |

In **update mode** the harness follows the existing project's architecture instead of migrating it.

## Pipeline

```
new app:   research → plan → design → contract → generator ⇄ evaluator → [human review]
           → monetize → build → screenshot → submit → [manual store submit] → retro

existing:  audit → plan (delta PRD) → design → contract (+ regression criteria)
           → generator ⇄ evaluator → [human review] → monetize? → build → screenshot → submit → retro
```

## Install (local)

```bash
/plugin marketplace add ~/flutter/flutter-app-harness
/plugin install flutter-app-harness@flutter-app-harness
```

After editing the plugin source, re-sync the cached copy:

```bash
/plugin marketplace update flutter-app-harness
/reload-plugins
```

## Usage

```
/app-harness "<idea>"            # new app from an idea
/app-harness                     # AI researches the market and proposes 2-3 app concepts
/app-harness --audit [path]      # existing app: audit, keep core idea, fix + extend
/app-harness --resume            # continue a paused run
```

| Flag | Default | Description |
|------|---------|-------------|
| `--audit [path]` | — | Update mode for an existing Flutter project (default: current directory) |
| `--strict` | off | Evaluator adds quality scoring + a 6-agent edge-case sweep |
| `--rounds N` | 3 | Maximum generator–evaluator rounds |
| `--skip-research` | off | Take the idea verbatim (4.2/4.3 store check still runs) |
| `--skip-monetize` | off | No ads, no IAP |
| `--auto-idea` | off | Research auto-picks the best concept (no prompt) |
| `--auto-deploy` | off | Skip the post-QA human-review pause |

### Update mode (`--audit`)

Run from (or point at) an existing Flutter project. The audit is read-only on app code:

1. Inventory + baseline — `flutter analyze` / `flutter test` counts, app launched and every flow
   screenshotted as the regression reference.
2. Core idea reverse-engineered from code, README and store listing — you confirm it; it stays **locked**.
3. Gap report against the gates (crash/data-loss/store-rejection risks first) + 2-4 extension ideas
   from competitor reviews.
4. You pick fixes + extensions (+ free-form changes). An optional hint seeds it:
   `/app-harness --audit "add iCloud backup and a widget"`.

Then plan writes a delta PRD (flows tagged KEEP / CHANGE / NEW), the contract adds regression
criteria, and the generator works on a `harness/<date>-update` branch following the app's existing
architecture. QA must end no worse than the baseline, re-walk every KEEP flow, and prove data from
the old version still loads. Build bumps the version name and reuses existing signing; submit writes
release notes and keeps the live listing. Re-running `--audit` after a completed cycle archives the
previous run to `docs/harness-archive/`.

By default, after QA passes the harness **pauses so you can run and approve the app**
(`cd <app_slug> && flutter run`) before any deploy work; `--resume` continues.

## Skills

| Skill | Purpose |
|-------|---------|
| `app-harness` | Orchestrator — bootstrap config/state, dispatch phases |
| `app-harness-audit` | Existing project: inventory, baseline, core idea, gap report, change request |
| `app-harness-research` | Market research, 2-3 concepts, App Store 4.2 / 4.3 check |
| `app-harness-plan` | PRD (in your language): user flows, screens, data model, scope guard, identity |
| `app-harness-design` | Design tokens (light + dark), screen specs with all states, icon/splash plan |
| `app-harness-contract` | Hard Gates 1–8 + robustness gates R1–R12 + functional criteria |
| `app-harness-generator` | Build in 3 gated sub-phases (scaffold → data/state → UI/polish) |
| `app-harness-evaluator` | Skeptical QA — runs the app, walks every flow, checks restart persistence |
| `app-harness-monetize` | AdMob strategy + consent + code; optional IAP / subscriptions |
| `app-harness-build` | Signing, fastlane config, IPA → TestFlight, AAB → internal track |
| `app-harness-screenshot` | Store screenshots per locale with seeded demo data, ASO metadata |
| `app-harness-submit` | Store metadata, privacy profiles, then pause for manual review submission |
| `app-harness-retro` | Score the run against 9 harness principles |
| `app-harness-status` / `-resume` | Read-only status / resume after a pause |

## File protocol

[`docs/harness-protocol.md`](docs/harness-protocol.md) is the single source of truth for every file
schema and the phase state machine. [`docs/app-gotchas.md`](docs/app-gotchas.md) holds the robustness
patterns behind gates R1–R12.

## Security

Credentials and secrets never enter this repository or generated apps' git history. Developer/store
identity lives in your own `<credentials_dir>/store-metadata.md` (or is asked at bootstrap). See
[SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE) (original copyright retained).
