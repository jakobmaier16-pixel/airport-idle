class_name TestWorld
extends RefCounted
## One small test world (docs/worlds.md): a question, a few "it should ..." checks, a build step that
## fills the airport brain (pure data, through the `Airport` API) and options for the views and the HUD.
## The catalog and the active world live in TestWorlds.

## LOOK: judge what things look like. FUNCTION: one function or rule. COMBINED: joins approved parts.
## SAVED: the player's own saved game (the only world that touches the save file).
enum Kind { LOOK, FUNCTION, COMBINED, SAVED }
## Which view a world opens in.
enum StartView { MANAGER, BUILD, VIEWER }

## Stable name, used by tests, screenshots and tools.
var id: StringName = &""
var title: String = ""
var kind: Kind = Kind.FUNCTION
## The one question this world answers.
var question: String = ""
## At most MAX_CHECKS short "it should ..." lines.
var checks: PackedStringArray = PackedStringArray()
## Fills the (already reset) airport. Called once when the world is entered or restarted.
var builder: Callable = Callable()
var start_view: StartView = StartView.MANAGER
## Where the manager starts (first person); ignored unless `has_start_pose`.
var has_start_pose: bool = false
var start_position: Vector3 = Vector3.ZERO
var start_yaw: float = 0.0
## HUD parts: the "next flight" / departures lines and the Build / Manager view button.
var show_flight_info: bool = true
var show_view_button: bool = true

const MAX_CHECKS: int = 5


static func make(world_id: StringName, world_title: String, world_kind: Kind, world_question: String,
		world_checks: PackedStringArray, world_builder: Callable, world_start_view: StartView = StartView.MANAGER) -> TestWorld:
	assert(world_checks.size() <= MAX_CHECKS, "a world has at most %d checks" % MAX_CHECKS)
	var world := TestWorld.new()
	world.id = world_id
	world.title = world_title
	world.kind = world_kind
	world.question = world_question
	world.checks = world_checks
	world.builder = world_builder
	world.start_view = world_start_view
	return world


## The kind as the list's header shows it.
static func kind_header(world_kind: Kind) -> String:
	match world_kind:
		Kind.LOOK:
			return "Look worlds"
		Kind.FUNCTION:
			return "Function worlds"
		Kind.COMBINED:
			return "Combined worlds"
	return "Your game"


## True for the one world that loads and writes the save file.
func is_saved() -> bool:
	return kind == Kind.SAVED
