class_name WorldList
extends Control
## The world list (debug builds): a full-screen panel with every test world, grouped by kind. Each world
## is one big button with its title and question. "Close" returns without switching. The content sits in
## a SafeAreaContainer, so nothing hides behind the notch or the home indicator; the list scrolls by
## touch if there are more worlds than fit.

signal world_picked(world: TestWorld)
signal closed

const BUTTON_HEIGHT: float = 84.0
const ENTRY_HEIGHT: float = 92.0
const FONT_SIZE: int = 26
const HEADER_FONT_SIZE: int = 22

var _entries: VBoxContainer
var _close_button: Button


func _ready() -> void:
	name = "WorldList"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Takes every touch while open, so nothing behind the panel reacts.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var theme_with_font := Theme.new()
	theme_with_font.default_font_size = FONT_SIZE
	theme = theme_with_font

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.07, 0.1, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var safe := SafeAreaContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	safe.add_child(column)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := Label.new()
	title.text = "Worlds"
	title.add_theme_font_size_override(&"font_size", 36)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(title)
	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "Close"
	_close_button.custom_minimum_size = Vector2(180, BUTTON_HEIGHT)
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.pressed.connect(close)
	title_row.add_child(_close_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_entries = VBoxContainer.new()
	_entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_entries)


## Shows the list (rebuilt, so the running world is marked).
func open() -> void:
	_rebuild()
	visible = true


## Hides the list without switching.
func close() -> void:
	visible = false
	closed.emit()


func _rebuild() -> void:
	for child in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()
	var running := TestWorlds.current()
	for kind in TestWorld.Kind.values():
		var worlds := TestWorlds.all().filter(func(w: TestWorld) -> bool: return w.kind == kind)
		if worlds.is_empty():
			continue
		var header := Label.new()
		header.text = TestWorld.kind_header(kind)
		header.add_theme_font_size_override(&"font_size", HEADER_FONT_SIZE)
		header.modulate = Color(1, 1, 1, 0.65)
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_entries.add_child(header)
		for world: TestWorld in worlds:
			var button := Button.new()
			button.name = "World_%s" % world.id
			button.text = "%s%s\n%s" % [world.title, "   (running)" if world == running else "", world.question]
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.clip_text = true
			button.custom_minimum_size = Vector2(0, ENTRY_HEIGHT)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.focus_mode = Control.FOCUS_NONE
			# Pass the touch on, so dragging over a world still scrolls the list (a scroll never presses it).
			button.mouse_filter = Control.MOUSE_FILTER_PASS
			button.pressed.connect(_on_world_pressed.bind(world))
			_entries.add_child(button)


func _on_world_pressed(world: TestWorld) -> void:
	visible = false
	world_picked.emit(world)
