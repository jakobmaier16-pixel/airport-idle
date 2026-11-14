class_name DisplayItem
extends Resource
## Something the asset viewer can show before it is a building: a wall, a ceiling, a hall in
## cross-section, or just a surface material. Listed in data/viewer/display_items.tres.
## Give a `scene` to show a model, or a `material` to show a swatch (a slab of `swatch_size` metres).

## Stable name, used by tests and tools (e.g. "swatch_grass"). Unique among all viewer items.
@export var id: StringName
## Name shown in the viewer.
@export var display_name: String
## The viewer's category row, e.g. "Materials".
@export var category: String = "Materials"
## A model shown as it is, standing on the ground with its origin at the middle of its footprint.
@export var scene: PackedScene
## A surface material (assets/materials) shown as a swatch.
@export var material: Material
## Width x height x depth of the swatch in metres (materials only).
@export var swatch_size: Vector3 = Vector3(4.0, 0.1, 4.0)
