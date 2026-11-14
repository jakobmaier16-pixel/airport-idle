class_name ViewerHud
extends VBoxContainer
## The asset viewer's controls, a child of the HUD's SafeArea (so everything stays inside the notch and
## home-indicator margins): Prev / Next and the item label on top, the category row and the view buttons
## at the bottom. Rows wrap when the screen is narrow. Plain buttons, finger-sized.

const BUTTON_SIZE: Vector2 = Vector2(150, 84)

var _viewer: AssetViewer
var _camera: ViewerCamera
var _label: Label
var _size_label: Label
var _category_row: HFlowContainer
var _person_button: Button
var _far_button: Button
var _label_settings: LabelSettings


## Builds the controls for `viewer` and `camera`.
func setup(viewer: AssetViewer, camera: ViewerCamera) -> void:
	_viewer = viewer
	_camera = camera
	name = "ViewerHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 6)
	_label_settings = LabelSettings.new()
	_label_settings.font_size = 24
	_label_settings.outline_size = 6
	_label_settings.outline_color = Color(0, 0, 0, 0.7)

	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_row)
	var previous := _button("PrevButton", "‹ Prev", top_row)
	previous.pressed.connect(viewer.previous_item)
	var next := _button("NextButton", "Next ›", top_row)
	next.pressed.connect(viewer.next_item)

	_label = _text_label("ItemLabel", 24)
	_size_label = _text_label("SizeLabel", 20)
	_size_label.modulate = Color(1.0, 0.88, 0.45)

	# The middle: empty (the item is there) with the view buttons in a column at the right edge, so
	# neither they nor the category row below cover the item.
	var middle := HBoxContainer.new()
	middle.name = "Middle"
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(middle)
	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(spacer)
	var action_row := VBoxContainer.new()
	action_row.name = "ActionRow"
	action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_row.add_theme_constant_override(&"separation", 6)
	middle.add_child(action_row)

	_category_row = HFlowContainer.new()
	_category_row.name = "CategoryRow"
	_category_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_category_row)
	for category in ViewerCatalog.categories(viewer.items):
		var button := _button("Category_%s" % category, category, _category_row)
		button.set_meta(&"category", category)
		button.toggle_mode = true
		button.pressed.connect(viewer.show_category.bind(category))

	_person_button = _button("PersonButton", "Person", action_row)
	_person_button.toggle_mode = true
	_person_button.button_pressed = viewer.person_visible
	_person_button.toggled.connect(_on_person_toggled)
	_far_button = _button("FarModelButton", "Far model", action_row)
	_far_button.toggle_mode = true
	_far_button.toggled.connect(_on_far_toggled)
	var reset := _button("ResetViewButton", "Reset view", action_row)
	reset.pressed.connect(camera.reset_view)
	var eye := _button("EyeLevelButton", "Eye level", action_row)
	eye.pressed.connect(camera.go_eye_level)

	viewer.item_changed.connect(_refresh)
	_refresh(viewer.index)


func _refresh(_index: int) -> void:
	_label.text = _viewer.label_text()
	_size_label.text = _viewer.size_text()
	var category := _viewer.current_item().category
	# The current category looks selected (pressed, yellow text), the others are normal and tappable.
	for button: Button in _category_row.get_children():
		var current: bool = button.get_meta(&"category") == category
		button.set_pressed_no_signal(current)
		if current:
			button.add_theme_color_override(&"font_color", Color(1.0, 0.88, 0.45))
			button.add_theme_color_override(&"font_pressed_color", Color(1.0, 0.88, 0.45))
			button.add_theme_color_override(&"font_hover_pressed_color", Color(1.0, 0.88, 0.45))
		else:
			button.remove_theme_color_override(&"font_color")
			button.remove_theme_color_override(&"font_pressed_color")
			button.remove_theme_color_override(&"font_hover_pressed_color")
	_person_button.set_pressed_no_signal(_viewer.person_visible)
	_person_button.text = "Person: %s" % ("on" if _viewer.person_visible else "off")
	# The far model exists only for items that have one; for the others the switch is off and disabled.
	var has_far := _viewer.has_far_model()
	_far_button.disabled = not has_far
	_far_button.set_pressed_no_signal(_viewer.far_model)
	_far_button.text = "Far model: %s" % ("on" if _viewer.far_model else "off")


func _on_person_toggled(on: bool) -> void:
	_viewer.set_person_visible(on)
	_person_button.text = "Person: %s" % ("on" if on else "off")


func _on_far_toggled(on: bool) -> void:
	_viewer.set_far_model(on)
	_far_button.text = "Far model: %s" % ("on" if on else "off")


func _button(node_name: String, text: String, row: Control) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_NONE
	row.add_child(button)
	return button


func _text_label(node_name: String, size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	var settings := _label_settings.duplicate() as LabelSettings
	settings.font_size = size
	label.label_settings = settings
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label
