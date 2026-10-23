# App Gotchas — required robustness patterns

Hard-won fixes for shipped Flutter mobile apps. The **generator must emit** these patterns, the
**contract must require** them (gate IDs R1–R12, see `docs/harness-protocol.md` §3), and the
**evaluator must verify** them — so a generated app does not silently regress on problems already
solved. Cite this file (DRY); skills do not restate it.

Universal rule: **every platform call (storage, network, ads, purchases, permissions, method
channels) is wrapped in try/catch, logs via `debugPrint` (or the app logger), and never crashes the
UI.** Failures surface as a localized error state with a retry, never as a red screen or a silent
blank.

---

## Async UI states (R1)

- **Every data-backed screen renders three explicit states**: loading (skeleton/spinner), empty
  (localized message + primary call-to-action), error (localized message + **Retry**). With Riverpod
  use `AsyncValue.when(data:, loading:, error:)` — never `.value!` / `.requireValue` in a build method.
- **Shared state widgets**: one `AsyncValueView` / `EmptyView` / `ErrorView` in `lib/core/widgets/`
  so every screen looks consistent and the evaluator can grep for them.
- **Retry = invalidate**: the retry button calls `ref.invalidate(provider)` (or the notifier's
  `refresh()`), not a manual re-fetch that bypasses the provider.
- **Global error capture** in `main()`: `FlutterError.onError` + `PlatformDispatcher.instance.onError`
  log instead of crash; in release set `ErrorWidget.builder` to a friendly localized widget instead
  of the grey error box.
- **Pull-to-refresh** (`RefreshIndicator`) on lists whose data can change remotely.
- **Optimistic updates roll back** on failure and show a SnackBar — never leave the UI claiming a
  write that did not persist.

## Network resilience (R2 — only when the app calls the network)

- **One HTTP client** (`dio` or `http`) in `lib/core/services/`, injected via a provider; widgets and
  notifiers never construct clients.
- **Timeouts on every request** (connect ~10 s, receive ~20 s) — a hung request otherwise spins forever.
- **Retry with exponential backoff + jitter** for idempotent requests (GET), max ~3 attempts; never
  auto-retry non-idempotent POSTs.
- **Offline**: detect with `connectivity_plus` *only as a hint* (it reports interface, not internet);
  treat the actual request failure as truth. Show cached data + an offline banner rather than an
  empty error screen.
- **Cancel on dispose**: tie request cancellation to provider disposal (`ref.onDispose(cancelToken.cancel)`)
  so leaving a screen does not deliver results into a dead notifier.
- **Parse off the UI thread** for large JSON (`compute()` / `Isolate.run`).
- **Never ship secrets in the binary** (API keys with write scope, service-account JSON). Public
  client keys go through `--dart-define`; anything privileged lives on a server.

## App lifecycle / cold start (R3)

- **Lifecycle hook**: an app-level `AppLifecycleListener` (or `WidgetsBindingObserver`) — on
  `paused`/`inactive` flush pending writes; on `resumed` refresh time-sensitive data (dates,
  "today" views, tokens). Without it a "today" screen opened yesterday shows stale data.
- **Dispose everything**: prefer `autoDispose` providers; cancel `StreamSubscription`s, timers, and
  controllers (`TextEditingController`, `AnimationController`, `ScrollController`) in `dispose()` /
  `ref.onDispose`.
- **Never use `BuildContext` across an async gap** without `if (!context.mounted) return;`.
- **Startup sequence in `main()`**: `WidgetsFlutterBinding.ensureInitialized()` → error handlers →
  open local storage (await `SharedPreferences.getInstance()` / open DB) and pass it in via a
  `ProviderScope` override → orientation → `runApp(ProviderScope(...))` → (if ads) after first
  frame: UMP consent → ATT → `MobileAds.instance.initialize()`. Ads must not be requested before
  consent completes. Keep work before `runApp` minimal — a slow `main()` is a long native splash.
- **ATT prompt must actually appear (App Store 2.1)**: the ATT dialog only presents while the app is
  active. Requesting in `main()` before the first frame silently no-ops on current iOS → "the alert
  never appears" rejection. Required pattern: **wait until
  `WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed`** (poll up to ~4 s), then a
  **~400 ms settle delay**, then request **only when `notDetermined`** — from a post-frame callback,
  after the UMP form and before ads init. Localize the prompt for **every** configured locale.
- **Android back navigation**: with go_router, back pops the nested route stack first. Only on the
  **root** route intercept with `PopScope(canPop: false)` and show a localized `SnackBar` ("Press
  back again to exit"), exiting on a second back within ~2 s. Dialogs/bottom sheets close on back.
  Unsaved form → confirm-discard dialog.
- **Orientation natively**: lock per `config.orientation` in `Info.plist`
  `UISupportedInterfaceOrientations` + Android `android:screenOrientation`;
  `SystemChrome.setPreferredOrientations` alone still lets the app launch rotated (a visible flash).
  `orientation: all` → leave all orientations and make every screen work in both.
- **Reset state on logout / data wipe** — invalidate every user-scoped provider so nothing leaks
  across accounts.

## Navigation & deep links

- **One `GoRouter`** in `lib/app/router.dart`, routes named via constants; screens navigate with
  `context.goNamed` / `pushNamed`, never raw `Navigator.push` with inline routes.
- **Redirect guards** for onboarding-complete / auth state read a provider, and the router
  `refreshListenable` listens to it — otherwise the guard only runs once.
- **Deep links only if the PRD needs them**: iOS Associated Domains + `apple-app-site-association`,
  Android `intent-filter` with `autoVerify` + `assetlinks.json`. Unknown paths → a localized
  not-found screen, never a crash.
- **Preserve tab state** with `StatefulShellRoute.indexedStack` for bottom-nav apps.

## Forms & keyboard (R4)

- **`Form` + `TextFormField` validators** returning localized messages; validate on submit and on
  user interaction after the first submit (`AutovalidateMode.onUserInteraction`).
- **Keyboard never covers the focused field**: content in a scroll view, `Scaffold`
  `resizeToAvoidBottomInset: true` (default), bottom buttons inside `SafeArea` + `viewInsets` padding.
- **Correct `keyboardType`, `textInputAction` (next → done), `autofillHints`**, and
  `FocusScope.of(context).nextFocus()` on next.
- **Tap outside dismisses the keyboard** (`GestureDetector(onTap: FocusScope.of(context).unfocus)`
  or `TapRegion`).
- **Disable submit while submitting** (no double-submit) and show progress on the button.
- **Dates/numbers via `intl`** with the active locale — never hand-formatted strings.

## Permissions & privacy (R12 — only when the app uses a runtime permission or ATT)

- **Ask in context, not at launch**: show a short in-app rationale screen/dialog, then the system
  prompt, at the moment the feature needs it (Apple/Play discourage cold prompts).
- **Handle every outcome**: granted → proceed; denied → degrade gracefully with an explanation;
  permanently denied → button to `openAppSettings()` (`permission_handler`).
- **Every `NS*UsageDescription` present and localized** per configured locale
  (`ios/Runner/<locale>.lproj/InfoPlist.strings`), describing the concrete user benefit — a vague
  string ("needs camera") is a 5.1.1 rejection.
- **Android 13+ notifications** need the runtime `POST_NOTIFICATIONS` request; exact alarms need
  `SCHEDULE_EXACT_ALARM` justification — prefer inexact scheduling.
- **Collect the minimum**: no analytics/tracking SDK unless the PRD requires it; whatever is added
  must be reflected in the App Privacy label, Play Data Safety, and `PrivacyInfo.xcprivacy`.

## Accessibility (R10)

- **Honor OS text scaling** — apps must NOT pin `MediaQuery.withNoTextScaling` on content. Layouts
  survive 200% text scale without overflow (use `Flexible`/`Wrap`, avoid fixed-height text rows).
  The only acceptable clamp is a global `TextScaler.clamp(maxScaleFactor: 2.0)`.
- **Tap targets ≥ 48×48 dp** for every interactive control.
- **`Semantics` / `tooltip` on icon-only buttons** (`IconButton(tooltip: ...)` counts); images that
  convey meaning get `semanticLabel`, decorative ones `excludeFromSemantics: true`.
- **Text contrast ≥ 4.5:1** (3:1 for large text) in both light and dark theme.
- **Respect Reduce Motion** — `MediaQuery.of(context).disableAnimations` skips non-essential
  animations (hero flourishes, parallax, auto-playing carousels).
- **No flashing faster than 3×/second** (photosensitive safety, WCAG 2.3.1).
- **Dark mode**: ship `theme` + `darkTheme` from the design tokens and default to
  `ThemeMode.system`; never hard-code `Colors.white`/`Colors.black` in widgets.
- **Focus order / screen reader**: logical reading order; custom tiles use `MergeSemantics`.

## Performance

- **Lists**: `ListView.builder` / `SliverList` for anything that can grow; never `Column` of
  `children: items.map(...)` for unbounded data. Provide `itemExtent`/`prototypeItem` when rows are fixed.
- **Rebuild scope**: `ref.watch(provider.select((s) => s.field))` for narrow dependencies; `const`
  constructors everywhere possible; split big build methods into widgets, not helper methods.
- **Images**: `cacheWidth`/`cacheHeight` for decoded size; `cached_network_image` for remote
  images; precache hero images.
- **No work in `build()`**: no sorting/filtering/formatting of large collections in build — derive
  it in a provider.
- **Jank budget**: 16 ms/frame; profile with `flutter run --profile` + DevTools before blaming the device.

## Build / platform

- **Bundle id identical on both platforms** — iOS `PRODUCT_BUNDLE_IDENTIFIER` (all build configs) ==
  Android `applicationId` + `namespace` == `config.bundle_id`, byte-for-byte (lowercase `[a-z0-9.]`,
  no `_`/`-`/uppercase). `flutter create` derives the id from the project name and can leave
  underscores/case or diverge between platforms — set it explicitly on both. AdMob + store records
  use this exact string.
- **Android `minSdk` = max(23, highest plugin requirement)** — `google_mobile_ads` needs ≥ 23 (newer majors
  may need more; check each plugin's own `minSdk`). Never lower an existing higher value.
- **iOS `Podfile` platform**: bump `platform :ios, '<x>'` to the highest plugin requirement, or
  `pod install` fails.
- **`Info.plist`**: `NSUserTrackingUsageDescription` (ATT) and `SKAdNetworkItems` are required for an
  ads build. `SKAdNetworkItems` is a **manual** step — the SDK does not inject it; include Google's
  `cstr6suwn9.skadnetwork` plus the full third-party buyer list (AdMob serves third-party demand even
  without mediation). Copy the current list at build time — it changes:
  [quick-start](https://developers.google.com/admob/ios/quick-start) /
  [3p SKAdNetwork IDs](https://developers.google.com/admob/ios/3p-skadnetworks).
- **iOS `PrivacyInfo.xcprivacy` (iOS 17+)**: ship a Privacy Manifest and register it in the Xcode
  project, or App Store Connect rejects the upload. Declare reasons for any required-reason APIs
  (UserDefaults, file timestamps, disk space, system boot time).
- **Android core library desugaring**: enable `coreLibraryDesugaring` in
  `android/app/build.gradle.kts` (e.g. `flutter_local_notifications` requires it) or the build fails.
- **Localized app display name**: set the store/home-screen name per locale — iOS
  `<locale>.lproj/InfoPlist.strings` (`CFBundleDisplayName`), Android per-locale `strings.xml`.
- **Icon + splash + in-app logo from one shared painter** for visual consistency; the native splash
  `color` must match the first Flutter frame background (else a color blink on launch), and provide a
  dark-mode splash color. iOS icon must be opaque (no alpha); `flutter_launcher_icons: remove_alpha_ios: true`.
- **Android adaptive icon ≠ iOS icon — don't reuse the full-bleed image.** The adaptive-icon canvas
  is 108dp but the launcher mask shows only ≤72dp, and just the centre ~66dp circle is guaranteed
  unclipped. A full-bleed iOS icon dropped in as the `adaptive_icon_foreground` gets cropped/"zoomed".
  Ship a **separate padded foreground** (`icon-fg.png`, motif inside the safe zone, ~25% margin) over
  a solid `adaptive_icon_background` colour, plus a **monochrome layer**
  (`adaptive_icon_monochrome`, white-on-transparent) for Android 13+ themed icons.
- **Device family**: `device_family: phone` → `TARGETED_DEVICE_FAMILY = 1` and remove the
  `UISupportedInterfaceOrientations~ipad` key (avoids the iPad screenshot requirement).
  `universal` → `"1,2"` with **all four iPad orientations** (or `UIRequiresFullScreen`), and layouts
  that use the extra width (master-detail / max content width) instead of stretched phone UI.
- **Asset paths lowercase**: Android/Linux are case-sensitive; keep `assets/**` names lowercase and
  declare directories (trailing slash) in `pubspec.yaml`. Every asset referenced in code or
  `pubspec.yaml` must exist — a dangling reference is a runtime crash/blank (R7).
- **Ship CI from day one**: `.github/workflows/ci.yml` running `flutter analyze --no-fatal-infos` +
  `flutter test` on push/PR.
- **Flavors / environments**: pass environment via `--dart-define` (`ENV=dev|prod`), not separate
  hard-coded files; debug builds use AdMob test IDs automatically.
- **A build script that `git checkout`s a generated-but-tracked file silently reverts real source
  changes.** iOS build scripts commonly restore `ios/Runner.xcodeproj/project.pbxproj` after
  `flutter build`/prebuild rewrites it. If someone edited that file on purpose (device family,
  capabilities, a build setting), `git checkout` throws the edit away. Copy the file before the step
  and `mv` the copy back after, instead of checking out.
- **Do not edit a shell script while it is running.** `zsh` reads the file by byte offset as it
  executes; an edit shifts every later offset and the shell resumes mid-line, running garbage.
- **Release builds for both platforms at once will OOM a 16 GB machine** and kill both. Run them
  sequentially, and gate an iOS build on free disk (~12 GB) — a full disk fails deep inside the
  archive step with an error that does not mention disk.
- **Release-mode R8/ProGuard**: anything reflective (Room via WorkManager pulled in by AdMob, Gson
  models) needs keep rules; test a `--release` build on a device before upload — debug never shows it.

## Ads (init coordination — see also the monetize skill)

- **Gate the ad SDK to mobile only**: guard on `!kIsWeb && (Platform.isIOS || Platform.isAndroid)`.
- **Coordinate with `MobileAds.instance.initialize()`** — don't request an ad before init completes.
  Test IDs in debug, real IDs (from config) on release.
- **Banners never cover content**: anchored adaptive banner placed in the `Scaffold`
  `bottomNavigationBar` slot (or above it) inside `SafeArea` — never in a `Stack` over the list.
  No banner on onboarding, forms in progress, paywall, or permission rationale screens.
- **Interstitials only at natural breaks** (after a task completes, between sections), with a
  frequency cap (time-based + action-count) and never on launch, on back press, or mid-task.
  Unexpected interstitials are a Play "disruptive ads" policy strike.
- **App-open ads**: on resume from background after a cooldown (e.g. ≥ 4 h background or first
  resume per session), never on the very first launch / before onboarding, never over a system dialog.
- **Native ads in lists** at a fixed cadence (e.g. every 8 items), visually labeled "Ad", styled
  with the design tokens; dispose `NativeAd` when its row scrolls off for good.
- **Rewarded**: user-initiated only ("Watch an ad to unlock X for 24 h"), reward granted in
  `onUserEarnedReward`, never auto-shown.
- **5 s timeouts on UMP** (`requestConsentInfoUpdate` + `loadAndShowConsentFormIfRequired`) — flaky
  networks otherwise hang forever. The UMP form needs a GDPR message created in the AdMob console.
- **A "Privacy options" entry in Settings** when `privacyOptionsRequirementStatus == required`
  (UMP), so users can change consent later.

## In-app purchases & subscriptions (only when `monetization.iap: true`)

- **Digital goods/features must use IAP (App Store 3.1.1 / Play Payments policy)** — no external
  payment links for unlocking in-app content.
- **Restore Purchases button** reachable from Settings and the paywall (Apple requirement for
  non-consumables and subscriptions).
- **Subscription paywall disclosures (3.1.2)**: price, period, free-trial terms, auto-renew notice,
  and tappable Terms of Use (EULA) + Privacy Policy links on the paywall itself and in store metadata.
- **Entitlement is the source of truth**, not the purchase event: on launch, query past purchases /
  verify receipts and derive `isPremium`; `completePurchase` every delivered transaction (Android
  refunds un-acknowledged purchases after 3 days).
- **Remove-ads entitlement** hides every ad format immediately (no app restart needed).
- **Test with sandbox / license testers**; product IDs exist in both consoles before review, and
  App Review needs the IAP products submitted together with the binary.

## Device flow tests (Maestro)

Suite layout and who writes what: `docs/harness-protocol.md` §3 Device test suite.

- **One flow at a time** — always `.maestro/suite.sh`. `maestro test <dir>` started several flows
  concurrently on one device (2.11.0); they fought over the app and failed at random.
- **Screenshots are not in the cwd** — `takeScreenshot` writes
  `<--test-output-dir>/<timestamp>/<flow>/takeScreenshot/<name>.png` (`~/.maestro/tests/…` without
  the flag). `suite.sh` copies them flat, so names must be unique across the suite: prefix `F<n>-`.
- **iOS build under test** — `flutter build ios --simulator --debug` + `xcrun simctl install <udid>
  build/ios/iphonesimulator/Runner.app`; that build cold-starts from `launchApp` with no debugger.
  If an app exits right after `launchApp` (a debug build that needs the Flutter tool attached),
  run it under `flutter run` and start the flows on its current screen without `launchApp`; every
  relaunch step then needs a new `flutter run`. Android: `flutter build apk --debug` +
  `adb install -r`. Every flow failing at install or `launchApp` is usually the build, not Maestro:
  a simulator build left x86_64-only (a pod excluding arm64) will not install on Apple Silicon
  simulators — override the archs in the Podfile `post_install`; an app without
  `UIApplicationSceneManifest` traps at launch on iOS 27 — adopt the UIScene lifecycle.
- **`--dart-define=screenshots=true` hides prompts** — besides ads it suppresses the permission and
  rating prompts, so R12 permission flows always run on a normal build.
- **`launchApp` defaults** — stops the running app first (`stopApp: true`) and grants every runtime
  permission unless `permissions:` is set. Permission flows (R12): `permissions: { all: unset }`
  → the system prompt appears (assert the in-app rationale came first); `{ all: deny }` → the
  denied path. Resume (R3): `pressKey: home`, then `launchApp: { stopApp: false }`.
- **Selectors** — Flutter exposes visible text, `tooltip` and `Semantics(label:)`. Match a regex
  alternation over every configured locale (`"Save|Lưu"`; escape `( ) . + ? *`), so the suite
  passes whatever the device language. A custom-painted canvas (`CustomPaint`) has no semantics →
  `point: "x%,y%"`; on a normal widget a needed `point:` tap is an R10 bug (missing label) — fix
  the label instead.
- **Merged semantics** — Flutter merges a card's or list tile's texts into one node
  (`"Title\n12 items"`), so match `"(?s)Title.*"` instead of the bare title. Content drawn in a
  system overlay window is not in Maestro's view tree at all.
- **Ads steal taps** (`admob_enabled: true`): `ready.yaml` closes the full-screen ones, but a banner
  (collapsible ones especially) covers bottom controls. Run every non-permission flow on a build
  with the project's ad-off flag (`screenshots`); if that flag also seeds demo data, the flows'
  fresh-install asserts expect the seed.
- **Address devices by UDID / serial** (`--device`, `xcrun simctl … "$SIM"`, `adb -s`), never
  `booted`: with two simulators booted, `booted` picks the wrong one.
- **Text input** — `tapOn` the field before `inputText`; `hideKeyboard` before tapping a button
  the keyboard may cover.
- **Slow on iOS** — each command takes seconds; one flow ≈ 1–3 min. Keep a flow to one PRD flow,
  `waitForAnimationToEnd` before `takeScreenshot`, `extendedWaitUntil` (≥ 30 s) for cold start, and
  run the suite in the background (Bash `run_in_background: true`).
- **Console log** — `suite.sh` streams the device log (`simctl spawn … log stream`, `adb logcat`).
  An empty log means capture broke, never a clean run.
- `MAESTRO_CLI_NO_ANALYTICS=1` (set by `suite.sh`) silences the analytics prompt.

## Store screenshots

- **Screenshot mode flag** (`--dart-define=screenshots=true`): disables ads, the ATT/UMP prompts,
  and permission prompts during capture, and seeds realistic demo data, so frames are clean.
- **Android: convert the Flutter surface to an image once** (not per shot) or multi-shot capture
  fails after the first frame.

## Persistence & data safety (R9)

- **All storage behind repositories** (`lib/features/<f>/data/*_repository.dart`) exposed via
  providers; widgets/notifiers never call `SharedPreferences`/DB APIs directly.
- **Pick storage by shape**: key-value settings → `shared_preferences`; structured/relational or
  > a few hundred records → `drift` or `sqflite`; documents → JSON file via `path_provider`. Decide
  in plan; don't add a DB for a settings screen.
- **Version the schema** (`schemaVersion` + migrations / `save_v1` key) so an update never corrupts
  existing user data; write a migration test when the schema changes.
- **Secrets/tokens in `flutter_secure_storage`**, never in `shared_preferences` (plaintext).
- **Write immediately on user action** (or debounce ≤ 1 s and flush on `paused`) so a kill doesn't
  lose input; batch high-frequency writes.
- **Durable restore (optional)**: if the PRD says data must survive reinstall/device change without
  an account, use `templates/save_repository.dart.template` (iOS Keychain + Android Block Store +
  prefs mirror). Otherwise rely on Android Auto Backup and say so in the PRD.
- **Export/delete user data** when the app stores personal data (good practice; required with accounts).

## Store rejections (App Review) — real ones already hit

These caused real App Store / Play rejections and were fixed; prevent them up front.

- **4.2 Minimum Functionality** — the most common rejection for utility apps: a thin wrapper, a
  single static screen, or a website in a WebView. Ship real, native, offline-capable functionality
  with enough depth (multiple meaningful flows, settings, persistence) and an onboarding that
  explains value.
- **4.3 Spam / copycats** — a near-identical app to many existing ones (flashlight, calculator,
  generic to-do) without a distinct feature gets bounced; research must name the differentiator.
- **5.1.1(v) Account deletion** — if the app lets users create an account, it must let them delete
  it in-app.
- **4.8 Login services** — offering third-party social login requires an equivalent privacy-focused
  option (Sign in with Apple) on iOS.
- **2.1 — ATT prompt never appears**: see the ATT pattern under *Lifecycle*. For the review reply,
  attach a screen recording on a physical device showing a fresh install → the ATT prompt.
- **Permission strings not localized** (real, repeat rejection): every `NS*UsageDescription`
  (especially `NSUserTrackingUsageDescription`) must be translated per configured locale in
  `ios/Runner/<locale>.lproj/InfoPlist.strings`. The monetize skill owns ATT; verify at submit.
- **App icon / screenshots with an alpha channel are rejected** — flatten to opaque RGB.
- **Play listing requires a hi-res icon (512×512) + feature graphic (1024×500)** — generate both
  (opaque) from the shared painter and place at `android/fastlane/metadata/android/<locale>/images/
  icon.png` + `featureGraphic.png` so `supply` uploads them.
- **ASC rejects duplicate build numbers** — bump the build number on every upload.
- **`sips -s format png` does NOT strip an alpha channel** — use
  `magick in.png -background white -alpha remove -alpha off out.png`, or round-trip through JPEG with
  `sips`. Always confirm with `sips -g hasAlpha` → `hasAlpha: no`.
- **Count store-metadata limits in characters, not bytes** — `wc -c` counts bytes (Hangul /
  Vietnamese diacritics are multi-byte). Use
  `printf '%s' "$s" | python3 -c 'import sys;print(len(sys.stdin.read()))'`.
- **`integrationDriver()` writes no screenshots without an `onScreenshot` callback** — the driver
  must pass a callback that writes the bytes to disk.
- **`deliver` silently uploads every iOS screenshot twice** when ASC's `sourceFileChecksum` doesn't
  match the local MD5; `overwrite_screenshots: true` does not help. The `screenshots` lane prunes by
  file name and asserts the per-locale count afterwards — keep that step; run
  `fastlane screenshots_prune` to clean an app that already has duplicates.
- **Export compliance prompt every upload** — set `ITSAppUsesNonExemptEncryption = false` in
  `Info.plist` if the app uses no non-exempt encryption (HTTPS alone is exempt).
- **AdMob "Publisher data not found" / no ads** — the ad unit's publisher prefix must match the
  AdMob app, and the bundle id / package name must exactly match what's registered in AdMob.
- **Store-listing + App-Review info must be filled** (from `config.md` developer block): privacy
  policy URL, support + marketing URLs, copyright, and App Review contact. If the app has login,
  provide a **demo account** in review notes. iOS: write `ios/fastlane/metadata/{copyright.txt,
  <locale>/support_url.txt,marketing_url.txt,privacy_url.txt,review_information/*}`. Android: contact
  email/website via the Publisher API (`set_contact_details.rb`); privacy URL + Data Safety are manual.
- **2.3.10 — no other-platform mentions in metadata** — keep store-specific copy.
- **ASCII-safe description** — App Store Connect's linter rejects decorative Unicode (box-drawing
  chars); use plain ASCII headers/punctuation.
- **Category must match the app** — `config.app_category` / `play_category` drive both stores;
  a mismatched category draws review scrutiny and hurts ASO.
- **iOS App Privacy label (App Store Connect)** — a Connect form, **separate from**
  `PrivacyInfo.xcprivacy`. For an offline app + AdMob: **Identifiers → Third-Party Advertising** +
  **Tracking**. Add every category the app actually collects (contact info for accounts, health,
  user content, diagnostics for crash SDKs). With no ads and no collection → **Data Not Collected**.
- **Play Data Safety** — must match the iOS label. Mismatched declarations across stores draw
  review scrutiny.
- **COPPA / child-directed consistency** — default every app to **not** child-directed unless the
  concept clearly targets kids; if it does, Play Target Audience, AdMob "Made for kids" +
  `tagForChildDirectedTreatment(true)` must all agree and personalized ads must be off.
- **Age rating: the declarations Apple added in 2026** — `userGeneratedContent`,
  `messagingAndChat`, `ageAssurance`, `gunsOrOtherWeapons`, `advertising`,
  `healthOrWellnessTopics`, `parentalControls`. Unset → `409 STATE_ERROR.ENTITY_STATE_INVALID`
  naming `ageRatingDeclarations`. **Every AdMob app must set `advertising` = Yes**.
  `ageRatingDeclarations` is write-only over the API (`GET` → `403`).
- **`POST /v1/appStoreVersionSubmissions` is deprecated** — submitting is now three calls:
  `POST /v1/reviewSubmissions` → `POST /v1/reviewSubmissionItems` →
  `PATCH /v1/reviewSubmissions/<id> { submitted: true }`. Reuse an existing `READY_FOR_REVIEW` one.
- **A rejected version is still attached to the submission that rejected it** — for every
  submission in `UNRESOLVED_ISSUES`, `PATCH /v1/reviewSubmissionItems/<itemId> { removed: true }`
  first, and attach the new build to the same (editable) version instead of creating a new one.
- **Metadata locks at release, not at submission** — `whatsNew`, URLs, and review notes stay
  editable through `IN_REVIEW`; `PATCH` returns `409` only at `READY_FOR_SALE`. Proofread before approval.
- **Resolution Center has no API** — read state, not rejection text; write the explanation into
  `appStoreReviewDetail.notes` **before** resubmitting.
- **A released version string cannot take another build** ("train version is closed") — bump the
  version name in `pubspec.yaml`, leave `+N` increasing on its own schedule.
- **Declaring iPad without supporting all iPad orientations is a rejection** (4.0 / 90474) — see
  *Device family* above; check what the template actually wrote.
- **Play Console declarations come from the merged manifest, not yours** — a dependency's own
  manifest (e.g. `FOREGROUND_SERVICE_*`, `SCHEDULE_EXACT_ALARM`, `QUERY_ALL_PACKAGES`,
  `READ_MEDIA_*`) becomes your declaration under **App content → Needs attention**. Check with
  `grep uses-permission android/app/build/intermediates/merged_manifests/release/AndroidManifest.xml`.
- **A privacy policy URL is readable over the App Store API and not over Play's** — auditing Play
  privacy URLs is a manual job.

---

## Long-tail

**Riverpod**
- **Don't `ref.read` in `build`** to get reactive data — `ref.watch` it; `ref.read` is for callbacks.
- **Don't create providers dynamically** inside widgets; use `.family` with a stable, `==`-comparable arg.
- **`ref.listen` for side effects** (SnackBar on error, navigation on success), not `watch` + if.
- **Override storage in tests** via `ProviderContainer(overrides: [...])` — no interfaces needed
  just for faking a concrete repository.

**Lifecycle / crash**
- **`setState() called after dispose()`** — every async callback in a `State` checks `mounted`.
- **Snapshot before mutating during iteration** — iterate `.toList()` when the loop body can modify the collection.

**Build / platform**
- **iOS Podfile static linkage** — `use_frameworks! :linkage => :static` + `use_modular_headers!`
  fixes the recurring "Failed to verify code signature (0xe8008014)" with AdMob / secure-storage pods.
- **Run `pod install`** after adding/changing any iOS plugin, or the iOS build fails.

**Persistence**
- **Migrate legacy keys** once (old key → new schema) then delete the old key.
- **Dates**: store UTC ISO-8601 / epoch ms; convert to local only for display. "Today" logic uses
  the device's local date, recomputed on resume.
