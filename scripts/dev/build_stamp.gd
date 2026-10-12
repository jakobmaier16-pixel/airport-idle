class_name BuildStamp
extends RefCounted
## Which export is running: the stamp written by tools/export_ios.sh ("commit · time"),
## or "dev" when running from the editor or a plain Godot run.

const DEV: String = "dev"
## Written by tools/export_ios.sh; missing when running from the editor.
const PATH: String = "res://build_info.gd"


static func text() -> String:
	if not ResourceLoader.exists(PATH):
		return DEV
	var info := load(PATH) as GDScript
	return info.get_script_constant_map().get("TEXT", DEV)
