# Changelog

All notable changes to flutter-app-harness are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and versions follow [Semantic Versioning](https://semver.org/).

## [0.2.0] — 2026-10-23

### Added
- **Maestro device test suite** (`.maestro/` in the app, protocol §3 Device test suite, templates
  `templates/maestro/`): the generator writes one flow per PRD primary flow (fresh install, assert
  after every action, kill + relaunch persistence, resume); the evaluator re-runs the whole suite
  every round in light, dark and largest-text modes on iOS and Android and turns each new
  device-visible bug into a `regress_r<N>_*` flow; audit writes the baseline flows that the
  evaluator replays against the new build. `suite.sh` runs flows one at a time, addresses the device
  by UDID, restores simulator settings, copies screenshots and the device log into
  `docs/harness/screenshots/`. `integration_test` stays as the fallback when Maestro is missing.
- `docs/app-gotchas.md` → Device flow tests (Maestro).
- **Tiered model routing** (protocol §8): phases stay in the main session (recommended: Sonnet) and
  delegate bounded sub-steps — Haiku for per-competitor review mining, audit inventory and
  round N > 1 diff review; Sonnet for the round-1 independent review and `--strict` device roles;
  Opus for the root cause of a criterion failing two rounds in a row and for store-policy /
  security review. One owner integrates; agent claims are re-checked before they count.
- Evaluator Step 8: independent fresh-context review of the round diff.

### Changed
- From real runs: no evidence carries over between rounds; widget tests never stand in for a
  device run; HG7/HG8 need the suite's `flows:` line and device log; the evaluator never edits app
  code; Android runs the suite too (not only when iOS is unavailable); the generator runs the
  largest-text pass before handoff.
- `--strict` 6.3: device roles run one after another on one device (not in parallel);
  `test-generator` became `test-gaps` (reports fix items, writes nothing); performance profiling
  needs a physical device (profile mode does not run on simulators).

## [0.1.0] — 2026-10-14

### Added
- Forked from flutter-flame-harness 0.22.0 and retargeted from Flutter/Flame games to Flutter
  mobile applications.
- Stack defaults: Riverpod (Notifier/AsyncNotifier) + feature-first layout, go_router, local-first
  backend (plan may opt into REST or Firebase).
- `monetize` phase (replaces `admob`): AdMob across all formats (banner, native, interstitial,
  app-open, rewarded), then asks whether to add in-app purchases / subscriptions.
- `docs/app-gotchas.md` (replaces game-gotchas) and app gates R1–R12: async UI states, network
  resilience, lifecycle, forms, branding, native config, assets/CI, store graphics, persistence,
  accessibility (text scaling honored), test depth, permissions/privacy.
- Research checks App Store 4.2 Minimum Functionality alongside 4.3 Spam.
- Stop hook also finds `state.md` after the generator moves `docs/harness/` into the app project.
- **Update mode** (`/app-harness --audit [path]`): new `audit` phase extracts the core idea, records a
  baseline (analyze/test counts, per-flow screenshots, commit), reports gaps, and captures a change
  request; downstream phases build only the delta on a branch, gated as "no worse than baseline" plus
  KEEP-flow regression and upgrade-data checks.

### Kept from upstream
- State machine, generator↔evaluator loop, human-review gate, and every deploy/store fix
  (fastlane lanes, screenshot prune, alpha strip, review submission API flow, age-rating 2026).
