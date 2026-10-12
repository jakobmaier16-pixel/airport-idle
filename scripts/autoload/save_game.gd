extends Node
## Saves and loads the airport automatically (design doc §5), registered as the autoload "SaveGame".
## Loads at startup; saves shortly after every change and right away when the app goes to the
## background or closes. There is no manual save.

## Bump when the save format changes in a way older code can't read.
const FORMAT_VERSION: int = 1
## Wait this long after a change before saving, so a burst of changes is saved once.
const SAVE_DELAY: float = 1.0
## Command-line flag (after "--") that turns saving and loading off, for automated tests:
## Godot --headless --path . res://test.tscn -- --no-save
const NO_SAVE_FLAG: String = "--no-save"

var enabled: bool = true
## Where the game is saved. Tests point this at a separate file.
var save_path: String = "user://savegame.json"

var _dirty: bool = false
var _time_until_save: float = 0.0
var _loading: bool = false


func _ready() -> void:
	enabled = not OS.get_cmdline_user_args().has(NO_SAVE_FLAG)
	load_game()
	Airport.layout_changed.connect(_on_airport_changed)


func _process(delta: float) -> void:
	if _dirty:
		_time_until_save -= delta
		if _time_until_save <= 0.0:
			save_now()


func _notification(what: int) -> void:
	# iOS can close a backgrounded app at any time without warning, so save when we get the chance.
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			if _dirty:
				save_now()


func save_now() -> void:
	_dirty = false
	if not enabled:
		return
	var data := Airport.save_state()
	data["version"] = FORMAT_VERSION
	# Write to a temporary file first, then swap it in, so a crash mid-save can't corrupt the save.
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write save game: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(save_path))


func load_game() -> void:
	if not enabled or not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary or int(data.get("version", 0)) != FORMAT_VERSION:
		push_warning("Save game is unreadable or from an incompatible version; starting fresh.")
		return
	_loading = true
	var skipped := Airport.load_state(data)
	_loading = false
	if skipped > 0:
		push_warning("%d saved buildings no longer fit and were skipped." % skipped)


## Deletes the save and clears the airport. The caller reloads the scene to rebuild the visuals.
func reset_game() -> void:
	Airport.reset()
	_dirty = false
	if enabled:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _on_airport_changed() -> void:
	if _loading:
		return
	_dirty = true
	_time_until_save = SAVE_DELAY
