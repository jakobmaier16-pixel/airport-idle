class_name WorldInfo
extends Control
## The "i" panel (debug builds): the active world's title, question and checks, plus "Restart world",
## which rebuilds the same world. Not for the saved game.

signal restart_pressed
signal closed

var _title: Label
var _kind: Label
var _question: Label
var _checks: Label


func _ready() -> void:
	name = "WorldInfo"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var theme_with_font := Theme.new()
	theme_with_font.default_font_size = 26
	theme = theme_with_font

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var safe := SafeAreaContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(safe)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.15, 0.96)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override(&"panel", style)
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	panel.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 34)
	column.add_child(_title)
	_kind = Label.new()
	_kind.modulate = Color(1, 1, 1, 0.6)
	column.add_child(_kind)
	_question = Label.new()
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_question)
	_checks = Label.new()
	_checks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_checks.add_theme_font_size_override(&"font_size", 22)
	column.add_child(_checks)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	column.add_child(row)
	var restart := _button("RestartButton", "Restart world")
	restart.pressed.connect(func() -> void:
		visible = false
		restart_pressed.emit())
	row.add_child(restart)
	var close := _button("CloseButton", "Close")
	close.pressed.connect(close_panel)
	row.add_child(close)


## Shows the panel for `world`.
func open(world: TestWorld) -> void:
	_title.text = world.title
	_kind.text = TestWorld.kind_header(world.kind)
	_question.text = world.question
	var lines: PackedStringArray = []
	for check in world.checks:
		lines.append("•  " + check)
	_checks.text = "\n".join(lines)
	visible = true


func close_panel() -> void:
	visible = false
	closed.emit()


func _button(node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(240, 84)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	return button
