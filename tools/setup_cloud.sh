#!/bin/sh
# Downloads the Linux build of Godot so the walkthrough tests can run without the Mac
# (cloud agents and GitHub Actions). Prints the path of the binary; use it like this:
#   GODOT=$(tools/setup_cloud.sh) TESTS_QUIET=1 tools/run_tests.sh
# The version must match the one in CLAUDE.md (export templates and the Mac editor).
set -e
VERSION=4.7.2-stable
DIR=${GODOT_DIR:-/tmp/godot-$VERSION}
BIN="$DIR/Godot_v${VERSION}_linux.x86_64"
if [ ! -x "$BIN" ]; then
	mkdir -p "$DIR"
	curl -sSL -o "$DIR/godot.zip" \
		"https://github.com/godotengine/godot/releases/download/$VERSION/Godot_v${VERSION}_linux.x86_64.zip"
	unzip -oq "$DIR/godot.zip" -d "$DIR"
	rm -f "$DIR/godot.zip"
fi
echo "$BIN"
