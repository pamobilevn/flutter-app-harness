#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
for tpl in "$ROOT/templates/fastlane/ios-Fastfile.template" "$ROOT/templates/fastlane/android-Fastfile.template"; do
  [ -f "$tpl" ] || { echo "FAIL: missing $tpl"; fail=1; continue; }
  # substitute placeholders with dummy values (same set the build skill fills), then ruby -c
  rendered="$(sed -e 's/__APP_ID__/com.<company>.dummy/g' \
      -e 's/__APP_NAME__/Dummy/g' \
      -e 's/__IPA_NAME__/dummy.ipa/g' \
      -e 's/__PACKAGE__/com.<company>.dummy/g' \
      -e 's/__PROFILE_NAME__/com.<company>.dummy AppStore/g' \
      -e 's/__TEAM_ID__/TEAMID1234/g' \
      -e 's/__ASC_KEY_ID__/KEYID12345/g' \
      -e 's/__ASC_ISSUER_ID__/00000000-0000-0000-0000-000000000000/g' \
      -e 's/__APP_CATEGORY__/PRODUCTIVITY/g' "$tpl")"
  # every placeholder must be covered above (and by the build skill's sed)
  if printf '%s\n' "$rendered" | grep -nE '__[A-Z][A-Z_]*__'; then
    echo "FAIL: unsubstituted placeholder in $tpl"; fail=1
  fi
  printf '%s\n' "$rendered" | ruby -c 2>/dev/null | grep -q "Syntax OK" || { echo "FAIL: ruby syntax in $tpl"; fail=1; }
done
[ "$fail" -eq 0 ] && echo "validate-fastlane: OK" || exit 1
