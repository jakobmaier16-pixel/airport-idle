#!/bin/sh
# Prints the asset viewer's numbered catalog (number | id | name | category | footprint | model size),
# so a number Jakob names ("No. 12") maps to an id for any commit.
# Usage: GODOT=$(tools/setup_cloud.sh) tools/viewer_catalog.sh
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
"$GODOT" --headless --path . --import > /dev/null 2>&1
LOG=$(mktemp "${TMPDIR:-/tmp}/viewer_catalog.XXXXXX")
"$GODOT" --headless --path . res://tools/viewer_catalog.tscn -- --no-save > "$LOG" 2>&1
CODE=$?
grep -E "^VIEWER|ERROR" "$LOG" | sed 's/^VIEWER //'
grep -q "^VIEWER total" "$LOG" || CODE=1
grep -q "^ERROR\|SCRIPT ERROR" "$LOG" && CODE=1
rm -f "$LOG"
exit $CODE
