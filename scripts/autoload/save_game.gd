extends Node
## Saves and loads the airport automatically (design doc §5), registered as the autoload "SaveGame".
## Loads at startup; saves shortly after every change and right away when the app goes to the
## background or closes. There is no manual save.
## Test builds: the first start after a new export loads the showcase airport instead
## (see ShowcaseAirport), so the newest features are ready to try without building by hand.

## Bump when the save format changes in a way older code can't read.
const FORMAT_VERSION: int = 1
## Wait this long after a change before saving, so a burst of changes is saved once.
const SAVE_DELAY: float = 1.0
## Money and the running airport are also saved this often while playing (seconds).
const AUTOSAVE_INTERVAL: float = 30.0
## Offline income (design doc §5): nothing for shorter breaks; after this many hours away the
## player gets OFFLINE_BONUS_HOURS of the airport's average profit once.
const OFFLINE_MIN_HOURS: float = 36.0
const OFFLINE_BONUS_HOURS: float = 4.0
## Command-line flag (after "--") that turns saving and loading off, for automated tests:
## Godot --headless --path . res://test.tscn -- --no-save
const NO_SAVE_FLAG: String = "--no-save"

var enabled: bool = true
## Where the game is saved. Tests point this at a separate file.
var save_path: String = "user://savegame.json"
## The running export (see BuildStamp), stored in the save to detect the first start after an update.
var build_stamp: String = BuildStamp.DEV

## Set when loading after a long break: the bonus paid and how long the player was away
## (main.gd shows a welcome-back notice).
var welcome_back_bonus: float = 0.0
var away_seconds: float = 0.0

# Stamp of the export that wrote the loaded save.
var _saved_build: String = ""
var _autosave_in: float = AUTOSAVE_INTERVAL

var _dirty: bool = false
var _time_until_save: float = 0.0
var _loading: bool = false


func _ready() -> void:
	enabled = not OS.get_cmdline_user_args().has(NO_SAVE_FLAG)
	build_stamp = BuildStamp.text()
	load_game()
	if enabled and OS.is_debug_build():
		load_showcase_if_new_build()
	Airport.layout_changed.connect(_on_airport_changed)


func _process(delta: float) -> void:
	_autosave_in -= delta
	if _autosave_in <= 0.0:
		_autosave_in = AUTOSAVE_INTERVAL
		save_now()
	if _dirty:
		_time_until_save -= delta
		if _time_until_save <= 0.0:
			save_now()


func _notification(what: int) -> void:
	# iOS can close a backgrounded app at any time without warning, so save when we get the chance.
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			# Always: the time of leaving counts for offline income, and money changes constantly.
			save_now()


func save_now() -> void:
	_dirty = false
	if not enabled:
		return
	var data := Airport.save_state()
	data["version"] = FORMAT_VERSION
	data["build"] = build_stamp
	data["saved_at"] = Time.get_unix_time_from_system()
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
	_saved_build = str(data.get("build", ""))
	_loading = true
	var skipped := Airport.load_state(data)
	_loading = false
	if skipped > 0:
		push_warning("%d saved buildings no longer fit and were skipped." % skipped)
	if data.has("saved_at"):
		apply_offline_time(Time.get_unix_time_from_system() - float(data["saved_at"]))


## Pays the welcome-back bonus if the player was away long enough (design doc §5).
## Returns the bonus (0 for shorter breaks).
func apply_offline_time(seconds_away: float) -> float:
	away_seconds = seconds_away
	welcome_back_bonus = 0.0
	if seconds_away < OFFLINE_MIN_HOURS * 3600.0:
		return 0.0
	welcome_back_bonus = maxf(Airport.economy.average_profit_per_minute, 0.0) * OFFLINE_BONUS_HOURS * 60.0
	Airport.economy.bonus(welcome_back_bonus)
	return welcome_back_bonus


## On the first start of a new export (test builds only), replaces the map with the showcase
## airport. Running from the editor ("dev") never does. Returns true if the showcase was loaded.
func load_showcase_if_new_build() -> bool:
	if build_stamp == BuildStamp.DEV or build_stamp == _saved_build:
		return false
	load_showcase()
	return true


## Replaces the map with the showcase airport and saves it. The caller reloads the scene
## if the game is already running, to rebuild the visuals.
func load_showcase() -> void:
	_loading = true
	ShowcaseAirport.build()
	_loading = false
	_saved_build = build_stamp
	save_now()


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
