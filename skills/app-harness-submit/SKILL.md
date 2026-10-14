---
name: app-harness-submit
description: Phase 10 — write store-listing and App Review info (contacts, copyright, demo account when the app has login, 3.1.2 subscription links), upload text metadata + the App Store category via fastlane, derive the App Privacy / Data Safety and age-rating answers from what the app actually does, then pause with exact manual steps for the final iOS review submission and Android production promotion.
argument-hint: ""
allowed-tools: [Read, Write, Edit, Bash, AskUserQuestion]
---

# app-harness-submit

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

Phase 10 of the flutter-app-harness pipeline. Uploads store text metadata and the App Store category
via fastlane for both iOS and Android, derives the privacy and rating answers from the app itself,
then pauses the pipeline with exact manual steps for the final review submission / production
promotion (see **Boundary** below for what is genuinely manual and what is a deliberate checkpoint).

All file schemas (`config.md`, `state.md`, `pipeline-log.md`) and the phase transition table are
defined in `docs/harness-protocol.md` — that document is the single source of truth (§1 for
`config.md`; §2 for `state.md` keys and `pause_reason` values; §6 for `pipeline-log.md` schema;
§7 for the `submit → metadata-done → paused` transition and the `(paused) → resume → retro`
transition). Do not redefine schemas here. Store-review pitfalls are in `docs/app-gotchas.md` →
Store rejections — cite it, don't restate it.

**Boundary:** Text metadata upload is automated. The final "Submit for Review" on iOS and the
"Promote to production" action on Android are **manual in this pipeline** — deliberately, so a
human sees the assembled listing once before it goes out, and because the Play questionnaires
(Content Rating, Data Safety, Target Audience, App access, Ads) and the Play app category have no API.

Note the iOS half *is* automatable if you want it: `reviewSubmissions` will submit a version
end-to-end (see **iOS submission over the API** below). What is genuinely not automatable is the
Play side and the age-rating questionnaire. Keep the pause unless you have a reason not to — the
review is the point of it.

**Prerequisites:** Phase 9 (`app-harness-screenshot`) completed; screenshots and ASO metadata
already uploaded (or kept, in `mode: update`); `state.md` shows `next_role: submit`.

---

## Input — Read Inputs

Before any action, load:

1. `docs/harness/config.md` — extract `mode`, `project_path`, `app_slug`, `bundle_id`,
   `bundle_id_android` (update mode; blank = same as `bundle_id`), `app_name`,
   `default_language`, `locales`, `app_category`, `play_category`, `device_family`, `backend`,
   the `developer` block, and the `monetization` block (`admob_enabled`, `iap`,
   `products`) (per protocol §1).
2. `docs/harness/state.md` — confirm `next_role: submit` (per protocol §2).
3. The PRD (`docs/harness/plans/*-prd.md`, newest) — whether the app has **accounts / login**,
   content users publish to other users (**UGC**), **user-to-user messaging**, health/wellness
   topics, and kids as the target audience. In `mode: update`, the delta PRD's change list.

Derive the app root `<app>`: `project_path` when `mode: update`, else `<projects-dir>/<app_slug>/`
(or `.` when cwd is already the app project, i.e. `./pubspec.yaml` exists).

`<plugin-templates>` = this plugin's `templates/` directory: `${CLAUDE_PLUGIN_ROOT}/templates` when
that env var is set, else `<skill base directory>/../../templates` (the skill base directory is shown
when the skill loads). Never a bare relative `templates/...` path — it resolves against the app and,
with `>`, truncates the target file before failing.

Locale folder codes (App Store vs Play) follow the mapping table in `app-harness-screenshot`.

Every message this skill prints to the user (questions, the manual-steps block) is written in
`default_language`; console button names may stay as the console shows them.

---

## Phase 0 — Generate store-info files from config

Before uploading, write the store-listing + App-Review files from the `developer` block in
`config.md` (sourced from `credentials/store-metadata.md`) so they actually get uploaded — these are
otherwise empty and the listing/review info would be missing.

**`mode: update` — the app is live (read before writing anything below):** the URL files
(`support_url.txt`, `marketing_url.txt`, `privacy_url.txt`), `copyright.txt`, the App Review contact
files (`first_name.txt`, `last_name.txt`, `phone_number.txt`, `email_address.txt`), and the Play
contact (`set_contact_details.rb`) are written / run **only when the change request touches that
field** — a missing file is NOT a reason to write it: `deliver`/`supply` leave a field alone when its
file is absent, so writing one replaces the live value with the `developer` block. Before editing ANY
listing file in update mode, pull the live listing first so edits start from what ships:
`cd ios && fastlane deliver download_metadata --force --app_identifier <bundle_id> --api_key_path <asc key json>`
(iOS) and `fastlane supply init --package_name <bundle_id_android or bundle_id> --json_key <play-store-key.json>
--metadata_path <tmpdir>` (Android — copy only the files you then edit into `android/fastlane/metadata`). Reviewer `notes.txt` and release notes
are about this build and are always written.

**iOS (deliver picks these up automatically):**
- `ios/fastlane/metadata/copyright.txt` ← `developer.copyright`
- per App Store locale: `support_url.txt` ← `developer.homepage`, `marketing_url.txt` ←
  `developer.homepage`, `privacy_url.txt` ← `developer.privacy`
- `ios/fastlane/metadata/review_information/`: `first_name.txt`, `last_name.txt`, `phone_number.txt`,
  `email_address.txt` ← `developer.*`; `notes.txt` ← reviewer notes, factual and about this build:
  how to reach every primary flow, the ATT screen-recording note for an ads build, where the paywall
  and **Restore Purchases** are when `monetization.iap: true`, and the demo-account hint below.

**Demo account (only when the app has login).** App Review must be able to sign in. Ask the user with
`AskUserQuestion` for a working reviewer account on the app's backend (never invent one, never reuse
a personal account), then write `review_information/demo_user.txt` + `demo_password.txt` — `deliver`
marks "Sign-in required" when both are present — and mention the demo account in `notes.txt`. Keep
both files out of git:
`grep -qxF 'ios/fastlane/metadata/review_information/demo_*.txt' .gitignore || echo 'ios/fastlane/metadata/review_information/demo_*.txt' >> .gitignore`.
The same credentials go into Play Console → App content → **App access** (manual step below). No login
→ no demo account files.

**Subscriptions (3.1.2) — only when `monetization.products` has a `subscription`.** (Update mode:
append to the **downloaded live** `description.txt` — never create a links-only description.) The App Store
listing must link the Terms of Use (EULA) and the privacy policy. Append to every App Store locale's
`description.txt`, in that locale's language, a "Terms of Use" line with Apple's standard EULA
(`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`, or the app's own EULA URL) and a
"Privacy Policy" line with `developer.privacy`, then check:

```bash
cd <app>
EULA="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"   # or the app's own EULA URL
for f in ios/fastlane/metadata/*/description.txt; do
  grep -qF "$EULA" "$f" && grep -qF '<developer.privacy>' "$f" || echo "MISSING 3.1.2 links: $f"
done   # no output = OK; re-run the screenshot phase's length check (description ≤ 4000)
```

The paywall itself must show price, period, trial terms, auto-renew notice, and both links
(`docs/app-gotchas.md` → In-app purchases) — verify on the simulator before pausing.

**`mode: update` — release notes.** No new app record. Write what's new per locale from the delta
PRD's change list: `ios/fastlane/metadata/<App Store locale>/release_notes.txt` and
`android/fastlane/metadata/android/<Play locale>/changelogs/<versionCode>.txt` (`<versionCode>` = the
`+N` in `pubspec.yaml`; ≤ 500 chars). Keep the existing listing text unless the change request
touched it.

**Android (contact email + website have no `supply` field — set via the Publisher API):**
- render `<plugin-templates>/set_contact_details.rb.template` → `android/fastlane/set_contact_details.rb`
  with `__PACKAGE__`=`<android package>` (`bundle_id_android || bundle_id`), `__EMAIL__`=`developer.email`,
  `__WEBSITE__`=`developer.homepage` (a URL — use `|` as the sed delimiter), through a temp file that
  is moved into place only when non-empty, then run it (`mode: update`: only when the change request
  touches the contact details — see above):

  ```bash
  cd <app>
  tmp="$(mktemp)"
  if sed -e 's|__PACKAGE__|<android package>|g' -e 's|__EMAIL__|<developer.email>|g' \
         -e 's|__WEBSITE__|<developer.homepage>|g' \
         <plugin-templates>/set_contact_details.rb.template > "$tmp" \
     && [ -s "$tmp" ] && ! grep -nE '__[A-Z][A-Z_]*__' "$tmp"; then
    mv "$tmp" android/fastlane/set_contact_details.rb
    (cd android && ruby fastlane/set_contact_details.rb)
  else
    rm -f "$tmp"; echo "RENDER FAILED: set_contact_details.rb"
  fi
  ```
- The **privacy policy URL**, **app category** (`play_category`), and Data Safety / Content Rating /
  Target Audience / App access / Ads are set in the manual step below (Play Console).

## Phase 1 — Metadata Upload

Run the fastlane metadata and categories lanes for both platforms. These lanes push text metadata
(localized titles, descriptions, release notes, URLs, review information) and the App Store category
to the stores without uploading a binary.

### iOS metadata upload

```bash
cd <app>/ios
VERSION=$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' ../pubspec.yaml)
DELIVER_APP_VERSION="$VERSION" fastlane metadata
fastlane categories
```

- `fastlane metadata` pushes all locale text files under `ios/fastlane/metadata/` to App Store
  Connect via `deliver` (titles, subtitles, descriptions, keywords, promotional text, release notes,
  URLs, copyright, review information). `DELIVER_APP_VERSION` makes `deliver` edit — or, in
  `mode: update`, create — the App Store version whose string matches the uploaded build (the
  screenshot phase may already have created it; re-running is a no-op).
- `fastlane categories` sets the App Store primary category from `config.app_category` (baked into
  the Fastfile by `app-harness-build`; no subcategories, no secondary category). If it fails with an
  invalid category, run `fastlane list_cats`, fix `app_category` in `config.md`, and regenerate the
  Fastfile constant.

### Android metadata upload

```bash
cd <app>/android
fastlane metadata
fastlane release_notes
```

- `fastlane metadata` pushes all locale text files under `android/fastlane/metadata/android/` to
  Google Play (titles, short descriptions, full descriptions) via `upload_to_play_store` with
  `skip_upload_apk: true` and `skip_upload_aab: true`.
- `fastlane release_notes` pushes the `changelogs/<version-code>.txt` files for the build in
  `pubspec.yaml` (`+N`) onto the production draft release.

If any fastlane lane exits non-zero, do NOT proceed to the pause step. Instead write
`docs/harness/state.md` with `status: paused`, `pause_reason: manual_action`, and
`next_role: submit` (retry), append
`| <ISO-8601 UTC now> | pause | submit | manual_action: <lane> failed — <what the user must fix> |`
to `pipeline-log.md` (protocol §7 rule 12), then explain the error and stop.

---

## Phase 2 — Privacy and Rating Profile

Derive the answers from what the app actually does — never from a template. Evidence:

```bash
cd <app>
grep -nE '^\s+(google_mobile_ads|in_app_purchase|firebase_auth|google_sign_in|sign_in_with_apple|supabase_flutter|cloud_firestore|firebase_storage|firebase_crashlytics|sentry_flutter|firebase_analytics|dio|http):' pubspec.yaml
grep -o 'NS[A-Za-z]*UsageDescription' ios/Runner/Info.plist | sort -u
```

plus `monetization.admob_enabled`, `monetization.iap`, `backend`, and the PRD (accounts, UGC,
messaging). Every ads / purchase answer below keys off `monetization.admob_enabled` /
`monetization.iap` only — never `skip_monetize`, which just says whether the monetize phase ran (a
`mode: update` app that skipped monetize still ships its existing ads/IAP). If the pubspec evidence
disagrees (e.g. `google_mobile_ads` present but `admob_enabled: false`), stop and ask — the
declarations must match what ships.

### Data-collection profile (App Privacy + Data Safety)

"Collected" means the data leaves the device. Local-first data that stays on the device is **not**
collected by either store's definition; purchases through StoreKit / Play Billing with no own server
add nothing. Declare one row per thing the app actually does:

| The app… | iOS App Privacy (Connect form) | Play Data Safety |
|---|---|---|
| shows AdMob ads (`monetization.admob_enabled: true`) | **Identifiers → Device ID**, purpose Third-Party Advertising, not linked to identity, **Used for Tracking** (matches the ATT prompt) | **Device or other IDs**, collected **and shared** (Google), purpose Advertising or marketing |
| has accounts / login | **Contact Info → Email Address** (+ Name if asked) and **Identifiers → User ID**, App Functionality, linked to identity | **Personal info → Email address** (+ Name), **User IDs**, App functionality + Account management; "users can request deletion" = Yes (in-app deletion, 5.1.1(v)) |
| ships a crash SDK (`firebase_crashlytics`, `sentry_flutter`) | **Diagnostics → Crash Data, Performance Data**, App Functionality, not linked | **App info and performance → Crash logs, Diagnostics**, App functionality |
| ships an analytics SDK (`firebase_analytics`) | **Usage Data → Product Interaction**, Analytics | **App activity → App interactions**, Analytics |
| stores what users create on a server (`backend: rest \| firebase`) | **User Content** (Photos or Videos / Other User Content), App Functionality, linked | **Photos and videos / Files and docs / Other user-generated content**, App functionality |
| none of the above | **Data Not Collected** | **No data collected** |

- Every collected type: encrypted in transit = Yes (HTTPS); deletion request = Yes with accounts,
  otherwise not applicable.
- Ads: cross-check Google's current Mobile Ads SDK data-disclosure pages (iOS + Android); if they list
  more types (e.g. coarse location from IP, product interaction, diagnostics), declare those too.
- `PrivacyInfo.xcprivacy` (`NSPrivacyCollectedDataTypes`, `NSPrivacyTracking`) must declare the same
  types as the Connect form, and Play must match iOS — mismatches draw review scrutiny.
- **COPPA / Target Audience:** default = **not directed at children**. Only if the PRD targets kids,
  set Play Target Audience to include under-13 **and** AdMob "Made for kids" +
  `tagForChildDirectedTreatment(true)` — all three must agree, personalized ads off.

### iOS age rating (2026 declarations)

Answer in App Store Connect → App Information → Age Rating (`ageRatingDeclarations` is write-only over
the API — `GET` → `403` — so verify in the Connect UI). Defaults for an app:

| Declaration | Answer |
|---|---|
| `advertising` | **Yes** when `monetization.admob_enabled: true` (banners count), else No |
| `userGeneratedContent` | Yes only if users publish content other users can see; else No |
| `messagingAndChat` | Yes only if users can message each other; else No |
| `healthOrWellnessTopics` | Yes if `app_category` is `HEALTH_AND_FITNESS` / `MEDICAL` or the PRD covers health/wellness; else No |
| `ageAssurance`, `parentalControls` | No, unless the app verifies age / offers parental controls |
| `gunsOrOtherWeapons`, violence, sexual content, profanity, horror, drugs/alcohol, mature themes, medical info | None, unless the content says otherwise |
| gambling, contests, loot boxes, unrestricted web access | No (Yes for web access only if the app embeds an open browser) |

### Play content rating (IARC) and App content

For a typical utility / productivity app: category **"All Other App Types"** (**"Social or
Communication"** when the PRD has messaging or UGC; **"Reference, News, or Educational"** for a content
app). Violence, fear, sexuality, language, controlled substances, crude humor, gambling → **No**.
Users interact or exchange content → Yes only with messaging/UGC. Shares the user's location with
other users → No. Purchases of digital goods → **Yes** when `monetization.iap: true`. Web browser or
search engine → No.

App content declarations: **Ads** = "Yes, my app contains ads" when `admob_enabled`; **Advertising
ID** = Yes, purpose Advertising or marketing, for ads builds; **App access** = all functionality
available without restrictions, or the demo account when there is login; **Data safety** = the profile
above; **Target audience** per the COPPA line; the remaining declarations (government, financial
features, health) answered for what the app actually is — usually "not applicable".

---

## Phase 3 — Manual Steps + Pause

After both upload sequences complete successfully, the pipeline must pause so the developer can
perform the final submission actions that cannot be automated.

**Pre-submit rejection checklist** (print this with the manual steps — these are the rejections
already hit; see `docs/app-gotchas.md` → Store rejections):
- **Age rating declarations complete — especially `advertising` = Yes for any AdMob build.** Apple
  added `userGeneratedContent`, `messagingAndChat`, `ageAssurance`, `gunsOrOtherWeapons`,
  `advertising`, `healthOrWellnessTopics`, `parentalControls` in 2026. An app record that only answered
  the old questionnaire is blocked before human review (`409 STATE_ERROR.ENTITY_STATE_INVALID` naming
  `ageRatingDeclarations`). Use the table in Phase 2.
- **Android: check the *merged* manifest, not the one you wrote.** Dependencies merge their own
  permissions into the bundle and Play Console demands a declaration for them under **App content
  → Needs attention**. `FOREGROUND_SERVICE_*` in particular requires a form with a **mandatory
  demo video link** (unlisted YouTube; private is invisible to reviewers) showing the feature
  working while the app is backgrounded. Past the deadline this blocks updates while the live
  listing stays up. Flutter builds into `build/app/` (not `android/app/build/`), and AGP nests the
  merged manifest below `merged_manifests/release/`, so search for it (after
  `flutter build appbundle --release`):
  ```bash
  cd <app>
  M=$(find build/app/intermediates/merged_manifests/release -name AndroidManifest.xml 2>/dev/null)
  if [ -n "$M" ]; then grep -h uses-permission $M | sort -u
  else echo "NO merged manifest — run flutter build appbundle --release first"; fi
  ```
- **iPad: `TARGETED_DEVICE_FAMILY` matches `config.device_family`.** Declaring iPad (`"1,2"`) obliges
  the app to support every iPad orientation (or `UIRequiresFullScreen`) and to ship 13" iPad
  screenshots — a portrait-only phone layout shipped with the template default is rejected under 4.0.
  `device_family: phone` uses `"1"`. Check:
  `grep -n TARGETED_DEVICE_FAMILY ios/Runner.xcodeproj/project.pbxproj | sort -u`
- **Version string not already released.** A new build under an already-released version fails with
  *"Invalid Pre-Release Train … closed for new build submissions."* Bump the name in `pubspec.yaml`
  and leave `+N` (the Android `versionCode`) on its own increasing schedule.
- **ATT (2.1), ads builds only (`monetization.admob_enabled: true`):** attach a **screen recording
  from a physical device** to App Review Information → Notes, showing fresh install → ATT prompt
  appears before any tracking → following flow. (The app must use the wait-for-resumed ATT pattern,
  or the prompt won't show on the latest iOS.)
- **Localized permission strings:** every configured locale's `ios/Runner/<lproj>.lproj/InfoPlist.strings`
  (`<lproj>`: `zh` / `zh-Hans` / `zh_CN` → `zh-Hans`, `zh-Hant` / `zh_TW` → `zh-Hant`, every other
  locale as-is — the generator's mapping) must carry every `NS*UsageDescription` the app declares
  (`NSUserTrackingUsageDescription` for ads builds, plus camera/photos/notifications/etc.) — a permission string left in only one language is a
  repeat localization rejection (the reviewer sees a foreign-language prompt). Verify:
  ```bash
  cd <app>
  for key in $(grep -o 'NS[A-Za-z]*UsageDescription' ios/Runner/Info.plist | sort -u); do
    for loc in en ko; do   # ← every config.locales code
      case "$loc" in zh|zh-Hans|zh_CN) lp=zh-Hans ;; zh-Hant|zh_TW) lp=zh-Hant ;; *) lp="$loc" ;; esac
      f="ios/Runner/$lp.lproj/InfoPlist.strings"
      grep -q "$key" "$f" 2>/dev/null || echo "MISSING: $f $key"
    done
  done   # no output = OK
  ```
  Wording must describe the concrete user benefit and match the App Privacy / tracking declaration.
- **Accounts:** in-app account deletion (5.1.1(v)); third-party social login → Sign in with Apple
  offered too (4.8); demo account filled (Phase 0).
- **IAP (`monetization.iap: true`):** every product in `monetization.products` is **Ready to Submit**
  in App Store Connect (price, localized name/description per locale, a paywall review screenshot —
  `xcrun simctl io booted screenshot paywall.png` — and a review note) and attached to the version
  (manual step 5); the Play products exist and are **Active** — monetize deferred their creation until
  a Play Billing build was on the internal track (the `PENDING … create Play products <ids>` note in
  `pipeline-log.md`), so they are created now (manual Android step 4); Restore Purchases reachable
  from Settings and the paywall; 3.1.2 links present for subscriptions.
- **No alpha** in the iOS icon or any screenshot.
- **Build number** incremented (ASC rejects duplicates).
- **Export compliance** set (`ITSAppUsesNonExemptEncryption=false`) so no per-upload prompt.
- **iOS App Privacy (nutrition label):** in App Store Connect → App Privacy, declare the
  **Data-collection profile** from Phase 2 (this is **separate from** `PrivacyInfo.xcprivacy`, which is
  a bundled manifest — the label is a Connect form). A missing/empty label blocks release.
- **Privacy:** `PrivacyInfo.xcprivacy` present in the bundle; tracking matches the ATT prompt.
- **Android:** privacy policy URL set (`developer.privacy`); app category set (`play_category`);
  Content Rating (IARC), Data Safety, Target Audience, App access, Ads, and Advertising ID completed
  per Phase 2. (Contact email/website were set in Phase 0 via the API script.)
- **COPPA / kids:** if the app is **child-directed** (see the profile), AdMob must be "Made for kids"
  with `tagForChildDirectedTreatment`, and Play Target Audience must include children — keep all three
  consistent or expect a rejection / FTC exposure.

### Pre-pause state write

Per `docs/harness-protocol.md` §7 (`submit → metadata-done` event row) and §7 rule 3 (when
`status` is `paused`, `pause_reason` must be non-empty), write `docs/harness/state.md` atomically
with **exactly** these field changes (leave `created_at`, `current_round`, `resume_attempts`
unchanged):

```yaml
status: paused
current_phase: submit
next_role: retro
pause_reason: manual_action
updated_at: "<ISO-8601 UTC now>"
```

**Important:** `next_role: retro` is set at pause time because a paused state stores the role to
run *after* resume. `app-harness-resume` reads `next_role` directly from `state.md` (it does
NOT set `next_role` itself) and dispatches `Skill("app-harness-<next_role>")`. Setting
`next_role: retro` here is what causes resume to advance to retro rather than re-dispatching
submit (see Resume Contract below).

### Append to pipeline-log.md

Append one row to `docs/harness/pipeline-log.md` per the schema in `docs/harness-protocol.md` §6,
using the transition event name `metadata-done` (matches protocol §7):

```
| <ISO-8601 UTC now> | pause | submit | metadata-done: iOS metadata+category uploaded, Android metadata+release_notes uploaded; awaiting manual Submit for Review (iOS) and production promotion (Android) |
```

### iOS submission over the API (reference — for resubmissions and automation)

`POST /v1/appStoreVersionSubmissions` is **deprecated**: `403 "Allowed operation is: DELETE"`.
The current flow is three calls:

```
1. POST  /v1/reviewSubmissions       { platform: IOS, app: <appId> }
         reuse an existing submission in state READY_FOR_REVIEW rather than creating a second
2. POST  /v1/reviewSubmissionItems   { reviewSubmission: <id>, appStoreVersion: <id> }
3. PATCH /v1/reviewSubmissions/<id>  { submitted: true }
```

**Resubmitting after a rejection.** The rejected version is still attached to the submission that
rejected it, so step 2 fails with `STATE_ERROR.ITEM_PART_OF_ANOTHER_SUBMISSION`. Detach first: for
every submission in state `UNRESOLVED_ISSUES`,
`PATCH /v1/reviewSubmissionItems/<itemId> { removed: true }`.

Do **not** create a new version for a rejection — `REJECTED`, `DEVELOPER_REJECTED`,
`METADATA_REJECTED`, `INVALID_BINARY` are editable, so attach the new build to the same version.
A duplicate version string fails with `ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE`.

**Reviewer communication.** Resolution Center has no API — you can read that a version is
`REJECTED` but not why, and you cannot reply. `appStoreReviewDetail.notes` is readable, writable,
and read by reviewers; it is the only channel available. When fixing a rejection, put the
explanation in `ios/fastlane/metadata/review_information/notes.txt` and upload it **before**
resubmitting. State facts about this build — "we will add it later" invites another rejection.

**Metadata stays editable through `WAITING_FOR_REVIEW` and `IN_REVIEW`** and locks at
`READY_FOR_SALE` (`PATCH` → `409`). A wrong release note is fixable until approval, then never.

### Print exact manual steps

After writing state, print the following instructions for the developer — translated into
`default_language`, with the Phase 2 profile, age-rating, and IARC answers filled in for this app:

---

**PIPELINE PAUSED — MANUAL SUBMISSION REQUIRED**

Fastlane has uploaded all text metadata and the App Store category. You must now complete the final
submission steps manually, as the Play questionnaires have no API and the final submission is a
deliberate human checkpoint.

**iOS — Submit for Review**

1. Open [App Store Connect](https://appstoreconnect.apple.com) and navigate to your app.
2. **App Information → Age Rating**: answer every declaration per the age-rating table (advertising =
   Yes for an ads build).
3. **App Privacy**: declare the data-collection profile (or **Data Not Collected**) and publish it.
4. Select the version `<x.y.z>` and attach build `<N>` uploaded by `app-harness-build` (Phase 8).
5. When `monetization.iap: true`: in **In-App Purchases and Subscriptions** on the version page, select
   every product (the first IAPs must be submitted together with an app version).
6. Verify that the build, all screenshots (iPhone, plus 13" iPad when universal), the demo account
   (if login), and all metadata are correct and complete.
7. Click **"Submit for Review"**.
8. Answer any pre-submission questionnaires Apple presents (export compliance, content rights,
   advertising identifier / IDFA).
9. Confirm submission. The app status will change to "Waiting for Review".

**Android — Promote to Production**

1. Open [Google Play Console](https://play.google.com/console) and navigate to your app.
2. **Store presence → Store settings → App category**: set to `<play_category>` (no API for this).
3. **Policy → App content**: complete Privacy policy (`<developer.privacy>`), App access (demo
   account if login), Ads, Advertising ID, Content Rating (IARC answers above), Target Audience, Data
   Safety (profile above), and any remaining declaration.
4. When `monetization.iap: true` and `pipeline-log.md` has the monetize `PENDING` note:
   **Monetize → Products** — create every product in `monetization.products` with the same ids
   (`<ids>`): in-app products for `consumable` / `non_consumable`, subscriptions with one
   auto-renewing base plan for `subscription`; localized name/description per locale, price; then
   **Activate** each. (Possible only now — Play needs an uploaded build with the BILLING permission.)
5. Go to **Testing → Internal testing** and locate the internal-track release uploaded by
   `app-harness-build` (Phase 8), or open the production draft that `fastlane release_notes`
   created (same build, notes already filled).
6. Once all declarations are complete, click **"Promote release → Production"** (or edit the draft).
7. Set the rollout percentage (100% recommended for a new app; a staged rollout for an update).
8. Click **"Review release"** then **"Start rollout to production"**.

When you have completed all of the above steps on both platforms, run:

```
/app-harness --resume
```

(or `/app-harness-resume`). `app-harness-resume` will confirm you are done, clear the pause, and
launch `app-harness-retro` (the pipeline was already set to `next_role: retro` at pause time).

---

## Resume Contract

This section documents the expected behaviour of `app-harness-resume` when it encounters the
pause written by this skill. It is informational — `app-harness-resume` is the authoritative
implementation (see its SKILL.md).

Per `docs/harness-protocol.md` §7:

- The pause event is `metadata-done`; it sets `status: paused` with `pause_reason: manual_action`.
- The resume event transitions `(paused) → resume → retro`.
- When the user confirms all manual steps are complete, `app-harness-resume` will:
  1. Clear `pause_reason` to `""` (per §7 rule 8).
  2. Set `status: running` atomically (per §7 rules 1 and 2). **`app-harness-resume` does NOT
     set `next_role`** — it reads whatever `next_role` is already in `state.md`. Because this
     skill wrote `next_role: retro` at pause time, resume dispatches `retro`.
  3. Increment `resume_attempts` (per §7 rule 4).
  4. Append a `resume` row to `pipeline-log.md` (per §6).
  5. Read `next_role` (= `retro`) from the updated `state.md` and dispatch
     `Skill("app-harness-retro")`.

The retro phase (`next_role: retro`) is the final phase; when it completes it sets
`status: completed` (per §7 `retro → complete` row).
