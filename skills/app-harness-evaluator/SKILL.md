---
name: app-harness-evaluator
description: Phase 6 — skeptical QA. Run the app on a simulator, walk every primary user flow, kill and relaunch to prove persistence, check dark mode and large text, then judge against the contract. Default = functional check; --strict adds quality scoring and an edge-case sweep.
argument-hint: ""
allowed-tools: [Agent, Read, Write, Edit, Bash, Glob, Grep]
---

# app-harness-evaluator

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

Phase 6 of the flutter-app-harness pipeline. Skeptical QA gate that decides PASS or FAIL
against the negotiated contract. Default mode runs the functional check (6.1) only; `--strict`
adds quality scoring (6.2) and an agent-team edge-case sweep (6.3).

All file schemas (`config.md`, `state.md`, `handoff/round-N-gen.md`, `feedback/round-N-qa.md`,
`build-log.md`) and the phase transition table are defined in `docs/harness-protocol.md` — that
document is the single source of truth (§1 for `config.md`; §2 for `state.md`; §3 for
`contract.md`; §4 for handoff layout; §5 for feedback layout; §6 for log schemas; §7 for the
`evaluator → monetize / evaluator → build / evaluator → generator` transitions). Do not redefine
schemas here. Robustness patterns are in `docs/app-gotchas.md` — judge against it, do not restate it.

---

## Critical Rule

**"Run the code, see the app, then judge." Never PASS on code review alone. Execute commands,
launch the app on a simulator, walk every primary user flow, kill and relaunch it, capture and
study screenshots. Stub detected = automatic FAIL, no exceptions.**

**The evaluator reports, it never fixes.** It does not edit app code, tests, or platform files and
commits nothing to the app; the generator fixes in the next round. In the app it writes only
`docs/harness/` and `.maestro/flows/regress_r<N>_*.yaml` (Step 7 item 7). A PASS "after in-loop
fixes" is not a PASS.

---

## Setup — Read Inputs

Before any check, load:

1. `docs/harness/state.md` — extract `current_round` (integer ≥ 1) and confirm
   `next_role: evaluator`.
2. `docs/harness/config.md` — extract `mode`, `project_path`, `architecture`, `baseline.*`,
   `app_slug`, `bundle_id`, `bundle_id_android`, `orientation`, `device_family`,
   `backend`, `locales`, `default_language`, `strict_mode` (bool), `max_rounds` (int),
   `skip_monetize`, `auto_deploy`, `monetization.admob_enabled`.
   Derive the app root `<app>` once: `project_path` when `mode: update`, else
   `<projects-dir>/<app_slug>` (or `.` when `./pubspec.yaml` already exists). Every command below
   runs from `<app>`, and every relative path in this skill is relative to it.
3. `docs/harness/contract.md` — parse `## Mandatory Hard Gates`, `## Platform-Robustness Gates`
   (which R-gates are REQUIRED vs N/A), and `## Functional Criteria`. Confirm `## Status: AGREED`
   is present; if missing, pause first (protocol §7 rule 12): `status: paused`, `pause_reason: error`, `next_role: contract`, `updated_at`, plus the `pause` row — so `--resume` can continue once it is fixed, then abort with:
   `app-harness-evaluator: contract not AGREED — run app-harness-contract first`.
4. `docs/harness/handoff/round-<N>-gen.md` (where N = `current_round`) per protocol §4.
   If the file is missing, pause first (protocol §7 rule 12): `status: paused`, `pause_reason: error`, `next_role: generator`, `updated_at`, plus the `pause` row — so `--resume` can continue once it is fixed, then abort with:
   `app-harness-evaluator: handoff for round <N> not found — generator must run first`.
5. The latest `docs/harness/plans/*-prd.md` — list its primary user flows and primary screens;
   Step 7 walks every one of them.

---

## Update mode (`config.mode: update`)

Same critical rule, same steps — with the update-mode gate overrides from `docs/harness-protocol.md`
§3 and two additions. Also read the latest `docs/harness/specs/*-audit.md` (accepted baseline
failures, gap report, change request). Compute the changed-file set and scope the file-level greps
to it — each Bash call is a fresh shell, so put these lines at the top of every block that uses them:

```bash
cd "<app>"; BASE="<config.baseline.commit>"
CHANGED=$({ git diff --name-only --diff-filter=d "$BASE"; git ls-files --others --exclude-standard; } | grep '\.dart$' | sort -u)
SCOPE=$(echo "$CHANGED" | grep '^lib/'); [ -n "$SCOPE" ] || SCOPE=/dev/null   # empty: never grep stdin/cwd
```

Create a baseline worktree once (Step 5a and the upgrade data check use it). Never check out or
stash to `baseline.commit` in the main working tree — that removes `docs/harness/` mid-phase:

```bash
cd "<app>"; BT="${TMPDIR:-/tmp}/harness-baseline-<app_slug>"
git worktree remove --force "$BT" 2>/dev/null; git worktree add --detach "$BT" "<config.baseline.commit>"
# when the evaluator finishes (PASS, FAIL or abort):  git worktree remove --force "$BT"
```

- **Step 1 analyze:** PASS when the total issue count ≤ `baseline.analyze_issues` AND
  `[ -z "$CHANGED" ] || flutter analyze $CHANGED` reports 0 issues. Any new issue in an unchanged
  file is still a FAIL (the change broke it).
- **Step 2 test:** all tests pass, except the tests named on the audit spec's
  `Accepted baseline failures (skip:):` line. Every other baseline failure was a fix item and must
  now pass.
- **Steps 3, 4, 4a, 5 (stub, magic values, data modeled, hard-coded strings):** run the same
  patterns with `$SCOPE` as the path operand instead of `lib/`, `lib/features`, … (4a: only the
  `$SCOPE` files under `*/presentation/*`; add `-H` so path filters still see file names). Legacy
  code outside the change set is not judged — unless its fix was selected in the change request
  (then judge those files too).
- **Step 5 l10n:** when the contract marks HG6 N/A (project has no localization and the change
  request does not add it), skip Step 5 entirely. Otherwise run `flutter gen-l10n` and the ARB parity
  check only when the project uses gen-l10n (`l10n.yaml`, or `generate: true` in `pubspec.yaml`);
  with another mechanism, check key parity in its own translation files.
- **Step 5a (R1–R12):** the block handles update mode itself (`$SCOPE` greps, Riverpod-only checks
  skipped for another `architecture`, D4 bundle ids, icon/display name unchanged vs baseline). Run it
  twice — in `<app>` and in the worktree (same block, the `$BT` path in its `cd` line). A FAIL line counts only
  when it is absent from the `$BT` output (the change introduced it) or its gap was selected in the
  change request (that gap must now be clean); judge CHECK lines on NEW/CHANGE screens and services
  only. Identity checks (bundle ids, display name, icon, orientation, device family) compare against
  the values audit recorded — they must be **unchanged** unless the change request changed them.
- **Step 7 — regression walk (required):** the audit's baseline flows are the regression proof —
  Step 7's suite run replays every `KEEP` flow's `.maestro/flows/F<n>_*.yaml` against the new build;
  compare `round-<N>-ios-F<n>-<screen>.png` with `baseline-F<n>-<screen>.png` (F<n> = the PRD flow
  id). Every `CHANGE`/`NEW` flow needs its own `F<n>` flow (a CHANGE flow updates the baseline
  flow's assertions only where the change request says the behavior changes). A KEEP flow that
  fails or visibly changed without a change-request reason is a FAIL.
- **Upgrade data check (required):** data created before the update must still load. If an emulator
  allows it: build the baseline app in the worktree
  (`cd "${TMPDIR:-/tmp}/harness-baseline-<app_slug>" && flutter build ios --simulator --debug`;
  copy any gitignored build config it needs — `google-services.json`, `GoogleService-Info.plist`,
  `.env` — from `<app>`), install it, run the KEEP `F<n>` flows from `<app>` (each leaves its data
  behind), then install the new build from `<app>` over it (no uninstall) and confirm the data with
  `.maestro/flows/regress_r<N>_upgrade.yaml`: `launchApp` without `clearState`, then an
  `assertVisible` per KEEP flow's record. If that is impractical, require a migration unit
  test that feeds a baseline-schema payload through the new repository and asserts nothing is lost —
  no test, no PASS.
- **Feedback** adds a `Baseline comparison` row: analyze <baseline> → <now>, tests
  <baseline passed/failed> → <now>.

---

## 6.1 Functional Check (default — always runs)

Run every step in order from the app root (`cd "<app>"`, see Setup). A failure on any
**Mandatory Hard Gate** from `contract.md` is an immediate FAIL — do not continue checking
remaining criteria.

### Step 1 — Static analysis

```bash
cd "<app>"
flutter analyze
```

Required result: **0 issues**. If any issues are reported, record each with file, line, and
message. This is a Mandatory Hard Gate. (`use_build_context_synchronously` findings here are also
R3 failures.)

### Step 2 — Tests

```bash
cd "<app>"
flutter test
```

Required result: **0 failures**. Capture the full output. This is a Mandatory Hard Gate.

### Step 3 — Stub / TODO / fake-data grep

```bash
cd "<app>"
grep -rnE "TODO|stub|placeholder|fake|[Ll]orem|mock data|스텁|미구현" \
  lib/ --include="*.dart" | grep -v "placeholder:"
```

Same pattern as the contract's anti-stub rule (`placeholder:` is excluded — it is a framework
parameter of `FadeInImage` / `CachedNetworkImage`, not a stub). Any match is an **automatic FAIL**. No exceptions
(per `docs/harness-protocol.md` §3 Hard Gate 3). Record each match with file path, line number,
and the matched text.

### Step 4 — No magic values (Hard Gate 4)

```bash
cd "<app>"
# colors: hex literals and Material palette constants outside the theme/config
grep -rnE 'Color\(0x[0-9A-Fa-f]+\)|Colors\.[a-z]' lib/ --include='*.dart' \
  | grep -vE 'lib/core/(theme|config)/|Colors\.transparent'
# spacing / typography: raw numbers in EdgeInsets, SizedBox, fontSize
grep -rnE 'EdgeInsets(Directional)?\.[A-Za-z]+\(([^)]*[:,] *)?[1-9][0-9.]* *[,)]|SizedBox[^(]*\([^)]*(width|height|dimension): *[1-9]|fontSize: *[1-9]' \
  lib/ --include='*.dart' | grep -vE 'lib/core/(theme|config)/'
# tunables (CHECK): 3+ digit literals in feature code belong in lib/core/config/app_config.dart
grep -rnE '[(:, ][0-9]{3,}[,)]' lib/features --include='*.dart'
```

Any hit from the first two commands is a Hard Gate 4 failure — the value must come from
`lib/core/theme/` (design tokens / `ThemeData`). For the third, each hit is a tunable (durations,
limits, page sizes) that belongs in `app_config.dart` unless it is a non-tunable fact (HTTP status,
unit conversion) justified in a comment; document any exclusion in the feedback file.

### Step 4a — Data is modeled (Hard Gate 5)

```bash
cd "<app>"
# storage / network APIs inside presentation code
find lib/features -path '*/presentation/*' -name '*.dart' -exec grep -nHE \
  'SharedPreferences|package:http/|package:dio/|[^A-Za-z_]Dio\(|http\.(get|post|put|delete)\(|openDatabase|FirebaseFirestore|FlutterSecureStorage' {} +
# CHECK: list literals in presentation that may hold seed content
find lib/features -path '*/presentation/*' -name '*.dart' -exec grep -nHE \
  '(final|const) +[A-Za-z_]+ *= *(const +)?(<[^>]+>)?\[' {} +
```

Any hit from the first command is a Hard Gate 5 failure — storage and network go through a
repository in `lib/features/<f>/data/` (or a service in `lib/core/services/`) exposed via a
provider. For the second, read each hit: a list of navigation destinations is fine; user-facing
content (items, tips, categories, sample entries) declared as widget literals is a FAIL — it
belongs in `data/` (typed model + repository, or a seed JSON asset).

### Step 5 — l10n completeness (Hard Gate 6)

```bash
cd "<app>"
flutter gen-l10n
```

Then confirm that every configured `lib/l10n/app_<locale>.arb` (one per entry in
`config.locales`) contains identical key sets:

```bash
python3 -c "
import glob, json
arbs = glob.glob('lib/l10n/app_*.arb')
keysets = {f: {k for k in json.load(open(f)) if not k.startswith('@')} for f in arbs}  # @-metadata lives only in the template ARB
allkeys = set().union(*keysets.values()) if keysets else set()
bad = {f: sorted(allkeys - ks) for f, ks in keysets.items() if allkeys - ks}
if len(arbs) < 1: print('NO ARB FILES'); exit(1)
if bad: print('MISSING KEYS:', bad); exit(1)
print('l10n OK', list(keysets))
"
```

Also confirm one ARB file exists per configured locale, then grep for hard-coded user-visible
strings:

```bash
grep -rnE "(Text\(|tooltip: |labelText: |hintText: |semanticLabel: |title: )['\"][^'\"\$]*[[:alpha:]]" \
  lib/features lib/app lib/core/widgets --include='*.dart'
```

Missing keys in any locale, a missing ARB for a configured locale, or any hard-coded user-visible
literal is a Hard Gate failure (protocol §3 Hard Gate 6). Strings that are pure interpolation or
symbols (`Text('$count')`, `Text('•')`) are not hits.

### Step 5a — Platform-robustness gates (R1–R12)

Verify the `## Platform-Robustness Gates` from `contract.md` against `docs/app-gotchas.md`. Run
the block for every REQUIRED gate. Substitute the `config.md` values first; `<locales>` is
`config.locales` written as iOS `.lproj` names, space-separated (e.g. `en vi ko zh-Hans`).

```bash
cd "<app>"
BUNDLE="<config.bundle_id>"; BUNDLE_AND="<config.bundle_id_android>"; ORIENT="<config.orientation>"; FAMILY="<config.device_family>"
ADMOB="<config.monetization.admob_enabled>"; MODE="<config.mode>"; ARCH="<config.architecture>"; BASE="<config.baseline.commit>"
# per-file greps run over $SCOPE: all of lib (new mode) or only the changed lib files (update mode)
SCOPE=lib
if [ "$MODE" = update ]; then
  CHANGED=$({ git diff --name-only --diff-filter=d "$BASE"; git ls-files --others --exclude-standard; } | grep '\.dart$' | sort -u)
  SCOPE=$(echo "$CHANGED" | grep '^lib/'); [ -n "$SCOPE" ] || SCOPE=/dev/null   # empty: never grep stdin/cwd
fi
RIVERPOD=true; [ "$MODE" = update ] && [ "$ARCH" != riverpod ] && RIVERPOD=false   # gates the Riverpod-only checks

# R1 async states: shared views, every watching screen branches on AsyncValue, global error capture
if $RIVERPOD; then
  grep -rqE 'class (AsyncValueView|EmptyView|ErrorView)' lib/core/widgets/ 2>/dev/null || echo "FAIL R1: no shared AsyncValueView/EmptyView/ErrorView in lib/core/widgets/"
  grep -rlE 'ref\.watch\(' $SCOPE --include='*.dart' | grep '^lib/features/' | while read -r f; do grep -qE '\.when\(|AsyncValueView' "$f" || echo "CHECK R1: $f watches a provider without .when/AsyncValueView — data-backed?"; done
  # build methods only: screens + presentation/widgets (notifiers may use state.requireValue)
  grep -rnHE '\.value!|\.requireValue' $SCOPE --include='*.dart' | grep -E '^lib/features/[^:]*(_screen\.dart|/presentation/widgets/[^:]*):' && echo "FAIL R1: .value!/.requireValue in a screen/widget skips loading/error states"
  grep -rqE 'AsyncValueView|ErrorView|onRetry' lib/features --include='*.dart' || echo "FAIL R1: no error state with Retry on any screen"
else
  echo "CHECK R1 ($ARCH): read every changed screen — loading, empty and error+retry states handled the $ARCH way (bloc: state classes/status for loading + error that BlocBuilder branches on)"
fi
grep -rqi 'retry' lib/core/widgets/ 2>/dev/null || echo "FAIL R1: shared ErrorView has no Retry action"
grep -rq 'FlutterError.onError' lib/ && grep -rq 'PlatformDispatcher.instance.onError' lib/ || echo "FAIL R1: global error capture missing"
grep -rq 'ErrorWidget.builder' lib/ || echo "FAIL R1: release ErrorWidget.builder not set"

# R2 network — runs when any HTTP client is imported; with none imported, R2 N/A holds
if grep -rqE 'package:(http|dio)/' lib/ --include='*.dart'; then
  grep -rnHE '[^A-Za-z_]Dio\(|http\.Client\(' $SCOPE --include='*.dart' | grep -v 'lib/core/services/' && echo "FAIL R2: HTTP client constructed outside lib/core/services/"
  grep -rqE 'connectTimeout|receiveTimeout|\.timeout\(' lib/core/services/ 2>/dev/null || echo "FAIL R2: no request timeouts"
  grep -rqiE 'backoff|retry' lib/core/services/ 2>/dev/null || echo "FAIL R2: no retry/backoff"
  grep -rqi 'offline' lib/ || echo "FAIL R2: no offline banner"
  grep -rqE 'CancelToken|onDispose' lib/ || echo "CHECK R2: requests not cancelled on dispose"
else echo "R2: no HTTP client imported"; fi

# R3 lifecycle: flush on pause, refresh on resume, controllers disposed
grep -rqE 'AppLifecycleListener|WidgetsBindingObserver' lib/ || echo "FAIL R3: no app lifecycle hook"
grep -rqE 'onPause|onInactive|AppLifecycleState\.(paused|inactive)' lib/ || echo "FAIL R3: nothing flushed on pause"
grep -rqE 'onResume|AppLifecycleState\.resumed' lib/ || echo "FAIL R3: nothing refreshed on resume"
grep -rlE '(TextEditing|Animation|Scroll|Page|Tab)Controller\(' $SCOPE --include='*.dart' | xargs grep -L 'dispose' | sed 's/^/FAIL R3: controller never disposed in /'

# R4 forms (when REQUIRED): validators, input actions, tap-outside, double-submit
grep -rlE 'TextFormField\(' $SCOPE --include='*.dart' | xargs grep -L 'validator:' | sed 's/^/FAIL R4: TextFormField without validator in /'
grep -rlE 'TextFormField\(|TextField\(' $SCOPE --include='*.dart' | xargs grep -L 'textInputAction:' | sed 's/^/FAIL R4: no textInputAction in /'
grep -rlE 'TextFormField\(|TextField\(' $SCOPE --include='*.dart' | xargs grep -L 'keyboardType:' | sed 's/^/CHECK R4: no keyboardType (needed for number\/email\/phone fields) in /'
grep -rqE 'unfocus\(\)|TapRegion|onTapOutside' lib/ || echo "FAIL R4: tapping outside does not dismiss the keyboard"
grep -rqE 'autofillHints:' lib/ || echo "CHECK R4: no autofillHints (needed for name/email/password fields)"
grep -rqiE 'submitting' lib/features 2>/dev/null || echo "CHECK R4: no double-submit guard found"

# R5 branding: custom icon + splash (+ dark colour) + adaptive icon + localized display name
if [ "$MODE" = update ]; then   # identity: icon + display name unchanged vs baseline (unless the change request changes them)
  git diff --quiet "$BASE" -- assets/icons ios/Runner/Assets.xcassets/AppIcon.appiconset 'android/app/src/main/res/mipmap-*' || echo "CHECK R5: app icon changed vs baseline — FAIL unless the change request changes it"
  for k in CFBundleDisplayName CFBundleName; do
    [ "$(git show "$BASE:ios/Runner/Info.plist" 2>/dev/null | plutil -extract $k raw -o - - 2>/dev/null)" = "$(plutil -extract $k raw -o - ios/Runner/Info.plist 2>/dev/null)" ] || echo "FAIL R5: iOS $k changed vs baseline (OK only when the change request changes it)"
  done
  git diff "$BASE" -- 'ios/Runner/*.lproj/InfoPlist.strings' android/app/src/main/AndroidManifest.xml 'android/app/src/main/res/values*/strings.xml' \
    | grep -qE '^[-+].*(CFBundleDisplayName|CFBundleName|android:label|name="app_name")' && echo "FAIL R5: display name changed vs baseline (OK only when the change request changes it)"
else
ls assets/icons/icon.png >/dev/null 2>&1 || echo "FAIL R5: no custom app icon"
grep -q "flutter_launcher_icons" pubspec.yaml && grep -q "flutter_native_splash" pubspec.yaml || echo "FAIL R5: launcher-icons/native-splash not configured"
sips -g hasAlpha assets/icons/icon.png 2>/dev/null | grep -qi "hasAlpha: no" || echo "FAIL R5: icon may have alpha (App Store rejects)"
cat pubspec.yaml flutter_native_splash.yaml 2>/dev/null | grep -q "color_dark" || echo "FAIL R5: no dark splash colour (flutter_native_splash color_dark)"
# R5 Android adaptive icon: padded foreground + monochrome configured & emitted (not the full-bleed iOS icon → avoids the cropped/"zoomed" launcher look)
grep -q "adaptive_icon_foreground" pubspec.yaml || echo "FAIL R5: no adaptive_icon_foreground — Android reuses full-bleed icon and looks cropped/zoomed"
grep -q "adaptive_icon_monochrome" pubspec.yaml || echo "FAIL R5: no adaptive_icon_monochrome — Android 13+ themed icon will look off"
ls android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml 2>/dev/null | grep -q . || echo "CHECK R5: adaptive-icon XML not emitted (run flutter_launcher_icons)"
for l in <locales>; do grep -qs "CFBundleDisplayName" "ios/Runner/$l.lproj/InfoPlist.strings" || echo "FAIL R5: no localized CFBundleDisplayName for $l"; done
grep -rn 'android:label' android/app/src/main/AndroidManifest.xml 2>/dev/null | grep -qiv "runner" || echo "FAIL R5: Android label still default/runner"
fi

# R6 orientation — locked natively per config.orientation
IOSO=$(plutil -extract UISupportedInterfaceOrientations json -o - ios/Runner/Info.plist 2>/dev/null)
ANDO=$(grep -o 'android:screenOrientation="[^"]*"' android/app/src/main/AndroidManifest.xml 2>/dev/null)
case "$ORIENT" in
  portrait)  echo "$IOSO" | grep -q Landscape && echo "FAIL R6: iOS allows landscape"
             echo "$ANDO" | grep -q '"portrait"' || echo "FAIL R6: Android not locked to portrait" ;;
  landscape) echo "$IOSO" | grep -q Portrait && echo "FAIL R6: iOS allows portrait"
             echo "$ANDO" | grep -qi 'landscape"' || echo "FAIL R6: Android not locked to landscape" ;;
  all)       [ -z "$ANDO" ] || echo "FAIL R6: Android orientation locked but config.orientation is all" ;;
esac
# R6 device family — one value across every build configuration, matching config.device_family
TDF=$(grep -oE 'TARGETED_DEVICE_FAMILY = [^;]+' ios/Runner.xcodeproj/project.pbxproj | sort -u)
echo "$TDF"
case "$FAMILY" in
  phone)     [ "$TDF" = "TARGETED_DEVICE_FAMILY = 1" ] || echo "FAIL R6: phone needs TARGETED_DEVICE_FAMILY = 1 in every config"
             plutil -extract 'UISupportedInterfaceOrientations~ipad' json -o - ios/Runner/Info.plist >/dev/null 2>&1 && echo "FAIL R6: ~ipad orientations present on a phone-only app" ;;
  universal) [ "$TDF" = 'TARGETED_DEVICE_FAMILY = "1,2"' ] || echo "FAIL R6: universal needs TARGETED_DEVICE_FAMILY = \"1,2\" in every config"
             if ! plutil -extract UIRequiresFullScreen raw ios/Runner/Info.plist 2>/dev/null | grep -qx true; then
               IPAD=$(plutil -extract 'UISupportedInterfaceOrientations~ipad' json -o - ios/Runner/Info.plist 2>/dev/null)
               for o in Portrait PortraitUpsideDown LandscapeLeft LandscapeRight; do echo "$IPAD" | grep -q "UIInterfaceOrientation$o\"" || echo "FAIL R6: iPad orientation $o missing (and no UIRequiresFullScreen)"; done
             fi ;;
esac
# R6 export compliance + root back
plutil -extract ITSAppUsesNonExemptEncryption raw ios/Runner/Info.plist 2>/dev/null | grep -qx false || echo "FAIL R6: ITSAppUsesNonExemptEncryption must be false"
grep -rq "PopScope" lib/ && grep -rqE "canPop: *false" lib/ || echo "FAIL R6: no root PopScope(canPop: false) double-back exit"
# R6 bundle id, update mode (D4): each platform keeps the id audit recorded — divergent / non-lowercase shipped ids are accepted
if [ "$MODE" = update ]; then
  grep -oE 'PRODUCT_BUNDLE_IDENTIFIER = "?[^;"]+' ios/Runner.xcodeproj/project.pbxproj 2>/dev/null | sed -E 's/.*= "?//' \
    | grep -qxF "$BUNDLE" || echo "FAIL R6: iOS PRODUCT_BUNDLE_IDENTIFIER is no longer config.bundle_id $BUNDLE"
  grep -hoE 'applicationId *=? *["'"'"'][^"'"'"']+["'"'"']' android/app/build.gradle.kts android/app/build.gradle 2>/dev/null | sed -E "s/.*[\"']([^\"']+)[\"']/\\1/" \
    | grep -qxF "${BUNDLE_AND:-$BUNDLE}" || echo "FAIL R6: Android applicationId is no longer ${BUNDLE_AND:-$BUNDLE} (config.bundle_id_android || bundle_id)"
else
# R6 bundle id identical on both platforms (new mode: == config.bundle_id, lowercase no _/-)
# Runner app target only — skip RunnerTests / extension targets, whichever order pbxproj lists them in.
IOSID=$(grep -oE 'PRODUCT_BUNDLE_IDENTIFIER = "?[A-Za-z0-9._-]+' ios/Runner.xcodeproj/project.pbxproj 2>/dev/null | sed -E 's/.*= "?//' | grep -vE '\.(RunnerTests|[A-Za-z]*[Ee]xtensions?|[A-Za-z]*Widget[A-Za-z]*)$' | sort -u | head -1)
ANDID=$(grep -hoE 'applicationId *=? *["'"'"'][^"'"'"']+["'"'"']' android/app/build.gradle.kts android/app/build.gradle 2>/dev/null | head -1 | sed -E "s/.*[\"']([^\"']+)[\"']/\\1/")  # .kts or Groovy
echo "iOS=$IOSID  Android=$ANDID  (must be byte-identical == config.bundle_id)"
{ [ -n "$IOSID" ] && [ "$IOSID" = "$ANDID" ]; } || echo "FAIL: iOS and Android bundle id differ (or unset)"
echo "$IOSID" | grep -qE '^[a-z0-9.]+$' || echo "FAIL: bundle id has uppercase/_/- (must be lowercase [a-z0-9.])"
[ "$IOSID" = "$BUNDLE" ] || echo "FAIL R6: bundle id $IOSID != config.bundle_id $BUNDLE"
fi
# R6/R12 consent order (only when monetization.admob_enabled: true AND the monetize phase has added
#    ads — it runs after QA, so this is usually skipped in round 1). The sequence
#    loadConsentForm() → requestATT() → MobileAds.instance.initialize() lives in
#    lib/core/services/ads/ads_service.dart (fall back to all of lib/). The UMP form must run BEFORE
#    the ATT prompt: AdMob's consent message tells the user to tap "Allow" on the next screen;
#    reversed, that guidance is meaningless and the opt-in rate drops.
if [ "$ADMOB" = "true" ] && grep -q "google_mobile_ads" pubspec.yaml; then
  ADS=lib/core/services/ads/ads_service.dart; [ -f "$ADS" ] || ADS=lib/
  grep -rnHE 'loadConsentForm\(|requestATT\(|MobileAds\.instance\.initialize\(' "$ADS" --include='*.dart' \
    | grep -vE '(Future|void)[^=(]*(loadConsentForm|requestATT)\(' | awk -F: '
    /loadConsentForm\(/ && !c { cf=$1; c=$2 } /requestATT\(/ && !a { af=$1; a=$2 }
    /MobileAds\.instance\.initialize\(/ && !m { mf=$1; m=$2 }
    END { if (!a || !c) print "CHECK: loadConsentForm()/requestATT() call not found — read the ads init sequence"
          else if (af != cf) print "CHECK: loadConsentForm() (" cf ") and requestATT() (" af ") in different files — confirm UMP runs first"
          else if (a+0 < c+0) print "FAIL: requestATT() runs before loadConsentForm() — the two prompts collide"
          else if (m && mf == af && m+0 < a+0) print "FAIL: MobileAds.instance.initialize() runs before requestATT()"
          else print "consent order OK (UMP → ATT → ads init)" }'
fi

# R7 assets & CI: CI runs analyze + test; every referenced asset exists
find .github/workflows -name '*.y*ml' 2>/dev/null | grep -q . || echo "FAIL R7: no CI workflow"
find .github/workflows -name '*.y*ml' -exec grep -l 'flutter analyze' {} + 2>/dev/null | xargs grep -l 'flutter test' 2>/dev/null | grep -q . || echo "FAIL R7: CI must run flutter analyze + flutter test"
grep -rhoE "[\"']assets/[^\"'\$]+[\"']" $SCOPE --include='*.dart' | tr -d "\"'" | sort -u | while read -r p; do [ -e "$p" ] || echo "FAIL R7: lib references missing asset $p"; done

# R8 Play listing graphics: hi-res icon (512) + feature graphic (1024x500), opaque.
# At QA time they exist as gen_icon output (assets/store/); the screenshot phase copies them into
# android/fastlane/metadata/android/<locale>/images/ later. Accept either location (update mode:
# a live app may already have them in metadata).
{ ls assets/store/play_icon.png || find android/fastlane/metadata/android -path '*/images/icon.png' | grep -q .; } >/dev/null 2>&1 || echo "FAIL R8: no Play hi-res icon (512x512)"
{ ls assets/store/feature_graphic.png || find android/fastlane/metadata/android -path '*/images/featureGraphic.png' | grep -q .; } >/dev/null 2>&1 || echo "FAIL R8: no Play feature graphic (1024x500)"
find assets/store android/fastlane/metadata/android \( -name play_icon.png -o -name feature_graphic.png -o -name icon.png -o -name featureGraphic.png \) -exec sips -g pixelWidth -g pixelHeight -g hasAlpha {} + 2>/dev/null

# R9 persistence: storage only in repositories/services, versioned schema, secrets secured
grep -rnHE 'SharedPreferences|openDatabase|FlutterSecureStorage|getApplicationDocumentsDirectory' $SCOPE --include='*.dart' \
  | grep -vE '_repository\.dart|lib/core/services/|lib/app/bootstrap\.dart|lib/main\.dart' && echo "FAIL R9: storage API used outside a repository"
grep -rqiE 'schemaVersion|_v[0-9]+|migrat' lib/ || echo "FAIL R9: no versioned schema / migration"
grep -rniE 'token|secret|password|api_?key' $SCOPE --include='*.dart' | grep -iE 'setString|SharedPreferences' && echo "FAIL R9: secret/token written to SharedPreferences"
grep -rqiE '(access|refresh|auth|id)_?token' lib/ && { grep -q "flutter_secure_storage" pubspec.yaml || echo "FAIL R9: tokens stored without flutter_secure_storage"; }
# R9 durable reinstall restore — only when the contract marks it REQUIRED
grep -q "play_services_block_store" pubspec.yaml && grep -rq "PlayServicesBlockStore" lib/ && grep -rq "FlutterSecureStorage" lib/ || echo "(if durable restore REQUIRED) FAIL R9: Keychain + Block Store tiers missing"

# R10 accessibility: text scaling honored, icon buttons labelled, dark theme, reduce motion, no strobe
grep -rnH "withNoTextScaling" $SCOPE --include='*.dart' && echo "FAIL R10: withNoTextScaling pins text size — content must honor OS text scaling"
grep -rnHE 'TextScaler\.noScaling|TextScaler\.linear\(1(\.0)?\)|textScaleFactor: *1' $SCOPE --include='*.dart' && echo "FAIL R10: text scaling disabled"
python3 - $SCOPE <<'PY'
import re, glob, os, sys
bad = []
files = [g for a in sys.argv[1:] for g in (glob.glob(a + '/**/*.dart', recursive=True) if os.path.isdir(a) else [a])]
for f in files:
    s = open(f, encoding='utf-8').read()
    for m in re.finditer(r'IconButton(\.\w+)?\(', s):
        i, d = m.end(), 1
        while d and i < len(s):
            d += {'(': 1, ')': -1}.get(s[i], 0); i += 1
        if 'tooltip:' not in s[m.end():i]:
            bad.append(f'{f}:{s.count(chr(10), 0, m.start()) + 1}')
print('FAIL R10: IconButton without tooltip (unless wrapped in Semantics):', bad) if bad else print('IconButton tooltips OK')
PY
grep -rq "darkTheme:" lib/ && grep -rq "ThemeMode.system" lib/ || echo "FAIL R10: no dark theme / ThemeMode.system default"
grep -rq "disableAnimations" lib/ || echo "CHECK R10: OS Reduce Motion (MediaQuery.disableAnimations) not respected"
grep -rnH "MaterialTapTargetSize.shrinkWrap" $SCOPE --include='*.dart' && echo "CHECK R10: shrinkWrap tap targets may fall below 48dp"
grep -rnHiE "flash|strobe|blink" $SCOPE --include='*.dart' | grep -iE "Timer|Duration" && echo "CHECK R10: verify nothing flashes faster than 3/sec"

# R11 test depth: count test cases, not files
UNIT=$(grep -rhE '^[[:space:]]*test\(' test/ --include='*_test.dart' 2>/dev/null | wc -l | tr -d ' ')
WIDGET=$(grep -rh 'testWidgets(' test/ --include='*_test.dart' 2>/dev/null | wc -l | tr -d ' ')
INTEG=$(grep -rh 'testWidgets(' integration_test/ --include='*.dart' 2>/dev/null | wc -l | tr -d ' ')
FLOWS=$(ls .maestro/flows/F*.yaml 2>/dev/null | wc -l | tr -d ' ')
echo "unit=$UNIT widget=$WIDGET maestro_flows=$FLOWS integration_test=$INTEG"
[ "${UNIT:-0}" -ge 3 ] || echo "FAIL R11: fewer than 3 unit tests"
[ "${WIDGET:-0}" -ge 2 ] || echo "FAIL R11: fewer than 2 widget tests (need >=1 per primary screen)"
if command -v maestro >/dev/null; then
  [ "${FLOWS:-0}" -ge 1 ] || echo "FAIL R11: no Maestro flows in .maestro/flows/ (one per PRD primary flow)"
  [ -x .maestro/suite.sh ] && [ -f .maestro/subflows/ready.yaml ] || echo "FAIL R11: .maestro/suite.sh or subflows/ready.yaml missing"
  for f in .maestro/flows/*.yaml .maestro/subflows/*.yaml; do
    [ -e "$f" ] || continue
    grep -vE '^[[:space:]]*#' "$f" | grep -qE '<__|<[a-z][^>]*>' && echo "FAIL R11: template placeholder left in $f"
    case "$f" in */subflows/*) continue;; esac
    grep -qE 'assertVisible|assertNotVisible|assertTrue' "$f" || echo "FAIL R11: $f asserts nothing"
    case "$(basename "$f")" in F*) grep -q 'clearState: true' "$f" || echo "FAIL R11: $f does not start from a fresh install";; esac
  done
  grep -lq 'stopApp: false' .maestro/flows/*.yaml 2>/dev/null || echo "FAIL R3: no flow proves resume (pressKey: home -> launchApp stopApp: false)"
else
  [ "${INTEG:-0}" -ge 1 ] || echo "FAIL R11: maestro not installed and no integration_test driving the main PRD flow"
fi
if $RIVERPOD; then
  grep -rq "ProviderContainer" test/ 2>/dev/null || echo "FAIL R11: unit tests do not drive notifiers via ProviderContainer"
else
  echo "CHECK R11 ($ARCH): unit tests drive the state holders directly (bloc: blocTest / bloc.add + expected states)"
fi
[ "$MODE" = update ] && echo "CHECK R11: every NEW/CHANGE flow needs unit + widget coverage in the changed tests:" && echo "$CHANGED" | grep -E '^(test|integration_test)/'

# Screenshot mode (generator §5a.5): the screenshot phase cannot capture without it, after the binary ships
{ [ "$MODE" = new ] || [ "$ADMOB" = true ]; } && ! grep -rqE "fromEnvironment\(['\"]screenshots" lib/ \
  && echo "FAIL R8: no screenshots dart-define in lib/ (AppConfig.screenshotMode, generator §5a.5)"

# R12 permissions & privacy (when REQUIRED): usage strings localized per locale, privacy manifest, denial paths
plutil -convert xml1 -o - ios/Runner/Info.plist 2>/dev/null | grep -oE 'NS[A-Za-z]+UsageDescription' | sort -u | while read -r k; do
  for l in <locales>; do grep -qs "$k" "ios/Runner/$l.lproj/InfoPlist.strings" || echo "FAIL R12: $k not localized for $l"; done
done
[ -f ios/Runner/PrivacyInfo.xcprivacy ] && grep -q "PrivacyInfo.xcprivacy" ios/Runner.xcodeproj/project.pbxproj || echo "FAIL R12: PrivacyInfo.xcprivacy missing or not registered in the Xcode project"
if grep -q "permission_handler" pubspec.yaml; then
  grep -rq "openAppSettings" lib/ || echo "FAIL R12: no openAppSettings() path for permanently denied"
  grep -rq "isPermanentlyDenied" lib/ || echo "FAIL R12: permanently-denied state not handled"
  grep -rnH "\.request()" $SCOPE --include='*.dart'   # read each call site: an in-app rationale must precede it
fi

# R7 every asset path declared in pubspec must exist on disk
python3 - <<'PY'
import re,glob,os,sys
try: txt=open('pubspec.yaml').read()
except FileNotFoundError: sys.exit(0)
m=re.search(r'\n\s*assets:\s*\n((?:\s*-\s.*\n)+)', txt)
missing=[]
if m:
    for line in m.group(1).splitlines():
        p=line.strip().lstrip('- ').strip().strip('"\'')
        if not p: continue
        if p.endswith('/'):
            if not (os.path.isdir(p) and os.listdir(p)): missing.append(p)
        elif not os.path.exists(p): missing.append(p)
print('MISSING ASSETS:',missing) if missing else print('assets OK')
PY
```

Judge the output against `docs/app-gotchas.md`:

- A `FAIL` line on a REQUIRED gate fails that gate. A `CHECK` line means read the code and decide;
  record the decision in the feedback file. A gate the contract marked N/A is skipped — but verify
  the N/A still holds: R2 N/A with an HTTP client imported, R4 N/A with a `TextField` present, or
  R12 N/A while the app uses a runtime permission (`permission_handler`, or an `NS*UsageDescription`
  other than `NSUserTrackingUsageDescription`) or has `monetization.admob_enabled: true` is a FAIL.
  An ATT string alone never voids R12 N/A — ads are judged by `admob_enabled`, not `skip_monetize`.
  Update mode: count FAIL lines only as the Update mode section says (absent from the `$BT` run, or
  a selected gap).
- **R1:** a data-backed screen that shows a blank or spinner forever on error, or an empty list with
  no message, is a FAIL — confirm visually in Step 7.
- **R3:** missing lifecycle hook or undisposed controllers is a FAIL.
- **R5:** default Flutter icon/splash, an alpha-channel icon, a missing dark splash colour, or a
  "Runner"/slug display name is a FAIL — the app must look shipped. Update mode: the icon and display
  name must be unchanged vs baseline unless the change request changes them.
- **R6:** the app must open directly in `config.orientation` (no rotate flash), carry the
  `device_family`-correct `TARGETED_DEVICE_FAMILY` in every build configuration, set
  `ITSAppUsesNonExemptEncryption=false`, handle the root back button (SnackBar double-exit), and
  carry a byte-identical bundle id equal to `config.bundle_id` (update mode, D4: iOS id ==
  `bundle_id`, Android id == `bundle_id_android || bundle_id`; divergent or non-lowercase shipped
  ids are accepted).
- **R7:** any missing declared or referenced asset, or a missing CI workflow, is a FAIL.
- **R8:** a missing Play hi-res icon (512×512) or feature graphic (1024×500), wrong dimensions, or
  `hasAlpha: yes` is a FAIL — the listing can't publish without them. iOS screenshots are produced
  and checked by the screenshot phase, not here.
- **R9:** storage outside repositories, no schema version, or a token in `shared_preferences` is a
  FAIL. When the contract marks durable restore REQUIRED, a missing Keychain/Block Store tier is a FAIL.
- **R10:** `withNoTextScaling` on content, unlabelled icon-only buttons, or no dark theme is a FAIL;
  overflow at large text is checked visually in Step 7. A full-screen effect that flashes faster
  than 3×/second is a FAIL.
- **R11:** a passing `flutter test` that only checks constants is a FAIL — there must be ≥3 real
  unit tests, ≥1 widget test per primary screen (min 2), and ≥1 integration test for the main flow
  that also asserts persistence, and all must pass.
- **R12:** every permission the app requests needs an in-app rationale first and denied /
  permanently-denied handling; every usage string must exist in every locale. The ATT prompt,
  `NSUserTrackingUsageDescription`, and the UMP-before-ATT order are added by the monetize phase
  after QA — their absence here is expected, not a FAIL (update mode with `admob_enabled: true`:
  they already ship and must still be there).

### Step 6 — Contract criteria evidence

For each criterion in `contract.md` §§ "Mandatory Hard Gates", "Platform-Robustness Gates", and
"Functional Criteria", record a row in the feedback evidence table showing the command run, the
result, and any screenshot or log path (Step 7 rows are added as Step 7 runs). Do not mark a
criterion DONE without running a command or capturing a screenshot that directly verifies it.

### Step 7 — Run the device suite and walk every primary flow

**This step is mandatory. A PASS verdict is not valid without completing it.**

The device verdict rests on `.maestro/` (protocol §3 Device test suite; pitfalls:
`docs/app-gotchas.md` → Device flow tests (Maestro)) — files every round re-runs, so the evidence is
reproducible and a fixed bug stays fixed. Tap around with the iOS Simulator control tool to explore,
but a finding that decides the verdict is written down as a flow (item 7). Run the whole suite
**every round**: evidence from an earlier round never counts, not even for "unchanged" code, and
widget tests never stand in for a device run. Every Step 7 Evidence row cites this round's
`round-<N>-*` files and the `flows: <passed>/<total>` line of each run. Address devices by UDID /
serial, never `booted` (two booted simulators → the wrong one).

Boot an iOS simulator — `<simulator>` is the name of any available iPhone from
`xcrun simctl list devices available` (no iOS on this machine, or an Android-only app → do items
2–4 on the Android emulator, item 6) — then build and install the app; the flows launch it (no
`flutter run`):

```bash
open -a Simulator
xcrun simctl boot "<simulator>" 2>/dev/null || true
SIM=$(xcrun simctl list devices booted | grep -F "<simulator> (" | grep -oE '[0-9A-F-]{36}' | head -1)
# Fresh boot: every Flutter app's process is `Runner`, so another app left running would write
# into this app's device log.
xcrun simctl shutdown "$SIM"; xcrun simctl boot "$SIM"
cd "<app>"
flutter build ios --simulator --debug --no-pub
xcrun simctl install "$SIM" build/ios/iphonesimulator/Runner.app
```

Each `.maestro/suite.sh` call below runs for minutes — Bash `run_in_background: true`. It prints
`flows: <passed>/<total>`, a `FAIL <flow>` line per failed flow, and `FAIL console` / `FAIL log`
lines; screenshots land in `docs/harness/screenshots/<prefix>-F<n>-<screen>.png`.

1. **Suite audit** — the R11 block (Step 5) passed, and every PRD primary flow has its `F<n>` flow
   that really does the flow: fresh install, an assert after every action, kill + relaunch + assert
   on the data it created. A flow that taps through without asserting the outcome is an R11 FAIL —
   do not let it count as evidence.
2. **Suite, light** — `.maestro/suite.sh "$SIM" round-<N>-ios`. Every flow must pass: a failing
   `F<n>` flow is a Hard Gate 7 FAIL (cold start, empty state, the flow end to end, and data
   surviving the relaunch are all asserted inside it); a failing `regress_r*` flow means an
   earlier fix regressed. Lost data after relaunch is a Hard Gate 7 failure.
3. **Console check** — read `docs/harness/screenshots/round-<N>-ios-device.log`. A `FAIL console`
   line (exception, overflow, `setState() called after dispose`) is a Hard Gate 8 failure (an
   overflow is also R10). `FAIL log` (empty log) means capture broke, not a clean run: capture again
   with `xcrun simctl spawn "$SIM" log stream --level debug --predicate 'process == "Runner"'` while
   re-running one flow; still empty → HG8 is not verified → FAIL.
4. **Dark mode + largest text (UI/UX)** — `.maestro/suite.sh "$SIM" round-<N>-ios-dark dark`, then
   `.maestro/suite.sh "$SIM" round-<N>-ios-xxxl xxxl` (replays the `ui` flows; the script sets the
   simulator setting and restores it on exit). Dark: check contrast and that nothing stays
   hard-coded white/black. XXXL: any overflow stripe, clipped or truncated essential text, or an
   unreachable button is an R10 FAIL (an app-wide `TextScaler.clamp(maxScaleFactor: 2.0)` is
   allowed — judge at the clamped size).
5. **iPad (only when `device_family: universal`)** — install on an iPad simulator and run
   `.maestro/suite.sh "$IPAD" round-<N>-ipad`; the layout must use the width (max content width /
   master-detail), not stretched phone UI.
6. **Android — every platform the app ships on runs the suite** (bugs seen only on Android
   surfaced after submission when QA ran iOS alone). Use an emulator no other session is driving
   (`EMU` = its serial from `adb devices`); `adb -s "$EMU" shell df -h /data` must show ≥ 1 GB
   free. Then
   `flutter build apk --debug && adb -s "$EMU" install -r build/app/outputs/flutter-apk/app-debug.apk`,
   `.maestro/suite.sh "$EMU" round-<N>-android` and
   `.maestro/suite.sh "$EMU" round-<N>-android-xxxl xxxl`. The same rules as items 2–4 apply.
7. **Every new device-visible bug becomes a flow** — for each failure this round found outside the
   existing flows (while exploring, or an assertion a flow was missing), write
   `.maestro/flows/regress_r<N>_<slug>.yaml` from `${CLAUDE_PLUGIN_ROOT}/templates/maestro/flow.yaml.template`
   that reproduces it and fails now (tag `ui` when it is visual; name its screenshots
   `R<N>-<slug>-<screen>` — the flat copy would overwrite the `F<n>-` shots), and cite it in the
   fix item. The
   generator fixes the app until it passes; the flow stays in the suite for good.
8. Study every screenshot carefully. Check for: blank/white screens, overflow stripes, overlapping
   or clipped UI, a keyboard covering the focused field, missing empty/error states, wrong language
   (must match `default_language` on a device in that locale), design-token inconsistencies, and
   UX problems — unclear primary action, dead ends with no way back, touch targets that look too
   small, missing feedback after an action.

Any crash, blank screen, lost data after relaunch, or console error is a Hard Gate failure
(protocol §3 Hard Gates 7–8).

### Step 8 — Independent review (fresh context)

The evaluator shares the generator's session and leans toward its reading of the code — in a real
run, a PASS was reversed only by an outside review. Spawn one read-only `general-purpose` agent
(protocol §8): `model: sonnet` in round 1, `model: haiku` in round N > 1. Give it
`docs/harness/contract.md`, the PRD's primary flows, and this round's diff — never your draft
verdict or Steps 1–7 results:

- round 1, `mode: new` — all of `lib/` and `.maestro/`;
- `mode: update` — `git diff <baseline.commit>..HEAD`;
- round N > 1 — `git diff <Commit evaluated in round N-1>..HEAD`.

Ask it for: stubs or fake data, a primary flow or REQUIRED R-gate the code does not really
implement, persistence that only lives in memory, errors swallowed silently, and Maestro flows that
pass without asserting the outcome. A finding counts only after you reproduce it (open the
file:line, re-run the command or flow); then it is a fix item like any other. List the rest under
Evidence as "not reproduced". Record `git rev-parse HEAD` as the Evidence row `Commit evaluated`.

---

## 6.2 Quality Scoring (`--strict` only)

Run this section only when `strict_mode: true` in `config.md` or `--strict` is passed.

Score the app on four axes, each 0–10:

| Axis | What to assess |
|---|---|
| **Usability & flow clarity** | Can a first-time user finish each primary flow without guessing? Clear labels, obvious primary actions, sensible navigation and back behaviour, onboarding that explains value |
| **Visual craft & consistency** | Design tokens applied consistently, spacing rhythm, typography hierarchy, polished light + dark themes, no jank |
| **Robustness (states / offline / errors)** | Loading, empty, error, and offline states handled; inputs validated; nothing lost on restart or background |
| **Value & originality** | Real, distinct value relative to the competitors identified in research (App Store 4.2 / 4.3 risk) |

Scoring threshold:

- Default (`strict_mode: false`): weighted average ≥ **7 / 10** to advise PASS (advisory only).
- Strict profile (`strict_mode: true`): weighted average ≥ **8 / 10** required for PASS.

Weight: Usability & flow clarity 30 %, Visual craft & consistency 25 %, Robustness 25 %,
Value & originality 20 %.

Record the score for each axis and the weighted total in the feedback file. If the weighted
total is below threshold, the verdict is FAIL regardless of 6.1 results, and each axis below
7 must have at least one specific, reproducible fix listed.

---

## 6.3 Edge-Case Sweep (`--strict` only)

Run this section only when `strict_mode: true` in `config.md` or `--strict` is passed.

Spawn six specialist agents via the `Agent` tool (protocol §8). The four device roles run **one
after another** on the same UDID (`model: sonnet`) — two agents on one simulator fight over it;
test-gaps (`model: haiku`) and adversarial-reviewer (`model: opus`) only read, so they run in
parallel with them. No agent edits the app. All six must report PASS for the overall verdict to be
PASS; a single FAIL from any agent is a FAIL verdict. Every device behavior that fails becomes a
`regress_r<N>_*` flow (Step 7 item 7), written by the evaluator once all verdicts are in.

| Agent role | Brief |
|---|---|
| **ux-states** | Exercise empty (fresh install, everything deleted), error (storage/network failure forced via a provider override), offline (network apps), very long text (200-character names, the longest translation), and RTL-safe layout (`EdgeInsetsDirectional`/`AlignmentDirectional`, no hard-coded left/right; a widget test under `Directionality(textDirection: TextDirection.rtl)`). |
| **data-integrity** | Persistence across kill + relaunch; migration from the previous schema version (write old-format data, launch, verify); rapid edits (20 adds/toggles in quick succession — no lost or duplicated rows); deletion (delete one, delete all, undo if offered, then relaunch). |
| **lifecycle/crash** | Background mid-flow and resume; rotation only if `config.orientation: all`; an interrupted form (background with a half-filled form → input kept or discard confirmed); permission denial and permanent denial for every permission used. Confirm no crash and no lost state. |
| **performance** | Profile mode does not run on simulators/emulators: with a physical device connected, `flutter run --profile -d <device>`, check frame rendering in DevTools, scroll a list seeded with ≥ 500 items and flag sustained frames over 16 ms, flag cold start over 2 s. With none, review the code only — `ListView.builder` for unbounded lists, narrow `select` watches, no work in `build()`, no whole-screen rebuild on a single field change — and report "frame timing not measured". |
| **test-gaps** | Identify the three highest-risk untested paths and specify the test each needs (unit, widget, or a Maestro flow) as fix items for the generator; write nothing in the app. |
| **adversarial-reviewer** | Adversarially review the code for secrets in the binary or repo, insecure storage (tokens/PII in `shared_preferences` or logs), and store-policy risks: 4.2 Minimum Functionality, 4.3 Spam, 5.1.1 data collection / permission strings, 3.1.1 digital goods outside IAP. |

Each agent must return a structured PASS/FAIL verdict with evidence. Collect all six verdicts
before proceeding to Judgment.

---

## Judgment

After completing all applicable sections (6.1, and 6.2 + 6.3 if `--strict`), write the verdict.

### Determine verdict

- **PASS** if and only if:
  - All 6.1 Mandatory Hard Gates pass AND every REQUIRED R-gate passes AND all 6.1 Functional
    Criteria verified with evidence.
  - If `--strict`: 6.2 weighted score ≥ threshold AND all six 6.3 agents report PASS.
- **FAIL** if any Hard Gate or REQUIRED R-gate fails, any functional criterion lacks evidence, or
  (when `--strict`) 6.2 score is below threshold or any 6.3 agent reports FAIL.

### max_rounds check

Before writing the verdict, check: if `current_round == max_rounds`, force the judgment. Do
not return FAIL regardless of results — write the verdict on the current state, record the
forced-advance note in the feedback file, and proceed to PASS transitions (per protocol §7
`evaluator → max_rounds → monetize / build`, applying the same `skip_monetize` branch as PASS).

### Write feedback/round-N-qa.md

Create `docs/harness/feedback/round-<N>-qa.md` following the layout in
`docs/harness-protocol.md` §5. Fill:

- `## Verdict` — **PASS** or **FAIL** (bold).
- `## Evidence` — one row per criterion checked; include screenshot paths for simulator checks.
- `## Failed Criteria` — for each FAIL, a specific reproducible fix (file:line, what is wrong, the
  exact fix). If PASS, write "none".

Never leave placeholder text. Every criterion must have a real command output or screenshot path
as evidence.

### Update state.md (PASS)

On PASS (or forced advance at max_rounds), the app has been built and has passed QA — but before
any deploy work (monetize/build/screenshot/submit), there is a **human-approval gate** by default
so the user can actually use and approve the app.

First read `skip_monetize` and `auto_deploy` from `docs/harness/config.md`, and decide `next_role`:
- if `skip_monetize: true` → `next_role: build`
- otherwise → `next_role: monetize`

Then branch on `auto_deploy`:

**Default (`auto_deploy: false`) — PAUSE for human review.**
Write `state.md` with `status: paused`, `pause_reason: manual_action`, and the `next_role`
decided above (per protocol §7 rule 10). Append a `pipeline-log.md` row and PRINT a review
checklist for the user. Print it in `config.default_language` — translate the prose, keep commands,
paths, and `/app-harness --resume` verbatim. English template:

> App built and QA passed. **Check it yourself before deploying:** run `cd <app> && flutter run`,
> try every primary flow, and review the QA screenshots in `docs/harness/screenshots/` and
> `docs/harness/feedback/round-<N>-qa.md`. When you are satisfied, run `/app-harness --resume` to
> deploy (monetize → build → screenshot → submit).

(With `skip_monetize: true` the chain reads build → screenshot → submit.)

```yaml
status: paused
current_phase: evaluator
next_role: monetize   # or "build" if skip_monetize: true
pause_reason: manual_action
updated_at: "<ISO-8601 UTC now>"
```

The orchestrator halts on `status: paused`; on `--resume`, `app-harness-resume` confirms the
user approved and dispatches the stored `next_role`.

**`auto_deploy: true` — no pause, continue straight to deploy.**
Write `status: running` with the same `next_role` so the orchestrator auto-continues:

```yaml
status: running
current_phase: evaluator
next_role: monetize   # or "build" if skip_monetize: true
updated_at: "<ISO-8601 UTC now>"
```

Leave `current_round`, `created_at`, and `resume_attempts` unchanged. (In the `auto_deploy: false`
case you set `pause_reason: manual_action`; in the `auto_deploy: true` case leave `pause_reason`
unchanged.)

### Update state.md (FAIL)

On FAIL (and `current_round < max_rounds`), update `docs/harness/state.md` per protocol §2 and
the `evaluator → generator` transition in §7. Increment `current_round` and set
`status: running` atomically (protocol §7 rule 2):

```yaml
status: running
current_phase: evaluator
next_role: generator
current_round: <N+1>
checkpoint: ""
updated_at: "<ISO-8601 UTC now>"
```

Leave `created_at`, `resume_attempts`, and `pause_reason` unchanged. **Reset `checkpoint: ""`** — the
next round is a fresh feedback-driven pass, so the generator must not skip sub-phases (per protocol §2).

### Append to build-log.md

Append one row to `docs/harness/build-log.md` per protocol §6:

```
| <N> | evaluator | PASS/FAIL | <duration> | <one-line summary> |
```

### Append to pipeline-log.md

Append one row to `docs/harness/pipeline-log.md` per protocol §6:

```
| <ISO-8601 UTC now> | PASS/FAIL | evaluator | round <N>; next: monetize|build/generator |
```

When the PASS path pauses for the human-review gate (default, `auto_deploy: false`), additionally
append a `pause` event row so `app-harness-resume` can show the user what they are approving:

```
| <ISO-8601 UTC now> | pause | evaluator | manual_action: run/approve the built app before deploy; next: monetize|build |
```

---

## Error Handling

- If `contract.md` is missing or has no `## Status: AGREED`, abort immediately.
- If `handoff/round-<N>-gen.md` is missing, abort with a clear message; do not set a FAIL
  verdict — the generator has not run yet.
- If the simulator cannot be booted (hardware CI), document the failure, skip Step 7, and set
  the verdict to FAIL with fix: "boot a simulator and complete Step 7."
- If `maestro` is not installed (`command -v maestro` prints nothing), say so in the feedback, run
  `flutter test integration_test/ -d "<simulator>"`, and walk the flows with the iOS Simulator
  control tool (`flutter run`, `xcrun simctl io "$SIM" screenshot`,
  `xcrun simctl ui "$SIM" appearance|content_size`, restored afterwards); add the Evidence row
  `Maestro | not installed — brew install maestro | —`.
- If a simulator setting was changed (appearance, content size) and the run aborts, restore it
  before exiting (`suite.sh` restores on its own exit; a killed run may not —
  `xcrun simctl ui "$SIM" appearance light; xcrun simctl ui "$SIM" content_size large`).
- Update mode: always remove the baseline worktree before exiting
  (`git worktree remove --force "${TMPDIR:-/tmp}/harness-baseline-<app_slug>"`).
- If any agent in 6.3 returns an error (not FAIL, but a tool error), retry once, then count it
  as FAIL with note "agent error — retry required."
