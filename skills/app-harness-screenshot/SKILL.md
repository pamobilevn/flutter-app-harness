---
name: app-harness-screenshot
description: Phase 9 — capture store screenshots of the PRD's primary flows with seeded demo data in every configured locale via integration_test (screenshot mode — no ads, consent, or permission prompts; iPad 13" too when universal), write per-locale ASO metadata, and upload screenshots + Play graphics via fastlane.
argument-hint: ""
allowed-tools: [Read, Write, Edit, Bash, Glob]
---

# app-harness-screenshot

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

Phase 9 of the flutter-app-harness pipeline. Captures store screenshots in every locale of
`config.locales` by driving the app's `integration_test` harness through the PRD's primary flows with
seeded, realistic demo data (screenshot mode: no ads, no ATT/UMP consent, no permission prompts), fills
ASO metadata (keywords, localized titles, descriptions), and uploads the screenshots and Play listing
graphics via fastlane.

All file schemas (`config.md`, `state.md`, `pipeline-log.md`) and the phase transition table are
defined in `docs/harness-protocol.md` — that document is the single source of truth (§1 for
`config.md`, `locales`, and `device_family`; §2 for `state.md`; §6 for log schemas; §7 for the
`screenshot → submit` transition and the `status: running` rule). Do not redefine schemas here.
Store-asset pitfalls are in `docs/app-gotchas.md` (Store screenshots + Store rejections).

**Prerequisites:** The app has been built and uploaded (Phase 8 `app-harness-build`), so the
generated `ios/fastlane/Fastfile` and `android/fastlane/Fastfile` exist. `flutter drive`, Xcode
simulators, an Android emulator, and fastlane are installed on the developer's macOS machine.

---

## Input — Read Inputs

Before any action, load:

1. `docs/harness/config.md` — extract `mode`, `project_path`, `app_slug`, `bundle_id`, `app_name`,
   `default_language`, `locales`, `device_family`, `orientation`, `app_category`, `play_category`,
   `monetization.admob_enabled` (per protocol §1).
2. `docs/harness/state.md` — confirm `next_role: screenshot` (per protocol §2).
3. The PRD (`docs/harness/plans/*-prd.md`, newest) — its primary user flows decide the screen list;
   in `mode: update` the delta PRD's NEW / CHANGE items decide whether to recapture at all.

Derive the app root `<app>`: `project_path` when `mode: update`, else `<projects-dir>/<app_slug>/`
(or `.` when cwd is already the app project, i.e. `./pubspec.yaml` exists).

`<plugin-templates>` = this plugin's `templates/` directory: `${CLAUDE_PLUGIN_ROOT}/templates` when
that env var is set, else `<skill base directory>/../../templates` (the skill base directory is shown
when the skill loads). Never a bare relative `templates/...` path — it resolves against the app.

### Store locale codes

`config.locales` holds ISO 639-1 codes; each store names its folders differently. Map every
configured locale once and reuse the mapping in every command below:

| `config.locales` | App Store folder (`ios/fastlane/...`) | Play folder (`android/fastlane/metadata/android/...`) |
|---|---|---|
| `en` | `en-US` | `en-US` |
| `ko` | `ko` | `ko-KR` |
| `ja` | `ja` | `ja-JP` |
| `vi` | `vi` | `vi` |
| `zh` (Simplified) | `zh-Hans` | `zh-CN` |
| `es` | `es-ES` | `es-ES` |
| `fr` | `fr-FR` | `fr-FR` |
| `de` | `de-DE` | `de-DE` |
| `pt` | `pt-BR` | `pt-BR` |
| `it` | `it` | `it-IT` |
| `ru` | `ru` | `ru-RU` |
| `id` | `id` | `id` |
| `th` | `th` | `th` |
| `tr` | `tr` | `tr-TR` |

App Store codes are fastlane's `FastlaneCore::Languages::ALL_LANGUAGES`; Play validates its codes on
upload (an unknown folder fails the lane) — for a locale not listed, use the code Play Console shows
under Store listing → Manage translations.

### `mode: update` — recapture only on visible change

If no NEW / CHANGE item in the delta PRD changes what a user sees on a screen that is (or should be) in
the store screenshots, skip this phase: append
`| <ISO-8601 UTC now> | complete | screenshot | update mode: no visible UI change — store screenshots kept; next: submit |`
to `pipeline-log.md`, write the Output state below, and stop. Otherwise run all phases, and keep the
live listing text (Phase 3) unless the change request touched it.

---

## Phase 1 — Harness Setup

### Screenshot mode in the app

`--dart-define=screenshots=true` must put the app in screenshot mode (`docs/app-gotchas.md` → Store
screenshots): every ad unit (banner, native, interstitial, app-open, rewarded) suppressed, no UMP
consent form, no ATT prompt, no runtime-permission request, no rating prompt. The **generator**
declares the flag — `AppConfig.screenshotMode` in `lib/core/config/app_config.dart` (`mode: update`
with existing ads: a `screenshots` dart-define in the project's own config spot, gating its existing
ad/consent init) — so it exists whether or not monetize ran. For an ads app
(`monetization.admob_enabled: true`) the ad layer (UMP → ATT → SDK init included) is gated on it
(`AppConfig.adsEnabled = !screenshotMode`). Verify before capturing:

```bash
cd <app>
grep -rnE "fromEnvironment\(['\"]screenshots" lib/      # the flag, declared once
grep -rlnE "screenshotMode|adsEnabled" lib/             # permission + rating code; ads + consent/ATT when admob_enabled
```

What must exist:

- `mode: new` — the flag, always (the generator declares it); plus the ad/consent gate when
  `monetization.admob_enabled: true`.
- `mode: update` with `monetization.admob_enabled: true` — the flag and the gate on the existing
  ad/consent init (it may use the project's own flag name).
- `mode: update` without ads — no flag is required (the generator adds none); capture, then check the
  frames for permission and rating prompts.

**A missing required flag or gate is a blocking finding, not something to patch here** — the
generator (or monetize, for the ad gate) was supposed to add it, and the build is already uploaded, so editing app code now would leave the uploaded binary out of sync with the
repo and skip QA. Do not edit the app: pause per **Error Handling and Pausing** with
`pause_reason: error` and the row `error: screenshots flag/gate missing in <file> — generator must add it (D5), then rebuild`.

### Copy the integration_test template

Keep an already-adapted copy (re-run, or a previous `mode: update` run); copy only when absent:

```bash
mkdir -p <app>/integration_test
[ -e <app>/integration_test/screenshots_test.dart ] || \
  cp <plugin-templates>/screenshots_test.dart.template <app>/integration_test/screenshots_test.dart
```

An existing copy that still calls `app.main()` must be rebooted the template's way (next section).

### Adapt the TODO markers

Open `<app>/integration_test/screenshots_test.dart` and replace every `// TODO(generator):` block
with the app's real driving code:

- Replace `<__APP_SLUG__>` in every import with the package name (`name:` in `pubspec.yaml` — the
  `app_slug` with hyphens converted to underscores).
- **Boot the way `<plugin-templates>/integration_test.dart.template` does**: a
  `ProviderContainer` with `storageOverrides()`, pumped as `UncontrolledProviderScope` around `App`.
  Never call `app.main()` / `bootstrap()` — they replace `FlutterError.onError` and the test binding
  fails the test at teardown. A `mode: update` app without `storageOverrides()` / `App`: replicate the
  storage/provider setup its own `main()` does before `runApp`, inline, minus error handlers and ad
  init, and pump its root widget.
- **Seed demo data**: clear storage, then write realistic records in the capture locale through the
  app's repositories (same code path as a user) and mark onboarding done. Lived-in, not lorem ipsum:
  6–10 records with varied names, dates, and states, enough that lists, detail, and stats screens look
  full. The seed lives in `integration_test/` (or in the app's own screenshot-mode seed, if it has
  one), never as widget literals.
- **Force the locale** to the `SCREENSHOT_LOCALE` dart-define so captures are language-deterministic
  regardless of the simulator's system language.
- **Screen list = the PRD's primary flows**, in the order a new user meets them, zero-padded two-digit
  prefixes, 5 shots (fits App Store 1–10 and Play 2–8):
  `01_home` (seeded main list / dashboard), `02_<key_feature>` (primary flow #1 in use),
  `03_<detail_or_result>` (the outcome — detail, stats, summary), `04_<secondary>` (a secondary flow),
  `05_settings` (or the home screen in dark theme, switched through the Settings UI). Show the app in
  use — no splash, login, onboarding, or empty states (App Store 2.3.3).
- Navigate by route path, Key, or icon — never by translated text (the same test runs in every
  locale). Delete the `go` helper and its import if the app does not use go_router.

Then `flutter analyze integration_test` must report no issues.

### Test driver

Ensure `<app>/test_driver/integration_test.dart` exists. **`integrationDriver()` has no default
screenshot writer** — its native path is guarded by `onScreenshot != null`, so without the callback
below every `takeScreenshot` byte is silently discarded and no file is ever written. Pass one:

```dart
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (
    String name,
    List<int> bytes, [
    Map<String, Object?>? args,
  ]) async {
    // The driver runs on the host, so Platform.environment works here (inside
    // the test it would not — that side uses String.fromEnvironment).
    final dir = Platform.environment['SCREENSHOT_DIR'] ?? 'build/screenshots';
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
```

---

## Phase 2 — Capture

### Device sizes

| Store set | Required device | When |
|---|---|---|
| App Store iPhone | 6.9" iPhone simulator (e.g. iPhone 17 Pro Max, 1320 × 2868; 1290 × 2796 also accepted) | always |
| App Store iPad | 13" iPad simulator (e.g. iPad Pro 13-inch (M4), 2064 × 2752) | `device_family: universal` — required then; none for `phone` |
| Play phone | 16:9 phone emulator (e.g. Pixel 2 AVD, 1080 × 1920) | always — Play caps the long side at 2× the short side, which a 20:9 phone (1080 × 2400) exceeds |

Run `flutter devices` to get the device IDs. Orientation follows `config.orientation` (landscape apps
capture landscape). Play tablet screenshots are optional — skip them.

### Locale loop — every configured locale, one run at a time

`SCREENSHOT_DIR` is read by the `onScreenshot` callback above — each device × locale gets its own
staging directory so runs can't overwrite each other. Run captures **sequentially** (never two
`flutter drive` builds at once — parallel builds OOM a 16 GB machine; `docs/app-gotchas.md` →
Build / platform). One `<config>:<App Store>:<Play>` entry per configured locale (table above):

```bash
cd <app>
IPHONE_ID="<6.9-inch iPhone simulator id>"
IPAD_ID="<13-inch iPad simulator id>"        # device_family: universal only
ANDROID_ID="<16:9 phone emulator id>"

capture() { # device-id, staging-dir, config-locale
  SCREENSHOT_DIR="$2" flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/screenshots_test.dart \
    -d "$1" \
    --dart-define=SCREENSHOT_LOCALE="$3" \
    --dart-define=screenshots=true
}

for entry in en:en-US:en-US ko:ko:ko-KR; do   # ← replace with config.locales
  IFS=: read -r loc ios play <<< "$entry"
  capture "$IPHONE_ID"  "build/screenshots/ios/$ios"      "$loc"
  if [ "<device_family>" = universal ]; then
    capture "$IPAD_ID"  "build/screenshots/ipad/$ios"     "$loc"
  fi
  capture "$ANDROID_ID" "build/screenshots/android/$play" "$loc"
done
```

### Screenshot output directory

The PNGs land in `$SCREENSHOT_DIR`, named after the `takeScreenshot` argument — e.g.
`build/screenshots/ios/en-US/01_home.png`. Nothing is written to the app root. Phase 4 copies these
into the fastlane-expected paths.

After each run, confirm the files actually exist before moving on — an empty directory means the
`onScreenshot` callback is missing or the capture failed:

```bash
ls -1 build/screenshots/ios/en-US/*.png | wc -l   # must match the number of shot() calls
```

Open a few of them and look: seeded data visible, correct language, no ad, no dialog, no debug banner.

### No alpha channel

**No alpha channel** (App Store rejection): store screenshots — and the iOS app icon — must be
flattened to opaque RGB. Check with `sips -g hasAlpha <file>` (must report `hasAlpha: no`).

**`sips -s format png` does NOT strip alpha** — it re-encodes and keeps the channel, so it silently
leaves the rejection in place. Use one of these instead:

```bash
# Preferred — lossless, needs ImageMagick
magick in.png -background white -alpha remove -alpha off out.png

# macOS built-ins only — round-trip through JPEG (lossy, fine for screenshots)
sips -s format jpeg in.png --out tmp.jpg && sips -s format png tmp.jpg --out out.png

sips -g hasAlpha out.png   # verify: hasAlpha: no
```

Flatten every staged PNG, then confirm none is left with alpha:

```bash
for f in build/screenshots/*/*/*.png; do
  sips -g hasAlpha "$f" | grep -q 'hasAlpha: yes' && magick "$f" -background white -alpha remove -alpha off "$f"
done
sips -g hasAlpha build/screenshots/*/*/*.png | grep -c 'hasAlpha: yes'   # must print 0
```

See `docs/app-gotchas.md` → Store rejections.

---

## Phase 3 — ASO Metadata

Write the metadata for **every** locale in `config.locales`, in that locale's language (the
`default_language` copy from the PRD is the source; translate it, don't machine-mangle keywords). In
`mode: update`, keep the live listing text unless the change request touched it — edit the project's
existing metadata files, and if it has none, write none (fastlane only uploads files that exist, so the
live listing stays as is); `app-harness-submit` writes the release notes.

Rules from `docs/app-gotchas.md` → Store rejections: ASCII-safe description (no decorative Unicode),
no other-platform mentions (2.3.10), store-specific copy.

### iOS keywords.txt

Write `<app>/ios/fastlane/metadata/<App Store locale>/keywords.txt` for each locale. The field holds
at most **100 characters** including commas; aim for **95–100** so none of it is wasted. Comma-separated,
no spaces after commas, no words already in the app name or subtitle (they are indexed anyway), no
competitor brand names.

Example EN keywords for a habit tracker named "Streakly", subtitle "Habit Tracker & Daily Goals"
(96 characters):
```
routine,streak,reminder,planner,checklist,todo,focus,self care,journal,mood,productivity,morning
```

Example KO keywords for the same app (97 characters):
```
루틴,습관만들기,목표,체크리스트,할일,플래너,리마인더,자기관리,미라클모닝,습관추적,데일리,갓생,동기부여,생산성,기록,다이어리,연속기록,알림,건강습관,아침루틴,작심삼일,자기계발
```

Verify the length before writing. **Count characters, not bytes** — `wc -c` counts bytes, and one
Hangul syllable is 3 bytes in UTF-8 (Vietnamese and Japanese are multi-byte too), so the KO example
above measures 249 with `wc -c`. Using `wc -c` makes a valid string look 2.5× over the limit and
costs you most of the field:

```bash
# a here-string (<<<) would append a newline and inflate the count by 1 — use printf '%s'
printf '%s' "your,keyword,string" | python3 -c 'import sys;print(len(sys.stdin.read()))'

# check what was actually written (trailing newline stripped)
python3 -c 'import sys;print(len(open(sys.argv[1],encoding="utf-8").read().strip()))' \
  <app>/ios/fastlane/metadata/ko/keywords.txt
```

Every locale must report **95–100**.

### iOS localized title and description

Write under `<app>/ios/fastlane/metadata/<App Store locale>/`:

- `name.txt` — localized app name (≤ 30 chars).
- `subtitle.txt` — localized subtitle (≤ 30 chars) — the app's core benefit, not a slogan.
- `description.txt` — full App Store description (≤ 4000 chars): first 2–3 lines carry the value
  (they show above "more"), then features matching the screenshots, then privacy/offline notes.
- `promotional_text.txt` — optional promotional text (≤ 170 chars).
- `release_notes.txt` — what's new in this version.

### Android localized title and description

Write under `<app>/android/fastlane/metadata/android/<Play locale>/`:

- `title.txt` — localized app title (≤ 30 chars).
- `short_description.txt` — localized short description (≤ 80 chars).
- `full_description.txt` — localized full description (≤ 4000 chars).
- `changelogs/<version-code>.txt` — what's new (≤ 500 chars; `<version-code>` = the `+N` in
  `pubspec.yaml`).

### Length check — all fields, all locales

```bash
cd <app>
python3 - <<'EOF'
import glob, os
LIMIT = {'name.txt': 30, 'subtitle.txt': 30, 'keywords.txt': 100, 'promotional_text.txt': 170,
         'description.txt': 4000, 'release_notes.txt': 4000, 'title.txt': 30,
         'short_description.txt': 80, 'full_description.txt': 4000}
files = glob.glob('ios/fastlane/metadata/*/*.txt') + glob.glob('android/fastlane/metadata/android/*/*.txt')
bad = 0
for f in files + glob.glob('android/fastlane/metadata/android/*/changelogs/*.txt'):
    n = len(open(f, encoding='utf-8').read().strip())
    lim = 500 if '/changelogs/' in f else LIMIT.get(os.path.basename(f))
    if lim and n > lim:
        bad += 1; print(f'OVER {n} > {lim}: {f}')
print('length check:', 'FAIL' if bad else 'OK')
EOF
```

---

## Phase 4 — Upload

### Screenshot file placement

After capture, place PNG files in the fastlane-expected directory layout before running the
upload lanes:

**iOS** — one subdirectory per App Store locale. iPhone and iPad (universal only) shots share it;
`deliver` sorts them into separate sets by resolution. iPad files get an `ipad_` prefix so the names
never collide:

```
<app>/ios/fastlane/screenshots/<App Store locale>/01_home.png … ipad_01_home.png …
```

**Android** — locale-scoped phone screenshot directories:

```
<app>/android/fastlane/metadata/android/<Play locale>/images/phoneScreenshots/
```

Create the directories, and **empty them before copying** — `deliver` and `supply` upload every
PNG they find, so a leftover file from an earlier run or another locale silently ships:

```bash
cd <app>
for entry in en:en-US:en-US ko:ko:ko-KR; do   # ← same list as Phase 2
  IFS=: read -r loc ios play <<< "$entry"
  dst="ios/fastlane/screenshots/$ios"
  mkdir -p "$dst"
  find "$dst" -name '*.png' -delete          # drop leftovers from an earlier run
  cp "build/screenshots/ios/$ios"/*.png "$dst"/
  if [ -d "build/screenshots/ipad/$ios" ]; then
    for f in "build/screenshots/ipad/$ios"/*.png; do cp "$f" "$dst/ipad_$(basename "$f")"; done
  fi
  adst="android/fastlane/metadata/android/$play/images/phoneScreenshots"
  mkdir -p "$adst"
  find "$adst" -name '*.png' -delete
  cp "build/screenshots/android/$play"/*.png "$adst"/
  echo "$ios: $(ls -1 "$dst"/*.png | wc -l) App Store file(s) | $play: $(ls -1 "$adst"/*.png | wc -l) Play file(s)"
done
```

Every locale must report the **same** non-zero counts (App Store = iPhone shots, plus the same number
of iPad shots when universal). A zero means capture produced nothing (see Phase 2's `onScreenshot`
note).

### iOS — fastlane screenshots lane

Run from the iOS fastlane directory to upload the locale screenshot directories to App Store
Connect. The screenshot lanes need an **editable App Store version** — a new app has its initial one,
but a live app (`mode: update`) has none until it is created — so first make the edit version match
the build (`deliver` creates or renames it and only sends the metadata files that exist):

```bash
cd <app>/ios
VERSION=$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' ../pubspec.yaml)
DELIVER_APP_VERSION="$VERSION" fastlane metadata
fastlane screenshots
```

The lane calls `upload_to_app_store` with `skip_binary_upload: true`, then runs a **duplicate
cleanup and count check** and fails if App Store Connect does not end up with exactly the local
number of screenshots per locale and display type (iPhone and iPad sets are counted separately). A
successful run ends with `Screenshots verified — no duplicates`.

**Do not remove that cleanup step.** `deliver` decides "is this screenshot already uploaded?" by
comparing App Store Connect's `sourceFileChecksum` against the local file's MD5. When that
comparison does not match, its post-upload verification concludes every local file is missing and
retries — and the retry keeps the already-uploaded screenshots while re-uploading the whole set, so
each image lands **twice**. Once a set holds 10 images its own "nothing missing" guard passes, so
`deliver` prints *Successfully uploaded all screenshots* and exits 0 with a doubled set.
`overwrite_screenshots: true` does not prevent this — it only clears the sets before the first
round.

If an app already carries duplicates from an earlier upload, clean it without re-uploading:

```bash
cd <app>/ios
fastlane screenshots_prune   # deletes duplicates + broken assets, reports per-set counts
```

Confirm the result against the live API — the per-locale counts must equal the local PNG counts
(iPhone + iPad):

```bash
fastlane verify   # VER[en-US] … screenshots=N for every App Store locale
```

Ensure the generated `<app>/ios/fastlane/Fastfile` contains both the `screenshots` and
`screenshots_prune` lanes.

### Android — Play listing graphics (required)

Google Play requires a **hi-res icon (512×512)** and a **feature graphic (1024×500)** in the listing,
in addition to phone screenshots — without them the listing cannot be published. They are produced
by `tool/gen_icon.dart` (generator branding step) at `assets/store/play_icon.png` +
`assets/store/feature_graphic.png`, opaque. Place them per Play locale where `supply` expects them:

```bash
for play in en-US ko-KR; do   # ← every Play locale
  d=<app>/android/fastlane/metadata/android/$play/images
  mkdir -p "$d"
  cp <app>/assets/store/play_icon.png       "$d/icon.png"            # 512×512 hi-res icon
  cp <app>/assets/store/feature_graphic.png "$d/featureGraphic.png"  # 1024×500 feature graphic
done
sips -g pixelWidth -g pixelHeight -g hasAlpha <app>/android/fastlane/metadata/android/*/images/{icon,featureGraphic}.png
```

(In `mode: update`, skip this unless the branding changed — `supply` leaves live graphics alone when
the files are absent. App Store needs no feature graphic — its icon is embedded in the build; only
screenshots upload via the iOS `screenshots` lane.)

### Android — fastlane images lane

Run from the Android fastlane directory to upload screenshots, the hi-res icon, and the feature
graphic to Google Play:

```bash
cd <app>/android
fastlane images
```

The `images` lane calls `upload_to_play_store` with `skip_upload_apk: true` and
`skip_upload_aab: true` so only metadata and images are pushed (no track needed for listing
graphics). Ensure the generated `<app>/android/fastlane/Fastfile` contains an `images` lane.

### Store assets archive

Copy the final PNGs into the app's `store-assets/` directory for reference:

```bash
cd <app>
mkdir -p store-assets/ios store-assets/android
cp -R ios/fastlane/screenshots/. store-assets/ios/
for d in android/fastlane/metadata/android/*/images; do
  play=$(basename "$(dirname "$d")")
  mkdir -p "store-assets/android/$play"
  cp -R "$d"/. "store-assets/android/$play/"
done
```

---

## Output — Write Handoff and State

### state.md

Write `docs/harness/state.md` atomically (per protocol §7 `screenshot → submit` transition and
§7 rule 2 — set `status: running` in the same write as `next_role`):

```yaml
status: running
current_phase: screenshot
next_role: submit
updated_at: "<ISO-8601 UTC now>"
```

Leave `current_round`, `created_at`, `resume_attempts`, and `pause_reason` unchanged.

### pipeline-log.md

Append one row to `docs/harness/pipeline-log.md` (per protocol §6):

```
| <ISO-8601 UTC now> | complete | screenshot | <locales> screenshots captured (iPhone[+iPad]+Android) and uploaded; ASO metadata written; next: submit |
```

---

## Error Handling and Pausing

If screenshot capture or upload fails and cannot be resolved immediately (or Phase 1 finds the
screenshot flag/gate missing — `pause_reason: error`), write `docs/harness/state.md` with:

```yaml
status: paused
current_phase: screenshot
next_role: screenshot
pause_reason: manual_action   # error for a missing screenshot flag/gate (Phase 1)
updated_at: "<ISO-8601 UTC now>"
```

and append the pause row to `docs/harness/pipeline-log.md` (protocol §7 rule 12):

```
| <ISO-8601 UTC now> | pause | screenshot | manual_action: <what the user must do> |
```

(`error: <reason>` instead when `pause_reason: error`.) Then explain (in `default_language`) what
manual action is required. The harness resumes when the user runs `/app-harness --resume` (or
`/app-harness-resume`), per protocol §7 pause/resume rules.
