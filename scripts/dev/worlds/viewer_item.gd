class_name ViewerItem
extends RefCounted
## One entry of the asset viewer's catalog (see ViewerCatalog): a building type, a ground surface,
## a plane or a display-only item.

enum Kind { BUILDING, GROUND, PLANE, DISPLAY }
enum Surface { GRASS, WALKWAY, TAXIWAY }

var id: StringName = &""
var display_name: String = ""
var category: String = ""
var sub_category: String = ""
var kind: Kind = Kind.BUILDING
## BUILDING: the type that is placed for real.
var building_type: BuildingType = null
## GROUND: which surface.
var surface: Surface = Surface.GRASS
## PLANE: wide-body or narrow-body.
var wide_body: bool = false
## DISPLAY: the resource.
var display: DisplayItem = null


## "Landside › Props" or just "Ground".
func category_path() -> String:
	return category if sub_category.is_empty() else "%s › %s" % [category, sub_category]
