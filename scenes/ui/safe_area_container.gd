class_name SafeAreaContainer
extends MarginContainer
## Full-screen container that keeps its children inside the device's safe area,
## away from the notch / Dynamic Island and the home indicator.
## Use it as the root of all HUD elements.

# iPhone 15 landscape insets in points, relative to its 852 x 393-point screen:
# the Dynamic Island side (iOS reserves the same space on both sides) and the home indicator.
const SIMULATED_SIDE_RATIO: float = 59.0 / 852.0
const SIMULATED_BOTTOM_RATIO: float = 21.0 / 393.0

## Fake iPhone safe-area insets on the Mac, to check the layout without a device.
@export var simulate_on_desktop: bool = false
## Extra space on every side, in UI pixels, so buttons don't touch the screen edge.
@export var padding: int = 16


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_update_margins)
	_update_margins()


func _update_margins() -> void:
	# Insets in UI pixels: left, top, right, bottom.
	var insets := Vector4.ZERO
	var window_size := Vector2(DisplayServer.window_get_size())
	# The window size can be zero for a moment at startup (and always in headless mode).
	if window_size.x > 0.0 and window_size.y > 0.0:
		insets = _get_insets_in_window_pixels(window_size)
		# The safe area is reported in screen pixels, but the UI uses scaled viewport units
		# (see Project Settings > Display > Window > Stretch), so convert between them.
		var scale_factor := get_viewport().get_visible_rect().size / window_size
		insets *= Vector4(scale_factor.x, scale_factor.y, scale_factor.x, scale_factor.y)

	add_theme_constant_override(&"margin_left", ceili(insets.x) + padding)
	add_theme_constant_override(&"margin_top", ceili(insets.y) + padding)
	add_theme_constant_override(&"margin_right", ceili(insets.z) + padding)
	add_theme_constant_override(&"margin_bottom", ceili(insets.w) + padding)


func _get_insets_in_window_pixels(window_size: Vector2) -> Vector4:
	if OS.has_feature("mobile"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		return Vector4(
			safe.position.x,
			safe.position.y,
			window_size.x - safe.end.x,
			window_size.y - safe.end.y,
		)
	if simulate_on_desktop:
		var side := window_size.x * SIMULATED_SIDE_RATIO
		return Vector4(side, 0.0, side, window_size.y * SIMULATED_BOTTOM_RATIO)
	return Vector4.ZERO
