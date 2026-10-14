---
name: app-harness-build
description: Phase 8 — bootstrap signing credentials (iOS API key, Android upload keystore + key.properties + release signingConfig), generate fastlane config from the plugin templates with the app's store category, bump the build number, and build + upload a signed IPA (TestFlight) and AAB (Play internal track), one platform at a time.
argument-hint: ""
allowed-tools: [Read, Write, Edit, Bash, Glob, AskUserQuestion]
---

# app-harness-build

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

Phase 8 of the flutter-app-harness pipeline. Bootstraps signing credentials into the generated
app, generates fastlane config from `<plugin-templates>/fastlane/`, bumps the build number, then
builds and uploads a signed IPA to TestFlight and a signed AAB to the Play Store internal track.

All file schemas (`config.md`, `state.md`, `pipeline-log.md`) and the phase transition table are
defined in `docs/harness-protocol.md` — that document is the single source of truth (§1 for
`config.md` including `credentials_dir`, `ios`, `android`, `app_category`, `play_category`, and
`mode`; §2 for `state.md`; §6 for log schemas; §7 for the `build → screenshot` transition and the
`status: running` rule). Do not redefine schemas here. Platform pitfalls are in
`docs/app-gotchas.md` (Build / platform + Store rejections) — cite it, don't restate it.

**Prerequisites:** An App Store Connect app record and a Google Play Console app must already exist
(created once manually; in `mode: update` they already do). The upload lanes fail without them.
Fastlane and Ruby must be installed on the developer's macOS machine (Xcode and the flutter CLI are
assumed present).

---

## Input — Read Inputs

Before any action, load:

1. `docs/harness/config.md` — extract `mode`, `project_path`, `app_slug`, `bundle_id`,
   `bundle_id_android` (update mode; blank = same as `bundle_id`), `app_name`,
   `app_category`, `play_category`, `credentials_dir`, `ios.team_id`, `ios.asc_key_id`,
   `ios.asc_issuer_id`, `ios.asc_private_key_path`, `android.keystore_path`, `android.key_alias`,
   `monetization.admob_enabled` (per protocol §1).
2. `docs/harness/state.md` — confirm `next_role: build` (per protocol §2).

Derive the app root `<app>`: `project_path` when `mode: update`, else `<projects-dir>/<app_slug>/`
(or `.` when cwd is already the app project, i.e. `./pubspec.yaml` exists).

`<plugin-templates>` = this plugin's `templates/` directory: `${CLAUDE_PLUGIN_ROOT}/templates` when
that env var is set, else `<skill base directory>/../../templates` (the skill base directory is shown
when the skill loads). Never a bare relative `templates/...` path — it resolves against the app and,
with `>`, truncates the target file before failing. `ls <plugin-templates>/fastlane` must list the
four `*-Appfile.template` / `*-Fastfile.template` files before anything below runs.

If any `ios.*` / `android.*` value is still a `<placeholder>` or blank (the user deferred it at
bootstrap), ask for it with `AskUserQuestion` and write it back to `config.md` before continuing.

---

## Phase 1 — Credential Bootstrap

Copy signing credentials from the shared `credentials_dir` (per protocol §1 — skills must not
hard-code credential paths; always read them from `config.md`) into the app's platform directories.

### Gitignore guard (before copying anything)

The secrets copied below must never be committable. A `mode: update` project never received the
template `.gitignore` excludes, so append them when missing, then prove every secret path is ignored
**before** it exists in the worktree (`git check-ignore` works on paths that do not exist yet):

```bash
cd <app>
grep -q play-store-key.json .gitignore 2>/dev/null || { echo; cat <plugin-templates>/gitignore.template; } >> .gitignore
for f in ios/fastlane/AuthKey_<asc_key_id>.p8 android/fastlane/play-store-key.json android/key.properties; do
  git check-ignore -q "$f" || { echo "NOT IGNORED: $f"; exit 1; }
done
```

`NOT IGNORED` (also printed for a path that is already **tracked** — `git rm --cached` it — or when
`<app>` is not a git repo) → copy nothing; pause per **Error Handling and Pausing** with
`pause_reason: error` and the row
`error: <path> not gitignored — fix .gitignore before credentials are copied`.

### iOS credentials

```bash
mkdir -p <app>/ios/fastlane/certs
cp "<ios.asc_private_key_path>" <app>/ios/fastlane/AuthKey_<asc_key_id>.p8
```

The Fastfile loads `AuthKey_<asc_key_id>.p8` from its own directory, so the copied name must encode
`ios.asc_key_id` exactly. The `certs/` directory holds the distribution certificate and provisioning
profile (written by `fastlane certs`).

### Android credentials

```bash
mkdir -p <app>/android/fastlane
cp <credentials_dir>/play-store-key.json <app>/android/fastlane/
```

### Android upload keystore

The keystore lives at `android.keystore_path` (outside the repo, so it survives the app folder).

- **It exists → reuse it.** Never generate a new key for an app that is already on Play (always the
  case in `mode: update`): a different upload key cannot update the existing listing.
- **It is missing (`mode: new` only) → generate it**, with a random password and the alias from
  `android.key_alias`, and save the password next to it so later builds and apps can reuse it:

  ```bash
  KS="<android.keystore_path>"; ALIAS="<android.key_alias>"
  KS_PASS="$(openssl rand -base64 24 | tr -d '/+=')"
  keytool -genkey -v -keystore "$KS" -alias "$ALIAS" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$KS_PASS" -keypass "$KS_PASS" \
    -dname "CN=<developer.first_name> <developer.last_name>, O=<developer.company>"
  printf 'storePassword=%s\nkeyPassword=%s\nkeyAlias=%s\nstoreFile=%s\n' \
    "$KS_PASS" "$KS_PASS" "$ALIAS" "$KS" > <credentials_dir>/key.properties
  ```

  Tell the user to back up the keystore + `<credentials_dir>/key.properties` — losing the upload key
  means a Play Console upload-key reset.

**Keystore password source**, in order: an existing `<app>/android/key.properties` (re-run /
`mode: update`), `<credentials_dir>/key.properties` whose `storeFile` equals `android.keystore_path`,
else ask the user with `AskUserQuestion`. Never write the password into `config.md`, the PRD, or any
committed file.

### android/key.properties

Write `<app>/android/key.properties` from `<plugin-templates>/key.properties.template`, substituting
`<keystore-password>`, `<key-alias>` (`android.key_alias`), and `<absolute-keystore-path>`
(`android.keystore_path`). Use the **absolute** path: Gradle resolves a relative `storeFile`
against `android/app/`, not `android/`, and the keystore is not copied into the project. Render it to
a temp file and `mv` it into place only when the result is non-empty (same rule as Phase 2). In
`mode: update`, an existing `android/key.properties` is the password source — keep it, never
rewrite it.

### Release signingConfig

`flutter create` signs `release` with the **debug** key, which Play rejects. Unless
`android/app/build.gradle(.kts)` already loads `key.properties` (`grep -n keystoreProperties
android/app/build.gradle*` — keep an existing setup in `mode: update`), add to
`android/app/build.gradle.kts` — imports at the top of the file, `keystoreProperties` above the
existing `android {}` block, and the `signingConfigs` / `buildTypes.release` parts merged into that
block, replacing its `signingConfig = signingConfigs.getByName("debug")` line (never a second
`android {}`):

```kotlin
import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ...existing config...
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
    buildTypes {
        release {
            // debug key only where key.properties is absent (CI, contributors) — never uploaded
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}
```

The nullable casts keep debug builds working on machines without `key.properties`.

---

## Phase 2 — Fastlane Config Generation

Generate fastlane `Appfile` and `Fastfile` for both platforms by substituting these placeholders in
`<plugin-templates>/fastlane/` (the same set `scripts/validate-fastlane.sh` checks):

| Placeholder | Value |
|---|---|
| `__APP_ID__` | `bundle_id` |
| `__PACKAGE__` | `bundle_id_android` when set (update mode), else `bundle_id` |
| `__TEAM_ID__` | `ios.team_id` |
| `__ASC_KEY_ID__` | `ios.asc_key_id` |
| `__ASC_ISSUER_ID__` | `ios.asc_issuer_id` |
| `__APP_CATEGORY__` | `app_category` (App Store primary category id) |
| `__IPA_NAME__` | `<app_slug>.ipa` (the slug is sed-safe; a display name with `&` or `/` is not) |
| `__PROFILE_NAME__` | `<bundle_id> AppStore` (e.g. `com.<company>.habittracker AppStore`) |

`__PROFILE_NAME__` is used both as the Xcode code-signing profile name and as the `.mobileprovision`
filename (with `.mobileprovision` appended). Spaces are acceptable.

### Category check (fail fast, before anything uploads)

`app_category` and `play_category` come from the plan (per protocol §1). The App Store category is set
by the `categories` lane; Google Play has **no API field** for the category, so `play_category` is a
Play Console step printed by `app-harness-submit`. Both must be real top-level ids — no
subcategories, no secondary category:

```bash
printf '%s' "<app_category>" | grep -qxE 'BOOKS|BUSINESS|DEVELOPER_TOOLS|EDUCATION|ENTERTAINMENT|FINANCE|FOOD_AND_DRINK|GRAPHICS_AND_DESIGN|HEALTH_AND_FITNESS|LIFESTYLE|MAGAZINES_AND_NEWSPAPERS|MEDICAL|MUSIC|NAVIGATION|NEWS|PHOTO_AND_VIDEO|PRODUCTIVITY|REFERENCE|SHOPPING|SOCIAL_NETWORKING|SPORTS|TRAVEL|UTILITIES|WEATHER' \
  || echo "INVALID app_category: <app_category>"
printf '%s' "<play_category>" | grep -qxE 'ART_AND_DESIGN|AUTO_AND_VEHICLES|BEAUTY|BOOKS_AND_REFERENCE|BUSINESS|COMICS|COMMUNICATION|DATING|EDUCATION|ENTERTAINMENT|EVENTS|FINANCE|FOOD_AND_DRINK|HEALTH_AND_FITNESS|HOUSE_AND_HOME|LIBRARIES_AND_DEMO|LIFESTYLE|MAPS_AND_NAVIGATION|MEDICAL|MUSIC_AND_AUDIO|NEWS_AND_MAGAZINES|PARENTING|PERSONALIZATION|PHOTOGRAPHY|PRODUCTIVITY|SHOPPING|SOCIAL|SPORTS|TOOLS|TRAVEL_AND_LOCAL|VIDEO_PLAYERS|WEATHER' \
  || echo "INVALID play_category: <play_category>"
```

Any `INVALID` line → fix the value in `config.md` (ask the user if the right category is unclear)
before continuing. After the Fastfile exists, `cd <app>/ios && fastlane list_cats` cross-checks
`app_category` against Apple's live list.

### Render rule — temp file, `mv` only on success

Never `sed … > <app>/…/Fastfile` directly: a failing `sed` (wrong template path) has already
truncated the target, and an empty file then passes the placeholder check. Every render goes to a
temp file, is checked there, and is moved into place only when non-empty and placeholder-free (Ruby's
own `__dir__` is lowercase and does not match the placeholder pattern):

```bash
MODE="<mode>"   # config.mode
render() { # template-name target sed-args… (template under <plugin-templates>/fastlane/)
  tpl="<plugin-templates>/fastlane/$1"; dst="$2"; shift 2
  tmp="$(mktemp)"
  if ! { sed "$@" "$tpl" > "$tmp" && [ -s "$tmp" ] && ! grep -nE '__[A-Z][A-Z_]*__' "$tmp"; }; then
    rm -f "$tmp"; echo "RENDER FAILED: $dst (from $tpl)"; return 1
  fi
  if [ "$MODE" = update ] && [ -e "$dst" ]; then
    echo "KEPT $dst — rendered template at $tmp, merge missing lanes from it"
  else
    mv "$tmp" "$dst" && echo "WROTE $dst"
  fi
}
```

**`mode: update` — existing fastlane config (read this before running the commands below):** never
overwrite a project's own `Fastfile`/`Appfile` — `render` prints `KEPT` for them instead of moving the
temp file. An existing `Appfile` stays as is (the template lanes pass the app id and key themselves).
For an existing `Fastfile`, copy from the rendered temp file into it only the template lanes it lacks
(`beta`, `certs`, `auth_check`, `metadata`, `verify`, `list_cats`, `categories`, `screenshots`,
`screenshots_prune` on iOS; `internal`, `metadata`, `images`, `release_notes` on Android) together
with every top-level constant and helper those lanes reference that the file does not already define
(`ASC_KEY_ID`, `ASC_KEY`, `APP_ID`, `TEAM_ID`, `APP_CATEGORY`, `CERTS_DIR`, `SHOTS_DIR`, `asc_key`,
`asc_token`, `prune_duplicate_screenshots!` on iOS; `PACKAGE`, `JSON_KEY`, `VERSION_CODE` on
Android). Keep the project's existing lanes and credentials untouched, then `ruby -c` the merged
`Fastfile` (must print `Syntax OK`).

Shell functions and variables do not survive between separate Bash calls: run the `render`
definition above together with the iOS and Android blocks below in **one** Bash call (or paste the
`MODE=…; render() {…}` lines in front of each block).

### iOS fastlane

```bash
mkdir -p <app>/ios/fastlane/certs
render ios-Appfile.template <app>/ios/fastlane/Appfile \
    -e 's/__APP_ID__/<bundle_id>/g' \
    -e 's/__TEAM_ID__/<team_id>/g'
render ios-Fastfile.template <app>/ios/fastlane/Fastfile \
    -e 's/__APP_ID__/<bundle_id>/g' \
    -e 's/__TEAM_ID__/<team_id>/g' \
    -e 's/__ASC_KEY_ID__/<asc_key_id>/g' \
    -e 's/__ASC_ISSUER_ID__/<asc_issuer_id>/g' \
    -e 's/__APP_CATEGORY__/<app_category>/g' \
    -e 's/__IPA_NAME__/<app_slug>.ipa/g' \
    -e 's/__PROFILE_NAME__/<bundle_id> AppStore/g'
```

### Android fastlane

```bash
mkdir -p <app>/android/fastlane
render android-Appfile.template <app>/android/fastlane/Appfile \
    -e 's/__PACKAGE__/<android package>/g'
render android-Fastfile.template <app>/android/fastlane/Fastfile \
    -e 's/__PACKAGE__/<android package>/g'
```

`<android package>` = `bundle_id_android || bundle_id` (the `__PACKAGE__` row above).

The Android `release_notes` lane reads the version code from `pubspec.yaml` (`+N`), so it always
targets the build this phase uploads.

Any `RENDER FAILED` → fix the template path / value and re-run; nothing was written. Then confirm all
four files exist, are non-empty, and hold no placeholder (this also covers merged update-mode files):

```bash
for f in ios/fastlane/Appfile ios/fastlane/Fastfile android/fastlane/Appfile android/fastlane/Fastfile; do
  [ -s "<app>/$f" ] || echo "EMPTY OR MISSING: $f"
done
grep -nE '__[A-Z][A-Z_]*__' <app>/ios/fastlane/Appfile <app>/ios/fastlane/Fastfile \
  <app>/android/fastlane/Appfile <app>/android/fastlane/Fastfile   # must print nothing
```

---

## Phase 3 — Build and Upload

Run all build commands from the app root `<app>`.

### Pre-build platform requirements

Before building, ensure the platform items in `docs/app-gotchas.md` (Build / platform + Store
rejections) are in place — these are submit-blockers if missing: iOS `PrivacyInfo.xcprivacy`
registered (iOS 17+), core-library desugaring when a plugin needs it, iOS `Podfile` platform bumped,
`ITSAppUsesNonExemptEncryption = false` (skips the export-compliance prompt), Android `minSdk` =
max(23, highest plugin requirement) — check each plugin's own `minSdk`; never lower an existing higher
value — and, for ads builds (`monetization.admob_enabled: true`), the `Info.plist` ATT string +
`SKAdNetworkItems` and the R8 keep rules (test a `--release` build on a device before uploading;
debug never shows R8 crashes). Whether the app ships ads is decided by `monetization.admob_enabled`
only — never by `skip_monetize`, which just says whether the monetize phase ran (an update-mode app
can skip monetize and still ship its existing ads).

### Version and build number

**Bump the build number on every upload** — App Store Connect rejects a duplicate build number, so
increment `+N` (never reuse `1`):

```bash
cd <app>
grep -qE '^version:[[:space:]]*[^+[:space:]]+\+[0-9]+' pubspec.yaml || echo "NO +N in pubspec version"
perl -i -pe 's/^(version:\s*[^+\s]+)\+(\d+)/$1."+".($2+1)/e' pubspec.yaml
grep '^version:' pubspec.yaml
```

A `NO +N` line (an existing project with `version: 1.2.3`) → append the store's latest build number
first (`version: 1.2.3+<latest>`), then bump — otherwise the bump silently does nothing and the
Android `VERSION_CODE` reads `0`.

The new `N` must be greater than the latest TestFlight build (`cd ios && fastlane auth_check` prints
it) and the latest Play version code (Play Console → App bundle explorer); bump again if not.

In `mode: update`, also bump the **version name** — a released version string cannot take another
build: **minor** when the delta PRD adds NEW features, **patch** for fixes only (e.g. `1.4.2+31` →
`1.5.0+32`). `config.baseline.version` is the pre-update value.

`fastlane beta` calls `build_app` directly, so refresh the Flutter-generated Xcode config first or the
IPA keeps the old build number:

```bash
flutter build ios --release --config-only
grep FLUTTER_BUILD_NUMBER ios/Flutter/Generated.xcconfig   # must show the new N
```

**Re-run / resume safety (store uploads are NOT idempotent):** if this phase is re-entered after a
partial or failed upload, **bump the build number again before re-uploading** — re-sending the same
build number fails on ASC and can create a stuck/duplicate build on Play. Verify in App Store Connect /
Play Console whether the prior build actually landed before retrying; never blindly re-run the upload
lane with the same number.

### One platform at a time + disk gate

Release builds for both platforms at once OOM a 16 GB machine and kill both — run iOS, then Android,
never in parallel. Gate the iOS archive on free disk (a full disk fails deep inside the archive step
with an error that never mentions disk):

```bash
df -g <app> | awk 'NR==2 { if ($4 < 12) { print "LOW DISK: " $4 " GB free, need ~12 GB"; exit 1 } }'
```

A non-zero exit → free space (e.g. `~/Library/Developer/Xcode/DerivedData`, old simulators via
`xcrun simctl delete unavailable`) before building.

### iOS — Signed IPA → TestFlight

```bash
cd <app>/ios
fastlane certs          # downloads/renews distribution cert + provisioning profile into certs/
fastlane beta           # builds the signed IPA and uploads it to TestFlight
```

`fastlane beta` calls `get_provisioning_profile`, `update_code_signing_settings`, `build_app`,
and `upload_to_testflight` (defined in the generated Fastfile). The lane sets
`skip_waiting_for_build_processing: true` so it does not block waiting for Apple's processing.

### Android — Signed AAB → internal track

Start only after the iOS build has finished.

```bash
cd <app>
flutter build appbundle --release   # produces build/app/outputs/bundle/release/app-release.aab
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | grep -m1 Owner
# must show your upload key's owner — "CN=Android Debug" means the signingConfig is not wired

cd android
fastlane internal                   # uploads AAB to the Play Store internal track
```

`fastlane internal` calls `upload_to_play_store` with `track: "internal"` and the relative AAB
path `../build/app/outputs/bundle/release/app-release.aab` (defined in the generated Fastfile).

### Build failure handling

- If `fastlane certs` fails with a certificate error, check that the Apple Distribution
  certificate is valid in Keychain Access, then re-run.
- If `fastlane beta` fails with a profile not found error, ensure the app record exists in App
  Store Connect (prerequisite above) and re-run `fastlane certs` first.
- If ASC auth fails, run `cd <app>/ios && fastlane auth_check` — it verifies the API key and that the
  app record is reachable.
- If `flutter build appbundle --release` fails, run `flutter analyze` to identify compilation
  errors and fix them before retrying.
- If Play rejects the AAB as debug-signed, or with a different upload key, fix the Phase 1
  `key.properties` / signingConfig (never replace the key of a published app).
- If `fastlane internal` fails with a `401` or credential error, verify that
  `android/fastlane/play-store-key.json` was copied correctly and that the service account has
  the Release Manager role in Play Console.

---

## Output — Write Handoff and State

### handoff/build-result.md

Write `docs/harness/handoff/build-result.md` with the following layout:

```markdown
# Build Result — <app_name>

## IPA

- Path: `<app>/ios/build/<app_slug>.ipa`
- Upload: TestFlight — uploaded successfully (build number: <N>)

## AAB

- Path: `<app>/build/app/outputs/bundle/release/app-release.aab`
- Upload: Play Store internal track — uploaded successfully (version code: <N>)

## Version

- Version name: <x.y.z>
- iOS build number: <N>
- Android version code: <N>
```

Fill the values with the actual numbers reported by `pubspec.yaml` and the fastlane output.

### state.md

Write `docs/harness/state.md` atomically (per protocol §7 `build → screenshot` transition and
§7 rule 2 — set `status: running` in the same write as `next_role`):

```yaml
status: running
current_phase: build
next_role: screenshot
updated_at: "<ISO-8601 UTC now>"
```

Leave `current_round`, `created_at`, `resume_attempts`, and `pause_reason` unchanged.

### pipeline-log.md

Append one row to `docs/harness/pipeline-log.md` (per protocol §6):

```
| <ISO-8601 UTC now> | complete | build | <x.y.z>+<N>: IPA uploaded to TestFlight; AAB uploaded to internal track; next: screenshot |
```

---

## Error Handling and Pausing

If either upload fails and cannot be resolved immediately (or the Phase 1 gitignore guard aborts —
`pause_reason: error`), write `docs/harness/state.md` with:

```yaml
status: paused
current_phase: build
next_role: build
pause_reason: manual_action   # error for the Phase 1 gitignore guard
updated_at: "<ISO-8601 UTC now>"
```

and append the pause row to `docs/harness/pipeline-log.md` (protocol §7 rule 12):

```
| <ISO-8601 UTC now> | pause | build | manual_action: <what the user must do> |
```

(`error: <reason>` instead when `pause_reason: error`.) Then explain (in `default_language`) what
manual action is required. The harness resumes when the user runs `/app-harness --resume` (or
`/app-harness-resume`), per protocol §7 pause/resume rules.
