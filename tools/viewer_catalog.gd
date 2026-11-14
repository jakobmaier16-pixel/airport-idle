extends Node
## Command-line entry of tools/viewer_catalog.sh (scene viewer_catalog.tscn): prints the asset viewer's
## numbered catalog: number, id, name, category and sizes. "No. 12" in Jakob's words is the id on line 12.


func _ready() -> void:
	var list := ViewerCatalog.items()
	for i in list.size():
		var item := list[i]
		var size := ViewerCatalog.model_aabb(item, self).size
		var footprint := ""
		if ViewerCatalog.has_footprint(item):
			var cells := ViewerCatalog.cells_of(item)
			footprint = "%dx%d cells" % [cells.x, cells.y]
		print("VIEWER %2d | %-28s | %-24s | %-22s | %-12s | model %.2f x %.2f x %.2f m (w x d x h)" % [
			i + 1, item.id, item.display_name, item.category_path(), footprint, size.x, size.z, size.y])
	print("VIEWER total %d" % list.size())
	get_tree().quit()
