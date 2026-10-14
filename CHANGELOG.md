# Changelog

All notable changes to flutter-app-harness are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and versions follow [Semantic Versioning](https://semver.org/).

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
