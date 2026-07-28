#!/usr/bin/env bash
# Runs every test suite without opening a window.
#
# Godot's --script mode creates a real window unless --headless is passed, and a
# suite that errors before reaching quit() leaves that window on screen with
# nothing in it. Headless removes the whole failure mode: nothing to close by
# hand, and the suites behave identically — UI suites included.
#
# Usage: tools/run_tests.sh [path-to-godot]
#        tools/run_tests.sh --gate     # also run the long week acceptance gate

set -u

GODOT="${GODOT:-godot}"
RUN_GATE=0
for argument in "$@"; do
	case "$argument" in
		--gate) RUN_GATE=1 ;;
		*) GODOT="$argument" ;;
	esac
done

if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "godot not found: $GODOT" >&2
	echo "pass the binary path, or set GODOT=/path/to/godot" >&2
	exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$(mktemp -d)"
passed=0
declare -a failed=()

run_suite() {
	local suite="$1"
	local name log
	name="$(basename "$suite" .gd)"
	log="$LOG_DIR/$name.log"
	# Redirect to a file rather than piping: Godot block-buffers stdout into a
	# pipe and the verdict is lost when the process exits.
	timeout 600 "$GODOT" --headless --path "$ROOT" --script "res://$suite" >"$log" 2>&1
	if grep -qiE "PASSED|tests passed|: PASS$|WRITTEN" "$log"; then
		passed=$((passed + 1))
	else
		failed+=("$suite")
		echo "FAIL $suite"
		grep -E "^  - |Parse Error|SCRIPT ERROR" "$log" | head -5
	fi
}

cd "$ROOT" || exit 2
for suite in tests/*.gd tests/ui/*.gd; do
	case "$suite" in
		*fixture*|*preview*|*integrity_suite*) continue ;;
		*m3f7_week_acceptance*) [ "$RUN_GATE" -eq 1 ] || continue ;;
	esac
	run_suite "$suite"
done

echo
echo "passed: $passed    failed: ${#failed[@]}"
if [ "${#failed[@]}" -gt 0 ]; then
	printf '  %s\n' "${failed[@]}"
	echo "logs: $LOG_DIR"
	exit 1
fi
rm -rf "$LOG_DIR"
