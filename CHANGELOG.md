# Changelog

All notable changes to flutter-app-harness are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and versions follow [Semantic Versioning](https://semver.org/).

## [0.2.1] — 2026-10-23

### Fixed
- Maestro flows use `appId: ${APP_ID}`; `suite.sh` passes `bundle_id_android` on Android when set.
- Stop hook pauses only a `running` run — no longer flips `completed` runs or overwrites
  `manual_action` / `error` pauses with `rate_limit`.
- `save_repository` reads the local cache first; preferring the durable copy loaded stale data
  once a durable write had failed.
- Store screenshots force `SCREENSHOT_LOCALE` in the test (`localesTestValue`) — every locale was
  captured in the simulator's language.
- Android `release_notes` lane targets the internal release that exists (production had no
  release for the version code, so the lane always failed).
- A new upload keystore's password goes next to the keystore, never over the shared
  `<credentials_dir>/key.properties`; the gitignore guard also checks `ios/fastlane/certs/*.p12`;
  the ASC API-key JSON for `download_metadata` lives in a temp file outside the repo.
- Audit preflight ignores its own `.maestro/` flows.
- Device log: Android counts only this app's native crash (`Process: <appId>,`); the evaluator
  reboots the simulator first (every Flutter app is `Runner`). Regression flows name screenshots
  `R<N>-…` so they never overwrite the `F<n>-` shots.
- Stop hook: `429` must stand alone (ids contain it), refreshes `updated_at`, logs the phase.
- State machine: the orchestrator counts a pause as progress; missing contract/handoff aborts
  leave a resumable `error` pause; resume finds `error:` pause rows; a missing `screenshots` flag
  pauses with `next_role: build` (protocol §7) and the evaluator now catches it before build.
- Ads rules (contract R12, plan §7, design slots) key off `monetization.admob_enabled`, not
  `skip_monetize`.
- Store: first upload to an unpublished Play app is a draft; `supply init` gets a fresh path;
  `set_contact_details.rb` runs via the new `contact_details` lane; manual iOS signing touches
  Release only; `ios/build/` ignored; screenshot placement keeps old shots when a capture is
  missing; a late version bump goes back to build.
- Templates: `debugShowCheckedModeBanner: false`; widget tests pump on a 390×844 phone surface.

### Added
- `scripts/test-suite-sh.sh` (CI): `suite.sh` against stub devices.

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
