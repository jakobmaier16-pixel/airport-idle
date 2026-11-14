extends Node3D
## Entry point of the game. Owns the two camera views and switches between them.
## The simulation (Airport autoload) keeps running in both views.

enum View { MANAGER, BUILD, VIEWER }

var current_view: View = View.MANAGER

# How the last building_at() call decided, for the test-build tap diagnosis line.
var _last_pick: String = ""

@onready var _manager: Manager = $Manager
@onready var _manager_camera: ManagerCamera = $ManagerCamera
@onready var _build_camera: BuildCamera = $BuildCamera
@onready var _viewer_camera: ViewerCamera = $ViewerCamera
@onready var _buildings: BuildingLayer = $Buildings
@onready var _build_mode: BuildMode = $BuildMode
@onready var _hud: Hud = $HUD
@onready var _ground: Ground = $Ground


func _ready() -> void:
	_hud.view_toggle_pressed.connect(_on_view_toggle_pressed)
	_hud.zone_overlay_toggled.connect(_ground.set_zone_overlay_enabled)
	_hud.setup_build_menu(Airport.CATALOG.types)
	_hud.building_type_selected.connect(_build_mode.start_placement)
	_hud.paint_tool_selected.connect(_build_mode.start_painting)
	_hud.rotate_pressed.connect(_build_mode.rotate_placement)
	_hud.place_pressed.connect(_build_mode.confirm_placement)
	_hud.cancel_pressed.connect(_build_mode.cancel_tool)
	_hud.done_pressed.connect(_build_mode.cancel_tool)
	_hud.demolish_tool_selected.connect(_build_mode.start_demolish)
	_hud.demolish_pressed.connect(_build_mode.confirm_demolish)
	Airport.building_removed.connect(func(building: Building) -> void:
		if _hud.shown_station == building:
			_hud.hide_station())
	_build_mode.tool_changed.connect(_hud.set_tool_state)
	_hud.reset_confirmed.connect(_on_reset_confirmed)
	_hud.world_picked.connect(_on_world_picked)
	_hud.world_restart_pressed.connect(_on_world_restart)
	_hud.benchmark_confirmed.connect(_on_benchmark_confirmed)
	TouchGestures.tapped.connect(_on_tapped)
	# First person: start where the manager was, or inside the entrance (design doc §15).
	var start: Array = Airport.manager_start()
	_manager.global_position = start[0]
	_manager_camera.yaw = start[1]
	_manager_camera.snap_to_target()
	_start_world()
	if not SaveGame.load_problem.is_empty():
		_hud.notify(SaveGame.load_problem)
		SaveGame.load_problem = ""
	# The device benchmark was asked for before the scene reload (test builds only).
	if Benchmark.pending:
		Benchmark.pending = false
		var benchmark := Benchmark.new()
		benchmark.main = self
		add_child(benchmark)


# Clears the map and reloads the scene, so every visual is rebuilt from the (now empty) simulation.
func _on_reset_confirmed() -> void:
	SaveGame.reset_game()
	get_tree().reload_current_scene()


# The player picked a test world: it is built (or, for the saved game, loaded) and the scene reloads,
# so every visual is rebuilt from the new airport.
func _on_world_picked(world: TestWorld) -> void:
	TestWorlds.enter(world, get_tree())


func _on_world_restart() -> void:
	TestWorlds.enter(TestWorlds.current(), get_tree())


# Opens the view of the active test world (the manager view when none was picked), and in the debug
# builds the world list once per app start (never in tests: they pass --no-save and use the button).
func _start_world() -> void:
	var world := TestWorlds.current()
	if world.has_start_pose:
		_manager.global_position = world.start_position
		_manager_camera.yaw = world.start_yaw
		_manager_camera.snap_to_target()
	match world.start_view:
		TestWorld.StartView.BUILD:
			_set_view(View.BUILD)
		TestWorld.StartView.VIEWER:
			_set_view(View.VIEWER)
			_start_viewer()
		_:
			_set_view(View.MANAGER)
	if OS.is_debug_build() and not TestWorlds.start_list_shown and not OS.get_cmdline_user_args().has(SaveGame.NO_SAVE_FLAG):
		TestWorlds.start_list_shown = true
		_hud.open_world_list()


# The asset viewer world: the viewer node with its catalog, and its controls in the HUD.
func _start_viewer() -> void:
	var viewer := (load("res://scenes/viewer/asset_viewer.tscn") as PackedScene).instantiate() as AssetViewer
	viewer.camera = _viewer_camera
	viewer.building_layer = _buildings
	add_child(viewer)
	viewer.set_items(ViewerCatalog.items())
	_hud.add_viewer_controls(viewer, _viewer_camera)


# Builds the benchmark airport (the player's save is kept safe) and reloads the scene for it.
func _on_benchmark_confirmed() -> void:
	Benchmark.prepare_airport()
	Benchmark.pending = true
	get_tree().reload_current_scene()


## Switches to `view` (used by the device benchmark).
func set_view(view: View) -> void:
	_set_view(view)


func _process(_delta: float) -> void:
	_hud.set_status(Airport.status_text())
	_hud.set_next_flight(Airport.schedule.next_flight_text())
	_hud.set_departures(Airport.schedule.departures_text())


# Manager view: tapping a building opens its panel; tapping elsewhere closes it.
func _on_tapped(screen_position: Vector2) -> void:
	if current_view != View.MANAGER:
		return  # build view taps belong to the build tools
	var where := "Tap (%d, %d)" % [roundi(screen_position.x), roundi(screen_position.y)]
	var building := building_at(screen_position)
	if building != null and building.type.role != BuildingType.Role.NONE:
		_hud.show_station(building)
		_hud.report_tap("%s → %s (%s)" % [where, building.type.display_name, _last_pick])
	else:
		_hud.hide_station()
		_hud.report_tap("%s → no building (%s)" % [where, _last_pick])


## The building under a screen position in the manager view, or null.
func building_at(screen_position: Vector2) -> Building:
	var from := _manager_camera.project_ray_origin(screen_position)
	var direction := _manager_camera.project_ray_normal(screen_position)
	# Solid buildings: hit their walls or roof, not just the ground under the finger.
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 300.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_last_pick = "ray hit nothing"
	else:
		var collider := hit.collider as Object
		if collider.has_meta(BuildingLayer.BUILDING_META):
			_last_pick = "ray"
			return collider.get_meta(BuildingLayer.BUILDING_META)
		_last_pick = "ray hit %s" % ((collider as Node).name if collider is Node else str(collider))

	# Backup without physics: the station whose box covers this point on screen.
	var on_screen := _station_on_screen(screen_position)
	if on_screen != null:
		_last_pick += ", found on screen"
		return on_screen

	# Flat buildings (stands) have no collision: look at the ground cell.
	var ground: Variant = Plane(Vector3.UP, 0.0).intersects_ray(from, direction)
	if ground == null:
		return null
	var cell := Airport.grid.world_to_cell(ground as Vector3)
	if not Airport.grid.is_inside(cell) or Airport.grid.is_empty(cell):
		return null
	_last_pick += ", ground cell"
	return Airport.grid.get_content(cell) as Building


# The closest station whose box (as seen by the manager camera) covers `screen_position`.
func _station_on_screen(screen_position: Vector2) -> Building:
	var best: Building = null
	var best_distance := INF
	for building in Airport.buildings:
		if building.type.role == BuildingType.Role.NONE or not building.type.is_solid:
			continue
		var size := Building.rotated_size(building.type.footprint, building.rotation_steps)
		var center := Airport.grid.block_center(building.origin_cell, size)
		var half := Vector3(size.x, 0.0, size.y) * Airport.grid.cell_size * 0.5
		var screen_box := Rect2()
		var behind_camera := false
		for corner in 8:
			var point := center + Vector3(
				half.x * (1.0 if corner & 1 else -1.0),
				building.type.height if corner & 2 else 0.0,
				half.z * (1.0 if corner & 4 else -1.0))
			if _manager_camera.is_position_behind(point):
				behind_camera = true
				break
			var on_screen := _manager_camera.unproject_position(point)
			screen_box = Rect2(on_screen, Vector2.ZERO) if corner == 0 else screen_box.expand(on_screen)
		if behind_camera or not screen_box.has_point(screen_position):
			continue
		var distance := _manager_camera.global_position.distance_to(center)
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


func _on_view_toggle_pressed() -> void:
	if current_view == View.VIEWER:
		return  # the viewer world has no other view
	_set_view(View.BUILD if current_view == View.MANAGER else View.MANAGER)


func _set_view(view: View) -> void:
	current_view = view
	var building := view == View.BUILD
	var viewing := view == View.VIEWER
	if building:
		# Open the build view above wherever the manager is standing.
		_build_camera.center_on(_manager.global_position)
		_build_camera.make_current()
	elif viewing:
		_viewer_camera.make_current()
	else:
		_manager_camera.make_current()
	_build_camera.update_shadows()
	# Distance haze is for the first-person view; seen from above it would only grey the map out.
	# The viewer judges single assets, some of them 2 km long: no haze there either.
	($WorldEnvironment as WorldEnvironment).environment.fog_enabled = not building and not viewing

	# The viewer has no manager: he neither walks nor is seen.
	_manager.input_enabled = not building and not viewing
	_manager.visible = not viewing
	_manager.process_mode = Node.PROCESS_MODE_DISABLED if viewing else Node.PROCESS_MODE_INHERIT
	_hud.joystick.enabled = not building and not viewing
	_build_mode.active = building
	_hud.hide_station()
	_hud.set_build_view_open(building)
	_ground.set_build_view(building)
	# Build view: adding a second finger turns a pan into a pinch.
	# Manager view: every finger is its own gesture (one walks, the other looks around).
	# Viewer: one finger turns the view, two fingers pinch.
	TouchGestures.pinch_cancels_drag = building or viewing
	TouchGestures.independent_drags = not building and not viewing
	_hud.set_view_button_text("Manager" if building else "Build")
