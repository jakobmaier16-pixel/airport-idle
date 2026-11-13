#!/bin/sh
# Prints the behaviour hash of the simulation (scripts/dev/behaviour_hash.gd): run it before and
# after a refactor; the two lines must be equal.
# Usage: GODOT=$(tools/setup_cloud.sh) tools/behaviour_hash.sh
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
"$GODOT" --headless --path . --import > /dev/null 2>&1
"$GODOT" --headless --path . res://scripts/dev/behaviour_hash_cli.tscn -- --no-save 2>&1 | grep -E "^BEHAVIOUR_HASH|ERROR"
