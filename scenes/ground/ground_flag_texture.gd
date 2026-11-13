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

var image: Image
var texture: ImageTexture
## Number of chunks the last `refresh()` / `fill_all()` copied (for tests and the performance budget).
var last_chunks_copied: int = 0

var _grid: AirportGrid


func _init(grid: AirportGrid) -> void:
	_grid = grid
	if maxi(grid.size.x, grid.size.y) > MAX_SAFE_SIDE:
		push_warning("Map %s is larger than %d texels: the ground texture may not fit on every GPU." % [grid.size, MAX_SAFE_SIDE])
	image = Image.create_empty(grid.size.x, grid.size.y, false, Image.FORMAT_R8)
	fill_all()
	texture = ImageTexture.create_from_image(image)


## Copies every allocated chunk (initial build, after a load). Empty chunks stay 0 (the image starts
## zeroed), so the cost follows the allocated chunks, not the map.
func fill_all() -> void:
	image.fill(Color(0, 0, 0))
	_grid.take_dirty_chunks()
	last_chunks_copied = 0
	for coord in _grid.get_allocated_chunks():
		_copy_chunk(coord)
		last_chunks_copied += 1


## Copies the chunks that changed since the last call and updates the GPU texture. Returns how many.
func refresh() -> int:
	var dirty := _grid.take_dirty_chunks()
	last_chunks_copied = dirty.size()
	if dirty.is_empty():
		return 0
	for coord in dirty:
		_copy_chunk(coord)
	texture.update(image)
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
	var chunk_image := Image.create_from_data(AirportGrid.CHUNK_SIZE, AirportGrid.CHUNK_SIZE, false, Image.FORMAT_R8, flags)
	image.blit_rect(chunk_image, Rect2i(Vector2i.ZERO, area.size), base)
