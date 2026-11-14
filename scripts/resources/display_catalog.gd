class_name DisplayCatalog
extends Resource
## The list of every display-only item of the asset viewer (data/viewer/display_items.tres).
## Listed explicitly, like BuildingCatalog: listing res:// folders is unreliable in exported builds.

@export var items: Array[DisplayItem] = []
