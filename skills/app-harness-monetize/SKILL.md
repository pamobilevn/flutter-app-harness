---
name: app-harness-monetize
description: Phase 7 — AdMob strategy across all formats (banner, native, interstitial, app-open, rewarded), guided ad-unit creation, consent (UMP/ATT) + ad code injection, then ask whether to add IAP/subscriptions and inject them if chosen.
argument-hint: ""
allowed-tools: [Agent, Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
---

# app-harness-monetize

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

Phase 7 of the flutter-app-harness pipeline. Decides where each AdMob format fits the app's
screens and flows, guides the user through manual ad-unit creation in the AdMob console, injects
`google_mobile_ads` + UMP/ATT consent + every chosen ad format, then asks whether to add in-app
purchases / subscriptions (`in_app_purchase`) and injects them if chosen.

All file schemas (`config.md`, `state.md`, `pipeline-log.md`) and the phase transition table are
defined in `docs/harness-protocol.md` — the single source of truth (§1 for `config.md` including the
`monetization:` block; §2 for `state.md`; §6 for log schemas; §7 for the `monetize → build`
transition and the `skip_monetize` rule). Do not redefine schemas here. Ad/IAP robustness patterns
live in `docs/app-gotchas.md` → **Ads** and **In-app purchases & subscriptions**; cite them, don't
restate them.

Derive the app root `<app>`: `config.project_path` when `config.mode: update`, else
`<projects-dir>/<app_slug>` (or `.` when cwd is already the app project, i.e. `./pubspec.yaml`
exists). Work inside `<app>` — `docs/harness/` lives there. `<app_pkg>` = the Dart package name
(snake_case, = pubspec `name:`; `sed -n 's/^name: *//p' pubspec.yaml`) used in `package:` imports —
in update mode read it, never derive it from `app_slug`.
Every message printed to the user is emitted in `config.default_language`.

---

## Input — Read Inputs

Before any action, load:

1. `docs/harness/config.md` — `app_slug`, `app_name`, `bundle_id`, `default_language`, `locales`,
   `backend`, `skip_monetize`, `auto_idea`, `auto_deploy`, `developer.privacy`, and the
   `monetization:` block.
2. `docs/harness/state.md` — confirm `next_role: monetize`.
3. PRD — the latest `docs/harness/plans/*-prd.md` (`ls -t docs/harness/plans/*-prd.md | head -1`):
   sections **Primary user flows**, **Screens & navigation**, **Monetization intent**.
4. Design doc — the latest `docs/harness/plans/*-design.md`: `## Screen specs` (one `### <routeName>`
   per screen, each noting its reserved ad-slot position — design reserves the position only;
   nothing renders until this phase fills it). Theme: `lib/core/theme/{design_tokens.dart,app_theme.dart}`.

---

## Re-entry — resuming after a pause

This phase can pause twice for `manual_action` (AdMob console in Step 2, IAP consoles in Step 5).
`app-harness-resume` confirms the manual step with the user and re-dispatches this skill **from the
top**. No extra state keys exist (`checkpoint` is generator-only), so derive the resume point from
artifacts and skip every step that is already done:

| Already done when… | Skip |
|---|---|
| `docs/harness/specs/*-monetization.md` exists | Step 1 (reuse its table) |
| `monetization.ios_app_id`, `android_app_id` are non-empty and **every `used: yes` key** in the strategy spec has an `ad_units[]` entry with non-empty `ios_id` and `android_id` (update mode: audit pre-filled the existing units, so a `NEW` unit without ids still needs Step 2) | Step 2 |
| the ad layer exists (`lib/core/services/ads/ads_service.dart`, or in update mode the existing layer extended with every `used: yes` key) and `flutter analyze` is clean (update mode: no new issues, protocol §3) | Step 3 code (still re-run the idempotent native-config edits in 3.2/3.3 — they are safe to repeat) |
| `monetization.iap` is `true` or `false` (not `ask`) — update mode instead: the change request adds no IAP, or every product it adds is already in `monetization.products` | Step 4 question |
| `lib/core/services/purchases/purchase_service.dart` exists (update mode: or the existing purchase layer handles every id in `monetization.products`) | Step 5 code |
| `pipeline-log.md` has a `pause \| monetize \| manual_action: IAP console…` row with no later `complete \| monetize` row (this skill only re-runs after `app-harness-resume` confirmed the manual step) | Step 5 console pause → go to Step 6 |

---

## Skip Flag — skip_monetize Handling

Check `skip_monetize` immediately after loading inputs. If `skip_monetize: true` (it only means
"this phase does not run" — downstream checks read `admob_enabled` / `iap`, protocol §1):

1. `monetization:` block in `docs/harness/config.md` (protocol §1):
   - **New mode** — write `admob_enabled: false`, `iap: false`, `ad_units: []`, `products: []`
     (the app ships no ads, no IAP).
   - **Update mode** — leave the block **exactly as audit recorded it** (`admob_enabled`, `iap`,
     ids): the existing monetization ships unchanged.
2. Write `docs/harness/state.md`:

   ```yaml
   status: running
   current_phase: monetize
   next_role: build
   updated_at: "<ISO-8601 UTC now>"
   ```

3. Append to `docs/harness/pipeline-log.md` (protocol §6):

   ```
   | <ISO-8601 UTC now> | complete | monetize | skip_monetize=true; no ads, no IAP; next: build |
   ```

   Update mode: `| <ISO-8601 UTC now> | complete | monetize | skip_monetize=true; existing monetization kept (admob_enabled=<v>, iap=<v>); next: build |`

4. Exit immediately. Do not ask questions, do not inject code.

---

## Update mode (`config.mode: update`)

Monetize only runs in update mode when the audit's change request put monetization in scope
(otherwise audit set `skip_monetize: true` and the Skip Flag section above applies). Then:

- **Start from what ships today.** The audit spec's inventory lists the existing ad SDK, formats, ad
  unit ids, consent flow, and IAP products (already copied into `config.monetization`). Keep every
  existing ad unit id and product id — they carry live revenue and store history; never rename or
  recreate them.
- **Delta only.** The strategy table marks each format/placement `KEEP`, `CHANGE`, or `NEW` per the
  change request. Step 2 asks the user only for the ad units that are `NEW`; Step 5 only for new
  products. Placements on `KEEP` screens move only if the change request says so.
- **Follow the project's architecture** (`config.architecture`): if the app is not on Riverpod, adapt
  the services in 3.5 / 5.2 to its existing pattern (a `ChangeNotifier`/Cubit/singleton the app already
  uses) instead of adding Riverpod for ads alone. Reuse an existing ads/purchase layer when one exists
  and extend it, rather than adding a second one.
- **Existing consent flow:** if the app already runs UMP + ATT, verify the order (UMP form → ATT → SDK
  init) and the localized ATT strings, and fix them only if wrong — that is an audit gap item.
- **Legacy seams** (the generator's `AppConfig`, `bootstrap.dart` container and `onboardingDoneProvider`
  may not exist): extend the app's existing config spot (§3.4), startup (§3.6, §5.3) and onboarding
  signal (§3.5 app-open) instead of creating parallel ones — each section names its fallback.
- **Gate** is the update-mode rule from `docs/harness-protocol.md` §3 (no new analyze issues, all tests
  pass, files touched by this phase are clean).

---

## Step 1 — Strategy (per format, per screen)

Read the PRD flows + monetization intent and the design screen inventory, then decide for **each**
format whether it is used and **exactly where** (route + trigger). Rules — `docs/app-gotchas.md` → Ads:

| Format | Use it when | Placement rule |
|---|---|---|
| **banner** | the app has list/detail screens | Anchored adaptive banner in the `Scaffold` `bottomNavigationBar` slot inside `SafeArea` (above an existing `NavigationBar`), **list/detail screens only**. Never on onboarding, forms in progress, paywall, permission rationale, or over content in a `Stack`. |
| **native** | a list can grow long (≥ 2 × `nativeAdInterval` items) | One `NativeAdSlot` after every `AppConfig.nativeAdInterval` items, visually labeled "Ad" (template badge), styled from the theme tokens. |
| **interstitial** | a flow has a clear "task completed" moment | Only at natural breaks **after** a task completes and its success feedback shows. Frequency cap: `AppConfig.interstitialMinInterval` **and** every `AppConfig.interstitialEveryNActions` completed tasks. Never on launch, on back press, or mid-task. |
| **app_open** | users return to the app repeatedly | On a real resume from background after a cooldown (`AppConfig.appOpenCooldown`, plus `appOpenMinBackground` away). Never on cold start / first launch, never before onboarding completes, never after a system dialog. |
| **rewarded** | a feature can be temporarily unlocked | User-initiated only ("Watch an ad to unlock <feature> for 24 h"); reward granted in `onUserEarnedReward`; never auto-shown. Unlock expiry persisted through the feature's repository (R9); duration in `app_config.dart`. |

A format with no valid placement is marked **not used** with a one-line reason (e.g. "no list
longer than 16 items → native not used"). If the app is child-directed, follow
`docs/app-gotchas.md` → Store rejections (Made for kids / `tagForChildDirectedTreatment`) first.

Ad-unit keys are `<format>_<placement>` in snake_case (`banner_list`, `native_feed`,
`interstitial_task_done`, `app_open_resume`, `rewarded_unlock_export`); the AdMob unit name is
`<app_slug>_<key>`; the `AdIds` getter is the camelCase key.

Write `docs/harness/specs/<YYYY-MM-DD>-monetization.md` — a fresh Claude implementing placements
must know exactly where each call goes:

```markdown
# Monetization strategy — <app_name>

| key | format | used | screen (route) | trigger / position | reason |
|---|---|---|---|---|---|
| banner_list | banner | yes | /habits, /habits/:id | Scaffold bottomNavigationBar, above NavigationBar | list + detail screens |
| native_feed | native | yes | /history | after every 8 rows | history grows unbounded |
| interstitial_task_done | interstitial | yes | /habits/:id/edit | after save succeeds + SnackBar | natural break |
| app_open_resume | app_open | yes | any | resume from background, cooldown 4 h | daily-return app |
| rewarded_unlock_export | rewarded | no | — | — | no lockable feature in PRD |

Caps: interstitial ≥ 90 s apart and every 3 completed tasks; app-open ≥ 4 h apart, ≥ 30 s away.
```

---

## Step 2 — AdMob Console (manual) → pause / resume

Google's API cannot create AdMob apps or ad units — the user creates them by hand. This applies
in fully hands-off mode too (there is no API), so this step always involves the user.

Use `AskUserQuestion` (text in `default_language`), listing **every** unit from the Step 1 table
with `used: yes`:

> "Please open the AdMob console (https://admob.google.com) and:
> 1. **Apps → Add app** → iOS, then Android. Use bundle id `<bundle_id>` (iOS) / package name
>    `<bundle_id_android or bundle_id>` (Android) exactly (a mismatch = "Publisher data not found", no ads). "Made for kids" = No unless child-directed.
>    Copy each **App ID** (`ca-app-pub-XXXX~YYYY`).
> 2. For each app → **Ad units → Add ad unit**, create:
>    - `<app_slug>_banner_list` — Banner
>    - `<app_slug>_native_feed` — Native advanced
>    - `<app_slug>_interstitial_task_done` — Interstitial
>    - `<app_slug>_app_open_resume` — App open
>    - `<app_slug>_rewarded_unlock_export` — Rewarded
>    Copy each **unit ID** (`ca-app-pub-XXXX/NNNN`) for iOS and Android.
> 3. **Privacy & messaging**: create + publish a **GDPR** message (European regulations) and an
>    **IDFA explainer** (iOS) message for both apps — the UMP consent form needs them.
>
> Paste all IDs here (key: iOS / Android). If you haven't done this yet, type 'defer' and I'll pause."

If the user types `defer` (or can't finish — console access, approval pending):

1. Write `docs/harness/state.md`:

   ```yaml
   status: paused
   current_phase: monetize
   next_role: monetize
   pause_reason: manual_action
   updated_at: "<ISO-8601 UTC now>"
   ```

2. Append the pause row — `app-harness-resume` shows its details to the user, so list the work:

   ```
   | <ISO-8601 UTC now> | pause | monetize | manual_action: AdMob console — add iOS+Android apps (<bundle_id>), create units <app_slug>_<key>…, publish GDPR + IDFA messages; paste IDs |
   ```

3. Stop. The user runs `/app-harness --resume` (→ `app-harness-resume`), which re-dispatches this
   skill; Re-entry skips Step 1 and asks for the IDs again.

On receiving IDs, validate the shapes (App ID contains `~`, unit ID contains `/`, same
`ca-app-pub-<publisher>` prefix everywhere) and write the `monetization:` block in
`docs/harness/config.md` (protocol §1):

```yaml
monetization:
  admob_enabled: true
  ios_app_id: "ca-app-pub-XXXX~YYYY"
  android_app_id: "ca-app-pub-XXXX~ZZZZ"
  ad_units:
    - key: banner_list
      format: banner
      placement: "/habits, /habits/:id — bottomNavigationBar"
      ios_id: "ca-app-pub-XXXX/IIII"
      android_id: "ca-app-pub-XXXX/AAAA"
    # one entry per used unit
  iap: ask
  products: []
```

Update mode: merge — set `admob_enabled: true`, fill the app IDs only if audit left them empty, add
the `NEW` units' ids to the existing `ad_units[]`, and keep the existing units, `iap` and `products`
exactly as audit recorded them.

---

## Step 3 — Ad Code Injection

### 3.1 Dependencies

```bash
flutter pub add google_mobile_ads app_tracking_transparency   # idempotent; resolves the latest
```

### 3.2 iOS — Info.plist (idempotent, safe on re-entry)

`plutil -replace` creates or overwrites a key, so re-running never duplicates anything. Don't use
PlistBuddy `Set`/`Add` for the ATT text — it silently strips `'` and `"` (`l'application` →
`lapplication`), which breaks French/Italian/… strings.

```bash
P=ios/Runner/Info.plist
plutil -replace GADApplicationIdentifier -string "<monetization.ios_app_id>" "$P"
plutil -replace NSUserTrackingUsageDescription -string "<ATT reason in default_language>" "$P"  # base / development-region fallback
JSON=$(printf '%s\n' cstr6suwn9.skadnetwork <every id from Google's current 3p list> \
  | python3 -c 'import json,sys; print(json.dumps([{"SKAdNetworkIdentifier": l.strip()} for l in sys.stdin if l.strip()]))')
plutil -replace SKAdNetworkItems -json "$JSON" "$P"
plutil -lint "$P"
```

**`SKAdNetworkItems` is a required manual step** — the SDK does not inject it. Without it iOS
install attribution breaks, and it's an expected config for an ads app at App Store review. AdMob's
exchange serves third-party demand even without mediation, so copy the **full current list** at
build time (it changes — never hard-code an old copy):
- Quick-start Info.plist snippet: <https://developers.google.com/admob/ios/quick-start>
- Full third-party SKAdNetwork IDs: <https://developers.google.com/admob/ios/3p-skadnetworks>

**Localize the ATT string for EVERY configured locale** (`config.locales`) — a reviewer or user in
another locale seeing a foreign-language permission prompt is a repeat rejection. The generator
already created `ios/Runner/<locale>.lproj/InfoPlist.strings` per locale (for `CFBundleDisplayName`)
and registered them in the Xcode project; **add the key to each** (create + register any missing
one; Chinese maps `zh`/`zh-Hans`/`zh_CN` → `zh-Hans.lproj`, `zh-Hant`/`zh_TW` → `zh-Hant.lproj`):

`ios/Runner/en.lproj/InfoPlist.strings`:
```
"NSUserTrackingUsageDescription" = "We use this to show ads that are more relevant to you.";
```
`ios/Runner/ko.lproj/InfoPlist.strings`:
```
"NSUserTrackingUsageDescription" = "더 관련성 높은 광고를 보여 드리기 위해 사용합니다.";
```
Every other locale: the same key, natural translation. Keep the wording truthful and consistent
with the App Privacy tracking declaration. Verify (loops over `config.locales`, not the lproj dirs,
so `Base.lproj` can't false-alarm and a missing dir is caught):

```bash
for l in $(sed -n 's/^locales: *\[\(.*\)\].*/\1/p' docs/harness/config.md | tr -d ' ' | tr ',' ' '); do
  case $l in zh|zh-Hans|zh_CN) d=zh-Hans;; zh-Hant|zh_TW) d=zh-Hant;; *) d=$l;; esac
  grep -q '"NSUserTrackingUsageDescription"' "ios/Runner/$d.lproj/InfoPlist.strings" 2>/dev/null \
    || echo "MISSING ATT string: ios/Runner/$d.lproj/InfoPlist.strings"
done
```

### 3.3 Android — manifest + minSdk

`minSdk` = **max(23, highest minSdk any plugin this phase adds declares)** (`docs/app-gotchas.md` →
Build/platform; `google_mobile_ads` 9.x declares 24) — a lower value fails at startup. Check the
plugins' own minSdk (Step 5 re-runs this for `in_app_purchase`):

```bash
for p in google_mobile_ads app_tracking_transparency; do
  V=$(awk -v p="  $p:" '$0==p{f=1} f&&/version:/{gsub(/"/,"",$2);print $2;exit}' pubspec.lock)
  D="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/$p-$V/android"
  grep -hs minSdk "$D/build.gradle" "$D/build.gradle.kts" | sed "s/^/$p: /"
done
```

In `android/app/build.gradle.kts` (legacy Groovy `build.gradle`: `minSdkVersion`): set
`minSdk = maxOf(flutter.minSdkVersion, <N>)` with N = that max. **Never lower an existing higher
value** — if the file already sets a higher literal, keep it.

In `android/app/src/main/AndroidManifest.xml` inside `<application>` — **grep first**; if the
key exists, update its value in place (a duplicate `<meta-data>` is a manifest-merger error):

```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-XXXX~ZZZZ"/>
```

### 3.4 Tunables — `lib/core/config/app_config.dart`

Edit the existing `AppConfig` class (Hard Gate 4 — no magic values in ad code). The generator
already declared `static const bool screenshotMode = bool.fromEnvironment('screenshots');` and the
seam `static const adsEnabled = false;`. **Replace only the `adsEnabled` line** with
`static const bool adsEnabled = !screenshotMode;` — do not declare `screenshotMode` again (a second
member is a compile error) — then add the tunables below:

```dart
  // ── Ads (monetize phase) ────────────────────────────────────────────────
  /// Master ad switch (replaces the generator's seam line). Screenshot mode turns every ad off.
  static const bool adsEnabled = !screenshotMode;

  /// Bound on each UMP network step (info update, form load) — flaky networks hang otherwise.
  static const Duration consentTimeout = Duration(seconds: 5);

  /// Interstitial frequency cap: both must hold before one may show.
  static const Duration interstitialMinInterval = Duration(seconds: 90);
  static const int interstitialEveryNActions = 3;

  /// App-open: min time between two app-open ads, and min time away that counts as a return.
  static const Duration appOpenCooldown = Duration(hours: 4);
  static const Duration appOpenMinBackground = Duration(seconds: 30);

  /// One native ad after every N list items.
  static const int nativeAdInterval = 8;
```

Keep only the constants of formats marked used. The screenshot skill passes
`--dart-define=screenshots=true` to every capture; `adsEnabled == false` makes `AdsService.start()`
return before UMP, ATT and SDK init, so no prompt or ad appears in store screenshots.

**Update mode, no `AppConfig`:** put the ad switch and these tunables in the project's existing
config spot (its constants/config class) and read them from there wherever the snippets say
`AppConfig`. Reuse the `screenshots` dart-define flag if it is already there (generator 5a adds it
when the app already shipped ads); only if it is absent (the app had no ads before), declare it there
once: `bool.fromEnvironment('screenshots')`, with the ad switch `= !<that flag>`.

### 3.5 `lib/core/services/ads/` — the ad layer

The snippets below compile cleanly (`flutter analyze`: 0 issues) against `google_mobile_ads` 9.1,
`app_tracking_transparency` 2.0.7 and `flutter_riverpod` 3.3. If `pub add` resolves a newer major,
re-check the deprecations it reports (e.g. 8.0 deprecated
`getCurrentOrientationAnchoredAdaptiveBannerAdSize`) — any analyzer info fails Hard Gate 1.

**`ad_ids.dart`** — Google's official test units in debug/profile (real units in a debug build are
invalid traffic → account strike), config IDs in release:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';

typedef _Ids = ({String ios, String android});

abstract final class AdIds {
  // https://developers.google.com/admob/flutter/test-ads
  static const _Ids _testBanner = (ios: 'ca-app-pub-3940256099942544/2435281174', android: 'ca-app-pub-3940256099942544/9214589741');
  static const _Ids _testNative = (ios: 'ca-app-pub-3940256099942544/3986624511', android: 'ca-app-pub-3940256099942544/2247696110');
  static const _Ids _testInterstitial = (ios: 'ca-app-pub-3940256099942544/4411468910', android: 'ca-app-pub-3940256099942544/1033173712');
  static const _Ids _testAppOpen = (ios: 'ca-app-pub-3940256099942544/5575463023', android: 'ca-app-pub-3940256099942544/9257395921');
  static const _Ids _testRewarded = (ios: 'ca-app-pub-3940256099942544/1712485313', android: 'ca-app-pub-3940256099942544/5224354917');

  static String _pick(_Ids real, _Ids test) {
    final ids = kReleaseMode ? real : test;
    return Platform.isIOS ? ids.ios : ids.android;
  }

  // One getter per config.md monetization.ad_units entry (getter = camelCase key).
  static String get bannerList => _pick(
    (ios: 'ca-app-pub-XXXX/IIII', android: 'ca-app-pub-XXXX/AAAA'), // banner_list ios_id / android_id
    _testBanner,
  );
  // nativeFeed → _testNative, interstitialTaskDone → _testInterstitial,
  // appOpenResume → _testAppOpen, rewardedUnlockExport → _testRewarded
}
```

Replace every `XXXX` placeholder with the collected IDs (Step 6 greps for leftovers, along with
`<bundle_id>` / `<app_pkg>` / `<app_slug>`); delete the
`_test*` constants of unused formats.

**`consent.dart`** — UMP then ATT. Keep these two function names: the evaluator's R6 check greps them.

```dart
import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../config/app_config.dart';

/// UMP consent. Returns only once the form (if one was required) has been DISMISSED.
///
/// Network steps (info update, form load) are bounded by [AppConfig.consentTimeout]; the form on
/// screen is never timed out — a timeout there lets the ATT alert stack on top of the open form.
/// Every completer completes once (`isCompleted` guard): success and failure callbacks can both
/// reach the same completion point, and without the guard ATT appears over the form.
Future<void> loadConsentForm() async {
  final info = ConsentInformation.instance;

  final updated = Completer<bool>();
  info.requestConsentInfoUpdate(
    ConsentRequestParameters(),
    () {
      if (!updated.isCompleted) updated.complete(true);
    },
    (FormError e) {
      debugPrint('UMP info update failed: ${e.message}');
      if (!updated.isCompleted) updated.complete(false);
    },
  );
  final ok = await updated.future.timeout(AppConfig.consentTimeout, onTimeout: () => false);
  if (!ok ||
      await info.getConsentStatus() != ConsentStatus.required ||
      !await info.isConsentFormAvailable()) {
    return;
  }

  final loaded = Completer<ConsentForm?>();
  ConsentForm.loadConsentForm(
    (form) {
      if (!loaded.isCompleted) loaded.complete(form);
    },
    (FormError e) {
      debugPrint('UMP form load failed: ${e.message}');
      if (!loaded.isCompleted) loaded.complete(null);
    },
  );
  final form = await loaded.future.timeout(AppConfig.consentTimeout, onTimeout: () => null);
  if (form == null) return;

  final dismissed = Completer<void>();
  form.show((FormError? e) {
    if (e != null) debugPrint('UMP form error: ${e.message}');
    if (!dismissed.isCompleted) dismissed.complete();
  });
  await dismissed.future; // untimed on purpose — see doc comment
}

const _resumedPollStep = Duration(milliseconds: 100);
const _resumedPollMax = 40; // ~4 s
const _attSettleDelay = Duration(milliseconds: 400);

/// Requests iOS App Tracking Transparency permission. No-op on Android.
///
/// App Store Guideline 2.1: the ATT system dialog ONLY presents while the app is active. On a
/// fresh launch the app may not be `resumed` yet, so requesting too early silently no-ops and the
/// prompt never appears ("NSUserTrackingUsageDescription present but the ATT alert never
/// appears"). So: wait until resumed, settle briefly, and only request when notDetermined.
Future<void> requestATT() async {
  if (!Platform.isIOS) return;
  try {
    for (var i = 0; i < _resumedPollMax; i++) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        break;
      }
      await Future<void>.delayed(_resumedPollStep);
    }
    if (await AppTrackingTransparency.trackingAuthorizationStatus ==
        TrackingStatus.notDetermined) {
      await Future<void>.delayed(_attSettleDelay);
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  } catch (e) {
    debugPrint('ATT request failed: $e');
  }
}
```

> **Do not reverse the order — UMP form first, then ATT.** The IDFA explainer message created in
> the AdMob console tells the user "tap Allow on the next screen". If ATT shows first, that
> explainer appears after the fact and makes no sense, and the opt-in rate drops — opt-in rate is
> IDFA coverage, which is eCPM.
>
> And remember the **two completion paths** (form dismissed / info update failed) land on the same
> completion point. The `isCompleted` guards make each completer finish exactly once; drop them
> (or time out the on-screen form) and ATT pops up on top of the still-open consent form — that
> exact bug shipped in production apps (found in a 51-app audit, 2026-08).

**`ads_service.dart`** — SDK init after consent, mobile-only guard, shared flags:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../config/app_config.dart';
import 'app_open_ad_manager.dart';
import 'consent.dart';
import 'interstitial_controller.dart';

/// Ads (and IAP) exist only on iOS/Android. `kIsWeb` first: `Platform` throws on web.
/// Not `defaultTargetPlatform` — that reports android under `flutter test` and would make
/// widget tests call the native plugin.
final bool isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);

/// `true` once consent is resolved and the SDK is initialized. Nothing loads before that.
class AdsService extends Notifier<bool> {
  /// True while a full-screen flow WE started is open (interstitial, rewarded, app-open, purchase
  /// sheet). Android pauses the activity for these, so returning is not a "resume from background".
  bool fullScreenOpen = false;

  @override
  bool build() => false;

  /// Called once, after the first frame (bootstrap). Order is load-bearing — see above.
  Future<void> start() async {
    if (!AppConfig.adsEnabled || !isMobile || state) return;
    await loadConsentForm(); // 1. UMP form first (dismissed before anything else shows)
    await requestATT(); //      2. then ATT — the AdMob IDFA explainer says "tap Allow next"
    if (!await ConsentInformation.instance.canRequestAds()) return;
    await MobileAds.instance.initialize(); // 3. only now may ads load
    state = true;
    // Preload full-screen formats; drop a line for a format the strategy marked "not used".
    ref.read(appOpenAdManagerProvider).load();
    ref.read(interstitialControllerProvider).preload();
  }
}

final adsServiceProvider = NotifierProvider<AdsService, bool>(AdsService.new);

/// Ad removal bought via IAP. Without IAP this stays false (Step 5 rewires it).
final adsRemovedProvider = Provider<bool>((ref) => false);

/// Banner / native / interstitial / app-open may load and show right now.
final showAdsProvider = Provider<bool>(
  (ref) => ref.watch(adsServiceProvider) && !ref.watch(adsRemovedProvider),
);

/// Settings shows "Privacy options" only when UMP says the user must be able to revisit consent.
/// autoDispose: re-read each time Settings opens (consent may have resolved since).
final privacyOptionsRequiredProvider = FutureProvider.autoDispose<bool>((ref) async {
  if (!AppConfig.adsEnabled || !isMobile) return false;
  return await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;
});
```

**`interstitial_controller.dart`** — pure, unit-tested cap + the controller:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../config/app_config.dart';
import 'ad_ids.dart';
import 'ads_service.dart';

/// Pure frequency cap (unit-tested): an interstitial may show only after [everyNActions]
/// completed tasks AND [minInterval] since the last one. Session start counts as "last shown",
/// so nothing shows within [minInterval] of launch.
class InterstitialCap {
  InterstitialCap({
    required this.minInterval,
    required this.everyNActions,
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock,
       _lastShown = clock();

  final Duration minInterval;
  final int everyNActions;
  final DateTime Function() _clock;
  DateTime _lastShown;
  int _actions = 0;

  /// Record one completed task; true when an interstitial may show now.
  bool registerAction() {
    _actions++;
    return _actions >= everyNActions && _clock().difference(_lastShown) >= minInterval;
  }

  void markShown() {
    _actions = 0;
    _lastShown = _clock();
  }
}

class InterstitialController {
  InterstitialController(this._ref);

  final Ref _ref;
  final _cap = InterstitialCap(
    minInterval: AppConfig.interstitialMinInterval,
    everyNActions: AppConfig.interstitialEveryNActions,
  );
  InterstitialAd? _ad;

  void preload() {
    if (_ad != null || !_ref.read(showAdsProvider)) return;
    InterstitialAd.load(
      adUnitId: AdIds.interstitialTaskDone,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _ad = ad,
        onAdFailedToLoad: (e) => debugPrint('Interstitial failed to load: $e'),
      ),
    );
  }

  /// Call ONLY at a natural break, right after a task completes (saved, finished, exported) and
  /// after the success feedback. Never on launch, on back press, or mid-task.
  void onTaskCompleted() {
    if (!_ref.read(showAdsProvider) || !_cap.registerAction()) return;
    final ad = _ad;
    // Not loaded: cap not consumed, so the next completed task retries.
    if (ad == null) return preload();
    _ad = null;
    final ads = _ref.read(adsServiceProvider.notifier)..fullScreenOpen = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        ads.fullScreenOpen = false;
        preload();
      },
      onAdFailedToShowFullScreenContent: (ad, e) {
        ad.dispose();
        ads.fullScreenOpen = false;
        preload();
      },
    );
    _cap.markShown();
    ad.show();
  }
}

final interstitialControllerProvider = Provider<InterstitialController>((ref) {
  final c = InterstitialController(ref);
  ref.onDispose(() => c._ad?.dispose());
  return c;
});
```

**`app_open_ad_manager.dart`** — wired to `AppLifecycleListener` with cooldown. `onboardingDoneProvider`
is the app's own onboarding-complete provider (use its real name/import; if the PRD has no
onboarding, drop that condition). **Update mode:** use the app's existing onboarding-complete signal
(flag/provider/prefs key) instead of the import below; if it has none, app-open ads require ≥ 1 prior
session — persist a session count (or first-launch flag) with the app's existing storage and check it
in place of `onboardingDoneProvider`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../features/onboarding/presentation/onboarding_notifier.dart'; // onboardingDoneProvider (generator 5c)
import '../../config/app_config.dart';
import 'ad_ids.dart';
import 'ads_service.dart';

// Google: a loaded app-open ad expires after 4 h.
const _adExpiry = Duration(hours: 4);

/// App-open ad on a REAL return from background — never on cold start, never before onboarding
/// completes, never after a system alert (ATT/UMP only go `inactive`, never `hidden`), never on
/// returning from our own full-screen ad or purchase sheet, and at most once per cooldown.
class AppOpenAdManager {
  AppOpenAdManager(this._ref) {
    _listener = AppLifecycleListener(onHide: _onHide, onResume: _onResume);
  }

  final Ref _ref;
  late final AppLifecycleListener _listener;
  AppOpenAd? _ad;
  DateTime? _loadedAt;
  DateTime? _hiddenAt;
  DateTime? _lastShownAt;
  bool _hiddenByOwnFlow = false;

  void load() {
    if (_ad != null || !_ref.read(showAdsProvider)) return;
    AppOpenAd.load(
      adUnitId: AdIds.appOpenResume,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loadedAt = DateTime.now();
        },
        onAdFailedToLoad: (e) => debugPrint('AppOpenAd failed to load: $e'),
      ),
    );
  }

  void _onHide() {
    _hiddenAt = DateTime.now();
    _hiddenByOwnFlow = _ref.read(adsServiceProvider.notifier).fullScreenOpen;
  }

  void _onResume() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    // No hide = a system alert (ATT/UMP only go inactive); own flow = our ad or purchase sheet.
    if (hiddenAt == null || _hiddenByOwnFlow) return;
    final now = DateTime.now();
    final last = _lastShownAt;
    if (now.difference(hiddenAt) < AppConfig.appOpenMinBackground ||
        (last != null && now.difference(last) < AppConfig.appOpenCooldown) ||
        !_ref.read(showAdsProvider) ||
        !_ref.read(onboardingDoneProvider)) {
      return;
    }
    final ad = _ad;
    final loadedAt = _loadedAt;
    if (ad == null || loadedAt == null || now.difference(loadedAt) >= _adExpiry) {
      ad?.dispose();
      _ad = null;
      return load();
    }
    _ad = null;
    final ads = _ref.read(adsServiceProvider.notifier)..fullScreenOpen = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        ads.fullScreenOpen = false;
        load();
      },
      onAdFailedToShowFullScreenContent: (ad, e) {
        ad.dispose();
        ads.fullScreenOpen = false;
        load();
      },
    );
    _lastShownAt = now;
    ad.show();
  }

  void dispose() {
    _listener.dispose();
    _ad?.dispose();
  }
}

final appOpenAdManagerProvider = Provider<AppOpenAdManager>((ref) {
  final m = AppOpenAdManager(ref);
  ref.onDispose(m.dispose);
  return m;
});
```

**`rewarded_ad_helper.dart`** — one instance per placement:

```dart
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Loads and shows a rewarded ad for one placement:
///   final _unlockAd = RewardedAdHelper(AdIds.rewardedUnlockExport);
/// Grant the reward ONLY in [onRewarded] (fires from `onUserEarnedReward`), never on dismiss.
class RewardedAdHelper {
  RewardedAdHelper(this.adUnitId);

  final String adUnitId;
  RewardedAd? _ad;

  Future<void> load() => RewardedAd.load(
    adUnitId: adUnitId,
    request: const AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      onAdLoaded: (ad) => _ad = ad,
      onAdFailedToLoad: (e) {
        debugPrint('RewardedAd failed to load: $e');
        _ad = null;
      },
    ),
  );

  bool get isLoaded => _ad != null;

  /// [onDismissed] fires when the ad closes (with or without reward) or is unavailable.
  /// [onFullScreen] toggles AdsService.fullScreenOpen so the return is not an app-open trigger.
  void show({
    required VoidCallback onRewarded,
    required void Function(bool open) onFullScreen,
    VoidCallback? onDismissed,
  }) {
    final ad = _ad;
    if (ad == null) {
      onDismissed?.call();
      return;
    }
    _ad = null;
    void closed(RewardedAd ad) {
      ad.dispose();
      onFullScreen(false);
      onDismissed?.call();
      load(); // ready for the next user-initiated tap
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: closed,
      onAdFailedToShowFullScreenContent: (ad, _) => closed(ad),
    );
    onFullScreen(true);
    ad.show(onUserEarnedReward: (_, _) => onRewarded());
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
```

**`banner_ad_slot.dart`** — renders nothing until loaded; vanishes the moment ads are removed:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_service.dart';

/// Anchored adaptive banner for the Scaffold `bottomNavigationBar` slot (inside SafeArea).
class BannerAdSlot extends ConsumerWidget {
  const BannerAdSlot({super.key, required this.adUnitId});

  final String adUnitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(showAdsProvider) ? _Banner(adUnitId) : const SizedBox.shrink();
}

class _Banner extends StatefulWidget {
  const _Banner(this.adUnitId);

  final String adUnitId;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    _load(MediaQuery.sizeOf(context).width.truncate());
  }

  Future<void> _load(int width) async {
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) return;
    _ad = BannerAd(
      adUnitId: widget.adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, e) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
```

**`native_ad_slot.dart`** — same two-widget shape as the banner (`NativeAdSlot` gates on
`showAdsProvider`, `_Native` owns the ad). Use Google's **native template** via
`nativeTemplateStyle` and **no `factoryId`** (a factory needs Kotlin/Swift registration and fails
without it). The template renders the required "Ad" attribution badge. Style it from the theme
(= design tokens); give `AdWidget` bounded constraints (a ListView row has unbounded height):

```dart
// Google's recommended bounds for the small native template.
const _minW = 320.0, _maxW = 400.0, _minH = 90.0, _maxH = 200.0;

// _NativeState.didChangeDependencies():
    if (_ad != null) return;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    _ad = NativeAd(
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: scheme.surfaceContainer,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: scheme.onPrimary,
          backgroundColor: scheme.primary,
          size: text.labelLarge?.fontSize,
        ),
        primaryTextStyle: NativeTemplateTextStyle(textColor: scheme.onSurface, size: text.titleMedium?.fontSize),
        secondaryTextStyle: NativeTemplateTextStyle(textColor: scheme.onSurfaceVariant, size: text.bodyMedium?.fontSize),
      ),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, e) => debugPrint('NativeAd failed to load: $e'),
      ),
    )..load();

// _NativeState.build(): SizedBox.shrink() until _loaded, then
    ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _minW, maxWidth: _maxW, minHeight: _minH, maxHeight: _maxH),
      child: AdWidget(ad: ad),
    );
// _NativeState.dispose(): _ad?.dispose(); — runs when the row scrolls off for good.
```

### 3.6 Bootstrap — consent after the first frame

`lib/app/bootstrap.dart` already creates an explicit `ProviderContainer` (generator 5a). **Do not
rebuild it** — keep its `overrides` and its `retry: (_, _) => null` (without it Riverpod 3 keeps a
failing provider in loading for ~40 s of backoff, so screens spin instead of showing ErrorView, R1).
Only append the post-frame start after the existing `runApp` — never start ads synchronously in
`main()`, which is what triggers the 2.1 "ATT alert never appears" rejection:

```dart
// existing (generator): final container = ProviderContainer(overrides: overrides, retry: (_, _) => null);
// existing (generator): runApp(UncontrolledProviderScope(container: container, child: const App()));
// Ads after the first frame: UMP → ATT → SDK init (AdsService.start). ATT no-ops before the
// app is active.
WidgetsBinding.instance.addPostFrameCallback(
  (_) => unawaited(container.read(adsServiceProvider.notifier).start()),
);
```

**Update mode, no `bootstrap.dart` / explicit container:** extend the app's existing startup instead —
after its `runApp`, or in its root widget's `initState`, add the same post-frame callback calling
`start()` through the app's own state access (`ref.read` in a `ConsumerStatefulWidget`, its
singleton/locator, …). Never start ads synchronously in `main()`.

### 3.7 Placements — exactly where the strategy table says

- **Banner**: `bottomNavigationBar: SafeArea(child: BannerAdSlot(adUnitId: AdIds.bannerList))`; with
  an existing `NavigationBar`, use `Column(mainAxisSize: MainAxisSize.min, children: [BannerAdSlot(...), NavigationBar(...)])`.
- **Native** (fixed cadence, `n = AppConfig.nativeAdInterval`):

  ```dart
  itemCount: items.length + items.length ~/ n,
  itemBuilder: (context, i) => (i + 1) % (n + 1) == 0
      ? NativeAdSlot(adUnitId: AdIds.nativeFeed)
      : ItemTile(item: items[i - i ~/ (n + 1)]),
  ```

- **Interstitial**: in the controller/notifier that completes the task, after the success feedback:
  `ref.read(interstitialControllerProvider).onTaskCompleted();` — nowhere else.
- **App-open**: nothing to place — `AdsService.start()` creates the manager.
- **Rewarded**: a button the user taps ("Watch an ad to unlock …", localized). Load once ads are
  ready (`ref.listen(adsServiceProvider, (_, ready) { if (ready) _unlockAd.load(); })`); disable the
  button with a localized "No ad available right now" when `!_unlockAd.isLoaded`. On tap:

  ```dart
  if (ref.read(adsRemovedProvider)) return grantUnlock(); // paid users never watch ads
  _unlockAd.show(
    onRewarded: grantUnlock, // persists unlock-until via the feature repository
    onFullScreen: (open) => ref.read(adsServiceProvider.notifier).fullScreenOpen = open,
  );
  ```

- **Settings → "Privacy options"** (shown only when UMP requires it):

  ```dart
  if (ref.watch(privacyOptionsRequiredProvider).value ?? false)
    ListTile(
      leading: const Icon(Icons.privacy_tip_outlined),
      title: Text(l10n.privacyOptions),
      onTap: () => ConsentForm.showPrivacyOptionsForm((e) {
        if (e != null) debugPrint('Privacy options: ${e.message}');
      }),
    ),
  ```

### 3.8 Strings

Every new user-visible string ("Privacy options", rewarded button + "No ad available right now",
and in Step 5 the paywall/restore copy) goes into **every** `lib/l10n/app_<locale>.arb` for
`config.locales`, then `flutter gen-l10n`. The "Ad" label comes from the native template.

### 3.9 Unit test (R11) — interstitial cap, no plugin calls

`test/core/services/interstitial_cap_test.dart`:

```dart
import 'package:<app_pkg>/core/services/ads/interstitial_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  InterstitialCap cap() => InterstitialCap(
    minInterval: const Duration(seconds: 90),
    everyNActions: 3,
    clock: () => now,
  );

  setUp(() => now = DateTime(2026));

  test('never within minInterval of session start, even after N actions', () {
    final c = cap();
    expect([c.registerAction(), c.registerAction(), c.registerAction()], [false, false, false]);
  });

  test('needs N actions even when the interval has elapsed', () {
    final c = cap();
    now = now.add(const Duration(minutes: 10));
    expect(c.registerAction(), isFalse);
    expect(c.registerAction(), isFalse);
    expect(c.registerAction(), isTrue);
  });

  test('markShown resets both the action count and the interval', () {
    final c = cap();
    now = now.add(const Duration(minutes: 10));
    for (var i = 0; i < 3; i++) {
      c.registerAction();
    }
    c.markShown();
    for (var i = 0; i < 3; i++) {
      expect(c.registerAction(), isFalse); // interval restarted
    }
    now = now.add(const Duration(seconds: 90));
    expect(c.registerAction(), isTrue);
  });
}
```

Run `flutter analyze` (0 issues) and `flutter test` (existing tests stay green — ad slots render
`SizedBox.shrink()` and `isMobile` is false under `flutter test`, so no test touches the plugin).
Commit: `feat(monetize): AdMob ads with UMP/ATT consent and frequency caps`.

---

## Step 4 — Ask about IAP / subscriptions

Skip when `monetization.iap` is already `true`/`false` (Re-entry). New mode, fully hands-off
(`auto_idea: true` **and** `auto_deploy: true`): do **not** ask — record `iap: false`, `products: []`.

**Update mode:** audit's `iap` is what ships today, not an answer — don't key on it. If the change
request adds no IAP, keep `iap`/`products` as recorded and go to Step 6. If it adds IAP, append only
the new products to the existing `products` (ask below only for what the change request leaves open),
set `iap: true`, and run Step 5 for the new ids.

Otherwise use `AskUserQuestion` (in `default_language`):

> "Ads are wired up. Add in-app purchases?"
> - **No IAP (ads only)**
> - **Remove-ads (non-consumable)** — one-time purchase that hides every ad format
> - **Premium subscription (also removes ads)** — monthly + yearly, unlocks premium features
> - **Both**

Record in `docs/harness/config.md` `monetization:` (protocol §1). Product ids are
`<bundle_id>.<name>` (valid on both stores: lowercase `[a-z0-9._]`, starts with a letter):

```yaml
  iap: true            # false for "No IAP (ads only)"
  products:
    - { id: "<bundle_id>.remove_ads",      type: non_consumable, entitlement: remove_ads, price_hint: "$2.99" }
    - { id: "<bundle_id>.premium_monthly", type: subscription,   entitlement: premium,    price_hint: "$2.99/month" }
    - { id: "<bundle_id>.premium_yearly",  type: subscription,   entitlement: premium,    price_hint: "$19.99/year" }
```

`price_hint` is only for creating the product in the consoles — the app always shows the
store-localized `ProductDetails.price`. No free trial unless the user asks for one; if one is
configured, the paywall must state its terms.

If `iap: false` → go to Step 6.

---

## Step 5 — IAP injection (only when `monetization.iap: true`)

Patterns: `docs/app-gotchas.md` → In-app purchases & subscriptions.

### 5.1 Dependencies + config

```bash
flutter pub add in_app_purchase url_launcher
```

Re-run the 3.3 minSdk check with `for p in in_app_purchase url_launcher` (raise, never lower).

Add to `AppConfig` (ids from `monetization.products`; keep only the chosen sets):

```dart
  // ── IAP ────────────────────────────────────────────────────────────────
  static const Set<String> removeAdsProductIds = {'<bundle_id>.remove_ads'};
  static const Set<String> premiumProductIds = {'<bundle_id>.premium_monthly', '<bundle_id>.premium_yearly'};
  /// Apple's standard EULA (iOS paywall "Terms of Use", App Store 3.1.2).
  static const String termsOfUseUrl = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
```

The Privacy Policy link uses `config.developer.privacy` (the app's existing privacy URL constant).

### 5.2 `lib/core/services/purchases/purchase_service.dart`

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../config/app_config.dart';
import '../ads/ads_service.dart';

/// What the user owns. Pure + unit-tested: derived only from store-reported product ids.
@immutable
class Entitlement {
  const Entitlement({this.isPremium = false, this.adsRemoved = false});

  factory Entitlement.fromOwned(
    Set<String> owned, {
    required Set<String> premiumIds,
    required Set<String> removeAdsIds,
  }) {
    final premium = owned.any(premiumIds.contains);
    return Entitlement(isPremium: premium, adsRemoved: premium || owned.any(removeAdsIds.contains));
  }

  final bool isPremium;
  final bool adsRemoved;
}

/// Entitlement is the source of truth, not the purchase event. On launch it restores what the
/// store says the user owns (StoreKit 2 current entitlements / Play owned purchases — both work
/// offline from the store cache), and `completePurchase`s every delivered transaction (Play
/// refunds purchases left unacknowledged for 3 days).
// Known limit: the owned set only grows within a session; a refund/expiry shows on next launch.
// Add server-side receipt validation when backend != local.
class PurchaseService extends Notifier<Entitlement> {
  final _owned = <String>{};

  @override
  Entitlement build() {
    if (!isMobile) return const Entitlement();
    final sub = InAppPurchase.instance.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => debugPrint('IAP stream error: $e'),
    );
    ref.onDispose(sub.cancel);
    unawaited(restore());
    return const Entitlement();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        _owned.add(p.productID);
      }
      if (p.status == PurchaseStatus.error) debugPrint('IAP error: ${p.error}');
      if (p.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(p);
      }
    }
    ref.read(adsServiceProvider.notifier).fullScreenOpen = false;
    state = Entitlement.fromOwned(
      _owned,
      premiumIds: AppConfig.premiumProductIds,
      removeAdsIds: AppConfig.removeAdsProductIds,
    );
  }

  /// Store-localized products for the paywall (never hard-code prices).
  Future<List<ProductDetails>> products() async {
    if (!isMobile || !await InAppPurchase.instance.isAvailable()) {
      return const [];
    }
    final res = await InAppPurchase.instance.queryProductDetails({
      ...AppConfig.removeAdsProductIds,
      ...AppConfig.premiumProductIds,
    });
    if (res.notFoundIDs.isNotEmpty) {
      debugPrint('IAP ids not found: ${res.notFoundIDs}');
    }
    return res.productDetails;
  }

  /// Non-consumables AND subscriptions both go through buyNonConsumable.
  Future<void> buy(ProductDetails product) async {
    ref.read(adsServiceProvider.notifier).fullScreenOpen = true;
    try {
      await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (e) {
      ref.read(adsServiceProvider.notifier).fullScreenOpen = false;
      rethrow;
    }
  }

  /// Settings + paywall "Restore Purchases". Returns false when the store is unreachable.
  Future<bool> restore() async {
    try {
      if (!await InAppPurchase.instance.isAvailable()) return false;
      await InAppPurchase.instance.restorePurchases();
      return true;
    } catch (e) {
      debugPrint('IAP restore failed: $e');
      return false;
    }
  }
}

final purchaseServiceProvider = NotifierProvider<PurchaseService, Entitlement>(PurchaseService.new);
```

### 5.3 Entitlement hides ads immediately

- In `ads_service.dart` rewire the one line (and import `../purchases/purchase_service.dart`):
  `final adsRemovedProvider = Provider<bool>((ref) => ref.watch(purchaseServiceProvider).adsRemoved);`
  — banner/native slots watch `showAdsProvider` and vanish at once; interstitial/app-open check it
  before every show; rewarded unlocks are granted without an ad. No restart needed.
- In `bootstrap.dart`, right after creating the container:
  `container.read(purchaseServiceProvider); // restore entitlement before any ad slot builds`
  (update mode without it: at the same startup spot as §3.6, before the first ad slot builds).
- Gate premium features on `ref.watch(purchaseServiceProvider).isPremium`.

### 5.4 Paywall — `lib/features/paywall/presentation/paywall_screen.dart` + `/paywall` route

A `ConsumerStatefulWidget` holding `late Future<List<ProductDetails>> _products =
ref.read(purchaseServiceProvider.notifier).products();`, with the app's R1 states (loading view;
empty/error view with Retry that re-queries) and **App Store 3.1.2 disclosures on the paywall itself**:

- each product: `p.title`, the store-localized `p.price`, and a localized terms line per product
  id stating the **period** ("{price} per month") and **trial terms** if a trial is configured —
  matching the console exactly; buy button → `purchaseServiceProvider.notifier.buy(p)`;
- for subscriptions, the **auto-renew notice** (localized): renews automatically unless cancelled
  at least 24 hours before the period ends; manage/cancel in the store account settings;
- tappable **Terms of Use** (iOS: `AppConfig.termsOfUseUrl`) and **Privacy Policy** links via
  `launchUrl`;
- a **Restore Purchases** button;
- close on a real purchase only — `Entitlement` has no `==`, so every purchase-stream event (cancel,
  restore, error) notifies; compare and guard:
  `ref.listen(purchaseServiceProvider, (prev, next) { final gained = (next.isPremium && !(prev?.isPremium ?? false)) || (next.adsRemoved && !(prev?.adsRemoved ?? false)); if (gained && context.canPop()) context.pop(); });`

No banner on the paywall. Entry points: the PRD's upsell spots + a Settings "Remove ads" /
"Go Premium" tile (hidden once entitled).

### 5.5 Settings — Restore Purchases

```dart
ListTile(
  leading: const Icon(Icons.restore),
  title: Text(l10n.restorePurchases),
  onTap: () async {
    final ok = await ref.read(purchaseServiceProvider.notifier).restore();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? l10n.restoreDone : l10n.restoreFailed)),
    );
  },
),
```

### 5.6 Unit test (R11) — entitlement logic, no plugin calls

`test/core/services/entitlement_test.dart`:

```dart
import 'package:<app_pkg>/core/services/purchases/purchase_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const premium = {'app.premium_monthly', 'app.premium_yearly'};
  const removeAds = {'app.remove_ads'};
  Entitlement of(Set<String> owned) =>
      Entitlement.fromOwned(owned, premiumIds: premium, removeAdsIds: removeAds);

  test('nothing owned → free with ads', () {
    final e = of({});
    expect((e.isPremium, e.adsRemoved), (false, false));
  });
  test('remove-ads only → ads removed, not premium', () {
    final e = of({'app.remove_ads'});
    expect((e.isPremium, e.adsRemoved), (false, true));
  });
  test('any premium subscription → premium and ads removed', () {
    final e = of({'app.premium_yearly'});
    expect((e.isPremium, e.adsRemoved), (true, true));
  });
  test('unknown product ids grant nothing', () {
    final e = of({'app.some_other_product'});
    expect((e.isPremium, e.adsRemoved), (false, false));
  });
}
```

Commit: `feat(monetize): in-app purchases with paywall and restore`.

### 5.7 IAP consoles (manual) → pause / resume

Skip if Re-entry shows these were already confirmed. Otherwise write `docs/harness/state.md`
(`status: paused`, `current_phase: monetize`, `next_role: monetize`, `pause_reason: manual_action`,
`updated_at`) and append the exact list as the pause row, then print the same list (in
`default_language`) and stop:

```
| <ISO-8601 UTC now> | pause | monetize | manual_action: IAP console — ASC: Paid Apps agreement + tax + banking active; create <ids> (localized name/description per locale, price, review screenshot of the paywall; subscriptions in group "<app_name> Premium" with group localization); add a Sandbox tester. Play: payments profile linked; add license testers. Play products are created after build's first upload |
```

The full list:

1. **App Store Connect** — Business → **Paid Apps agreement** Active, with tax + banking complete
   (without it every product comes back `notFoundIDs`, even in sandbox).
2. **App Store Connect** → app → Monetization: create the non-consumable `<bundle_id>.remove_ads`;
   create subscription group `<app_name> Premium` (+ group localization per locale) with
   `<bundle_id>.premium_monthly` / `.premium_yearly` (duration, price, trial if any). Each product
   needs a localized display name + description for every `config.locales` entry and a **review
   screenshot** (the paywall).
3. **App Store Connect** → Users and Access → **Sandbox** → add a sandbox tester.
4. **Play Console** → Settings → **Payments profile** linked (merchant account).
5. **Play Console** → Settings → **License testing** → add tester Google accounts.
6. **Play Console products** (in-app product `<bundle_id>.remove_ads`; each subscription
   `<bundle_id>.premium_monthly` / `.premium_yearly` with one auto-renewing base plan, activated) —
   Play only allows creating products after a bundle that uses Play Billing has been uploaded, so
   this happens **after** the build phase's first internal-track upload. Record it in the complete
   row below so it isn't lost.
7. At first submission the IAPs are attached to the app version and submitted **with the binary**
   (App Review needs them together) — the submit phase does that.

On resume, Re-entry sees this pause row (no later `complete | monetize` row) and continues to Step 6.

---

## Step 6 — Gate, Commit, State

Run from `<app>`; every check must pass before writing `state.md`:

```bash
flutter gen-l10n
flutter analyze                     # Hard Gate 1: 0 issues (update mode: no new issues, protocol §3)
flutter test                        # Hard Gate 2: all pass
# Consent order: UMP form → ATT → SDK init (the 0.22.0 fix), checked in the file that runs the
# sequence = the one calling MobileAds.instance.initialize (new mode: lib/core/services/ads/
# ads_service.dart; update mode: wherever the existing ad layer does it).
grep -rqE 'MobileAds\.instance\.initialize\(' lib/ || echo "FAIL: no MobileAds.instance.initialize() in lib/"
for f in $(grep -rlE 'MobileAds\.instance\.initialize\(' lib/); do
  awk -v f="$f" '/loadConsentForm\(\)|loadAndShowConsentFormIfRequired/{c=NR}
       /requestATT\(\)|requestTrackingAuthorization/{a=NR} /MobileAds\.instance\.initialize\(/{m=NR}
       END{ if(!(c&&a&&m&&c<a&&a<m)) print "FAIL: " f " order must be UMP consent form → ATT → MobileAds.initialize" }' "$f"
done
grep -rnE 'XXXX|<bundle_id>|<app_pkg>|<app_slug>' lib/ test/ && echo "FAIL: unsubstituted placeholder (Hard Gate 3)"
for k in GADApplicationIdentifier SKAdNetworkItems NSUserTrackingUsageDescription; do
  /usr/libexec/PlistBuddy -c "Print :$k" ios/Runner/Info.plist >/dev/null 2>&1 || echo "FAIL: Info.plist missing $k"
done
[ "$(grep -c com.google.android.gms.ads.APPLICATION_ID android/app/src/main/AndroidManifest.xml)" = 1 ] \
  || echo "FAIL: AdMob APPLICATION_ID meta-data missing or duplicated"
# + the ATT-per-locale loop from 3.2 (no MISSING lines)
# l10n: every ARB carries every key
python3 - <<'PY'
import glob, json
arbs = {f: {k for k in json.load(open(f)) if not k.startswith('@')} for f in glob.glob('lib/l10n/app_*.arb')}
every = set().union(*arbs.values())
for f, keys in arbs.items():
    if every - keys: print('FAIL: missing in', f, sorted(every - keys))
PY
```

If an existing ad layer (update mode) reaches UMP/ATT through its own wrapper names, add those names
to the awk patterns rather than skipping the check. Also eyeball that no ad code contains a literal
duration/count/color (all from `AppConfig` / the theme). Fix and re-run until clean. Commit any remaining changes with a Conventional Commit
(`feat(monetize): …` / `test(monetize): …`).

---

## Output — Write State and Logs

### Write config.md

Ensure the `monetization:` block is complete (protocol §1) and states **what the app actually ships**
after this phase — downstream checks read only these two keys: `admob_enabled: true` iff at least
one ad unit ships (update mode: kept existing units count), both app IDs, one `ad_units` entry per
shipped unit with `placement`, `iap: true|false` = whether IAP ships (update mode: existing products
count), and `products`.

### Write state.md

Atomically (protocol §7 `monetize → build`, rule 2 — `status: running` in the same write):

```yaml
status: running
current_phase: monetize
next_role: build
updated_at: "<ISO-8601 UTC now>"
```

Leave `current_round`, `created_at`, `resume_attempts`, `checkpoint`, and `pause_reason` unchanged
(`app-harness-resume` already cleared `pause_reason` if this phase had paused).

### Append to pipeline-log.md

```
| <ISO-8601 UTC now> | complete | monetize | ads: <used formats>; UMP→ATT→init wired; caps in app_config; iap=<true|false>[; products <ids>; PENDING after build upload: create Play products <ids>]; next: build |
```

---

## Error Handling

- `flutter analyze` / `flutter test` fail after injection → fix every issue before writing
  `state.md`. A deprecation info from a newer `google_mobile_ads` counts — migrate to the
  replacement API it names.
- The user cannot provide AdMob IDs or finish console steps (access issue, approval pending) →
  pause with `pause_reason: manual_action` plus a `pause` log row listing exactly what is needed.
- No ads during testing with real IDs → expected (debug uses test units). "Publisher data not found"
  in release → bundle id / publisher prefix mismatch (`docs/app-gotchas.md` → Store rejections);
  new AdMob apps/units can take hours to serve.
- Products come back in `notFoundIDs` → Paid Apps agreement not active, ids differ between
  `AppConfig` and the console, or (Play) products not yet created / tester not on the license list.
  The paywall shows its error state with Retry — never a blank screen.
- A package fails to resolve → `flutter pub outdated`, check the package page on pub.dev, and pin
  the newest version compatible with the project's Flutter SDK.
