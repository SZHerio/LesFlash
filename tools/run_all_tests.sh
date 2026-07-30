#!/usr/bin/env bash
# Compatibility entry point for the complete technical suite. The real runner
# owns verdict parsing and, on Windows, serializes every Godot process through
# tools/run_godot_test.ps1 so native crash/JIT windows cannot multiply.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/c/Users/SZHerio/AppData/Local/Temp/godot-runner-bin-019f89fa/godot.windows.opt.tools.64.exe}"

exec "$ROOT/tools/run_tests.sh" --gate "$GODOT"
