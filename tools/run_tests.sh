#!/bin/sh
# Runs every automated walkthrough test (tests/cases/) headless.
# Exit code 0 = all passed. Any failed check, engine error or memory leak counts as a failure.
# Usage: tools/run_tests.sh            all tests
#        tools/run_tests.sh --only=save   only tests whose name contains "save"
# Set GODOT to use another Godot binary (cloud agents and CI use the Linux build from
# tools/setup_cloud.sh). Set TESTS_QUIET=1 to print only failures and the result line:
# agents use it to keep the output short.
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
LOG=$(mktemp "${TMPDIR:-/tmp}/airport_tests.XXXXXX")

"$GODOT" --headless --path . --import > /dev/null 2>&1
# perl's alarm is a timeout (macOS has no `timeout` command): a hanging test can't block forever.
perl -e 'alarm shift; exec @ARGV' 600 "$GODOT" --headless --path . res://tests/test_runner.tscn -- --no-save "$@" > "$LOG" 2>&1
CODE=$?

if [ "$TESTS_QUIET" = "1" ]; then
	grep -E "^(FAIL|  - |RESULT)" "$LOG"
else
	grep -E "^(PASS|FAIL|  - |INFO|RESULT)" "$LOG"
fi
if grep -qE "SCRIPT ERROR|^ERROR|leaked" "$LOG"; then
	echo "Engine errors or leaks:"
	grep -E -A2 "SCRIPT ERROR|^ERROR|leaked" "$LOG"
	CODE=1
fi
if ! grep -q "^RESULT" "$LOG"; then
	echo "Tests did not finish (crash or timeout). Last output:"
	tail -20 "$LOG"
	CODE=1
fi
rm -f "$LOG"
exit $CODE
