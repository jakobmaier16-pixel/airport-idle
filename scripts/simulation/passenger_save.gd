class_name PassengerSave
extends RefCounted
## The passengers in a save game (save format 6, tech architecture §13): one compressed block of
## packed numbers instead of a long list of dictionaries with 17-digit floats.
##
## A passenger as a "record" (Dictionary, see `record_of` keys below) is turned into columns
## (all states, then all flights, ...), which compress well, then deflated and stored as base64
## text. Positions keep the engine's own 32-bit precision and times keep 64 bits, so a loaded
## game continues exactly like the saved one. Paths are grid cells (index = y * width + x), so
## the grid width is stored too, and only the part of the path still ahead is kept.

const NO_TYPE: int = 255
## Bytes one passenger takes in all the fixed-size columns together (without its path cells).
const RECORD_BYTES: int = 98

## Record keys: state, flight, type (id text), arriving, transfer, by_car, has_bag, goal, target
## (building id), color, after_shop, position (Vector3), offset (Vector3), path (PackedInt32Array,
## cells still ahead), bag_ready_at, queued_since, visit_left, leave_shop_by, mood, walked, retry_in.
const TIMES: Array[String] = ["bag_ready_at", "queued_since", "visit_left", "leave_shop_by", "mood", "walked", "retry_in"]


static func encode(records: Array[Dictionary], grid_width: int) -> Dictionary:
	if records.is_empty():
		return {"count": 0, "grid_width": grid_width, "types": [], "raw_size": 0, "data": ""}
	var types: Array[String] = []
	var type_index: Dictionary = {}
	for record in records:
		var id: String = record["type"]
		if not type_index.has(id):
			type_index[id] = types.size()
			types.append(id)
	var buffer := StreamPeerBuffer.new()
	for record in records:
		buffer.put_u8(int(record["state"]))
	for record in records:
		buffer.put_32(int(record["flight"]))
	for record in records:
		buffer.put_u8(type_index[record["type"]])
	for record in records:
		var flags := int(record["arriving"]) | int(record["transfer"]) << 1 | int(record["by_car"]) << 2 | int(record["has_bag"]) << 3
		buffer.put_u8(flags)
	for record in records:
		buffer.put_u8(int(record["goal"]))
		buffer.put_u8(int(record["after_shop"]))
		buffer.put_u8(int(record["color"]))
	for record in records:
		buffer.put_32(int(record["target"]))
	for key in ["position", "offset"]:
		for record in records:
			var vector: Vector3 = record[key]
			buffer.put_float(vector.x)
			buffer.put_float(vector.y)
			buffer.put_float(vector.z)
	for key in TIMES:
		for record in records:
			buffer.put_double(float(record[key]))
	for record in records:
		buffer.put_u32((record["path"] as PackedInt32Array).size())
	for record in records:
		for cell in record["path"] as PackedInt32Array:
			buffer.put_32(cell)
	var raw := buffer.data_array
	return {
		"count": records.size(), "grid_width": grid_width, "types": types, "raw_size": raw.size(),
		"data": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE)),
	}


## Returns the records, or an empty list if the block is damaged.
static func decode(packed: Dictionary) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var count := int(packed.get("count", 0))
	var raw_size := int(packed.get("raw_size", 0))
	if count <= 0 or raw_size <= 0:
		return records
	var raw := Marshalls.base64_to_raw(String(packed.get("data", ""))).decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_size:
		push_warning("The saved passengers are damaged and were dropped.")
		return records
	# Every length below is checked against the bytes really there, so a damaged block can't
	# make us allocate or read far beyond the buffer.
	if count > raw.size() / RECORD_BYTES:
		push_warning("The saved passengers are inconsistent and were dropped.")
		return records
	var types: Array = packed.get("types", [])
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = raw
	for i in count:
		records.append({})
	for record in records:
		record["state"] = buffer.get_u8()
	for record in records:
		record["flight"] = buffer.get_32()
	for record in records:
		var index := buffer.get_u8()
		record["type"] = String(types[index]) if index < types.size() else ""
	for record in records:
		var flags := buffer.get_u8()
		record["arriving"] = flags & 1 != 0
		record["transfer"] = flags & 2 != 0
		record["by_car"] = flags & 4 != 0
		record["has_bag"] = flags & 8 != 0
	for record in records:
		record["goal"] = buffer.get_u8()
		record["after_shop"] = buffer.get_u8()
		record["color"] = buffer.get_u8()
	for record in records:
		record["target"] = buffer.get_32()
	for key in ["position", "offset"]:
		for record in records:
			record[key] = Vector3(buffer.get_float(), buffer.get_float(), buffer.get_float())
	for key in TIMES:
		for record in records:
			record[key] = buffer.get_double()
	var lengths := PackedInt32Array()
	var total_cells := 0
	for record in records:
		var length := buffer.get_u32()
		total_cells += length
		if length > (raw.size() - buffer.get_position()) / 4 or total_cells * 4 > raw.size():
			push_warning("The saved passengers are inconsistent and were dropped.")
			return []
		lengths.append(length)
	if buffer.get_position() + total_cells * 4 != raw.size():
		push_warning("The saved passengers are inconsistent and were dropped.")
		return []
	for i in count:
		var path := PackedInt32Array()
		path.resize(lengths[i])
		for k in lengths[i]:
			path[k] = buffer.get_32()
		records[i]["path"] = path
	return records


## Cells of a record's path on a grid of another width: the same (x, y) cells moved by `shift`
## (a smaller map placed in the middle of a bigger one), or an empty path if one of them doesn't
## exist on the current grid (the passenger then finds a new way).
static func remap_path(path: PackedInt32Array, from_width: int, to_size: Vector2i, shift: Vector2i = Vector2i.ZERO) -> PackedInt32Array:
	if from_width == to_size.x and shift == Vector2i.ZERO:
		for cell in path:
			if cell < 0 or cell >= to_size.x * to_size.y:
				return PackedInt32Array()
		return path
	var result := PackedInt32Array()
	if from_width <= 0:
		return result
	for cell in path:
		var x := cell % from_width + shift.x
		var y := cell / from_width + shift.y
		if cell < 0 or x < 0 or y < 0 or x >= to_size.x or y >= to_size.y:
			return PackedInt32Array()
		result.append(y * to_size.x + x)
	return result


## Version 5 saves: a list of dictionaries with world-position paths. Returns records, with the
## paths turned into cells of a grid of `map_size` cells of `cell_size` meters (centered on the origin).
static func from_v5(entries: Array, map_size: Vector2i, cell_size: float) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var origin_x := -map_size.x * cell_size * 0.5
	var origin_z := -map_size.y * cell_size * 0.5
	for entry: Dictionary in entries:
		var offset := _vector(entry.get("offset"))
		var flat: Array = entry.get("path", [])
		var path := PackedInt32Array()
		var first := int(entry.get("path_index", 0))
		for k in range(first * 3, flat.size() - 2, 3):
			var x := floori((float(flat[k]) - offset.x - origin_x) / cell_size)
			var y := floori((float(flat[k + 2]) - offset.z - origin_z) / cell_size)
			path.append(y * map_size.x + x)
		records.append({
			"state": int(entry.get("state", 0)), "flight": int(entry.get("flight", -1)), "type": String(entry.get("type", "")),
			"arriving": bool(entry.get("arriving", false)), "transfer": bool(entry.get("transfer", false)),
			"by_car": bool(entry.get("by_car", false)), "has_bag": bool(entry.get("has_bag", false)),
			"goal": int(entry.get("goal", 0)), "target": int(entry.get("target", 0)), "color": int(entry.get("color", 0)),
			"after_shop": int(entry.get("after_shop", BuildingType.Role.GATE)),
			"position": _vector(entry.get("position")), "offset": offset, "path": path,
			"bag_ready_at": float(entry.get("bag_ready_at", 0.0)), "queued_since": float(entry.get("queued_since", 0.0)),
			"visit_left": float(entry.get("visit_left", 0.0)), "leave_shop_by": float(entry.get("leave_shop_by", 0.0)),
			"mood": float(entry.get("mood", 100.0)), "walked": float(entry.get("walked", 0.0)),
			"retry_in": float(entry.get("retry_in", 0.0)),
		})
	return records


static func _vector(values: Variant) -> Vector3:
	var list: Array = values if values is Array else [0.0, 0.0, 0.0]
	return Vector3(float(list[0]), float(list[1]), float(list[2]))
