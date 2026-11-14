class_name TestWorlds
extends RefCounted
## The ordered catalog of test worlds and the active one (docs/worlds.md). Debug builds only use it
## (the list and the buttons are hidden in release builds); the active world is a static variable, so it
## survives `reload_current_scene()` just like `Benchmark.pending`.
##
## Test worlds are never saved: while one is active SaveGame refuses to write (`saving_allowed`).
## "Free build" is the player's normal saved game and the only world that touches the save file.

const ASSET_VIEWER: StringName = &"asset_viewer"
const FRESH_AIRPORT: StringName = &"fresh_airport"
const EVERYTHING_TOGETHER: StringName = &"everything_together"
const FREE_BUILD: StringName = &"free_build"

## Seconds the "Everything together" airport runs before the player sees it. Short on purpose: the
## opening flight touches down about 26 s after the start, and the player should be there to watch it.
const SHOWCASE_WARM_UP: float = 10.0
## The same dice every time the asset viewer is entered.
const VIEWER_SEED: int = 2026

## The world that is running, or null: then the player's own saved game ("Free build") runs.
static var active: TestWorld = null
## The list opens by itself once per app start (debug builds); this remembers it across scene reloads.
static var start_list_shown: bool = false
## Tests: how the scene is rebuilt after entering a world. Empty = `reload_current_scene()`.
static var reload: Callable = Callable()

static var _worlds: Array[TestWorld] = []


## Every world, in the order of the list (and of the kinds inside it).
static func all() -> Array[TestWorld]:
	if _worlds.is_empty():
		_worlds = _create_all()
	return _worlds


static func find(id: StringName) -> TestWorld:
	for world in all():
		if world.id == id:
			return world
	return null


## The running world; "Free build" while none was picked.
static func current() -> TestWorld:
	return active if active != null else find(FREE_BUILD)


## SaveGame asks before every write: only the saved game may touch the save file.
static func saving_allowed() -> bool:
	return current().is_saved()


## Enters `world`: leaves the running one (the saved game is written first, so nothing is lost),
## puts a fresh airport in place and rebuilds the scene. Does nothing to the save file.
static func enter(world: TestWorld, tree: SceneTree) -> void:
	# Written while the saved game is still the running world, because saving is refused afterwards.
	if saving_allowed():
		SaveGame.save_now()
	active = world
	if world.is_saved():
		# Back to the player's game: a missing or unreadable save simply starts a new airport.
		Airport.reset()
		SaveGame.load_game()
	elif world.builder.is_valid():
		# Every builder starts from a fresh airport of its own (Airport.reset or ShowcaseAirport.build).
		world.builder.call()
	if reload.is_valid():
		reload.call()
	else:
		tree.reload_current_scene()


## Tests: forget the active world and the hooks.
static func reset_for_tests() -> void:
	active = null
	start_list_shown = false
	reload = Callable()


static func _create_all() -> Array[TestWorld]:
	var worlds: Array[TestWorld] = []
	var viewer := TestWorld.make(ASSET_VIEWER, "Asset viewer", TestWorld.Kind.LOOK,
		"How does each single asset look in the game: building, piece, plant, sign, ground, material, plane?",
		PackedStringArray([
			"it should show one asset alone on an empty grass field",
			"it should step through every asset with Prev and Next",
			"it should let me turn, tilt and zoom with my fingers",
			"it should show the size and a 1.80 m figure for scale",
			"it should show the view from eye height with Eye level",
		]),
		func() -> void: Airport.reset(false, VIEWER_SEED),
		TestWorld.StartView.VIEWER)
	viewer.show_flight_info = false
	viewer.show_view_button = false
	worlds.append(viewer)
	worlds.append(TestWorld.make(FRESH_AIRPORT, "Fresh airport", TestWorld.Kind.FUNCTION,
		"Do the build tools work on an empty field?",
		PackedStringArray([
			"it should open in the build view on an empty map with one runway",
			"it should let me place a building, a walkway and a taxiway",
			"it should let me demolish them again",
			"it should keep every control inside the screen",
		]),
		func() -> void: Airport.reset(),
		TestWorld.StartView.BUILD))
	worlds.append(TestWorld.make(EVERYTHING_TOGETHER, "Everything together", TestWorld.Kind.COMBINED,
		"The old all-in-one showcase. Kept for the automated tests, not for judging.",
		PackedStringArray([
			"it should open with a busy airport in the first-person view",
			"it should show planes landing, taxiing and taking off",
			"it should not be used to judge looks: use the asset viewer",
		]),
		func() -> void: ShowcaseAirport.build(SHOWCASE_WARM_UP)))
	worlds.append(TestWorld.make(FREE_BUILD, "Free build (saved)", TestWorld.Kind.SAVED,
		"My own saved airport: is it still there, and does it save by itself?",
		PackedStringArray(), Callable()))
	return worlds
