#!/bin/sh
# Installs Blender as a Python module (bpy from PyPI) into a venv and prints the python path:
#   BPY=$(tools/setup_blender.sh) && "$BPY" art/<area>/<script>.py
# bpy supports exactly one Python version (3.11 for Blender 4.x/5.x), so uv fetches a matching one.
set -e
VENV=${BLENDER_VENV:-/tmp/blender-venv}
PY="$VENV/bin/python"
if ! "$PY" -c "import bpy" >/dev/null 2>&1; then
	command -v uv >/dev/null 2>&1 || pip install --quiet uv >&2
	uv venv --quiet --python 3.11 "$VENV" >&2
	uv pip install --quiet --python "$PY" bpy >&2
fi
echo "$PY"
