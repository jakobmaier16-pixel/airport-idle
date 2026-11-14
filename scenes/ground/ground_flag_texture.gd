class_name GroundFlagTexture
extends RefCounted
## The ground's data texture: an R8 image that is exactly the flag layer of the AirportGrid
## (1 texel = 1 cell, the byte is the cell's flag byte, nearest filter). The ground shader decodes the
## bits. No per-cell colour conversion happens in GDScript: whole chunks are copied (blit) into the
## image, and only chunks that changed since the last `refresh()` (AirportGrid dirty set).
##
## Size: one byte per cell, 3.5 MB at 2,200 x 1,600. Texture size limits: Vulkan guarantees 4,096 per
## side (Mobile renderer), Apple GPUs (A9 and newer, MoltenVK) allow 16,384; the map stays below 4,096.
## `ImageTexture.update` re-sends the whole image to the GPU (a 3.5 MB copy, no per-cell work); Godot
## has no partial upload for ImageTexture.

const MAX_SAFE_SIDE: int = 4096
## A taxiway strip up to this many cells wide gets a centreline (a taxiway must be 12 wide for planes;
## one more is tolerated). Runs longer than this count as "long".
const TAXI_RUN_MAX: int = 13

var image: Image
var texture: ImageTexture
## The taxiway markings, worked out here on the CPU once per change so the shader reads ONE more texel
## per pixel instead of walking the neighbours (RG8, 1 texel per cell):
##   R: 0 = no line; else 14 + (cells after - cells before) along the short axis, so the centreline sits
##      (R - 14) / 2 cells from the cell's middle.
##   G: bit 0 = the short axis is y (the strip runs along x); bit 1 = an edge line on the low side of the
##      cell (the strip ends here and the neighbour is grass); bit 2 = the same on the high side.
var marks_image: Image
var marks_texture: ImageTexture
## Number of chunks the last `refresh()` / `fill_all()` copied (for tests and the performance budget).
var last_chunks_copied: int = 0
## How many times the image was sent to the GPU (`texture.update`); a debug counter for tests.
var upload_count: int = 0

var _grid: AirportGrid
# One chunk-sized image, reused for every chunk copy.
var _chunk_image: Image = Image.create_empty(AirportGrid.CHUNK_SIZE, AirportGrid.CHUNK_SIZE, false, Image.FORMAT_R8)


func _init(grid: AirportGrid) -> void:
	_grid = grid
	if maxi(grid.size.x, grid.size.y) > MAX_SAFE_SIDE:
		push_warning("Map %s is larger than %d texels: the ground texture may not fit on every GPU." % [grid.size, MAX_SAFE_SIDE])
	image = Image.create_empty(grid.size.x, grid.size.y, false, Image.FORMAT_R8)
	marks_image = Image.create_empty(grid.size.x, grid.size.y, false, Image.FORMAT_RG8)
	fill_all()
	texture = ImageTexture.create_from_image(image)
	marks_texture = ImageTexture.create_from_image(marks_image)


## Copies every allocated chunk (initial build, after a load). Empty chunks stay 0 (the image starts
## zeroed), so the cost follows the allocated chunks, not the map.
func fill_all() -> void:
	image.fill(Color(0, 0, 0))
	marks_image.fill(Color(0, 0, 0))
	_grid.take_dirty_chunks()
	last_chunks_copied = 0
	for coord in _grid.get_allocated_chunks():
		_copy_chunk(coord)
		_update_marks(coord)
		last_chunks_copied += 1
	if marks_texture != null:
		marks_texture.update(marks_image)


## Copies the chunks that changed since the last call and updates the GPU texture. Returns how many.
func refresh() -> int:
	var dirty := _grid.take_dirty_chunks()
	last_chunks_copied = dirty.size()
	if dirty.is_empty():
		return 0
	for coord in dirty:
		_copy_chunk(coord)
	# A change can alter the markings up to TAXI_RUN_MAX cells away, i.e. in the neighbour chunks.
	var marks_chunks: Dictionary[Vector2i, bool] = {}
	for coord in dirty:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				marks_chunks[coord + Vector2i(dx, dy)] = true
	for coord in marks_chunks:
		_update_marks(coord)
	texture.update(image)
	marks_texture.update(marks_image)
	upload_count += 1
	return dirty.size()


# Writes the chunk's flag bytes into its square of the image (clipped at the map edge); a chunk that
# is no longer allocated is cleared to 0.
func _copy_chunk(coord: Vector2i) -> void:
	var base := coord * AirportGrid.CHUNK_SIZE
	var area := Rect2i(base, Vector2i(AirportGrid.CHUNK_SIZE, AirportGrid.CHUNK_SIZE)).intersection(Rect2i(Vector2i.ZERO, _grid.size))
	var flags := _grid.get_chunk_flags(coord)
	if flags.is_empty():
		image.fill_rect(area, Color(0, 0, 0))
		return
	_chunk_image.set_data(AirportGrid.CHUNK_SIZE, AirportGrid.CHUNK_SIZE, false, Image.FORMAT_R8, flags)
	image.blit_rect(_chunk_image, Rect2i(Vector2i.ZERO, area.size), base)


# Recomputes the markings of one chunk (see `marks_image`). The taxiway bits of the chunk and a border of
# TAXI_RUN_MAX cells around it are read once; the run lengths along every row and column then come from
# two sweeps, so the cost is a few operations per cell, only for changed chunks.
func _update_marks(coord: Vector2i) -> void:
	var map_rect := Rect2i(Vector2i.ZERO, _grid.size)
	var base := coord * AirportGrid.CHUNK_SIZE
	var area := Rect2i(base, Vector2i(AirportGrid.CHUNK_SIZE, AirportGrid.CHUNK_SIZE)).intersection(map_rect)
	if area.size.x <= 0 or area.size.y <= 0:
		return
	marks_image.fill_rect(area, Color(0, 0, 0))
	if _grid.get_chunk_flags(coord).is_empty():
		return
	var pad := TAXI_RUN_MAX
	var window := area.grow(pad)
	var w := window.size.x
	var h := window.size.y
	# Flag bytes of the window (cells outside the map are 0).
	var flags := PackedByteArray()
	flags.resize(w * h)
	var any_taxiway := false
	for y in h:
		for x in w:
			var value := _grid.get_flags(window.position + Vector2i(x, y))
			flags[y * w + x] = value
			if value & AirportGrid.TAXIWAY_BIT != 0 and area.has_point(window.position + Vector2i(x, y)):
				any_taxiway = true
	if not any_taxiway:
		return
	# Run lengths through each cell: `before` / `after` count the taxiway cells in a row of the same run.
	var left := PackedInt32Array()
	var right := PackedInt32Array()
	var up := PackedInt32Array()
	var down := PackedInt32Array()
	left.resize(w * h)
	right.resize(w * h)
	up.resize(w * h)
	down.resize(w * h)
	for y in h:
		for x in w:
			var index := y * w + x
			if flags[index] & AirportGrid.TAXIWAY_BIT != 0:
				left[index] = (left[index - 1] + 1) if x > 0 and flags[index - 1] & AirportGrid.TAXIWAY_BIT != 0 else 0
				up[index] = (up[index - w] + 1) if y > 0 and flags[index - w] & AirportGrid.TAXIWAY_BIT != 0 else 0
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var index := y * w + x
			if flags[index] & AirportGrid.TAXIWAY_BIT != 0:
				right[index] = (right[index + 1] + 1) if x < w - 1 and flags[index + 1] & AirportGrid.TAXIWAY_BIT != 0 else 0
				down[index] = (down[index + w] + 1) if y < h - 1 and flags[index + w] & AirportGrid.TAXIWAY_BIT != 0 else 0
	for cell_y in area.size.y:
		for cell_x in area.size.x:
			var x := cell_x + area.position.x - window.position.x
			var y := cell_y + area.position.y - window.position.y
			var index := y * w + x
			if flags[index] & AirportGrid.TAXIWAY_BIT == 0:
				continue
			# The short axis: vertical if the strip is at most TAXI_RUN_MAX cells tall here, else horizontal.
			var horizontal := up[index] + down[index] + 1 <= TAXI_RUN_MAX
			var before := up[index]
			var after := down[index]
			var step := w
			if not horizontal:
				before = left[index]
				after = right[index]
				step = 1
				if before + after + 1 > TAXI_RUN_MAX:
					continue  # a junction or a wide area: no line
			var edges := 1 if horizontal else 0
			# An edge line only where the strip borders grass (not a stand, runway or walkway).
			if before == 0 and _is_grass(flags, index - step, w, h):
				edges |= 2
			if after == 0 and _is_grass(flags, index + step, w, h):
				edges |= 4
			marks_image.set_pixel(area.position.x + cell_x, area.position.y + cell_y, Color8(14 + after - before, edges, 0))


func _is_grass(flags: PackedByteArray, index: int, w: int, h: int) -> bool:
	if index < 0 or index >= w * h:
		return true  # beyond the window, only reached at the map edge (the border is wider than a run)
	var value := flags[index]
	return (value >> 6) == 0 and value & AirportGrid.WALKWAY_BIT == 0
