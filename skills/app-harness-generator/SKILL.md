---
name: app-harness-generator
description: Phase 5 — build the Flutter app (Riverpod + go_router, feature-first) in 3 gated sub-phases (scaffold + architecture + navigation → data + state → UI + content + polish), then self-evaluate against the contract.
argument-hint: ""
allowed-tools: [Agent, Read, Write, Edit, Bash, Glob, Grep, Skill]
---

# app-harness-generator

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

Phase 5 of the flutter-app-harness pipeline. Builds the app in three gated sub-phases
(5a → 5b → 5c). Each sub-phase ends with a HARD GATE (`flutter analyze` zero issues +
`flutter test` all pass) before the next one starts. On round N > 1 it reads the previous
evaluator feedback and fixes only the listed failures.

All file schemas (`config.md`, `state.md`, `handoff/round-N-gen.md`, `feedback/round-N-qa.md`)
and the phase transition table are defined in `docs/harness-protocol.md`, the single source of
truth (§1 config, §2 `state.md`, §3 gates, §4 handoff layout, §5 feedback layout, §7 the
`generator → evaluator` transition). Do not redefine schemas here. The robustness patterns behind
gates R1–R12 live in `docs/app-gotchas.md`. Cite it and emit its patterns. Do not restate it.

Fixed stack (protocol header): `flutter_riverpod` (`Notifier` / `AsyncNotifier`, no codegen
required), `go_router` (one `GoRouter` in `lib/app/router.dart`), feature-first layout
(`lib/features/<feature>/{data,presentation}`), local-first storage. The code below targets
Riverpod 3.x (`retry:`, `Override` from `package:flutter_riverpod/misc.dart`). If pub resolves
2.x, adapt those two spots.

---

> **`config.mode: update`?** Read [Update mode](#update-mode-mode-update) below **before 5a**: work on
> a `harness/<YYYYMMDD>-update` branch, follow `config.architecture`, and gate against `config.baseline`.
> These new-mode steps are **skipped** (they would damage a shipped app):
> - 5a.1 entirely: `flutter create`, the bundle-id / `MainActivity` rewrite, the `docs/harness` move.
> - 5a.2 demo removal.
> - 5a.3 pubspec header: never touch `name:`, `description:`, `publish_to:` or `version:`. Never reset
>   `version:` to `1.0.0+1`; only the build phase bumps it. Skip the fixed-stack `flutter pub add`
>   list; add only what the delta needs.
> - 5a.4–5a.8 wholesale writes of `app_config.dart`, `main.dart`, `bootstrap.dart`, `app.dart`,
>   `router.dart`, theme, l10n: extend the project's existing files instead (screenshot flag: see Update mode).
> - 5a.9 CI, 5c.9 branding (icon, splash, display name), 5c.11 README/LICENSE: keep the existing ones.
> - 5a.10 `git init`. **But do** run its guarded `.gitignore` append (adds
>   `<plugin-templates>/gitignore.template` when `.gitignore` lacks `play-store-key.json`), because the
>   build phase copies signing secrets into the repo.
> - 5c.10.1/.2: keep the shipped orientation and device family (dropping iPad from a live universal app is rejected).
>   5c.10.5 writes `PrivacyInfo.xcprivacy` only if absent. 5c.10.6/.8 only raise the iOS target /
>   `minSdk`, never lower an existing higher value.
> - 5c HARD GATE "bundle id identical on both platforms": replaced by "ids unchanged from audit" (iOS =
>   `bundle_id`, Android = `bundle_id_android` or else `bundle_id`).
>
> Only CI, branding, README/LICENSE, orientation/device family and the privacy manifest may change,
> and only when a selected audit gap targets them. `name:`, `version:`, the bundle ids, `flutter create`
> and the harness move have no exception. Every other step applies only to the delta PRD's CHANGE/NEW
> items and selected fixes.

## Paths

cwd is either `<projects-dir>` (the directory where the orchestrator bootstrapped `docs/harness/`,
i.e. the parent of the app project) or, after the orchestrator `cd`s in following round 1, the
app project itself. `./docs/harness/config.md` exists in both cases. Read `app_slug` from it first.
If cwd is still `<projects-dir>` after the 5a.1 move, the harness is `./<app_slug>/docs/harness/`.
Find it with `ls */docs/harness/state.md` and pick the one with `next_role: generator`.

- `<app_pkg>` = `app_slug` with `-` → `_`. This is the Dart package name (pubspec `name:`, every
  `package:` import). A kebab-case name is invalid Dart.
- **cwd is the project** when `./pubspec.yaml` exists with `name: <app_pkg>`. Then `APP=$PWD` and
  `<projects-dir>` = its parent. Never `flutter create` a nested `<app_slug>/<app_slug>`.
- Otherwise `<projects-dir>` = cwd and `APP=<projects-dir>/<app_slug>`.
- Harness dir = `$APP/docs/harness` once it exists (5a.1 moves it there). Before that it is
  `<projects-dir>/docs/harness`. All later reads and writes of harness files use the moved path.
- `<plugin-templates>` = this plugin's `templates/` directory as an absolute path:
  `${CLAUDE_PLUGIN_ROOT}/templates` when that env var is set, else `<skill base directory>/../../templates`
  (the skill base directory is shown when this skill loads). Never a bare relative `templates/...`
  path: it resolves against the app, and with `>` the shell truncates the target before the copy fails.
- `<lproj>` = a `config.locales` entry as an iOS `.lproj` name: `zh` / `zh-Hans` / `zh_CN` →
  `zh-Hans`, `zh-Hant` / `zh_TW` → `zh-Hant`, every other locale as-is.
- `mode: update` (protocol §1): `APP = config.project_path`, and the harness already lives inside
  it. See **Update mode** below.

---

## Round Handling and Feedback Intake

### Determine current round

Read `state.md` from the harness dir and extract `current_round` (integer, ≥ 1).

### Round 1 — build from scratch

When `current_round` is 1:

1. Read `config.md`: `mode`, `app_slug`, `app_name`, `bundle_id`, `default_language`, `locales`,
   `orientation`, `device_family`, `backend`, `developer.company`, `developer.privacy`.
2. Read the latest PRD (`docs/harness/plans/*-prd.md`, sort descending, take the first). You need
   its user flows, feature list, `lib/` map, storage choice, onboarding/permission needs, and scope
   guard.
3. Read the latest design doc (`docs/harness/plans/*-design.md`, same rule). You need the token
   spec, light/dark palettes, screen inventory with loading/empty/error states, and any external
   design source (Figma/Stitch).
4. Read `docs/harness/contract.md`. If `## Status: AGREED` is missing, abort with
   `app-harness-generator: contract not AGREED — run app-harness-contract first`.
5. Read `checkpoint` from `state.md` (protocol §2). **Re-entry:** if a prior run crashed or paused
   mid-phase, skip every sub-phase `≤ checkpoint` (its HARD GATE passed and its output exists) and
   resume at the next one. `checkpoint: 5a` → start at 5b. `checkpoint: 5c` → go straight to
   handoff. `""` → start at 5a. This makes the generator safe to re-run without redoing, or
   colliding with, completed work.

### Round N > 1 — fix only listed failures (feedback intake)

When `current_round` is greater than 1:

1. Read `docs/harness/feedback/round-<N-1>-qa.md` (protocol §5). If it does not exist, abort with
   `app-harness-generator: feedback file for round <N-1> not found — cannot determine fixes`
   (see Error handling).
2. Parse `## Failed Criteria`. Each entry names a criterion, a location, and the prescribed fix.
3. Make only the minimum change for each listed fix. Do NOT redesign or refactor areas that were
   not listed.
4. One commit per discrete fix: `fix(<feature|scope>): <criterion id> <what changed>`. On
   re-entry (crash mid-round, `checkpoint: ""`), check `git log --oneline` and skip fixes that
   already landed.
5. Run the 5c HARD GATE (the full command set plus every 5c check the fixes touched). When green,
   write `checkpoint: 5c`, then write the handoff.

---

## Sub-phase 5a — Scaffold + Architecture + Navigation

### 5a.1 Create the Flutter project (flutter create)

```bash
if grep -q "^name: <app_pkg>$" pubspec.yaml 2>/dev/null; then APP=$PWD; else APP=<projects-dir>/<app_slug>; fi
if [ -d "$APP/lib" ]; then
  echo "project already exists — reusing (skipping flutter create)"
else
  flutter create --platforms ios,android --org com.<company> --project-name <app_pkg> "$APP"
fi
```

**Idempotency:** `flutter create` fails if the target already exists, which would break a resume or a
re-run of round 1. The guard makes 5a.1 safe to re-enter: it reuses the existing scaffold instead of
hard-failing. If the user passed `--clean`, `rm -rf "$APP"` first, then create fresh. Only do this
while the harness still lives in `<projects-dir>/docs/harness`. Never delete a project that
contains `docs/harness/`.

**Bundle id: set it explicitly and IDENTICALLY on both platforms.** `flutter create` derives the
bundle id from `--org` + project name. It gives `com.<company>.<appPkgCamel>` on iOS and
`com.<company>.<app_pkg>` (with underscores) on Android. Force both to `config.bundle_id`
(lowercase `[a-z0-9.]`, protocol §1):

```bash
cd "$APP"; B=<bundle_id>
sed -i '' -E "s/PRODUCT_BUNDLE_IDENTIFIER = [^;]*\.RunnerTests;/PRODUCT_BUNDLE_IDENTIFIER = $B.RunnerTests;/; /RunnerTests;/! s/PRODUCT_BUNDLE_IDENTIFIER = [^;]*;/PRODUCT_BUNDLE_IDENTIFIER = $B;/" ios/Runner.xcodeproj/project.pbxproj
sed -i '' -E "s/(namespace|applicationId) = \"[^\"]*\"/\1 = \"$B\"/" android/app/build.gradle.kts
# The manifest's ".MainActivity" resolves against `namespace`. Move the class to match, or the app
# crashes at launch with ClassNotFoundException.
OLD=$(find android/app/src/main/kotlin -name MainActivity.kt); NEW=android/app/src/main/kotlin/$(echo $B | tr . /)/MainActivity.kt
if [ "$OLD" != "$NEW" ]; then mkdir -p "$(dirname "$NEW")"; sed -E "s/^package .*/package $B/" "$OLD" > "$NEW"; rm "$OLD"; find android/app/src/main/kotlin -type d -empty -delete; fi
```

Verify that iOS `PRODUCT_BUNDLE_IDENTIFIER` (all 3 Runner build configs) == Android
`applicationId` == `namespace` == `config.bundle_id`, **byte-for-byte** (same case, no `_`, no
`-`). The RunnerTests target keeps `<bundle_id>.RunnerTests`. The AdMob app and the store records
use this exact id.

```bash
grep -o 'PRODUCT_BUNDLE_IDENTIFIER = [^;]*' ios/Runner.xcodeproj/project.pbxproj | sort | uniq -c
grep -nE 'applicationId|namespace' android/app/build.gradle.kts
```

**Move the harness into the project** so all artifacts share one repository. The source is
`<projects-dir>/docs/harness`, where the orchestrator bootstrapped. It is not this plugin's
directory. `flutter create` makes no `docs/`, so create it first. Skip the move if it already
happened:

```bash
if [ -d "<projects-dir>/docs/harness" ] && [ ! -e "$APP/docs/harness" ]; then
  mkdir -p "$APP/docs" && mv "<projects-dir>/docs/harness" "$APP/docs/harness"
fi
```

### 5a.2 Remove the counter demo

Delete the demo only while it is still the demo. On re-entry these paths hold real code:

```bash
grep -q "MyHomePage" lib/main.dart 2>/dev/null && rm lib/main.dart
grep -q "Counter increments" test/widget_test.dart 2>/dev/null && rm test/widget_test.dart
```

### 5a.3 Configure pubspec.yaml

Set `description: <app_name>`, `publish_to: none`, and `version: 1.0.0+1`: explicit semver
`MAJOR.MINOR.PATCH+BUILD`. The App Store marketing version is `1.0.0`, not `1.0`, and the build
phase bumps `+BUILD` on each upload. `name:` is already `<app_pkg>`. Add dependencies with
`flutter pub add` so pub resolves the latest mutually compatible versions instead of stale pins:

```bash
flutter pub add flutter_riverpod go_router shared_preferences intl url_launcher \
  'flutter_localizations:{"sdk":"flutter"}'
flutter pub add dev:image dev:flutter_launcher_icons dev:flutter_native_splash \
  'dev:integration_test:{"sdk":"flutter"}'
```

(`flutter_test` + `flutter_lints` come from `flutter create`. `url_launcher` serves the Settings
privacy-policy link.) Add a package only when its condition holds:

| Condition (PRD / config) | Add |
|---|---|
| the app stores auth tokens / API secrets | `flutter_secure_storage` (never `shared_preferences` for secrets) |
| PRD storage = drift | `drift`, `drift_flutter`, `dev:drift_dev`, `dev:build_runner` |
| PRD storage = sqflite | `sqflite`, `path` |
| PRD storage = JSON documents | `path_provider` |
| `backend: rest` | `dio` |
| `backend: firebase` | `firebase_core` + the PRD's products (`firebase_auth`, `cloud_firestore`, …) via `flutterfire configure` (below) |
| PRD requires reinstall-durable data (5b.7) | `flutter_secure_storage`, `play_services_block_store` |
| a runtime permission (5c.5) | `permission_handler` |

Under `flutter:` set `generate: true` (l10n). Declare an asset directory under `flutter: assets:`
(trailing slash, lowercase paths) **only once it contains files**. A declared directory that does
not exist is an analyzer warning, which breaks the 0-issue gate. Run `flutter pub get` and
confirm it exits 0.

**Firebase is a manual credential step.** When `backend: firebase` and `lib/firebase_options.dart`
does not exist, `flutterfire configure` needs the user's own Firebase login. Pause instead of
guessing: write `state.md` `status: paused`, `pause_reason: manual_action`, `current_phase:
generator`, `next_role: generator` (no `checkpoint` write), and append to `pipeline-log.md`
`| <ISO-8601 UTC now> | pause | generator | manual_action: run flutterfire configure |`. Then tell the user, in `default_language`, to run this in `$APP` and
`/app-harness --resume` afterwards. 5a re-runs idempotently on resume.

```bash
dart pub global activate flutterfire_cli && firebase login && flutterfire configure --platforms=ios,android
```

### 5a.4 Create the feature-first lib/ tree

Follow the PRD's `lib/` map:

```
lib/
  main.dart                      `main() => bootstrap()` (5a.6)
  app/
    app.dart                     MaterialApp.router + lifecycle hook (5a.7)
    router.dart                  the one GoRouter (5a.7)
    bootstrap.dart               startup sequence, storage overrides, ProviderContainer (5a.6)
  core/
    config/app_config.dart       every tunable constant (5a.5)
    theme/design_tokens.dart     from the design doc (5a.7, completed in 5c.1)
    theme/app_theme.dart         light + dark ThemeData from the tokens
    services/                    shared_preferences_provider.dart, api_client.dart (rest), …
    widgets/                     AsyncValueView / EmptyView / ErrorView (5c.2)
    utils/
  features/<feature>/
    data/                        models + repository (5b)
    presentation/                screens, widgets, notifiers (5b/5c)
  l10n/app_<locale>.arb          one per config.locales entry
test/                            mirrors lib/ (test/features/<feature>/…)
integration_test/app_test.dart   primary flow (5c.8)
```

Add `lib/features/<feature>/domain/` (or `lib/core/domain/`) only when logic is shared across
features. Create directories as files land. Do not add empty folders or `.gitkeep` files.

### 5a.5 app_config.dart — every tunable constant

`lib/core/config/app_config.dart` centralizes every value someone might tune: timeouts, page
sizes, debounce windows, caps, limits, and links. No magic numbers elsewhere (Hard Gate 4). Visual
values (colors, spacing, radii, type) belong in `design_tokens.dart`, not here.

```dart
// lib/core/config/app_config.dart: edit here, never hard-code elsewhere.
abstract final class AppConfig {
  // Persistence (5b.5)
  static const schemaVersion = 1;
  static const saveDebounce = Duration(milliseconds: 500);  // <= 1 s, flushed on pause

  // Lists / input (from the PRD)
  static const pageSize = 20;
  static const searchDebounce = Duration(milliseconds: 300);
  static const maxTitleLength = 80;

  // Network: only when backend != local (5b.6)
  static const connectTimeout = Duration(seconds: 10);
  static const receiveTimeout = Duration(seconds: 20);
  static const maxRetries = 3;
  static const retryBaseDelay = Duration(milliseconds: 400);

  // UX
  static const exitBackWindow = Duration(seconds: 2);  // root double-back (5c.10)
  static const maxTextScale = 2.0;                      // global clamp, never lower (5c.7)

  // Links
  static const privacyPolicyUrl = '<config.developer.privacy>';

  // Store capture (`--dart-define=screenshots=true`): no ads, consent/ATT, permission or rating prompts.
  static const bool screenshotMode = bool.fromEnvironment('screenshots');

  // Monetization seam: the monetize phase replaces the adsEnabled line and owns all ad/IAP code.
  static const adsEnabled = false;
}
```

Fill values from the PRD. Delete the ones the app does not use (e.g. the network block when
`backend: local`). Always keep `screenshotMode` and `adsEnabled`: the screenshot and monetize phases
read them.

### 5a.6 Startup: main.dart + bootstrap.dart

Order per `docs/app-gotchas.md` (App lifecycle / cold start): `ensureInitialized` → error
handlers → open storage and inject it as overrides → orientation → `runApp`. Keep pre-`runApp`
work minimal; a slow startup means a long native splash. `bootstrap()` creates the
`ProviderContainer` explicitly and runs `UncontrolledProviderScope`. The monetize phase later
appends its after-first-frame consent → ATT → ads start to this container, so it must exist here.

```dart
// lib/core/services/shared_preferences_provider.dart
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError('sharedPreferencesProvider must be overridden in ProviderScope'),
);
```

```dart
// lib/main.dart
Future<void> main() => bootstrap();
```

```dart
// lib/app/bootstrap.dart
import 'package:flutter_riverpod/misc.dart' show Override;

/// Opens local storage once. Shared by bootstrap() and integration_test, which must not call
/// main(): the test binding fails any test that leaves FlutterError.onError changed.
Future<List<Override>> storageOverrides() async {
  final prefs = await SharedPreferences.getInstance();
  // Open the DB here if the PRD chose drift/sqflite, and run schema migrations (5b.5).
  return [sharedPreferencesProvider.overrideWithValue(prefs)];
}

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true; // logged, never a crash
  };
  // Release: ErrorWidget.builder -> the shared ErrorView instead of the grey box (5c.2).
  final overrides = await storageOverrides();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    // portrait -> portraitUp; landscape -> landscapeLeft, landscapeRight; all -> skip this call
  ]);
  final container = ProviderContainer(
    overrides: overrides,
    // Riverpod 3 auto-retries failed providers and keeps them in AsyncLoading meanwhile (~40 s
    // of backoff), so screens would spin instead of showing ErrorView + Retry (R1). Repositories
    // own retry (R2), so disable it here.
    retry: (_, _) => null,
  );
  runApp(UncontrolledProviderScope(container: container, child: const App()));
}
```

### 5a.7 App, router, base theme, l10n skeleton, lifecycle hook

**Base theme.** Write `lib/core/theme/design_tokens.dart` verbatim from the design doc's token
spec. Write `lib/core/theme/app_theme.dart` with `AppTheme.light` / `AppTheme.dark` built from the
tokens' light/dark color schemes. 5c.1 completes the component themes.

**l10n skeleton.** Create `l10n.yaml`:

```yaml
arb-dir: lib/l10n
template-arb-file: app_<default_language>.arb
output-localization-file: app_localizations.dart
nullable-getter: false
```

Create one `lib/l10n/app_<locale>.arb` per `config.locales` entry with at least `appTitle`. Current
Flutter generates into `lib/l10n/` (the synthetic `package:flutter_gen` import is gone). Import
`package:<app_pkg>/l10n/app_localizations.dart`. `AppLocalizations.supportedLocales` is derived
from the ARB files, so it equals `config.locales`.

**`lib/app/app.dart`** is a `ConsumerStatefulWidget` that hosts the app-level
`AppLifecycleListener` (R3):

```dart
class _AppState extends ConsumerState<App> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onPause: _onPause, onResume: _onResume); // wired in 5b.8
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system, // 5c.4: ref.watch(themeModeProvider)
        routerConfig: ref.watch(routerProvider),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Honor OS text scaling. The only allowed clamp is this global one (R10).
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          maxScaleFactor: AppConfig.maxTextScale,
          child: child!,
        ),
      );
}
```

**`lib/app/router.dart`** has one `GoRouter` behind a provider, so redirect guards can read
providers (`docs/app-gotchas.md` → Navigation & deep links):

- Route names are constants (`abstract final class Routes { static const home = 'home'; … }`).
  Screens navigate with `context.goNamed` / `pushNamed`, never `Navigator.push` with inline routes.
- Add **every route in the PRD**. Minimal screens are allowed at 5a (a `Scaffold` with a localized
  `AppBar` title). 5c replaces them, and the anti-stub grep (5c.12) runs before the final gate.
- Bottom-nav apps use `StatefulShellRoute.indexedStack` (preserves tab state).
- `errorBuilder` → a localized not-found screen. Unknown deep links never crash.
- Onboarding/auth guards: `redirect` reads a provider, and `refreshListenable` is a `ValueNotifier`
  updated by `ref.listen` on that provider. Otherwise the guard runs only once.
- `final routerProvider = Provider<GoRouter>((ref) { final r = GoRouter(...); ref.onDispose(r.dispose); return r; });`

### 5a.8 Minimal passing test

`test/app_test.dart` boots the real `App` with storage overridden:

```dart
testWidgets('app boots to the home route', (tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const App(),
  ));
  await tester.pumpAndSettle();
  expect(find.byType(HomeScreen), findsOneWidget); // the PRD's initial screen
});
```

### 5a.9 CI workflow

Copy `<plugin-templates>/ci.yml.template` → `.github/workflows/ci.yml`. It is a GitHub Actions job
running `flutter analyze --no-fatal-infos` + `flutter test` on push and PR.

### 5a.10 Initialize version control

The generated app is its own git repository, with atomic history from the start so the user can
diff or revert per sub-phase. `flutter create` already wrote a complete Flutter `.gitignore`.
**Do not overwrite it.** Append the harness credential/secret excludes from
`gitignore.template` (`secrets/`, `*.jks`/`*.p8`/`*.p12`, `key.properties`,
`play-store-key.json`, `**/google-services.json`, `ios/Runner/Runner.entitlements`,
`ios/fastlane/certs/`). Those keep the signing and API key files that the build phase copies in
from ever being committed.

```bash
cd "$APP"
[ -d .git ] || git init -q
grep -q "play-store-key.json" .gitignore || cat <plugin-templates>/gitignore.template >> .gitignore
```

**`pubspec.lock` is committed.** This is an app, so builds must be reproducible. Never add it to
`.gitignore`; `git add -A` includes it by design. Use **Conventional Commits**: one atomic commit
at each sub-phase gate (5a/5b/5c) and one per discrete fix on round N > 1.

### 5a HARD GATE

```bash
cd "$APP"
flutter analyze
flutter test
```

`flutter analyze` must report **0 issues**, and `flutter test` must report **0 failures**. When both
are green, commit with `git add -A && git commit -q -m "feat: scaffold app architecture and
navigation (5a)"`, then write `checkpoint: 5a` to `state.md` atomically.

**If either command fails, fix every reported issue and re-run both. Do not start 5b until this
gate is green.**

---

## Sub-phase 5b — Data + State

Implements every model, data source, repository, and provider the PRD needs. Start only after the
5a HARD GATE passes. Patterns: `docs/app-gotchas.md` → Persistence & data safety (R9), Network
resilience (R2), Riverpod long-tail.

### 5b.1 Models

Immutable typed models in `lib/features/<feature>/data/<model>.dart`: `final` fields, a `const`
constructor, and hand-written `copyWith` / `==` / `hashCode` / `toJson` / `fromJson`. Use a Dart
record for small value tuples. `freezed` is optional, not required. Store dates as UTC ISO-8601 or
epoch ms and convert to local time only for display. Widgets never pass raw maps around.

### 5b.2 Repositories (+ data sources)

One **concrete** repository per feature in `lib/features/<feature>/data/<feature>_repository.dart`.
No interface for a single implementation; tests override the provider instead. The repository is
the only code that touches storage or network (Hard Gate 5). It wraps every platform call in
try/catch, logs with `debugPrint`, and rethrows so the failure becomes `AsyncError` → ErrorView +
Retry (R1):

```dart
final habitsRepositoryProvider = Provider<HabitsRepository>(
  (ref) => HabitsRepository(ref.watch(sharedPreferencesProvider)),
);

class HabitsRepository {
  HabitsRepository(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'habits_v1'; // versioned key (5b.5)

  Future<List<Habit>> loadAll() async {
    try {
      final raw = _prefs.getString(_key);
      if (raw == null) return const [];
      return [for (final e in jsonDecode(raw) as List) Habit.fromJson(e as Map<String, Object?>)];
    } catch (e, st) {
      debugPrint('HabitsRepository.loadAll: $e\n$st');
      rethrow;
    }
  }

  Future<void> saveAll(List<Habit> habits) async {
    try {
      await _prefs.setString(_key, jsonEncode([for (final h in habits) h.toJson()]));
    } catch (e, st) {
      debugPrint('HabitsRepository.saveAll: $e\n$st');
      rethrow;
    }
  }
}
```

Storage follows the PRD's choice. Key-value → `shared_preferences`. Relational or more than a few
hundred records → drift/sqflite (opened in `storageOverrides()`, injected by override). Documents → a
JSON file via `path_provider`. Tokens and secrets → `flutter_secure_storage`, never prefs. Write
immediately on user action, or debounce by `AppConfig.saveDebounce` and expose `flush()` for
5b.8. Batch high-frequency writes.

### 5b.3 Providers and notifiers

One `Notifier` / `AsyncNotifier` per feature in
`lib/features/<feature>/presentation/<feature>_notifier.dart`. Use `autoDispose` for
screen-scoped state (Riverpod 3: `AsyncNotifierProvider.autoDispose(...)` with a plain
`AsyncNotifier`). Mutations are optimistic and roll back on failure:

```dart
final habitsProvider =
    AsyncNotifierProvider.autoDispose<HabitsNotifier, List<Habit>>(HabitsNotifier.new);

class HabitsNotifier extends AsyncNotifier<List<Habit>> {
  @override
  Future<List<Habit>> build() => ref.watch(habitsRepositoryProvider).loadAll();

  Future<void> add(Habit habit) async {
    final previous = await future;
    state = AsyncData([...previous, habit]);
    try {
      await ref.read(habitsRepositoryProvider).saveAll(state.requireValue);
    } catch (_) {
      state = AsyncData(previous); // roll back; the screen shows a SnackBar (5c.3)
      rethrow;
    }
  }
}
```

Rules: derive filtered, sorted, or "today" views in providers, not in `build()`. `ref.watch` for
reactive reads, `ref.read` only in callbacks. Use `.family` with `==`-comparable args. Never
create providers inside widgets. Logout or data wipe invalidates every user-scoped provider.

### 5b.4 Seed and static content as data

Catalogs, default categories, onboarding pages, tips, and similar content live in data files:
`assets/data/<name>.json` (declared in pubspec, loaded by a repository via `rootBundle`) or a
`const` list in `lib/features/<feature>/data/<name>_seed.dart`. Widgets never carry content
literals (Hard Gate 5). Use real, finished content, never lorem or "sample item".

### 5b.5 Schema version + migration

v1 uses versioned storage keys (`<feature>_v1`) or drift `schemaVersion => AppConfig.schemaVersion`.
On every later schema change: bump `AppConfig.schemaVersion`, then add the migration. For prefs or
JSON, add it in `storageOverrides()`: read the old key, write the new one, delete the old one, once. For
drift, add a `MigrationStrategy(onUpgrade:)`. Add a migration test. An update must never corrupt
or drop existing user data (R9).

### 5b.6 Backend client (only when `backend ≠ local`) — R2

**rest:** one `Dio` in `lib/core/services/api_client.dart`, injected via a provider. Notifiers and
widgets never construct clients.

```dart
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: const String.fromEnvironment('API_BASE_URL'), // --dart-define, never a secret
    connectTimeout: AppConfig.connectTimeout,
    receiveTimeout: AppConfig.receiveTimeout,
  ));
  ref.onDispose(dio.close);
  return dio;
});

/// Idempotent requests (GET) only. Never auto-retry a POST.
Future<T> withRetry<T>(Future<T> Function() request) async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await request();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final retryable = e.type != DioExceptionType.cancel && (status == null || status >= 500);
      if (!retryable || attempt >= AppConfig.maxRetries) rethrow;
      await Future<void>.delayed(AppConfig.retryBaseDelay * (1 << (attempt - 1)) +
          Duration(milliseconds: Random().nextInt(250))); // backoff + jitter
    }
  }
}
```

- **Cancel on dispose:** the notifier creates a `CancelToken`, registers
  `ref.onDispose(token.cancel)`, and passes it to the repository.
- **Offline:** keep the last good response in local storage. Show cached data + an offline banner
  instead of an empty error. The request failure is the truth; `connectivity_plus` is at most a
  hint.
- **Parse large JSON off the UI thread** (`Isolate.run`).

**firebase:** repositories wrap every Firestore/Auth call in try/catch. Streams go through
`StreamNotifier`. No Firebase calls in widgets. If the app has accounts: in-app account deletion
(5.1.1(v)) and Sign in with Apple when any social login is offered (4.8), per `docs/app-gotchas.md`
→ Store rejections.

`backend: local` with no network calls → R2 is N/A.

### 5b.7 Durable restore (optional)

Only when the PRD requires data to survive reinstall or a new device **without an account**:
copy `<plugin-templates>/save_repository.dart.template` → `lib/core/services/save_repository.dart`,
replace `__SAVE_KEY__` with `<app_pkg>_save_v1`, and add `flutter_secure_storage` +
`play_services_block_store`. Feature repositories persist their JSON through it (iOS Keychain +
Android Block Store + prefs mirror; each tier in try/catch). This is last-write-wins restore, not
sync. Otherwise rely on Android Auto Backup (on by default) and say so in the handoff R9 row.

### 5b.8 Lifecycle wiring (R3)

Fill the 5a.7 `AppLifecycleListener` handlers with real work. `_onPause` flushes pending debounced
writes (`ref.read(<feature>RepositoryProvider).flush()`). `_onResume` invalidates time-sensitive
providers (`ref.invalidate(todayProvider)`, token refresh). Dispose every
`TextEditingController` / `AnimationController` / `ScrollController` / `StreamSubscription` /
`Timer` in `dispose()` or `ref.onDispose`. Every async gap in a `State` checks `mounted` and every
async gap with a `BuildContext` checks `context.mounted`.

### 5b.9 Unit tests

Scaffold from `<plugin-templates>/test_unit.dart.template` → `test/features/<feature>/<feature>_notifier_test.dart`
and adapt every `<...>` placeholder. It runs a `ProviderContainer` test of the notifier with the
real repository over in-memory prefs injected by override, plus subclassed failing repositories.
Write **at least 3** unit tests in total (contract R11). Cover load, mutate + persist (a second
container over the same storage = restart), and the failure / rollback path. Add model
`toJson`/`fromJson` round-trips, a migration test when `schemaVersion > 1`, and `withRetry` tests
when `backend: rest`.

### 5b HARD GATE

```bash
cd "$APP"
flutter analyze
flutter test
```

`flutter analyze` must report **0 issues**, and `flutter test` must report **0 failures**. When both
are green, commit with `git add -A && git commit -q -m "feat: data layer, repositories and state
(5b)"`, then write `checkpoint: 5b` to `state.md`.

**If either command fails, fix every reported issue and re-run both. Do not start 5c until this
gate is green.**

---

## Sub-phase 5c — UI, Content, and Polish

Builds every screen from the design doc, then l10n, accessibility, tests, branding, and native
config. Start only after the 5b HARD GATE passes.

### 5c.1 Theme

Complete `lib/core/theme/app_theme.dart` from the design doc. Build a `ColorScheme` per brightness
from the token palettes and a `TextTheme` from the token typography. Add component themes (filled
and outlined buttons with `minimumSize` ≥ 48×48, `InputDecorationTheme`, cards, app bar,
SnackBar). Every color, spacing, radius, and text style in widgets comes from the tokens or
`Theme.of(context)`. No raw hex, no `Colors.white`/`Colors.black`, no numeric literals (Hard Gate
4). Both themes keep text contrast ≥ 4.5:1.

### 5c.2 Shared state widgets (R1)

`lib/core/widgets/`:

- `AsyncValueView<T>({value, data, onRetry})` → `value.when(data:, loading:, error:)`. Loading is a
  skeleton or spinner. Error is `ErrorView(onRetry)`. Never `.value!` / `.requireValue` in a build
  method.
- `EmptyView({message, actionLabel, onAction})` shows a localized message + the primary call to
  action.
- `ErrorView({onRetry})` shows a localized message + **Retry**. Retry = `ref.invalidate(provider)`
  or the notifier's `refresh()`.
- In `bootstrap()` (release only): `ErrorWidget.builder` → a non-interactive `ErrorView` instead of the
  grey box.

### 5c.3 Screens

Build every screen in the design doc's screen inventory under
`lib/features/<feature>/presentation/` as a `ConsumerWidget` / `ConsumerStatefulWidget`. Replace
every minimal 5a screen.

- `ref.watch(provider)` → `AsyncValueView`. Inside `data`, an empty collection renders `EmptyView`.
  Every data-backed screen shows loading / empty / error+Retry / success exactly as the design doc
  specifies.
- Lists use `ListView.builder` / slivers, never `Column(children: items.map(...))`. Use
  `RefreshIndicator` when data can change remotely.
- Side effects go through `ref.listen`: a SnackBar when a mutation fails (optimistic rollback),
  navigation on success.
- `device_family: universal` → layouts use the extra width (max content width / master-detail at a
  token breakpoint), not a stretched phone UI.

**External design source.** If the design doc names a Figma file or a Stitch project for some
screens, implement those screens from it. Use whichever Figma/Stitch MCP tools or installed
design-to-Flutter skills are available (`Skill`). Fetch per screen: cheap metadata/screenshot
first, then design context for one node at a time. Map every color, size, and font onto the
existing tokens; never paste raw values from the export. If no tool can reach the source,
implement from the design doc's written screen specs and record that under Known Issues.

### 5c.4 Onboarding + Settings

- **Onboarding** (only if the PRD has it): first-run pages that explain the app's value (guards
  against 4.2). Expose completion as **`onboardingDoneProvider`** (a `Notifier<bool>`, persisted
  through a repository, in `lib/features/onboarding/presentation/onboarding_notifier.dart`). The name is fixed because the monetize
  phase's app-open ad manager reads it. The router `redirect` + `refreshListenable` (5a.7) sends
  first launches to onboarding, and it never shows again after completion.
- **Settings** (always), `lib/features/settings/`:
  - Theme mode (system / light / dark), persisted through a settings repository and exposed as
    `themeModeProvider`. `app.dart` watches it.
  - Privacy policy: `launchUrl(Uri.parse(AppConfig.privacyPolicyUrl), mode:
    LaunchMode.externalApplication)`. Check its `bool` result and show a SnackBar on `false`. Do
    not gate it on `canLaunchUrl`: Android 11+ package visibility makes that return `false`
    without a `<queries>` entry.
  - Licenses: `showLicensePage(context: context, applicationName: l10n.appTitle)`.
  - **Monetize seam:** build Settings as a `ListView` of sections (Appearance, About & legal). The
    monetize phase later inserts "Privacy options" (UMP) and "Restore purchases" tiles into About &
    legal and reads `AppConfig.adsEnabled`. Do not add placeholder tiles now, because the
    anti-stub check would flag them.

### 5c.5 Forms (R4) and permissions (R12)

**Forms** (any text input), per `docs/app-gotchas.md` → Forms & keyboard:
- `Form` + `TextFormField` validators that return localized messages. Use
  `AutovalidateMode.onUserInteraction` after the first submit.
- Set `keyboardType`, `textInputAction` (next → done), and `autofillHints`. `maxLength` comes from
  `AppConfig`.
- Content sits in a scroll view so the keyboard never covers the focused field. Bottom buttons sit
  in `SafeArea` + `viewInsets` padding. Tapping outside unfocuses.
- Submit is disabled while submitting, and the button shows progress (no double submit).
- Unsaved changes → `PopScope` confirm-discard dialog.
- Dates and numbers are formatted with `intl` for the active locale.

No text input → R4 N/A.

**Permissions** (only if the PRD uses a runtime permission): request in context with a short
rationale first, through `permission_handler`. Handle granted / denied (degrade with an
explanation) / permanently denied (button → `openAppSettings()`). Every `NS*UsageDescription`
goes in `Info.plist` and is localized in each `ios/Runner/<lproj>.lproj/InfoPlist.strings`, naming
the concrete user benefit. Declare Android manifest permissions, plus the runtime
`POST_NOTIFICATIONS` request on Android 13+. ATT belongs to the monetize phase. No runtime
permission → R12 N/A (until monetize adds ATT).

### 5c.6 Localization (Hard Gate 6)

- One `lib/l10n/app_<locale>.arb` per `config.locales` entry. The `default_language` file is the
  template, with `@key` descriptions. Use ICU plurals and placeholders for counts and names.
- Every user-visible string goes through `AppLocalizations.of(context).<key>`: text, tooltips,
  labels, hints, semantics labels, SnackBars, dialog copy, validator messages.
- iOS: add `CFBundleLocalizations` (one `<lproj>` entry per `config.locales`) to `Info.plist` so iOS exposes
  the app's languages.
- Check key parity (must print nothing) and hard-coded strings. Every hit must be a
  non-translatable value such as `Text('$count')`; move everything else to the ARB files.

```bash
python3 - <<'EOF'
import json, glob
keys = {f: {k for k in json.load(open(f)) if not k.startswith('@')} for f in sorted(glob.glob('lib/l10n/app_*.arb'))}
allk = set().union(*keys.values())
missing = {f: sorted(allk - k) for f, k in keys.items() if allk - k}
if missing: print(missing); raise SystemExit(1)
EOF
grep -rnE "(Text|Tooltip)\(\s*['\"]|(tooltip|label|labelText|hintText|helperText|title|semanticLabel|semanticsLabel|message):\s*['\"]" \
  lib --include='*.dart' | grep -v '^lib/l10n/'
```

### 5c.7 Accessibility (R10)

Per `docs/app-gotchas.md` → Accessibility:
- Every icon-only control has a label: `IconButton(tooltip: …)`, `FloatingActionButton(tooltip:
  …)`, or a `Semantics(label: …)` wrapper. Meaningful images get `semanticLabel`, and decorative
  ones get `excludeFromSemantics: true`. Custom tiles use `MergeSemantics`.
- Every tap target is ≥ 48×48 dp.
- **Honor text scaling:** never `MediaQuery.withNoTextScaling` (or a fixed `textScaler`) on
  content. The only clamp is the global `withClampedTextScaling(maxScaleFactor:
  AppConfig.maxTextScale)` from 5a.7, which must be ≤ 2.0. Layouts survive 200% (use
  `Flexible`/`Wrap`, no fixed-height text rows).
- Reduce motion: `MediaQuery.of(context).disableAnimations` skips non-essential animations. Nothing
  flashes faster than 3×/second.
- Logical focus and reading order. Text contrast ≥ 4.5:1 in both themes.

```bash
grep -rn "withNoTextScaling\|TextScaler.noScaling\|textScaleFactor:" lib --include='*.dart'  # must be empty
```

### 5c.8 Tests (R11)

- **Widget tests:** at least one per primary screen, and at least 2 in total. Copy
  `<plugin-templates>/widget_test.dart.template` → `test/features/<feature>/<screen>_screen_test.dart`
  and adapt every `<...>`. The template pumps the screen in `ProviderScope` + `MaterialApp`
  (localization delegates, real theme). It asserts the empty state, finds the primary action by
  tooltip, and checks Flutter's tap-target / label / contrast guidelines. It taps the action,
  asserts the outcome, and pumps at 200% text scale with no overflow.
- **Integration test:** copy `<plugin-templates>/integration_test.dart.template` →
  `integration_test/app_test.dart`. It drives the PRD's primary flow from a fresh install, asserts
  the result is visible, and reads it back through the repository (stored). `flutter test` does
  not run `integration_test/`. Run it on a booted simulator/emulator when one exists:
  `flutter test integration_test -d <device-id>`. Otherwise record that it was not run under Known
  Issues (the evaluator runs it).

### 5c.9 App branding: icon, splash, display name (R5)

A shipped app must not carry the default Flutter icon, the default splash, or a slug-ish name.
Follow `docs/app-gotchas.md` → Build / platform + Store rejections.

1. **Icon + splash art.** Default: copy `<plugin-templates>/gen_icon.dart.template` →
   `tool/gen_icon.dart`. Fill its color constants from `design_tokens` (Background / Primary /
   Accent RGB) and `kGlyph` from the first letter of `app_name`, then run
   `dart run tool/gen_icon.dart`. It writes:
   - `assets/icons/icon.png`: 1024×1024, **opaque, no alpha** (iOS)
   - **`assets/icons/icon-fg.png`**: Android adaptive **foreground**, transparent, motif inside
     the safe zone
   - **`assets/icons/icon-mono.png`**: Android 13+ **themed/monochrome** layer, white on transparent
   - `assets/images/splash.png`
   - **`assets/store/play_icon.png`**: 512×512 Play hi-res icon
   - **`assets/store/feature_graphic.png`**: 1024×500 Play feature graphic

   The screenshot phase places the last two into the Android listing. If the design doc supplied
   icon art, flatten it **opaque** into `assets/icons/icon.png` **and** still produce a padded
   `icon-fg.png` + `icon-mono.png`. Never reuse full-bleed art as the adaptive foreground. These
   files feed the tools; declare them under `flutter: assets:` only if the app shows the logo
   in-app.
2. **Config + run the tools.** Add the `flutter_launcher_icons` block with **all** Android adaptive
   layers, not just `image_path`. A full-bleed `image_path` reused as the Android icon gets
   cropped/"zoomed" by the launcher mask (108dp canvas, only the centre ~66dp is safe). Add
   `flutter_native_splash` with light **and dark** colors that match the first Flutter frame
   background, or the launch blinks:
   ```yaml
   flutter_launcher_icons:
     android: true
     ios: true
     remove_alpha_ios: true
     image_path: assets/icons/icon.png                    # iOS + legacy Android
     adaptive_icon_background: "<design Background hex>"   # solid color, opaque
     adaptive_icon_foreground: assets/icons/icon-fg.png    # safe-zone padded
     adaptive_icon_monochrome: assets/icons/icon-mono.png  # Android 13+ themed
     min_sdk_android: 21

   flutter_native_splash:
     color: "<light background hex>"
     color_dark: "<dark background hex>"
     image: assets/images/splash.png
     android_12:
       color: "<light background hex>"
       color_dark: "<dark background hex>"
   ```
   ```bash
   dart run flutter_launcher_icons
   dart run flutter_native_splash:create
   ```
   Verify the adaptive layers: `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
   references `<foreground>` and `<monochrome>`.
3. **Localized display name.** `app_name` is the home-screen name, not "Runner" and not the slug.
   - iOS: `CFBundleDisplayName` in `Info.plist` plus one
     `ios/Runner/<lproj>.lproj/InfoPlist.strings` per `config.locales`
     (`"CFBundleDisplayName" = "<localized name>";`), registered in the Xcode project by the 5c.10
     script.
   - Android: `android:label="@string/app_name"`, with `res/values/strings.xml` plus a
     `res/values-<lang>/strings.xml` per extra locale (a region goes as `values-pt-rBR`).

### 5c.10 Native platform config (R6)

Apply `docs/app-gotchas.md` → Build / platform + Store rejections:

1. **Orientation, locked natively** per `config.orientation`. `setPreferredOrientations` alone
   still lets the app launch rotated.
   - iOS `Info.plist` `UISupportedInterfaceOrientations`: portrait → `UIInterfaceOrientationPortrait`.
     landscape → `…LandscapeLeft` + `…LandscapeRight`. all → keep every entry.
   - Android: the main `<activity>` gets `android:screenOrientation="portrait"` (or
     `"sensorLandscape"`). all → omit it. Android 16+ ignores the lock on large screens
     (≥ 600dp), so tablet layouts must still work rotated.
2. **Device family.** `phone` → `TARGETED_DEVICE_FAMILY = 1` in every Runner build config, and
   **remove** `UISupportedInterfaceOrientations~ipad` (avoids the iPad screenshot requirement).
   `universal` → `"1,2"` with **all four** iPad orientations in `~ipad` (or `UIRequiresFullScreen`)
   and wide layouts (5c.3). Declaring iPad without them is a rejection.
3. **Export compliance.** `ITSAppUsesNonExemptEncryption = false` in `ios/Runner/Info.plist`
   (HTTPS alone is exempt). This skips the per-upload prompt.
4. **Root back button (Android).** go_router pops nested routes first. Only the **root** route (or
   the shell scaffold) intercepts:
   ```dart
   PopScope(
     canPop: false,
     onPopInvokedWithResult: (didPop, _) {
       if (didPop) return;
       final now = DateTime.now();
       if (_lastBack != null && now.difference(_lastBack!) < AppConfig.exitBackWindow) {
         SystemNavigator.pop();
         return;
       }
       _lastBack = now;
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(
         content: Text(AppLocalizations.of(context).pressBackAgainToExit),
         duration: AppConfig.exitBackWindow,
       ));
     },
     child: …,
   )
   ```
   Dialogs and sheets close on back. Unsaved forms confirm-discard (5c.5).
5. **Privacy manifest.** Write `ios/Runner/PrivacyInfo.xcprivacy` with `NSPrivacyTracking` false,
   empty `NSPrivacyTrackingDomains` / `NSPrivacyCollectedDataTypes`, and `NSPrivacyAccessedAPITypes`
   for each required-reason API in use. `shared_preferences` → `NSPrivacyAccessedAPICategoryUserDefaults`
   with reason `CA92.1`. Add file-timestamp / disk-space reasons only if used. The monetize phase
   extends it for ads.
6. **iOS deployment target.** Xcode 27+ fails pod targets below iOS 15.0 ("Target Integrity"
   error). Set `platform :ios, '15.0'` in `ios/Podfile` and `IPHONEOS_DEPLOYMENT_TARGET = 15.0` in
   the Runner project. In the Podfile `post_install`, add
   `target.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0' }`
   after `flutter_additional_ios_build_settings(target)`. Raise it further if a plugin requires
   more.
7. **Register iOS resources** (privacy manifest + localized `InfoPlist.strings`) in the Runner
   target. This is idempotent and uses the `xcodeproj` gem that ships with CocoaPods:
   ```bash
   ruby -e 'require "xcodeproj"; locales = ARGV.map { |l| {"zh"=>"zh-Hans","zh_CN"=>"zh-Hans","zh_TW"=>"zh-Hant"}.fetch(l, l) }.uniq  # <lproj>
     p = Xcodeproj::Project.open("ios/Runner.xcodeproj"); t = p.targets.find { |x| x.name == "Runner" }; g = p.main_group["Runner"]
     pi = g.files.find { |f| f.path == "PrivacyInfo.xcprivacy" } || g.new_file("PrivacyInfo.xcprivacy")
     t.resources_build_phase.add_file_reference(pi, true)
     p.root_object.known_regions |= locales
     vg = g.children.find { |c| c.isa == "PBXVariantGroup" && c.name == "InfoPlist.strings" } || g.new_variant_group("InfoPlist.strings")
     locales.each { |l| vg.files.any? { |f| f.name == l } || (vg.new_reference("#{l}.lproj/InfoPlist.strings").name = l) }
     t.resources_build_phase.add_file_reference(vg, true); p.save' <config.locales…>
   grep -c "PrivacyInfo.xcprivacy in Resources\|InfoPlist.strings in Resources" ios/Runner.xcodeproj/project.pbxproj   # 4 (2 build files + 2 resources-phase entries)
   ```
8. If a dependency requires it (e.g. `flutter_local_notifications`), enable core library
   desugaring in `android/app/build.gradle.kts`. Set `minSdk` = `max(23, highest plugin
   requirement)` (check each plugin's own minSdk); never lower an existing higher value.

### 5c.11 Project README + LICENSE

- **`README.md`** from `<plugin-templates>/README.md.template`. Fill `<app_name>`, the one-line
  pitch, the primary flows as features, the actual stack from `pubspec.yaml`, the locales, and any
  `--dart-define` the app needs. Author it in `default_language`, and add an English section when
  that is not `en`.
- **`LICENSE`** from `<plugin-templates>/LICENSE.template` (MIT), with `Copyright (c) <year>
  <company>` taken from `config.developer.company` and the current year. If the user prefers a
  different license, use that one.

### 5c.12 Anti-stub and final checks

Run before the final gate. Each command must print nothing:

```bash
cd "$APP"
# Hard Gate 3: no stubs, fake or placeholder data. Review each hit; a legit `placeholder:` named
# argument (e.g. a text field hint) can stay once confirmed.
grep -rniE "TODO|FIXME|stub|placeholder|lorem|fake|mock data|dummy|UnimplementedError|coming soon" \
  lib --include='*.dart' --include='*.arb' | grep -v 'lib/l10n/app_localizations' | grep -v '"placeholders"'
# R7: every referenced asset exists
grep -rhoE "assets/[A-Za-z0-9_./-]+" lib pubspec.yaml | sort -u | while read -r p; do [ -e "$p" ] || echo "MISSING $p"; done
```

---

### 5c HARD GATE

```bash
cd "$APP"
flutter analyze
flutter test
```

`flutter analyze` must report **0 issues**, and `flutter test` must report **0 failures**. Also confirm:

- **5c.6 / 5c.7 / 5c.12:** l10n parity, hard-coded-string, text-scaling, anti-stub, and
  dangling-asset checks all print nothing.
- **Branding (5c.9):** a **custom** icon + splash exist, not the default Flutter art.
  `sips -g hasAlpha assets/icons/icon.png` → `hasAlpha: no`. The adaptive layers include
  monochrome. The display name equals `app_name` on both platforms, not "Runner" or the slug.
- **Native (5c.10):** orientation is locked per `config.orientation`. `TARGETED_DEVICE_FAMILY`
  matches `config.device_family`. `ITSAppUsesNonExemptEncryption = false`. The root back SnackBar
  is in place. `PrivacyInfo.xcprivacy` is registered. The bundle id is identical on both platforms
  (5a.1). Update mode: the ids are unchanged from the audit instead (iOS = `bundle_id`, Android =
  `bundle_id_android` or else `bundle_id`).
- **CI (5a.9):** `.github/workflows/ci.yml` is present.
- **Tests (5c.8):** ≥ 3 unit, ≥ 2 widget, and 1 integration test exist.

**This is the final gate. Do not write the handoff until it is green. If anything fails, fix it
and re-run.** When green, commit with `git add -A && git commit -q -m "feat: screens, l10n,
branding and native config (5c)"`, then write `checkpoint: 5c` to `state.md` before writing the
handoff.

---

## Update mode (`mode: update`)

Protocol §1, §3 (update-mode gate overrides), §7 rule 11. The project already exists at
`config.project_path` with `docs/harness/` inside it.

- **Never** run `flutter create`, rewrite the bundle id, move `docs/harness/`, or `git init`.
  `bundle_id` never changes.
- Work on a branch, never on the default branch. Reuse today's branch only when it already holds
  the baseline; a `harness/*-update` branch from a prior cycle (stale or merged) is never reused:
  ```bash
  B="harness/$(date +%Y%m%d)-update"; BASE=<baseline.commit>
  if git rev-parse -q --verify "refs/heads/$B" >/dev/null && git merge-base --is-ancestor "$BASE" "$B"; then
    git switch "$B"
  else
    # Name taken by a stale branch: never reset it (no -C), take a fresh name.
    git rev-parse -q --verify "refs/heads/$B" >/dev/null && B="$B-$(date +%H%M)"
    # From HEAD when it holds the baseline (keeps earlier rounds' commits across midnight), else from the baseline.
    if git merge-base --is-ancestor "$BASE" HEAD; then git switch -c "$B"; else git switch -c "$B" "$BASE"; fi
  fi
  ```
- Inputs: the delta PRD (latest `*-prd.md`), `docs/harness/specs/*-audit.md` +
  `*-baseline-prd.md`, the design doc if present, and the contract.
- Follow `config.architecture`. New code uses the project's existing state management, navigation,
  layout, storage, and l10n conventions. Do not migrate to Riverpod / go_router / feature-first
  unless the change request says so. Adapt the test templates to that architecture (e.g. a bloc
  test in place of a `ProviderContainer` test).
- The sub-phases still gate the work, scoped to the delta. 5a covers dependencies, routes, and
  config for the change. 5b covers data/state for CHANGE/NEW flows, plus a migration so data
  created before the update still loads. 5c covers UI for CHANGE/NEW flows plus the audit gap
  fixes the user selected. Keep existing CI and branding unless a selected gap targets them.
- **Screenshot flag (5a, only when `monetization.admob_enabled: true`).** If
  `grep -rnE "fromEnvironment\(['\"]screenshots" lib/` finds nothing, add
  `static const bool screenshotMode = bool.fromEnvironment('screenshots');` to the project's existing
  config/constants class (none → `AppConfig` in `lib/core/config/app_config.dart`), then wrap the
  existing ad + consent/ATT init in `if (!screenshotMode)`. Find it with
  `grep -rnE "MobileAds\.instance\.initialize|ConsentInformation|requestTrackingAuthorization|AppOpenAd\.load" lib/`.
  Minimal change, no ad-code refactor. Every file touched joins `CHANGED` (0 analyze issues).
- Gate commands follow the overrides. `flutter test` must pass. `flutter analyze` total must be ≤
  `baseline.analyze_issues`, with **0** issues in the changed files. The stub grep runs on the
  changed files only.
  ```bash
  CHANGED=$({ git diff --name-only --diff-filter=d <baseline.commit>; git ls-files --others --exclude-standard; } | grep '\.dart$' | sort -u)
  [ -z "$CHANGED" ] || flutter analyze $CHANGED
  [ -z "$CHANGED" ] || grep -niE "TODO|FIXME|stub|placeholder|lorem|fake|mock data|dummy|UnimplementedError|coming soon" $CHANGED | grep -v 'app_localizations'
  ```

---

## Self-evaluation and Handoff

After the 5c HARD GATE passes, smoke-run the app if a simulator/emulator is booted:
`flutter run -d <id>`, covering cold start + the primary flow + a restart, with the console free of
errors. This fills Hard Gate 8 and Environment Detection. If no device is available, write
"none — evaluator runs it" and mark Hard Gate 8 PARTIAL.

### Write handoff/round-N-gen.md

Create `docs/harness/handoff/round-<N>-gen.md` inside the app project, following the layout in
`docs/harness-protocol.md` §4: one row per Hard Gate, one per R-gate, one per app-specific
functional criterion from the contract. Mark conditional R-gates N/A with a one-line reason that
matches the contract.

```markdown
# Generator Handoff — Round <N>

## What Was Built / Fixed

<!-- Bullet list of features implemented (round 1) or failures fixed (round N>1, one per commit). -->

## Contract Self-Assessment

| Criterion | Status | Notes |
|---|---|---|
| HG1 `flutter analyze` 0 issues | DONE / PARTIAL / FAIL | … |
| HG2 `flutter test` all pass | DONE / PARTIAL / FAIL | <unit / widget counts> |
| HG3 no TODO/stub/placeholder/fake data in lib/ | DONE / PARTIAL / FAIL | 5c.12 grep output |
| HG4 no magic values (theme + app_config.dart) | DONE / PARTIAL / FAIL | … |
| HG5 data modeled behind repositories | DONE / PARTIAL / FAIL | … |
| HG6 l10n complete for <locales> | DONE / PARTIAL / FAIL | parity check |
| HG7 primary flows end to end + restart persistence | DONE / PARTIAL / FAIL | … |
| HG8 zero crashes / console errors on simulator | DONE / PARTIAL / FAIL | device or "evaluator runs it" |
| R1 Async UI states | DONE / PARTIAL / FAIL | … |
| R2 Network resilience | DONE / N/A / PARTIAL / FAIL | N/A: backend local, no network calls |
| R3 Lifecycle | DONE / PARTIAL / FAIL | … |
| R4 Forms & keyboard | DONE / N/A / PARTIAL / FAIL | … |
| R5 App branding | DONE / PARTIAL / FAIL | … |
| R6 Native config | DONE / PARTIAL / FAIL | … |
| R7 Assets & CI | DONE / PARTIAL / FAIL | … |
| R8 Store graphics | DONE / PARTIAL / FAIL | play_icon + feature_graphic generated; iOS screenshots in screenshot phase |
| R9 Persistence & data safety | DONE / PARTIAL / FAIL | storage choice, schema version, durable restore or Auto Backup |
| R10 Accessibility | DONE / PARTIAL / FAIL | … |
| R11 Test depth | DONE / PARTIAL / FAIL | unit / widget / integration counts; integration run? |
| R12 Permissions & privacy | DONE / N/A / PARTIAL / FAIL | N/A: no runtime permission (ATT added by monetize) |
| <app-specific functional criterion> | DONE / PARTIAL / FAIL | … |

## Test Results

\`\`\`
<last 20 lines of flutter analyze output>
\`\`\`

\`\`\`
<last 20 lines of flutter test output>
\`\`\`

## Environment Detection

- Flutter version: <output of `flutter --version`>
- Dart version: <from above>
- Device/emulator used for smoke test: <name, or "none — evaluator runs it">

## Known Issues

<!-- Known issues or deferred items (e.g. integration test not run, design source unreachable). "none" if clean. -->
```

Fill every section with actual output and real assessments. Leave no placeholder text.

### Update state.md

Update `state.md` per `docs/harness-protocol.md` §2 and the `generator → evaluator` transition in
§7. Per §7 rule 2, a successful phase completion sets `status: running` in the same atomic write:

```yaml
status: running
current_phase: generator
next_role: evaluator
updated_at: "<ISO-8601 UTC now>"
```

Leave `current_round`, `created_at`, `resume_attempts`, `checkpoint`, and all other keys unchanged.
Use `Edit` for a targeted update.

> **Note:** the evaluator increments `current_round` when it returns FAIL. The generator reads it
> but never writes it.

### Append to pipeline-log.md

Append one row to `docs/harness/pipeline-log.md` per `docs/harness-protocol.md` §6:

```
| <ISO-8601 UTC now> | handoff | generator | round <N> built; analyze 0; test 0; next: evaluator |
```

---

## Error handling

- If `contract.md` is missing or lacks `## Status: AGREED`, abort immediately.
- If any HARD GATE fails (analyzer issues or failing tests), stop at that sub-phase, fix the
  failures, and re-run the gate. Do not advance to the next sub-phase and do not write its
  checkpoint.
- If the feedback file for round N-1 is missing on a round > 1 run, abort with a clear message.
  Set `state.md` to `status: paused`, `pause_reason: manual_action`, and append to `pipeline-log.md`
  `| <ISO-8601 UTC now> | pause | generator | manual_action: restore feedback/round-<N-1>-qa.md |`.
- If `flutter create` fails, abort immediately and do not proceed to 5a.2.
- If `flutter pub get` / `flutter pub add` fails, resolve the version conflict (run
  `flutter pub outdated` and relax the conflicting constraint) before continuing. Never pin around
  it by deleting `pubspec.lock`.
- Firebase not configured (`backend: firebase`) → the `manual_action` pause in 5a.3.
- Any message printed to the user (abort, pause, manual step) is written in `default_language`.
