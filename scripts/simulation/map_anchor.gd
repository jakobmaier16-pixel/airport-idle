class_name MapAnchor
extends RefCounted
## Places things relative to the middle of the map, so the showcase, tests and tools do not depend
## on the map size. Layouts are written in the cells of the 64 x 64 reference map the first
## prototype used (REFERENCE_SIZE); `cell()` moves them to the same spot relative to the map centre.
## The map size is always even (AirportGrid asserts it), so the shift is whole cells.

## The map the layouts in the showcase and the tests were first drawn on.
const REFERENCE_SIZE: Vector2i = Vector2i(64, 64)


## The middle cell of a map of `size` cells (the cell whose corner is the world origin).
static func centre_of(size: Vector2i) -> Vector2i:
	return size / 2


## Cells to add to a reference-map cell to get the same spot on a map of `size` cells.
static func shift_for(size: Vector2i) -> Vector2i:
	return (size - REFERENCE_SIZE) / 2


## `reference_cell` (a cell of the 64 x 64 reference map) on the current airport's map.
static func cell(reference_cell: Vector2i, size: Vector2i) -> Vector2i:
	return reference_cell + shift_for(size)


## A rectangle given in reference-map cells, moved onto the current map.
static func rect(reference_rect: Rect2i, size: Vector2i) -> Rect2i:
	return Rect2i(reference_rect.position + shift_for(size), reference_rect.size)


## The cell `offset` cells from the map centre of a map of `size` cells.
static func from_centre(offset: Vector2i, size: Vector2i) -> Vector2i:
	return centre_of(size) + offset
