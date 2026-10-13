class_name StarRating
extends Control
## Draws five stars, filled up to `value` in half steps (design doc §11.7).
## Drawn as polygons because the default font has no star glyph.

const STAR_COUNT: int = 5
const FILLED: Color = Color(1.0, 0.8, 0.25)
const EMPTY: Color = Color(1.0, 1.0, 1.0, 0.25)
const OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.6)

## Stars to fill, 0..5 (rounded to half stars for drawing).
@export var value: float = 0.0:
	set(new_value):
		var rounded := Reputation.shown_stars(new_value)
		if rounded != value:
			value = rounded
			queue_redraw()

# One star's outline (unit size, centered on 0), built once.
var _shape: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	for i in 10:
		var angle := -PI / 2.0 + i * PI / 5.0
		var radius := 0.5 if i % 2 == 0 else 0.2
		_shape.append(Vector2(cos(angle), sin(angle)) * radius)


func _draw() -> void:
	var star_size := minf(size.y, size.x / STAR_COUNT)
	for i in STAR_COUNT:
		var center := Vector2(star_size * (i + 0.5), star_size * 0.55)
		var points := _transformed(center, star_size)
		draw_colored_polygon(points, EMPTY)
		var fill := clampf(value - i, 0.0, 1.0)
		if fill >= 1.0:
			draw_colored_polygon(points, FILLED)
		elif fill > 0.0:
			draw_colored_polygon(_left_half(points, center.x), FILLED)
		var closed := points.duplicate()
		closed.append(points[0])
		draw_polyline(closed, OUTLINE, 1.5, true)


func _transformed(center: Vector2, star_size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in _shape:
		points.append(center + point * star_size)
	return points


# The part of the star left of x = `cut` (for half stars).
func _left_half(points: PackedVector2Array, cut: float) -> PackedVector2Array:
	var left := Geometry2D.intersect_polygons(points, PackedVector2Array([
		Vector2(cut - 1000.0, -1000.0), Vector2(cut, -1000.0), Vector2(cut, 1000.0), Vector2(cut - 1000.0, 1000.0)]))
	return left[0] if not left.is_empty() else PackedVector2Array()
