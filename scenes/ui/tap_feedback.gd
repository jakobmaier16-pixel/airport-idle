class_name TapFeedback
extends Control
## Test builds only: draws a small fading ring wherever a tap is recognized, and a line at the
## bottom saying what the last tap did, so touch problems on the device are easy to diagnose
## ("no ring" = the tap wasn't recognized as a tap).

const RING_RADIUS: float = 28.0
const RING_LIFETIME: float = 0.5
const RING_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)

const REPORT_FONT_SIZE: int = 22

## What the last tap did (set through Hud.report_tap()).
var report_text: String = ""

# Positions (UI pixels) and ages (seconds) of the rings currently shown.
var _positions: PackedVector2Array = PackedVector2Array()
var _ages: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	if not OS.is_debug_build():
		queue_free()
		return
	TouchGestures.tapped.connect(_on_tapped)


func _process(delta: float) -> void:
	if _ages.is_empty():
		return
	for i in range(_ages.size() - 1, -1, -1):
		_ages[i] += delta
		if _ages[i] >= RING_LIFETIME:
			_ages.remove_at(i)
			_positions.remove_at(i)
	queue_redraw()


## Shows what the last tap did at the bottom of the screen.
func report(text: String) -> void:
	report_text = text
	queue_redraw()


func _draw() -> void:
	if not report_text.is_empty():
		var font := ThemeDB.fallback_font
		var width := font.get_string_size(report_text, HORIZONTAL_ALIGNMENT_LEFT, -1, REPORT_FONT_SIZE).x
		# Top center, under the build stamp, clear of the buttons at the bottom.
		var at := Vector2((size.x - width) * 0.5, 64.0)
		draw_string_outline(font, at, report_text, HORIZONTAL_ALIGNMENT_LEFT, -1, REPORT_FONT_SIZE, 6, Color(0, 0, 0, 0.7))
		draw_string(font, at, report_text, HORIZONTAL_ALIGNMENT_LEFT, -1, REPORT_FONT_SIZE, Color(1, 1, 0.6))
	for i in _ages.size():
		var progress := _ages[i] / RING_LIFETIME
		var color := RING_COLOR
		color.a *= 1.0 - progress
		draw_arc(_positions[i], RING_RADIUS * (0.6 + 0.4 * progress), 0.0, TAU, 32, color, 4.0, true)


func _on_tapped(screen_position: Vector2) -> void:
	_positions.append(get_global_transform().affine_inverse() * screen_position)
	_ages.append(0.0)
	queue_redraw()
