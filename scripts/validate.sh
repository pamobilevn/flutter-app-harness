#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
err() { echo "FAIL: $1"; fail=1; }

# 1. Manifests are valid JSON
for f in "$ROOT/.claude-plugin/plugin.json" "$ROOT/.claude-plugin/marketplace.json"; do
  [ -f "$f" ] || { err "missing $f"; continue; }
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null || err "invalid JSON: $f"
done

# 2. Every skill has name+description frontmatter, and name == directory name
while IFS= read -r skill; do
  dir="$(basename "$(dirname "$skill")")"
  head -20 "$skill" | grep -q "^name:[[:space:]]*$dir[[:space:]]*$" || err "name: in $skill must equal '$dir'"
  head -20 "$skill" | grep -q '^description:[[:space:]]*[^[:space:]]' || err "no description: in $skill"
done < <(find "$ROOT/skills" -name SKILL.md 2>/dev/null)

# Every phase role has a skill
for role in audit research plan design contract generator evaluator monetize build screenshot submit retro resume status; do
  [ -f "$ROOT/skills/app-harness-$role/SKILL.md" ] || err "missing skills/app-harness-$role/SKILL.md"
done
[ -f "$ROOT/skills/app-harness/SKILL.md" ] || err "missing orchestrator skills/app-harness/SKILL.md"
# Skills run with cwd = the app, so plugin docs/templates must be resolved via the plugin root.
for f in "$ROOT"/skills/*/SKILL.md; do
  grep -q 'CLAUDE_PLUGIN_ROOT}/<path>' "$f" || err "$(basename "$(dirname "$f")") missing plugin-paths preamble"
done

# 3. harness-protocol.md exists and defines required keys
PROTO="$ROOT/docs/harness-protocol.md"
[ -f "$PROTO" ] || err "missing docs/harness-protocol.md"
if [ -f "$PROTO" ]; then
  for key in current_phase current_round next_role status pause_reason checkpoint \
             skip_monetize device_family backend app_category play_category locales \
             mode project_path architecture baseline "Update-mode gate overrides"; do
    grep -q "$key" "$PROTO" || err "harness-protocol.md missing key: $key"
  done
  for g in R1 R2 R3 R4 R5 R6 R7 R8 R9 R10 R11 R12; do
    grep -q "| $g |" "$PROTO" || err "harness-protocol.md missing gate id table row: $g"
  done
fi
GOTCHAS="$ROOT/docs/app-gotchas.md"
[ -f "$GOTCHAS" ] || err "missing docs/app-gotchas.md"

# 4. Per-skill required-section assertions (inline grep checks).
require_section() { # file, pattern, label
  [ -f "$1" ] || { err "missing $1"; return; }
  grep -qiE -- "$2" "$1" || err "$(basename "$(dirname "$1")") missing section: $3"
}
S="$ROOT/skills"

ORCH="$S/app-harness/SKILL.md"
require_section "$ORCH" "next_role" "dispatch-by-next_role"
require_section "$ORCH" "config\.md" "config-init"
require_section "$ORCH" "skip_research|skip-research" "skip-research flag"
require_section "$ORCH" "skip_monetize|skip-monetize" "skip-monetize flag"
require_section "$ORCH" "app-harness-monetize" "dispatch to monetize"
require_section "$ORCH" "ISO 639|any language|vi" "default_language is any ISO code"
require_section "$ORCH" "--audit" "update mode flag"
require_section "$ORCH" "app-harness-audit" "dispatch to audit"

AUD="$S/app-harness-audit/SKILL.md"
require_section "$AUD" "read-only" "audit never edits app code"
require_section "$AUD" "flutter analyze" "baseline analyze"
require_section "$AUD" "flutter test" "baseline test"
require_section "$AUD" "Core Idea|core idea" "core idea extraction"
require_section "$AUD" "AskUserQuestion" "confirms idea + change request"
require_section "$AUD" "Gap Report|gap report" "gap report vs gates"
require_section "$AUD" "Extension" "extension candidates"
require_section "$AUD" "baseline-prd" "baseline PRD output"
require_section "$AUD" "baseline:" "baseline recorded in config"
require_section "$AUD" "accepted exception|never change" "bundle id preserved"
require_section "$AUD" "next_role: plan" "state update"
require_section "$AUD" "\.maestro/flows" "baseline Maestro flows"

RES="$S/app-harness-research/SKILL.md"
require_section "$RES" "AskUserQuestion" "user query"
require_section "$RES" "4\.3" "App Store 4.3 spam/copycat check"
require_section "$RES" "4\.2|Minimum Functionality" "App Store 4.2 minimum-functionality check"
require_section "$RES" "auto_idea" "auto-idea handling"
require_section "$RES" "next_role" "state update"

PLAN="$S/app-harness-plan/SKILL.md"
require_section "$PLAN" "app_slug" "slug assignment"
require_section "$PLAN" "com\.<company>" "bundle id rule"
require_section "$PLAN" "Scope Guard|scope guard" "scope guard"
require_section "$PLAN" "lib/features/" "feature-first lib structure map"
require_section "$PLAN" "app_category" "store category decision"
require_section "$PLAN" "device_family" "device family decision"
require_section "$PLAN" "backend" "backend decision"
require_section "$PLAN" "user flow|User Flows|primary flow" "primary user flows"
require_section "$PLAN" "KEEP" "update mode: KEEP/CHANGE/NEW tags"
require_section "$PLAN" "locked" "update mode: core idea locked"

DES="$S/app-harness-design/SKILL.md"
require_section "$DES" "design_tokens" "design tokens spec"
require_section "$DES" "darkTheme|dark theme|dark mode" "light + dark theme"
require_section "$DES" "screen inventory|Screen inventory|Screen specs" "screen inventory"
require_section "$DES" "empty|error" "loading/empty/error state designs"
require_section "$DES" "adaptive_icon_foreground|safe zone" "Android adaptive icon guidance"
require_section "$DES" "Figma|Stitch" "optional external design source"
require_section "$DES" "next_role" "state update"
require_section "$DES" "Update mode" "update mode: extract existing design"

CON="$S/app-harness-contract/SKILL.md"
require_section "$CON" "flutter analyze" "analyze gate"
require_section "$CON" "flutter test" "test gate"
require_section "$CON" "app_config" "config centralization gate"
require_section "$CON" "AGREED" "agreed status"
require_section "$CON" "stub|TODO" "anti-stub gate"
require_section "$CON" "Platform-Robustness Gates" "robustness gates block"
for g in "R1 Async" "R2 Network" "R3 Lifecycle" "R4 Forms" "R5 App branding" "R6 Native" \
         "R7 Assets" "R8 Store graphics" "R9 Persistence" "R10 Accessibility" "R11 Test depth" "R12 Permissions"; do
  require_section "$CON" "$g" "gate $g"
done
require_section "$CON" "N/A" "conditional gates marked N/A"
require_section "$CON" "Update mode" "update mode section"
require_section "$CON" "### Regression" "update mode: regression criteria"
require_section "$CON" "baseline\\.analyze_issues" "update mode: baseline numbers"
require_section "$CON" "\.maestro/flows" "R11 Maestro device flows"

GEN="$S/app-harness-generator/SKILL.md"
require_section "$GEN" "flutter create" "scaffold step"
require_section "$GEN" "5a|5b|5c" "3 sub-phases"
require_section "$GEN" "HARD GATE" "per-subphase gate"
require_section "$GEN" "handoff" "handoff output"
require_section "$GEN" "feedback" "feedback intake on round>1"
require_section "$GEN" "git init" "generated app git init + atomic commits"
require_section "$GEN" "checkpoint" "sub-phase checkpoints (resilience)"
require_section "$GEN" "already exists|Idempotency" "flutter-create idempotency guard"
require_section "$GEN" "app-gotchas" "generator cites gotchas"
require_section "$GEN" "flutter_riverpod" "riverpod dependency"
require_section "$GEN" "ProviderScope" "riverpod root"
require_section "$GEN" "go_router|GoRouter" "router"
require_section "$GEN" "lib/features/" "feature-first layout"
require_section "$GEN" "app_config\.dart" "constants centralization"
require_section "$GEN" "AsyncValue" "async UI states"
require_section "$GEN" "Repository|repository" "repository layer"
require_section "$GEN" "AppLifecycleListener|WidgetsBindingObserver" "lifecycle hook"
require_section "$GEN" "flutter_launcher_icons" "branding: launcher icons"
require_section "$GEN" "adaptive_icon_foreground" "branding: Android adaptive foreground"
require_section "$GEN" "adaptive_icon_monochrome" "branding: Android 13+ themed icon"
require_section "$GEN" "flutter_native_splash" "branding: native splash"
require_section "$GEN" "CFBundleDisplayName|android:label" "branding: display name"
require_section "$GEN" "UISupportedInterfaceOrientations" "native: orientation"
require_section "$GEN" "TARGETED_DEVICE_FAMILY" "native: device family"
require_section "$GEN" "ITSAppUsesNonExemptEncryption" "native: export compliance"
require_section "$GEN" "PopScope" "native: root back-button"
require_section "$GEN" "PRODUCT_BUNDLE_IDENTIFIER.*applicationId|byte-for-byte" "bundle id identical both platforms"
require_section "$GEN" "ci\.yml" "ci workflow"
require_section "$GEN" "gitignore\.template" "uses gitignore template"
require_section "$GEN" "pubspec\.lock" "commits pubspec.lock"
require_section "$GEN" "README\.md\.template" "README step"
require_section "$GEN" "LICENSE" "LICENSE step"
require_section "$GEN" "integration_test" "integration-test scaffold (no-Maestro fallback)"
require_section "$GEN" "maestro/flow\.yaml\.template" "Maestro device flows"
require_section "$GEN" "model: opus" "escalates a repeat failure"
require_section "$GEN" "test_unit\.dart\.template" "unit-test scaffold"
require_section "$GEN" "Semantics|tooltip" "accessibility baseline"
require_section "$GEN" "textScaler|text scal" "honors text scaling"
require_section "$GEN" "flutter_secure_storage" "secrets in secure storage"
require_section "$GEN" "Update mode" "update mode section"
require_section "$GEN" "harness/<YYYYMMDD>-update" "update mode: works on a branch"
require_section "$GEN" "config\\.architecture" "update mode: follows existing architecture"
require_section "$GEN" "baseline\\.analyze_issues" "update mode: baseline-relative analyze gate"

EVA="$S/app-harness-evaluator/SKILL.md"
require_section "$EVA" "Run the|run the app|see the app" "run-then-judge rule"
require_section "$EVA" "review alone|code review alone" "no code-review-only pass"
require_section "$EVA" "automatic FAIL" "stub auto-fail"
require_section "$EVA" "max_rounds" "forced judgment"
require_section "$EVA" "strict" "strict-mode phases"
require_section "$EVA" "auto_deploy" "post-QA review gate"
require_section "$EVA" "AsyncValue|ErrorView|error state" "R1 async-state check"
require_section "$EVA" "restart|relaunch" "persistence-across-restart check"
require_section "$EVA" "withNoTextScaling" "R10 text-scaling check"
require_section "$EVA" "integration_test" "R11 test-depth check"
require_section "$EVA" "suite\.sh" "runs the Maestro suite every round"
require_section "$EVA" "regress_r" "device bugs become regression flows"
require_section "$EVA" "never fixes|reports, it never" "evaluator does not edit app code"
require_section "$EVA" "Independent review" "fresh-context diff review"
require_section "$EVA" "four device roles" "strict device roles never share a device"
require_section "$EVA" "skip_monetize" "skip-monetize branch"
require_section "$EVA" "Update mode" "update mode section"
require_section "$EVA" "regression walk" "update mode: KEEP-flow regression walk"
require_section "$EVA" "Upgrade data check" "update mode: pre-update data still loads"
require_section "$EVA" "build\\.gradle\\.kts android/app/build\\.gradle" "bundle id check covers Groovy gradle"

STA="$S/app-harness-status/SKILL.md"
require_section "$STA" "read-only|state\.md" "status reads state"
RSM="$S/app-harness-resume/SKILL.md"
require_section "$RSM" "rate_limit" "rate_limit resume"
require_section "$RSM" "manual_action" "manual_action resume"
require_section "$RSM" "monetize" "resume knows monetize role"

MON="$S/app-harness-monetize/SKILL.md"
require_section "$MON" "banner" "banner format"
require_section "$MON" "native" "native format"
require_section "$MON" "interstitial" "interstitial format"
require_section "$MON" "app.open|app_open|AppOpenAd" "app-open format"
require_section "$MON" "rewarded" "rewarded format"
require_section "$MON" "frequency cap|cooldown" "ad frequency capping"
require_section "$MON" "ATT|UMP|consent" "ATT/UMP consent"
require_section "$MON" "lproj/InfoPlist\.strings" "ATT string localized per locale"
require_section "$MON" "AskUserQuestion" "asks user about IAP"
require_section "$MON" "in_app_purchase" "IAP package"
require_section "$MON" "Restore" "restore purchases"
require_section "$MON" "monetization\.iap|iap:" "records iap decision"
require_section "$MON" "skip_monetize" "skip flag"
require_section "$MON" "next_role" "state update"
require_section "$MON" "Update mode" "update mode: keep existing ad units/products"

BLD="$S/app-harness-build/SKILL.md"
require_section "$BLD" "key\.properties" "android signing setup"
require_section "$BLD" "Appfile|Fastfile" "fastlane config generation"
require_section "$BLD" "TestFlight|testflight" "ios upload"
require_section "$BLD" "internal" "android internal track"
require_section "$BLD" "app_category|play_category" "category from config"
require_section "$BLD" "next_role" "state update"
require_section "$BLD" "mode: update" "update mode: reuse signing, bump version name"

SHOT="$S/app-harness-screenshot/SKILL.md"
require_section "$SHOT" "integration_test" "integration test harness"
require_section "$SHOT" "locale" "per-locale capture"
require_section "$SHOT" "keywords" "ASO keywords"
require_section "$SHOT" "screenshots_prune" "duplicate screenshot cleanup"
require_section "$SHOT" "onScreenshot" "driver screenshot callback"
require_section "$SHOT" "alpha remove|hasAlpha" "working alpha-strip recipe"
require_section "$SHOT" "len\(sys\.stdin\.read\(\)\)|wc -m" "character-count check"
require_section "$SHOT" "featureGraphic" "play feature graphic"
require_section "$SHOT" "icon\.png|512" "play hi-res icon"
require_section "$SHOT" "device_family|iPad" "iPad screenshots when universal"
require_section "$SHOT" "demo data|seed" "seeded demo data for capture"
require_section "$SHOT" "mode: update" "update mode: recapture only changed UI"

SUB="$S/app-harness-submit/SKILL.md"
require_section "$SUB" "metadata" "metadata upload"
require_section "$SUB" "manual_action|paused" "manual pause"
require_section "$SUB" "Submit for Review|production" "manual submit steps"
require_section "$SUB" "retro" "resume target"
require_section "$SUB" "review_information|review-information" "ios app review contact"
require_section "$SUB" "UsageDescription" "localized permission-string check"
require_section "$SUB" "copyright" "copyright metadata"
require_section "$SUB" "set_contact_details|contact_email" "android contact details"
require_section "$SUB" "App Privacy|Data Safety" "store privacy/data-safety profile"
require_section "$SUB" "app_category|play_category" "category from config"
require_section "$SUB" "demo account" "review demo account when login"
require_section "$SUB" "mode: update" "update mode: release notes, keep listing"

RET="$S/app-harness-retro/SKILL.md"
require_section "$RET" "principle" "harness principles"
require_section "$RET" "Generator.*Evaluator|generator-evaluator" "generator-evaluator principle"
require_section "$RET" "retro\.md" "retro output"
require_section "$RET" "completed" "completion state"

# 5. Templates
for t in ci.yml save_repository.dart README.md LICENSE test_unit.dart widget_test.dart \
         integration_test.dart screenshots_test.dart gen_icon.dart gitignore key.properties \
         set_contact_details.rb; do
  [ -f "$ROOT/templates/$t.template" ] || err "missing templates/$t.template"
done
grep -q "icon-fg.png" "$ROOT/templates/gen_icon.dart.template" || err "gen_icon template must emit icon-fg.png"
grep -q "icon-mono.png" "$ROOT/templates/gen_icon.dart.template" || err "gen_icon template must emit icon-mono.png"
grep -q "ProviderContainer\|ProviderScope" "$ROOT/templates/test_unit.dart.template" || err "test_unit template must use Riverpod ProviderContainer"
grep -q "ProviderScope" "$ROOT/templates/widget_test.dart.template" || err "widget_test template must wrap in ProviderScope"
for t in suite.sh ready.yaml flow.yaml; do
  [ -f "$ROOT/templates/maestro/$t.template" ] || err "missing templates/maestro/$t.template"
done
bash -n "$ROOT/templates/maestro/suite.sh.template" 2>/dev/null || err "templates/maestro/suite.sh.template: bash syntax error"
grep -q "Device test suite" "$PROTO" || err "harness-protocol.md missing Device test suite section"
grep -q "Model Routing" "$PROTO" || err "harness-protocol.md missing §8 Model Routing"

# 6. Contributor infra
[ -f "$ROOT/.github/workflows/validate.yml" ] || err "missing .github/workflows/validate.yml"
for f in SECURITY.md CONTRIBUTING.md CHANGELOG.md README.md CLAUDE.md .github/pull_request_template.md \
         .github/ISSUE_TEMPLATE/bug_report.md .github/ISSUE_TEMPLATE/feature_request.md; do
  [ -f "$ROOT/$f" ] || err "missing $f"
done

# 7. No upstream author identity / credential IDs leaked (credit lines in LICENSE/README allowed).
LEAK=$(grep -rnE 'gonigon|tjdrhs90@gmail|8DHJJJ66LY|339MZ7CUZ5|f9a69502-1e93' "$ROOT" \
        --exclude-dir=.git 2>/dev/null | grep -vE '/LICENSE:|/README\.md:|/scripts/validate\.sh:' || true)
[ -z "$LEAK" ] || err "identity/credential leaked into tracked files: $LEAK"

# 8. Residual game terms — this is an app harness. Only the pointer to the upstream game harness
#    (flutter-flame-harness) is allowed.
RESID=$(grep -rniE 'flame|sprite|gameplay|game_config|FlameGame|enemy|enemies|revive|game.?over|high.?score|\bplayer\b|\bgames?\b' \
          "$ROOT/skills" "$ROOT/docs" "$ROOT/templates" "$ROOT/hooks" 2>/dev/null \
        | grep -viE 'flutter-flame-harness|\bGAMES\b category|media player|video player|audio player' || true)
[ -z "$RESID" ] || { echo "$RESID" | head -40; err "residual game terms in skills/docs/templates/hooks (see above)"; }

# 9. No stale skill names
STALE=$(grep -rnE 'flame-harness-|/flame-harness|skip_admob|skip-admob|admob\.ad_units|game-gotchas' \
          "$ROOT/skills" "$ROOT/docs" "$ROOT/templates" "$ROOT/hooks" "$ROOT/scripts/test-hook.sh" 2>/dev/null || true)
[ -z "$STALE" ] || { echo "$STALE" | head -20; err "stale flame-harness names / admob keys (see above)"; }

[ "$fail" -eq 0 ] && echo "validate: OK" || exit 1
