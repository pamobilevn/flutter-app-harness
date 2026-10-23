#!/usr/bin/env bash
set -euo pipefail
# state.md lives in ./docs/harness until the generator moves it into ./<app_slug>/docs/harness.
# Only a RUNNING run is paused: completed runs and manual_action / error pauses stay as they are.
STATE="$(grep -l '^status:[[:space:]]*running' docs/harness/state.md $(ls -t ./*/docs/harness/state.md 2>/dev/null) 2>/dev/null | head -1 || true)"
[ -n "$STATE" ] || exit 0           # no running harness here
payload="$(cat 2>/dev/null || true)"
# 429 only as a standalone number — session ids / paths are hex and can contain "429".
echo "$payload" | grep -qiE 'rate.?limit|(^|[^0-9a-z])429([^0-9a-z]|$)' || exit 0
now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
phase="$(sed -n 's/^current_phase:[[:space:]]*//p' "$STATE" | head -1)"
# mark paused (portable sed); updated_at is what resume measures the rate-limit wait from
tmp="$(mktemp)"
sed -e 's/^status:.*/status: paused/' \
    -e 's/^pause_reason:.*/pause_reason: rate_limit/' \
    -e "s/^updated_at:.*/updated_at: \"$now\"/" "$STATE" > "$tmp" && mv "$tmp" "$STATE"
grep -q '^status:' "$STATE" || printf 'status: paused\n' >> "$STATE"
grep -q '^pause_reason:' "$STATE" || printf 'pause_reason: rate_limit\n' >> "$STATE"
printf '| %s | pause | %s | rate_limit |\n' "$now" "${phase:--}" >> "$(dirname "$STATE")/pipeline-log.md" 2>/dev/null || true
command -v osascript >/dev/null && osascript -e 'display notification "app-harness paused (rate limit)"' 2>/dev/null || true
exit 0
