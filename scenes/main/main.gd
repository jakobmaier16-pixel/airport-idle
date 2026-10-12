extends Node3D
## Entry point of the game. Owns the two camera views and switches between them.
## The simulation (Airport autoload) keeps running in both views.

enum View { MANAGER, BUILD }

var current_view: View = View.MANAGER

@onready var _manager: Manager = $Manager
@onready var _manager_camera: ManagerCamera = $ManagerCamera
@onready var _build_camera: BuildCamera = $BuildCamera
@onready var _build_mode: BuildMode = $BuildMode
@onready var _hud: Hud = $HUD


func _ready() -> void:
	_hud.view_toggle_pressed.connect(_on_view_toggle_pressed)
	_hud.setup_build_menu(Airport.CATALOG.types)
	_hud.building_type_selected.connect(_build_mode.start_placement)
	_hud.paint_tool_selected.connect(_build_mode.start_painting)
	_hud.rotate_pressed.connect(_build_mode.rotate_placement)
	_hud.place_pressed.connect(_build_mode.confirm_placement)
	_hud.cancel_pressed.connect(_build_mode.cancel_tool)
	_hud.done_pressed.connect(_build_mode.cancel_tool)
	_build_mode.tool_changed.connect(_hud.set_tool_state)
	_hud.reset_confirmed.connect(_on_reset_confirmed)
	_hud.showcase_confirmed.connect(_on_showcase_confirmed)
	_hud.upgrade_pressed.connect(func(building: Building) -> void: Airport.start_upgrade(building))
	TouchGestures.tapped.connect(_on_tapped)
	_set_view(View.MANAGER)


# Clears the map and reloads the scene, so every visual is rebuilt from the (now empty) simulation.
func _on_reset_confirmed() -> void:
	SaveGame.reset_game()
	get_tree().reload_current_scene()


# Loads the ready-made showcase airport and reloads the scene to rebuild every visual.
func _on_showcase_confirmed() -> void:
	SaveGame.load_showcase()
	get_tree().reload_current_scene()


func _process(_delta: float) -> void:
	_hud.set_money(Airport.economy.balance, Airport.economy.profit_per_minute())
	_hud.set_status(Airport.passenger_flow.status_text())
	_hud.set_departures(Airport.passenger_flow.departures_text())


# Manager view: tapping a building opens its station panel; tapping elsewhere closes it.
func _on_tapped(screen_position: Vector2) -> void:
	if current_view != View.MANAGER:
		return
	var building := building_at(screen_position)
	if building != null and building.type.role != BuildingType.Role.NONE:
		_hud.show_station(building)
	else:
		_hud.hide_station()


## The building under a screen position in the manager view, or null.
func building_at(screen_position: Vector2) -> Building:
	var from := _manager_camera.project_ray_origin(screen_position)
	var direction := _manager_camera.project_ray_normal(screen_position)
	# Solid buildings: hit their walls or roof, not just the ground under the finger.
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 300.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and (hit.collider as Object).has_meta(BuildingLayer.BUILDING_META):
		return (hit.collider as Object).get_meta(BuildingLayer.BUILDING_META)
	# Flat buildings (stands) have no collision: look at the ground cell.
	var ground: Variant = Plane(Vector3.UP, 0.0).intersects_ray(from, direction)
	if ground == null:
		return null
	var cell := Airport.grid.world_to_cell(ground as Vector3)
	if not Airport.grid.is_inside(cell) or Airport.grid.is_empty(cell):
		return null
	return Airport.grid.get_content(cell) as Building


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
	# Manager view: a second finger must never interrupt the joystick.
	TouchGestures.pinch_cancels_drag = building
	_hud.set_view_button_text("Manager" if building else "Build")
