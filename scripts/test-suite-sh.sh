#!/usr/bin/env bash
# templates/maestro/suite.sh.template against stub maestro / xcrun / adb: flow selection, exit code,
# per-platform APP_ID, screenshot copy, setting restore.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
APP="$T/app"; export CALLS="$T/calls"
mkdir -p "$APP/.maestro/flows" "$APP/docs/harness" "$T/bin"
cp "$ROOT/templates/maestro/suite.sh.template" "$APP/.maestro/suite.sh"
printf 'appId: ${APP_ID}\ntags:\n  - flow\n  - ui    # main screen\n---\n- assertVisible: "ok"\n' > "$APP/.maestro/flows/F1_home.yaml"
printf 'appId: ${APP_ID}\ntags:\n  - flow\n---\n- assertVisible: "FAILME"\n' > "$APP/.maestro/flows/F2_edit.yaml"

cat > "$T/bin/xcrun" <<'EOF'
#!/usr/bin/env bash
echo "xcrun $*" >> "$CALLS"
case "$*" in
  "simctl list devices") echo "    iPhone 17 (SIM1) (Booted)" ;;
  "simctl ui SIM1 appearance") echo light ;;
  *"log stream"*) echo "Df Runner[42:7] [com.acme.demo] started"; exec sleep 30 ;;
esac
EOF
cat > "$T/bin/adb" <<'EOF'
#!/usr/bin/env bash
echo "adb $*" >> "$CALLS"
case "$*" in
  *"logcat -v brief"*) echo "I/ActivityManager( 1): Start proc 9:com.acme.demo.old/u0a1"; exec sleep 30 ;;
esac
EOF
cat > "$T/bin/maestro" <<'EOF'
#!/usr/bin/env bash
echo "maestro $*" >> "$CALLS"
prev=""; for a in "$@"; do [ "$prev" = --test-output-dir ] && out=$a; prev=$a; flow=$a; done
n=$(basename "$flow" .yaml); mkdir -p "$out/2026-01-01_000000/$n/takeScreenshot"
: > "$out/2026-01-01_000000/$n/takeScreenshot/$n-shot.png"
! grep -q FAILME "$flow"
EOF
chmod +x "$T/bin/"* "$APP/.maestro/suite.sh"
run() { : > "$CALLS"; set +e; PATH="$T/bin:$PATH" "$APP/.maestro/suite.sh" "$@" > "$T/out" 2>&1; rc=$?; set -e; }
fail() { echo "FAIL: $1"; cat "$T/out"; exit 1; }

printf 'bundle_id: "com.acme.demo"  # id\nbundle_id_android: ""\n' > "$APP/docs/harness/config.md"
run SIM1 r1-ios
[ "$rc" -eq 1 ] || fail "light: exit code should be 1 failed flow, got $rc"
grep -q 'F2_edit.yaml' "$CALLS" && grep -q 'F1_home.yaml' "$CALLS" || fail "light must run every flow"
grep -q -- '-e APP_ID=com.acme.demo ' "$CALLS" || fail "iOS APP_ID must be bundle_id"
[ -f "$APP/docs/harness/screenshots/r1-ios-F1_home-shot.png" ] || fail "screenshot not copied"
grep -q 'FAIL log' "$T/out" && fail "log with an app line reported as broken"
echo "PASS: light runs all flows, counts failures, copies screenshots"

run SIM1 r1-ios-dark dark
[ "$rc" -eq 0 ] || fail "dark: only the ui flow should run, got exit $rc"
grep -q 'F2_edit.yaml' "$CALLS" && fail "dark ran a flow not tagged ui"
grep -q 'simctl ui SIM1 appearance dark' "$CALLS" && grep -q 'simctl ui SIM1 appearance light' "$CALLS" \
  || fail "dark must set and restore the appearance"
echo "PASS: dark runs only ui flows and restores the appearance"

printf 'bundle_id: com.acme.demo\nbundle_id_android: "com.acme.demo.old"\n' > "$APP/docs/harness/config.md"
run emulator-5554 r1-android
grep -q -- '-e APP_ID=com.acme.demo.old ' "$CALLS" || fail "Android APP_ID must be bundle_id_android"
grep -q 'FAIL log' "$T/out" && fail "Android log with the app's process reported as broken"
echo "PASS: Android uses bundle_id_android"

run SIM1 r1-ios bogus
[ "$rc" -eq 64 ] || fail "unknown mode must exit 64"
echo "PASS: unknown mode rejected"
