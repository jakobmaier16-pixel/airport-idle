class_name BuildingCatalog
extends Resource
## The list of every building type in the game (data/buildings/catalog.tres).
## The build menu shows them in this order; save games look types up by id.

@export var types: Array[BuildingType] = []


## The type with this id, or null if there is none (e.g. a save game from an older version).
func find(id: StringName) -> BuildingType:
	for type in types:
		if type.id == id:
			return type
	return null
