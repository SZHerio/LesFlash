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
	local name log display godot_for_ps wrapper_for_ps code
	name="$(basename "$suite" .gd)"
	log="$LOG_DIR/$name.log"
	# The visual reference suites save screenshots, and there is nothing to
	# capture without a window. They are the only suites that need one.
	display="--headless"
	case "$suite" in
		*_visual_reference.gd) display="" ;;
	esac
	# On Windows every invocation goes through the shared mutex/error-mode
	# wrapper. Several Codex agents used to launch the Steam editor binary at the
	# same time; four processes then hung in teardown and opened Visual Studio's
	# native JIT debugger. The wrapper also gives each process its own engine log.
	if command -v powershell.exe >/dev/null 2>&1 && [ -f "$ROOT/tools/run_godot_test.ps1" ]; then
		godot_for_ps="$GODOT"
		wrapper_for_ps="$ROOT/tools/run_godot_test.ps1"
		if command -v cygpath >/dev/null 2>&1; then
			godot_for_ps="$(cygpath -w "$GODOT")"
			wrapper_for_ps="$(cygpath -w "$wrapper_for_ps")"
		fi
		if [ -n "$display" ]; then
			powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$wrapper_for_ps" \
				-Suite "$suite" -Godot "$godot_for_ps" -TimeoutSeconds 600 >"$log" 2>&1
		else
			powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$wrapper_for_ps" \
				-Suite "$suite" -Godot "$godot_for_ps" -TimeoutSeconds 600 -Windowed >"$log" 2>&1
		fi
		code=$?
	else
		# Non-Windows fallback. Redirect to a file rather than piping: Godot
		# block-buffers stdout into a pipe and the verdict can be lost on exit.
		timeout 600 "$GODOT" $display --path "$ROOT" --log-file "$log.godot" \
			--script "res://$suite" >"$log" 2>&1
		code=$?
	fi
	if [ "$code" -eq 0 ] && grep -qiE "PASSED|tests passed|: PASS$|WRITTEN" "$log"; then
		passed=$((passed + 1))
	else
		failed+=("$suite")
		echo "FAIL $suite (exit=$code)"
		grep -E "^  - |Parse Error|SCRIPT ERROR" "$log" | head -5
	fi
}

cd "$ROOT" || exit 2
for suite in tests/*.gd tests/ui/*.gd; do
	case "$suite" in
		# Замеры печатают таблицы, а не вердикт: они инструмент для разбора
		# поломки, и считать их провалом за отсутствие слова PASSED неправильно.
		*fixture*|*preview*|*integrity_suite*|*_probe.gd) continue ;;
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
