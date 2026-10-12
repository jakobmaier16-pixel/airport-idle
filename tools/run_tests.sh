#!/bin/sh
# Runs every automated walkthrough test (tests/cases/) headless.
# Exit code 0 = all passed. Any failed check, engine error or memory leak counts as a failure.
# Usage: tools/run_tests.sh            all tests
#        tools/run_tests.sh --only=save   only tests whose name contains "save"
cd "$(dirname "$0")/.."
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
LOG=$(mktemp -t airport_tests)

"$GODOT" --headless --path . --import > /dev/null 2>&1
# perl's alarm is a timeout (macOS has no `timeout` command): a hanging test can't block forever.
perl -e 'alarm shift; exec @ARGV' 300 "$GODOT" --headless --path . res://tests/test_runner.tscn -- --no-save "$@" > "$LOG" 2>&1
CODE=$?

grep -E "^(PASS|FAIL|  - |INFO|RESULT)" "$LOG"
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
