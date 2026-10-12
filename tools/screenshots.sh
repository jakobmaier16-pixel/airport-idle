#!/bin/sh
# Renders standard screenshots of the reference airport into build/screenshots/ (ignored by Git),
# to check the look after visual changes. Opens a game window for a few seconds.
cd "$(dirname "$0")/.."
mkdir -p build/screenshots
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tests/screenshots.tscn -- --no-save 2>&1 | grep -E "SCRIPT ERROR|^ERROR|Saved"
