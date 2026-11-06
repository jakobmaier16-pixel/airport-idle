extends Node3D
## Entry point of the game. Owns the two camera views and switches between them.
## The simulation (Airport autoload) keeps running in both views.

enum View { MANAGER, BUILD }

var current_view: View = View.MANAGER

# How the last building_at() call decided, for the test-build tap diagnosis line.
var _last_pick: String = ""
# A new airline's first flight, waiting for its plane to appear for the cutscene.
var _first_landing: Flight = null

@onready var _manager: Manager = $Manager
@onready var _manager_camera: ManagerCamera = $ManagerCamera
@onready var _build_camera: BuildCamera = $BuildCamera
@onready var _build_mode: BuildMode = $BuildMode
@onready var _hud: Hud = $HUD
@onready var _cinematic: CinematicCamera = $CinematicCamera
@onready var _planes: PlaneLayer = $Planes


func _ready() -> void:
	_hud.view_toggle_pressed.connect(_on_view_toggle_pressed)
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
	_hud.showcase_confirmed.connect(_on_showcase_confirmed)
	_hud.benchmark_confirmed.connect(_on_benchmark_confirmed)
	# Managing a station needs the manager on the spot (design doc §15.1).
	_hud.upgrade_pressed.connect(func(building: Building) -> void:
		if Airport.manage_problem(building).is_empty():
			Airport.start_upgrade(building))
	_hud.hire_pressed.connect(func(building: Building) -> void:
		if Airport.manage_problem(building).is_empty():
			Airport.hire(building))
	_hud.dismiss_pressed.connect(func(building: Building) -> void:
		if Airport.manage_problem(building).is_empty():
			Airport.dismiss(building))
	_hud.train_pressed.connect(func(building: Building) -> void:
		if Airport.manage_problem(building).is_empty():
			Airport.train(building))
	_hud.promote_pressed.connect(func(building: Building) -> void:
		if Airport.manage_problem(building).is_empty():
			Airport.promote(building))
	_hud.fast_track_pressed.connect(func(building: Building) -> void:
		if Airport.manage_problem(building).is_empty():
			Airport.buy_fast_track(building))
	TouchGestures.tapped.connect(_on_tapped)
	Airport.restructured.connect(_on_restructured)
	Airport.progression.tier_reached.connect(_on_tier_reached)
	Airport.weather.changed.connect(_on_weather_changed)
	Airport.incident_started.connect(_on_incident_started)
	Airport.vip_announced.connect(func(flight: Flight) -> void:
		var seconds := ceili(flight.departure_time - Airport.passenger_flow.time)
		_hud.notify("A VIP flies with %s in %d:%02d (gold). Short queues, fast track and a lounge keep them happy." % [
			flight.number, seconds / 60, seconds % 60]))
	Airport.vip_result.connect(func(happy: bool, mood: float) -> void:
		if happy:
			_hud.notify("The VIP was delighted (%d %%)! %s and half a star for a while." % [roundi(mood), Economy.format(Airport.VIP_REWARD)])
		else:
			_hud.notify("The VIP was unhappy (%d %%). The press noticed: half a star less for a while." % roundi(mood)))
	Airport.passenger_flow.schedule.plane_arriving.connect(_on_plane_arriving)
	_cinematic.finished.connect(func() -> void: _manager.input_enabled = current_view == View.MANAGER)
	Airport.airlines.offer_arrived.connect(_on_offer_arrived)
	Airport.airlines.airline_unhappy.connect(_on_airline_unhappy)
	Airport.airlines.airline_left.connect(_on_airline_left)
	# First person: start where the manager was, or inside the entrance (design doc §15).
	var start: Array = Airport.manager_start()
	_manager.global_position = start[0]
	_manager_camera.yaw = start[1]
	_manager_camera.snap_to_target()
	_set_view(View.MANAGER)
	if SaveGame.welcome_back_bonus > 0.0:
		_hud.notify("Welcome back! You were away %d hours. Your airport earned %s while you were gone." % [
			floori(SaveGame.away_seconds / 3600.0), Economy.format(SaveGame.welcome_back_bonus)])
		SaveGame.welcome_back_bonus = 0.0
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


# Loads the ready-made showcase airport and reloads the scene to rebuild every visual.
func _on_showcase_confirmed() -> void:
	SaveGame.load_showcase()
	get_tree().reload_current_scene()


# Builds the benchmark airport (the player's save is kept safe) and reloads the scene for it.
func _on_benchmark_confirmed() -> void:
	Benchmark.prepare_airport()
	Benchmark.pending = true
	get_tree().reload_current_scene()


## Switches to `view` (used by the device benchmark).
func set_view(view: View) -> void:
	_set_view(view)


func _process(_delta: float) -> void:
	if _first_landing != null:
		_start_first_landing()
	_hud.set_money(Airport.economy.balance, Airport.economy.profit_per_minute())
	var economy := Airport.economy
	_hud.set_loan(economy.debt(), economy.interest_per_minute(), Airport.credit_limit(), Airport.restructure_in())
	_hud.set_rating(Airport.stars(), Airport.progression.name_of(Airport.progression.tier))
	_hud.set_status(Airport.passenger_flow.status_text())
	_hud.set_departures(Airport.passenger_flow.departures_text())


func _on_restructured(sold: PackedStringArray) -> void:
	var what := "Sold: %s." % ", ".join(sold) if not sold.is_empty() else "Nothing was left to sell."
	_hud.notify("The bank restructured your airport to cover the debt. %s The rest was written off. Reputation −1 star." % what)


func _on_tier_reached(tier: Progression.Tier) -> void:
	_hud.show_milestone("%s airport!" % Airport.progression.name_of(tier), Progression.REWARDS[tier])
	# Newly unlocked buildings lose their "(National)" note.
	_hud.setup_build_menu(Airport.CATALOG.types)


# A new airline's first landing gets a short cutscene (design doc §14), in the manager view.
# The plane's visual appears a frame later, so the cutscene starts from _process.
func _on_plane_arriving(flight: Flight) -> void:
	var airline := flight.airline
	if airline == null or airline.first_landing_seen or airline.type.id == Airlines.STARTER:
		return
	airline.first_landing_seen = true
	if current_view == View.MANAGER and not _cinematic.is_playing():
		_first_landing = flight


func _start_first_landing() -> void:
	var flight := _first_landing
	if not _planes.has_plane(flight):
		return
	_first_landing = null
	_manager.input_enabled = false
	_cinematic.play(_planes.plane_of(flight))
	_hud.notify("First landing: %s comes to your airport!" % flight.airline.type.display_name)


func _on_incident_started(building: Building) -> void:
	_hud.notify("Unattended bag at %s: it's closed until the police clear it (1:30). Walk there to speed it up." % \
		Airport.passenger_flow.station_label(building))


func _on_weather_changed(kind: Weather.Kind) -> void:
	match kind:
		Weather.Kind.STORM:
			_hud.notify("Thunderstorm: ground crews stop work and nothing lands until it passes. Weather delays don't count against your on-time rate.")
		Weather.Kind.FOG:
			_hud.notify("Fog: no landings until it lifts. Planes waiting to arrive hold.")
		Weather.Kind.SNOW:
			_hud.notify("Snow: every departure needs de-icing first (much faster with a de-icing pad).")


func _on_offer_arrived(offer: AirlineOffer) -> void:
	if offer.is_renewal:
		_hud.notify("%s's contract ends in 10 minutes. They offer to renew: %d flights/h at %s. Tap Airlines; without a renewal they leave." % [
			offer.type.display_name, offer.flights_per_hour, Economy.format(offer.fee)])
		return
	_hud.notify("New offer: %s (%s) wants %d flights per hour. Tap Airlines to negotiate." % [
		offer.type.display_name, offer.type.route, offer.flights_per_hour])


func _on_airline_unhappy(airline: Airline) -> void:
	_hud.notify("%s is unhappy (%d %%): late flights, missed passengers or no free gate. If it gets worse, they leave." % [
		airline.type.display_name, roundi(airline.happiness)])


func _on_airline_left(airline: Airline) -> void:
	_hud.notify("%s ended its deal and left the airport." % airline.type.display_name)


# Manager view: tapping a building opens its station panel; tapping elsewhere closes it.
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
	_set_view(View.BUILD if current_view == View.MANAGER else View.MANAGER)


func _set_view(view: View) -> void:
	current_view = view
	var building := view == View.BUILD
	if building:
		# Open the build view above wherever the manager is standing.
		_build_camera.center_on(_manager.global_position)
		_build_camera.make_current()
	else:
		_manager_camera.make_current()

	_manager.input_enabled = not building
	_hud.joystick.enabled = not building
	_build_mode.active = building
	_hud.hide_station()
	_hud.set_build_view_open(building)
	# Build view: adding a second finger turns a pan into a pinch.
	# Manager view: every finger is its own gesture (one walks, the other looks around).
	TouchGestures.pinch_cancels_drag = building
	TouchGestures.independent_drags = not building
	_hud.set_view_button_text("Manager" if building else "Build")
