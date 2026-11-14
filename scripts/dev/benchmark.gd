class_name Benchmark
extends Node
## Device benchmark (tech_architecture.md §15), test builds only ("Bench" in the build menu).
## Builds the showcase airport with its planes landing, taxiing and taking off, runs it for a while
## in the top-down view and then in first person at a gate looking at its stand, and shows frame
## time, heartbeat time and memory against the performance budget. (Until 2026-11-14 it filled the
## airport with 1,000 passengers; see docs/removed_features.md.)
## The player's save stays safe: it is written before the benchmark starts, saving is off while
## it runs, and closing the results loads it again.

## The same airport and the same dice every run, so results from different days compare.
const SEED: int = 2026
## Budget (tech_architecture.md §15), in milliseconds. Judged on the 95th percentile: 95 % of
## all frames (or heartbeats) must stay within it; single spikes are reported but don't fail.
const PHONE_WORK_BUDGET_MS: float = 8.0
const TABLET_WORK_BUDGET_MS: float = 12.0
const HEARTBEAT_BUDGET_MS: float = 2.0
## The first-person run stands this many meters behind a gate (on the apron), looking at its stand.
const STAND_VIEW_DISTANCE: float = 30.0
## The wait for planes ends when this many flights are on their way (or after `fill_seconds`).
const PLANES_WANTED: int = 2

enum Phase { FILL, TOP_DOWN, FIRST_PERSON, DONE }

## Set before the scene is reloaded; main.gd starts the benchmark when it finds it set.
static var pending: bool = false

## Longest wait for the airport to fill up, and how long each measured run lasts (seconds).
@export var fill_seconds: float = 30.0
@export var phase_seconds: float = 60.0

## The main scene: switches the views.
var main: Node
var phase: Phase = Phase.FILL
## The finished report, one line per measurement (also printed with the prefix "BENCHMARK").
var report: String = ""

var _phase_left: float = 0.0
# Phase -> measurements of that run. Plain Arrays on purpose: Packed arrays inside a Dictionary
# are copied when read, so appending to them would change a copy and lose every sample.
var _runs: Dictionary = {}
var _peak_memory: float = 0.0
var _peak_video_memory: float = 0.0
var _status: Label
var _results: PanelContainer


## Saves the player's airport, turns saving off and builds the benchmark airport. Call it before
## reloading the scene, so every visual is built for the new airport.
static func prepare_airport() -> void:
	SaveGame.save_now()
	SaveGame.enabled = false
	Airport.reseed(SEED)
	ShowcaseAirport.build(180.0, Vector2i.ZERO, false)
	# The timetable opens its first flights a little after the start: wait until there are enough
	# upcoming departures to fill the airport with.
	for i in int(2400.0 / Airport.SIM_STEP):
		if Airport.schedule.flights.size() >= 4:
			break
		Airport.step(Airport.SIM_STEP)


## How many flights have a plane on its way or at a stand right now.
static func planes_active() -> int:
	return Airport.schedule.flights.filter(func(f: Flight) -> bool:
		return f.phase >= Flight.Phase.ARRIVING and f.phase < Flight.Phase.DEPARTED).size()


## Loads the player's save again and reloads the scene.
static func restore_player_game(tree: SceneTree) -> void:
	Airport.reset()
	SaveGame.enabled = not OS.get_cmdline_user_args().has(SaveGame.NO_SAVE_FLAG)
	SaveGame.load_game()
	tree.reload_current_scene()


## The value below which `share` of `values` lie (e.g. 0.95: 95 % of the frames were faster).
static func percentile(values: PackedFloat32Array, share: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(share * sorted.size()) - 1, 0, sorted.size() - 1)]


static func is_tablet() -> bool:
	return OS.get_model_name().begins_with("iPad")


func _ready() -> void:
	# Ask the renderer to time each frame on the processor and on the graphics chip.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(40, 120)
	_status.add_theme_font_size_override("font_size", 28)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 8)
	layer.add_child(_status)
	_start(Phase.FILL)


func _process(delta: float) -> void:
	_phase_left -= delta
	var planes := planes_active()
	match phase:
		Phase.FILL:
			_status.text = "Benchmark: waiting for planes… %d on their way\nPlease don't touch the screen." % planes
			if planes >= PLANES_WANTED or _phase_left <= 0.0:
				_start(Phase.TOP_DOWN)
		Phase.TOP_DOWN, Phase.FIRST_PERSON:
			_record(delta)
			_status.text = "Benchmark: %s · %d s left · %d planes\nPlease don't touch the screen." % [
				_phase_name(phase), ceili(maxf(_phase_left, 0.0)), planes]
			if _phase_left <= 0.0:
				_start(Phase.FIRST_PERSON if phase == Phase.TOP_DOWN else Phase.DONE)


func _start(next: Phase) -> void:
	phase = next
	_phase_left = fill_seconds if next == Phase.FILL else phase_seconds
	match next:
		Phase.TOP_DOWN:
			# The whole airport at once: every plane and building in view.
			main.set_view(main.View.BUILD)
			var camera: BuildCamera = main.get_node("BuildCamera")
			camera.view_height = 1000.0  # clamped to the farthest zoom
			camera.center_on(Vector3.ZERO)
		Phase.FIRST_PERSON:
			main.set_view(main.View.MANAGER)
			_stand_at_gate()
		Phase.DONE:
			_finish()
	if next in [Phase.TOP_DOWN, Phase.FIRST_PERSON]:
		_runs[next] = {
			"frame": [], "work": [], "gpu": [], "heartbeat": [],
			"planes": 0, "frames": 0, "seconds": 0.0,
		}


# The first gate (and its stand): the manager stands on the apron behind it, looking at the stand.
func _stand_at_gate() -> void:
	for building in Airport.buildings:
		if building.type.role != BuildingType.Role.GATE:
			continue
		var stand := Airport.stand_behind(building)
		var size := Building.rotated_size(building.type.footprint, building.rotation_steps)
		var center := Airport.grid.block_center(building.origin_cell, size)
		# The gate's front faces up, right, down, left on screen for each clockwise step; the stand lies behind it.
		var front: Vector2i = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][building.rotation_steps]
		var behind := Vector3(-front.x, 0.0, -front.y)
		var manager: Manager = main.get_node("Manager")
		manager.global_position = center + behind * STAND_VIEW_DISTANCE
		var target := center
		if stand != null:
			target = Airport.grid.block_center(stand.origin_cell, Building.rotated_size(stand.type.footprint, stand.rotation_steps))
		(main.get_node("ManagerCamera") as ManagerCamera).face(target + Vector3.UP * 3.0)
		return


func _record(delta: float) -> void:
	var run: Dictionary = _runs[phase]
	var viewport := get_viewport().get_viewport_rid()
	# Work per frame on the main processor: game code, physics and preparing the drawing.
	var work := (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0 \
		+ RenderingServer.viewport_get_measured_render_time_cpu(viewport) + RenderingServer.get_frame_setup_time_cpu()
	(run["frame"] as Array).append(delta * 1000.0)
	(run["work"] as Array).append(work)
	(run["gpu"] as Array).append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
	for usec in Airport.last_heartbeats_usec:
		(run["heartbeat"] as Array).append(usec / 1000.0)
	run["planes"] += planes_active()
	run["frames"] += 1
	run["seconds"] += delta
	_peak_memory = maxf(_peak_memory, Performance.get_monitor(Performance.MEMORY_STATIC))
	_peak_video_memory = maxf(_peak_video_memory, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))


## How many heartbeats were measured in the run of `which` phase (0 before it ran).
func heartbeat_samples(which: Phase) -> int:
	return (_runs[which]["heartbeat"] as Array).size() if _runs.has(which) else 0


func _finish() -> void:
	var tablet := is_tablet()
	var work_budget := TABLET_WORK_BUDGET_MS if tablet else PHONE_WORK_BUDGET_MS
	var lines: PackedStringArray = []
	lines.append("Benchmark · %s · build %s · seed %d" % [OS.get_model_name(), BuildStamp.text(), SEED])
	# The cap is 60 fps on iPhone and iPad (project setting application/run/max_fps.mobile), even on
	# 120 Hz screens (tech_architecture.md §15). 0 = no cap (e.g. the Mac).
	var refresh := DisplayServer.screen_get_refresh_rate()
	lines.append("Frame cap %s · screen %s" % [
		"%d fps" % Engine.max_fps if Engine.max_fps > 0 else "none", "%.0f Hz" % refresh if refresh > 0.0 else "unknown"])
	lines.append("Budget (%s): work per frame ≤ %.0f ms, heartbeat ≤ %.0f ms (95 %% of frames)" % [
		"iPad" if tablet else "iPhone", work_budget, HEARTBEAT_BUDGET_MS])
	var all_pass := true
	for run_phase: Phase in [Phase.TOP_DOWN, Phase.FIRST_PERSON]:
		var run: Dictionary = _runs[run_phase]
		var frames := maxi(int(run["frames"]), 1)
		var work_95 := percentile(PackedFloat32Array(run["work"]), 0.95)
		var heartbeat_95 := percentile(PackedFloat32Array(run["heartbeat"]), 0.95)
		var work_ok := work_95 <= work_budget
		var heartbeat_ok := heartbeat_95 <= HEARTBEAT_BUDGET_MS
		all_pass = all_pass and work_ok and heartbeat_ok
		lines.append("")
		lines.append("%s · %d s · %d planes on average" % [
			_phase_name(run_phase), roundi(run["seconds"]), int(run["planes"]) / frames])
		lines.append("  Frames per second   %.1f" % (frames / maxf(run["seconds"], 0.001)))
		lines.append("  Work per frame      %s   %s" % [_spread(run["work"]), "PASS" if work_ok else "FAIL"])
		if (run["gpu"] as Array).any(func(ms: float) -> bool: return ms > 0.0):
			lines.append("  Graphics chip       %s" % _spread(run["gpu"]))
		else:
			# Some devices (e.g. the iPhone) don't report it this way: 0 means "not measured".
			lines.append("  Graphics chip       not measured on this device (Xcode's GPU gauge shows it)")
		lines.append("  Heartbeat           %s   %s" % [_spread(run["heartbeat"]), "PASS" if heartbeat_ok else "FAIL"])
	lines.append("")
	lines.append("Memory (peak)  Godot %.0f MB · video %.0f MB" % [_peak_memory / 1048576.0, _peak_video_memory / 1048576.0])
	lines.append("Result: %s" % ("PASS" if all_pass else "FAIL"))
	report = "\n".join(lines)
	for line in lines:
		print("BENCHMARK " + line)
	_status.text = ""
	_show_results()


# "avg 5.1 ms · 95% 6.8 ms · worst 12.0 ms"
func _spread(samples: Array) -> String:
	var values := PackedFloat32Array(samples)
	var total := 0.0
	var worst := 0.0
	for value in values:
		total += value
		worst = maxf(worst, value)
	var average := total / maxi(values.size(), 1)
	return "avg %.1f ms · 95%% %.1f ms · worst %.1f ms" % [average, percentile(values, 0.95), worst]


func _phase_name(which: Phase) -> String:
	return "Top-down (whole map)" if which == Phase.TOP_DOWN else "First person (at a gate)"


## Background of the results screen: solid, so the game doesn't show through the numbers.
const RESULTS_BACKGROUND: Color = Color(0.07, 0.08, 0.1)


func _show_results() -> void:
	_results = PanelContainer.new()
	_results.name = "Results"
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := StyleBoxFlat.new()
	background.bg_color = RESULTS_BACKGROUND
	background.set_content_margin_all(32.0)
	_results.add_theme_stylebox_override("panel", background)
	var box := VBoxContainer.new()
	_results.add_child(box)
	var text := Label.new()
	text.text = report
	text.add_theme_font_size_override("font_size", 22)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "Close and load my airport"
	close.custom_minimum_size = Vector2(0, 80)
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(func() -> void: restore_player_game(get_tree()))
	box.add_child(close)
	_status.get_parent().add_child(_results)
