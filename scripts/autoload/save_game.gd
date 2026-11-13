extends Node
## Saves and loads the airport automatically (design doc §5), registered as the autoload "SaveGame".
## Loads at startup; saves shortly after every change and right away when the app goes to the
## background or closes. There is no manual save.
## Test builds: the first start after a new export loads the showcase airport instead
## (see ShowcaseAirport), so the newest features are ready to try without building by hand.

## Bump when the save format changes in a way older code can't read, and add a converter to
## `migrations` for the old version (tech_architecture.md §13). Keep every old converter.
const FORMAT_VERSION: int = 9
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

## Converters for old saves: migrations[n] takes a version-n save (a Dictionary) and returns it as
## version n + 1. Loading runs them one after another, so a save is never thrown away for being old.
var migrations: Dictionary[int, Callable] = default_migrations()
## The version this build reads and writes. A variable only so tests can pretend to be a newer build.
var format_version: int = FORMAT_VERSION
## Why the save couldn't be loaded, for the player ("" if it loaded or there was none).
## main.gd shows it as a notice.
var load_problem: String = ""
## Where a save that couldn't be loaded was put aside ("" if none). It is never overwritten.
var backup_path: String = ""

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
	data["version"] = format_version
	data["build"] = build_stamp
	data["saved_at"] = Time.get_unix_time_from_system()
	# Write to a temporary file first, then swap it in, so a crash mid-save can't corrupt the save.
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write save game: %s" % error_string(FileAccess.get_open_error()))
		return
	# Full precision: the default writes ~14 digits, which would nudge times and money at every load.
	file.store_string(JSON.stringify(data, "", true, true))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(save_path))


func load_game() -> void:
	load_problem = ""
	backup_path = ""
	if not enabled or not FileAccess.file_exists(save_path):
		return
	# JSON.parse() (unlike JSON.parse_string()) reports a broken file quietly: it's handled below.
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(save_path)) == OK else null
	if not parsed is Dictionary or not (parsed as Dictionary).has("version"):
		_put_aside("unreadable", "Your saved airport couldn't be read. It was kept as a backup, and a new airport starts.")
		return
	var version := int(parsed["version"])
	if version > format_version:
		_put_aside("newer", "Your saved airport is from a newer version of the game. It was kept as a backup, and a new airport starts.")
		return
	var data := migrate(parsed)
	if data.is_empty():
		_put_aside("unconvertible", "Your saved airport couldn't be converted to this version. It was kept as a backup, and a new airport starts.")
		return
	_saved_build = str(data.get("build", ""))
	_loading = true
	var skipped := Airport.load_state(data)
	_loading = false
	if skipped > 0:
		push_warning("%d saved buildings no longer fit and were skipped." % skipped)
		# Nothing is lost silently: tell the player what was paid back.
		load_problem = "%d building(s) could not be restored (%s). %s was refunded." % [
			skipped, ", ".join(Airport.load_refunded), Economy.format(Airport.load_refund)]
	if data.has("saved_at"):
		apply_offline_time(Time.get_unix_time_from_system() - float(data["saved_at"]))


## Converts `data` from its version to `format_version`, one step at a time (tech_architecture.md
## §13). Returns the converted save, or an empty Dictionary if a converter is missing.
func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	while version < format_version:
		if not migrations.has(version):
			push_warning("No converter for save version %d." % version)
			return {}
		data = migrations[version].call(data)
		version += 1
		data["version"] = version
	return data


## The converters this build ships (tests put them back after swapping in their own).
func default_migrations() -> Dictionary[int, Callable]:
	return {1: _v1_to_v2, 2: _v2_to_v3, 3: _v3_to_v4, 4: _v4_to_v5, 5: _v5_to_v6, 6: _v6_to_v7, 7: _v7_to_v8, 8: _v8_to_v9}


## Version 1 -> 2: buildings get permanent IDs (their old list position + 1) and staff point to
## the ID instead of the list position (tech_architecture.md §13). Building types were already names.
func _v1_to_v2(data: Dictionary) -> Dictionary:
	var buildings: Array = data.get("buildings", [])
	for i in buildings.size():
		(buildings[i] as Dictionary)["id"] = i + 1
	data["next_building_id"] = buildings.size() + 1
	if data.has("staff"):
		for entry: Dictionary in data["staff"]:
			var index := int(entry.get("building", -1))
			entry["building_id"] = index + 1 if index >= 0 and index < buildings.size() else 0
			entry.erase("building")
	return data


## Version 3 -> 4: zones are computed from the layout (tech_architecture.md §4), so the painted
## zones ("zones") are dropped.
func _v3_to_v4(data: Dictionary) -> Dictionary:
	data.erase("zones")
	return data


## Version 4 -> 5: weather, security incidents, VIP visits and the first-landing cutscene were
## removed (2026-11-13), so their fields are dropped. A saved de-icing pad is not touched here: its
## building type is gone, so loading refunds it through the normal "type vanished" path (half the
## saved price, with a notice). Very old saves didn't store the price: the pad's last price is filled in.
const DEICING_PAD_PRICE: float = 7000.0


func _v4_to_v5(data: Dictionary) -> Dictionary:
	for key in ["weather", "next_incident_in", "next_vip_in"]:
		data.erase(key)
	for entry: Dictionary in data.get("buildings", []):
		entry.erase("closed")
		if entry.get("type") == "deicing_pad" and not entry.has("cost"):
			entry["cost"] = DEICING_PAD_PRICE
	var flow: Dictionary = data.get("flow", {})
	for entry: Dictionary in flow.get("schedule", {}).get("flights", []):
		for key in ["vip_pending", "weather_delay", "deiced"]:
			entry.erase(key)
	for entry: Dictionary in flow.get("passengers", []):
		entry.erase("vip")
	for entry: Dictionary in data.get("airlines", {}).get("signed", []):
		entry.erase("first_landing")
	return data


## Version 5 -> 6: the passengers are saved as one compressed block (see PassengerSave) with their
## paths as grid cells. The old list is packed; paths are turned from positions into cells of the
## saved map size, and only the part still ahead is kept.
func _v5_to_v6(data: Dictionary) -> Dictionary:
	var flow: Dictionary = data.get("flow", {})
	if flow.get("passengers") is Array:
		var map_size: Array = data.get("map_size", [AirportWorld.MAP_SIZE_CELLS.x, AirportWorld.MAP_SIZE_CELLS.y])
		var size := Vector2i(int(map_size[0]), int(map_size[1]))
		var records := PassengerSave.from_v5(flow["passengers"], size, AirportWorld.CELL_SIZE)
		flow["passengers"] = PassengerSave.encode(records, size.x)
	return data


## Version 6 -> 7: one clock (tech_architecture.md §3). The passengers' own timer ("flow"/"time",
## real seconds) is gone; the brain's clock now carries it as "clock_elapsed", in game seconds
## (time x 15). The times saved inside flights and passengers stay in real seconds
## for now, so they need no conversion.
func _v6_to_v7(data: Dictionary) -> Dictionary:
	var flow: Dictionary = data.get("flow", {})
	data["clock_elapsed"] = float(flow.get("time", 0.0)) * 15.0  # game seconds per real second, as it was then
	flow.erase("time")
	return data


## Version 7 -> 8: the daily timetable (tech_architecture.md §6). Its slots are built from the
## saved state: every flight that is already planned becomes a filled slot, and no day counts as
## planned, so the first step plans the rest of today (and tomorrow) with the saved dice.
func _v7_to_v8(data: Dictionary) -> Dictionary:
	var day := int(float(data.get("clock", Clock.START_HOUR * 3600.0)) / 86400.0) + 1
	var slots: Array = []
	for entry: Dictionary in data.get("flow", {}).get("schedule", {}).get("flights", []):
		if not bool(entry.get("scheduled", true)):
			continue
		var wide := bool(entry.get("wide_body", false))
		var cargo := bool(entry.get("cargo", false))
		var number := str(entry.get("number", ""))
		slots.append({
			"time": float(entry.get("departure_time", 0.0)), "day": day,
			"class": int(TimetableSlot.PlaneClass.CARGO) if cargo else (int(TimetableSlot.PlaneClass.WIDE) if wide else int(TimetableSlot.PlaneClass.NARROW)),
			"route": str(entry.get("route", "Holiday")), "seats": int(entry.get("seats", 0)),
			"state": int(TimetableSlot.State.FILLED), "airline": number.get_slice(" ", 0), "number": number,
		})
	data["timetable"] = {"generated_days": [], "slots": slots}
	return data


## Version 8 -> 9: walkways and taxiways are lists of non-empty 64 x 64 chunks (see GridSave)
## instead of one dense array over the whole map, so a save does not grow with the map.
func _v8_to_v9(data: Dictionary) -> Dictionary:
	var map_size: Variant = data.get("map_size", [AirportWorld.MAP_SIZE_CELLS.x, AirportWorld.MAP_SIZE_CELLS.y])
	var size := Vector2i(int(map_size[0]), int(map_size[1]))
	for key in ["walkways", "taxiways"]:
		if data.get(key) is String:
			data[key] = GridSave.from_dense(Marshalls.base64_to_raw(data[key]), size)
	return data


## Version 2 -> 3: flights and passengers on their way are saved (key "flow"). An older save has
## none: it starts with an empty apron, as every load did before. Nothing to convert.
func _v2_to_v3(data: Dictionary) -> Dictionary:
	return data


# Moves a save that can't be loaded out of the way, so the next autosave can't overwrite it.
func _put_aside(reason: String, message: String) -> void:
	backup_path = "%s.%s-%d.bak" % [save_path, reason, int(Time.get_unix_time_from_system())]
	DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(backup_path))
	load_problem = message
	push_warning("Save game put aside as %s: %s" % [backup_path, message])


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
