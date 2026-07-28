#!/usr/bin/env bash
# Runs every suite in tests/ and tests/ui/ and reports one line per suite.
# Suites print different success lines — PASSED, "N tests passed", PASS, WRITTEN —
# so success is decided by the exit code, with the last output line for context.
set -u

GODOT="${GODOT:-/c/Users/SZHerio/AppData/Local/Temp/godot-runner-bin-019f89fa/godot.windows.opt.tools.64.exe}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGDIR="${1:-/tmp/homeless_test_run}"
mkdir -p "$LOGDIR"

cd "$ROOT" || exit 1
if [ ! -x "$GODOT" ]; then
  echo "Godot not found at $GODOT — set GODOT=<path> and run again." >&2
  exit 2
fi

passed=0
failed=0
failed_names=()

for path in tests/*.gd tests/ui/*.gd; do
  name="$(basename "$path" .gd)"
  case "$name" in
    _*) continue ;;
  esac
  # Shared helpers are not suites: they never start a SceneTree and never exit.
  grep -q "extends SceneTree" "$path" || continue
  log="$LOGDIR/$name.log"
  # Visual references capture real frames: they need a rendering device, so
  # they are the one group that must not run headless.
  case "$name" in
    *_visual_reference) display="" ;;
    *) display="--headless" ;;
  esac
  timeout 1800 "$GODOT" $display --path . --script "res://$path" > "$log" 2>&1
  code=$?
  last="$(grep -v '^$' "$log" | tail -1)"
  if [ "$code" -eq 0 ]; then
    passed=$((passed + 1))
    printf 'OK    %-42s %s\n' "$name" "$last"
  else
    failed=$((failed + 1))
    failed_names+=("$name")
    printf 'FAIL  %-42s exit=%s %s\n' "$name" "$code" "$last"
  fi
done

echo "----"
echo "suites passed: $passed, failed: $failed"
if [ "$failed" -gt 0 ]; then
  echo "failing suites:"
  for n in "${failed_names[@]}"; do echo "  - $n"; done
fi
exit "$failed"
