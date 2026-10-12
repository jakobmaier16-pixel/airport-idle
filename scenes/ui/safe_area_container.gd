class_name SafeAreaContainer
extends MarginContainer
## Full-screen container that keeps its children inside the device's safe area,
## away from the notch / Dynamic Island and the home indicator.
## Use it as the root of all HUD elements.

# iPhone 15 portrait insets in points, relative to its 852-point screen height.
const SIMULATED_TOP_RATIO: float = 59.0 / 852.0
const SIMULATED_BOTTOM_RATIO: float = 34.0 / 852.0

## Fake iPhone safe-area insets on the Mac, to check the layout without a device.
@export var simulate_on_desktop: bool = false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_update_margins)
	_update_margins()


func _update_margins() -> void:
	var window_size := Vector2(DisplayServer.window_get_size())
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return

	# Insets in window pixels: left, top, right, bottom.
	var insets := Vector4.ZERO
	if OS.has_feature("mobile"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		insets = Vector4(
			safe.position.x,
			safe.position.y,
			window_size.x - safe.end.x,
			window_size.y - safe.end.y,
		)
	elif simulate_on_desktop:
		insets = Vector4(0.0, window_size.y * SIMULATED_TOP_RATIO, 0.0, window_size.y * SIMULATED_BOTTOM_RATIO)

	# The safe area is reported in screen pixels, but the UI uses scaled viewport units
	# (see Project Settings > Display > Window > Stretch), so convert between them.
	var scale_factor := get_viewport().get_visible_rect().size / window_size
	add_theme_constant_override(&"margin_left", ceili(insets.x * scale_factor.x))
	add_theme_constant_override(&"margin_top", ceili(insets.y * scale_factor.y))
	add_theme_constant_override(&"margin_right", ceili(insets.z * scale_factor.x))
	add_theme_constant_override(&"margin_bottom", ceili(insets.w * scale_factor.y))
