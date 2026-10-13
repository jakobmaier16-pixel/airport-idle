class_name AirlineCatalog
extends Resource
## Every airline in the game (data/airlines/catalog.tres). Save games look airlines up by id.

@export var types: Array[AirlineType] = []


func find(id: StringName) -> AirlineType:
	for type in types:
		if type.id == id:
			return type
	return null
