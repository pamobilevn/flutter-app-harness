#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; cd "$tmp"
# no state.md → hook must exit 0 silently
out=$(echo '{"reason":"429 rate limit"}' | bash "$ROOT/hooks/stop-failure-handler.sh"); rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: no-state should exit 0 (got $rc)"; exit 1; }
[ -z "$out" ] || { echo "FAIL: no-state should be silent (got: $out)"; exit 1; }
echo "PASS: no-state silent exit 0"
# with state.md + rate limit → must set paused
mkdir -p docs/harness; printf 'status: running\ncurrent_phase: generator\npause_reason: ""\nupdated_at: "2000-01-01T00:00:00Z"\n' > docs/harness/state.md
echo '{"reason":"429 rate limit reached"}' | bash "$ROOT/hooks/stop-failure-handler.sh" || true
grep -q 'status: paused' docs/harness/state.md && echo "PASS: paused set" || { echo "FAIL: not paused"; exit 1; }
grep -q 'updated_at: "2000' docs/harness/state.md && { echo "FAIL: updated_at not refreshed"; exit 1; } || echo "PASS: updated_at refreshed"
grep -q '| pause | generator | rate_limit |' docs/harness/pipeline-log.md && echo "PASS: log row names the phase" || { echo "FAIL: log row phase"; exit 1; }
grep -q 'pause_reason: rate_limit' docs/harness/state.md && echo "PASS: reason set" || { echo "FAIL: reason"; exit 1; }
# state.md moved into the generated project (<app_slug>/docs/harness) → still found
rm -rf docs; mkdir -p my-app/docs/harness; printf 'status: running\npause_reason: ""\n' > my-app/docs/harness/state.md
echo '{"reason":"429 rate limit reached"}' | bash "$ROOT/hooks/stop-failure-handler.sh" || true
grep -q 'status: paused' my-app/docs/harness/state.md && echo "PASS: nested state paused" || { echo "FAIL: nested state not paused"; exit 1; }
# completed run / manual_action pause → never touched by a rate limit
printf 'status: completed\npause_reason: ""\n' > my-app/docs/harness/state.md
echo '{"reason":"429 rate limit reached"}' | bash "$ROOT/hooks/stop-failure-handler.sh" || true
grep -q 'status: completed' my-app/docs/harness/state.md && echo "PASS: completed run untouched" || { echo "FAIL: completed run paused"; exit 1; }
printf 'status: paused\npause_reason: manual_action\n' > my-app/docs/harness/state.md
echo '{"reason":"429 rate limit reached"}' | bash "$ROOT/hooks/stop-failure-handler.sh" || true
grep -q 'pause_reason: manual_action' my-app/docs/harness/state.md && echo "PASS: manual_action kept" || { echo "FAIL: manual_action overwritten"; exit 1; }
# "429" inside a session id is not a rate limit
printf 'status: running\npause_reason: ""\n' > my-app/docs/harness/state.md
echo '{"session_id":"7f3a429b-1c2d","reason":"network error"}' | bash "$ROOT/hooks/stop-failure-handler.sh" || true
grep -q 'status: running' my-app/docs/harness/state.md && echo "PASS: 429 inside an id ignored" || { echo "FAIL: id with 429 paused the run"; exit 1; }
# non-rate-limit failure → untouched
printf 'status: running\npause_reason: ""\n' > my-app/docs/harness/state.md
echo '{"reason":"network error"}' | bash "$ROOT/hooks/stop-failure-handler.sh" || true
grep -q 'status: running' my-app/docs/harness/state.md && echo "PASS: non-rate-limit ignored" || { echo "FAIL: non-rate-limit changed state"; exit 1; }
