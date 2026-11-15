class_name Decals
extends Node2D
## The ground, plus everything that stays on it forever: blood, bodies, shell
## casings, scorch marks.
##
## HOW IT STAYS FAST: nothing here is a node. The ground is a picture (an
## off-screen SubViewport that is never cleared). A new decal is "stamped"
## onto that picture once and then costs nothing, so the map can hold tens of
## thousands of decals at the same speed as zero.
##
## THE MAP IS BIG, so the picture is cut into squares ("chunks"). A chunk is
## only made when the screen first comes near it (or something bleeds on it),
## so a run only pays for the ground it has actually seen.

const T_GROUND := 0
const T_TEX := 1
const T_RECT := 2

# How much detail the ground gets, per 1000 x 1000 px.
const PATCHES_PER_MILLION := 62.0
const TUFTS_PER_MILLION := 310.0
const PEBBLES_PER_MILLION := 66.0
const PATCH_COLORS := [
	Color(0.24, 0.22, 0.16, 0.24), Color(0.47, 0.43, 0.33, 0.24),
	Color(0.27, 0.33, 0.18, 0.26), Color(0.33, 0.40, 0.22, 0.22),
	Color(0.42, 0.37, 0.27, 0.20),
]

class Chunk:
	var cx := 0
	var cy := 0
	var rect := Rect2()           # the part of the world it covers
	var viewport: SubViewport
	var stamper: DrawLayer
	var queue: Array = []         # stamps waiting for the next frame
	var drawing: Array = []       # stamps being painted this frame
	var dirty := false

var ground_tint := Color(0, 0, 0, 0)   # the map's colour wash over the ground (set before the first frame)
var ground_floor: String = Config.GROUND_FLOOR      # the picture the ground is made of (assets/ground/<name>.jpg)
var ground_litter: Array = Config.GROUND_LITTER     # ...and the pictures of the soft patches on it
var chunks_made := 0
var stamps_made := 0          # everything ever put on the ground this run (a count for the tests)

var _arena := Rect2(Vector2.ZERO, Config.ARENA_SIZE)   # the playable area
var _area := Rect2()          # everything that gets ground: the arena plus a margin under the trees
var _margin: float
var _res: float
var _cols := 1
var _rows := 1
var _chunk_size := Vector2.ONE
var _inv_chunk := Vector2.ONE
var _chunks: Array = []       # Chunk or null, one per square of the map
var _dirty: Array[Chunk] = []
var _seed := 0
var _splats: Array[Texture2D] = []
var _dot: Texture2D
var _glow: Texture2D
var _floor_tex: Texture2D     # null = no picture: plain painted dirt
var _litter_tex: Array[Texture2D] = []


## Say how big the map is. Call before the node enters the scene.
func setup(arena_rect: Rect2) -> void:
	_arena = arena_rect


func _ready() -> void:
	_margin = Config.ARENA_OUTER_MARGIN
	_res = Config.DECAL_RESOLUTION
	_splats = [Art.t("splat_0"), Art.t("splat_1"), Art.t("splat_2")]
	_dot = Art.t("dot")
	_glow = Art.t("glow")
	_seed = randi()
	_floor_tex = _ground_picture(ground_floor)
	for litter: Variant in ground_litter:
		var picture := _ground_picture(String(litter))
		if picture != null:
			_litter_tex.append(picture)

	_area = _arena.grow(_margin)
	_cols = maxi(int(ceil(_area.size.x / Config.DECAL_CHUNK_SIZE)), 1)
	_rows = maxi(int(ceil(_area.size.y / Config.DECAL_CHUNK_SIZE)), 1)
	_chunk_size = Vector2(_area.size.x / _cols, _area.size.y / _rows)
	_inv_chunk = Vector2.ONE / _chunk_size
	_chunks.resize(_cols * _rows)


func _process(_delta: float) -> void:
	if _dirty.is_empty():
		return
	# Paint this frame's stamps exactly once, then the viewports go back to sleep.
	for c: Chunk in _dirty:
		c.drawing = c.queue
		c.queue = []
		c.dirty = false
		c.stamper.queue_redraw()
		c.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_dirty.clear()


# ----------------------------------------------------------------------------
#  Chunks
# ----------------------------------------------------------------------------
## Make sure there is ground wherever `view` (a rectangle of the world, e.g.
## what the camera shows plus a bit) reaches. `limit` = how many new chunks
## may be made in this call (making one takes a moment; 0 = as many as needed).
func show_area(view: Rect2, limit: int = 0) -> void:
	var x0 := clampi(int((view.position.x - _area.position.x) * _inv_chunk.x), 0, _cols - 1)
	var x1 := clampi(int((view.end.x - _area.position.x) * _inv_chunk.x), 0, _cols - 1)
	var y0 := clampi(int((view.position.y - _area.position.y) * _inv_chunk.y), 0, _rows - 1)
	var y1 := clampi(int((view.end.y - _area.position.y) * _inv_chunk.y), 0, _rows - 1)
	var made := 0
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if _chunks[cy * _cols + cx] == null:
				_chunk(cx, cy)
				made += 1
				if limit > 0 and made >= limit:
					return


func chunk_count() -> int:
	return _cols * _rows


## Has the ground at this spot been made yet?
func has_ground(pos: Vector2) -> bool:
	var cx := clampi(int((pos.x - _area.position.x) * _inv_chunk.x), 0, _cols - 1)
	var cy := clampi(int((pos.y - _area.position.y) * _inv_chunk.y), 0, _rows - 1)
	return _chunks[cy * _cols + cx] != null


func _chunk(cx: int, cy: int) -> Chunk:
	var index := cy * _cols + cx
	var c: Chunk = _chunks[index]
	if c != null:
		return c
	c = Chunk.new()
	c.cx = cx
	c.cy = cy
	c.rect = Rect2(_area.position + Vector2(cx, cy) * _chunk_size, _chunk_size)
	var pixels := Vector2i((_chunk_size * _res).ceil())
	var per_px := Vector2(pixels) / _chunk_size          # picture pixels per world pixel

	c.viewport = SubViewport.new()
	c.viewport.size = pixels
	c.viewport.disable_3d = true
	c.viewport.transparent_bg = false
	c.viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	c.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(c.viewport)

	c.stamper = DrawLayer.new()
	c.stamper.painter = _paint.bind(c)
	c.stamper.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED   # (the ground pictures repeat)
	c.stamper.position = -c.rect.position * per_px
	c.stamper.scale = per_px
	c.viewport.add_child(c.stamper)

	var sprite := Sprite2D.new()
	sprite.texture = c.viewport.get_texture()
	sprite.centered = false
	sprite.position = c.rect.position
	sprite.scale = Vector2.ONE / per_px
	add_child(sprite)

	c.queue.append([T_GROUND])
	c.dirty = true
	_dirty.append(c)
	_chunks[index] = c
	chunks_made += 1
	return c


## Hand a stamp to every chunk it touches (nearly always just one).
func _route(s: Array, pos: Vector2, reach: float) -> void:
	var x0 := clampi(int((pos.x - reach - _area.position.x) * _inv_chunk.x), 0, _cols - 1)
	var x1 := clampi(int((pos.x + reach - _area.position.x) * _inv_chunk.x), 0, _cols - 1)
	var y0 := clampi(int((pos.y - reach - _area.position.y) * _inv_chunk.y), 0, _rows - 1)
	var y1 := clampi(int((pos.y + reach - _area.position.y) * _inv_chunk.y), 0, _rows - 1)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var c := _chunk(cx, cy)
			c.queue.append(s)
			if not c.dirty:
				c.dirty = true
				_dirty.append(c)


# ----------------------------------------------------------------------------
#  Public API
# ----------------------------------------------------------------------------
## Stamp any texture onto the ground.
func stamp(texture: Texture2D, pos: Vector2, rot: float, size: Vector2, color: Color) -> void:
	stamps_made += 1
	_route([T_TEX, texture, pos, rot, size, color], pos, maxf(size.x, size.y) * 0.71)


func stamp_rect(pos: Vector2, rot: float, size: Vector2, color: Color) -> void:
	stamps_made += 1
	_route([T_RECT, pos, rot, size, color], pos, maxf(size.x, size.y) * 0.71)


## A pool / splash of blood. `dir` stretches it in the direction of the hit.
func blood_splat(pos: Vector2, size: float, dir: Vector2 = Vector2.ZERO) -> void:
	var color := Config.BLOOD_COLOR_DARK.lerp(Config.BLOOD_COLOR, randf())
	color.a = randf_range(0.72, 0.92)
	var tex: Texture2D = _splats[randi() % _splats.size()]
	var rot := randf() * TAU
	var dims := Vector2(size, size)
	if dir != Vector2.ZERO:
		rot = dir.angle() + randf_range(-0.3, 0.3)
		dims = Vector2(size * randf_range(1.2, 1.7), size * randf_range(0.7, 1.0))
	stamp(tex, pos, rot, dims, color)


func blood_dot(pos: Vector2, size: float) -> void:
	var color := Config.BLOOD_COLOR_DARK.lerp(Config.BLOOD_COLOR, randf())
	color.a = randf_range(0.7, 0.9)
	stamp(_dot, pos, 0.0, Vector2(size, size), color)


func scorch(pos: Vector2, radius: float) -> void:
	# A soft burnt patch with a darker core and a few cinders around it.
	stamp(_glow, pos, 0.0, Vector2(radius, radius) * 3.0, Color(0.04, 0.03, 0.02, 0.7))
	stamp(_glow, pos, 0.0, Vector2(radius, radius) * 1.6, Color(0.02, 0.015, 0.01, 0.8))
	for k in 7:
		var p := pos + Vector2.from_angle(randf() * TAU) * randf_range(radius * 0.5, radius * 1.3)
		var s := randf_range(3.0, 8.0)
		stamp(_dot, p, 0.0, Vector2(s, s), Color(0.05, 0.04, 0.03, 0.6))


## A dead zombie lying on the ground (darkened so it reads as dead).
func body(kind: int, variant: int, pos: Vector2, rot: float, size_scale: float = 1.0) -> void:
	var sprite := "%s_%d" % [Art.ENEMY_SPRITE[kind], variant]
	stamp(Art.t(sprite), pos, rot, Art.size_of(sprite) * size_scale, Color(0.5, 0.42, 0.42, 1.0))


# ----------------------------------------------------------------------------
#  Painting (runs inside a chunk's off-screen viewport)
# ----------------------------------------------------------------------------
func _paint(ci: CanvasItem, c: Chunk) -> void:
	for s: Array in c.drawing:
		match s[0]:
			T_TEX:
				var size: Vector2 = s[4]
				ci.draw_set_transform(s[2], s[3], Vector2.ONE)
				ci.draw_texture_rect(s[1], Rect2(-size * 0.5, size), false, s[5])
			T_RECT:
				var rsize: Vector2 = s[3]
				ci.draw_set_transform(s[1], s[2], Vector2.ONE)
				ci.draw_rect(Rect2(-rsize * 0.5, rsize), s[4])
			T_GROUND:
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				_paint_ground(ci, c)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The ground of one chunk. Everything that can lie across the line between
## two chunks (the big soft patches, the shadows under the trees) is worked
## out from the map's seed and painted in the same order by both, so the
## chunks join without a visible seam.
func _paint_ground(ci: CanvasItem, c: Chunk) -> void:
	var here := c.rect.grow(2.0)
	var rng := RandomNumberGenerator.new()

	# The ground itself: a photo of forest floor, repeated. It is lined up
	# with the MAP (not with this chunk), so neighbouring chunks join.
	if _floor_tex != null:
		var per_px := float(_floor_tex.get_width()) / Config.GROUND_TEXTURE_TILE
		ci.draw_texture_rect_region(_floor_tex, here, Rect2(here.position * per_px, here.size * per_px), Config.GROUND_FLOOR_TINT)
		# Soft-edged patches of leaf litter and moss: this chunk's and its
		# neighbours' (they reach across the line).
		var litter := int(round(Config.GROUND_LITTER_PER_MILLION * _chunk_size.x * _chunk_size.y / 1000000.0))
		for ny in range(c.cy - 1, c.cy + 2):
			for nx in range(c.cx - 1, c.cx + 2):
				if nx < 0 or ny < 0 or nx >= _cols or ny >= _rows or _litter_tex.is_empty():
					continue
				rng.seed = _seed + nx * 49157 + ny * 786433 + 7
				var corner := _area.position + Vector2(nx, ny) * _chunk_size
				for i in litter:
					var at := corner + Vector2(rng.randf(), rng.randf()) * _chunk_size
					var radius := rng.randf_range(Config.GROUND_LITTER_RADIUS_MIN, Config.GROUND_LITTER_RADIUS_MAX)
					_litter_patch(ci, _litter_tex[rng.randi() % _litter_tex.size()], at, radius, rng)
	else:
		# Dusty dirt base.
		ci.draw_rect(here, Color("5d5646"))

	# Big soft patches of darker / lighter dirt and grass: this chunk's and
	# its neighbours' (they reach across the line).
	var patches := int(round(PATCHES_PER_MILLION * _chunk_size.x * _chunk_size.y / 1000000.0))
	for ny in range(c.cy - 1, c.cy + 2):
		for nx in range(c.cx - 1, c.cx + 2):
			if nx < 0 or ny < 0 or nx >= _cols or ny >= _rows:
				continue
			rng.seed = _seed + nx * 7919 + ny * 104729
			var from := _area.position + Vector2(nx, ny) * _chunk_size
			for i in patches:
				var p := from + Vector2(rng.randf(), rng.randf()) * _chunk_size
				var s := rng.randf_range(150.0, 460.0)
				var size := Vector2(s, s * rng.randf_range(0.6, 1.0))
				ci.draw_set_transform(p, rng.randf() * TAU, Vector2.ONE)
				ci.draw_texture_rect(_glow, Rect2(-size * 0.5, size), false, PATCH_COLORS[rng.randi() % PATCH_COLORS.size()])
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Grass tufts and pebbles (the painted ground only: a photo has its own).
	rng.seed = _seed + c.cx * 15485863 + c.cy * 32452843 + 1
	var area_m := _chunk_size.x * _chunk_size.y / 1000000.0 if _floor_tex == null else 0.0
	for i in int(round(TUFTS_PER_MILLION * area_m)):
		var p := c.rect.position + Vector2(rng.randf(), rng.randf()) * _chunk_size
		var col := Color(0.30, 0.38, 0.20, rng.randf_range(0.35, 0.8)) if rng.randf() < 0.7 else Color(0.40, 0.44, 0.24, 0.6)
		var s := rng.randf_range(3.0, 7.0)
		ci.draw_texture_rect(_dot, Rect2(p, Vector2(s * rng.randf_range(1.0, 2.2), s)), false, col)

	# Pebbles with a tiny shadow.
	for i in int(round(PEBBLES_PER_MILLION * area_m)):
		var p := c.rect.position + Vector2(rng.randf(), rng.randf()) * _chunk_size
		var s := rng.randf_range(3.0, 8.0)
		ci.draw_texture_rect(_dot, Rect2(p + Vector2(1.0, 1.5), Vector2(s, s)), false, Color(0.1, 0.09, 0.07, 0.5))
		var grey := rng.randf_range(0.42, 0.6)
		ci.draw_texture_rect(_dot, Rect2(p, Vector2(s, s)), false, Color(grey, grey, grey * 0.96, 0.9))

	# The map's mood: a wash of colour over everything painted so far.
	if ground_tint.a > 0.0:
		ci.draw_rect(here, ground_tint)

	# Darken the ground outside the playable clearing (under the trees).
	var m := _margin
	var arena := _arena
	var full := _area
	var shade := Color(0.02, 0.04, 0.02, 0.62)
	ci.draw_rect(Rect2(full.position, Vector2(full.size.x, m)), shade)
	ci.draw_rect(Rect2(Vector2(full.position.x, arena.end.y), Vector2(full.size.x, m)), shade)
	ci.draw_rect(Rect2(Vector2(full.position.x, arena.position.y), Vector2(m, arena.size.y)), shade)
	ci.draw_rect(Rect2(Vector2(arena.end.x, arena.position.y), Vector2(m, arena.size.y)), shade)
	# Soft shadow creeping in from the tree line.
	var edge_shadow := Color(0.02, 0.04, 0.02, 0.4)
	var near := c.rect.grow(160.0)
	var step := 90.0
	var x := arena.position.x
	while x <= arena.end.x:
		_shadow_blob(ci, Vector2(x, arena.position.y), edge_shadow, near)
		_shadow_blob(ci, Vector2(x, arena.end.y), edge_shadow, near)
		x += step
	var y := arena.position.y
	while y <= arena.end.y:
		_shadow_blob(ci, Vector2(arena.position.x, y), edge_shadow, near)
		_shadow_blob(ci, Vector2(arena.end.x, y), edge_shadow, near)
		y += step


## A ground picture from assets/ground/ (null if it is not there).
func _ground_picture(picture: String) -> Texture2D:
	for ext: String in ["jpg", "png", "webp"]:
		var path := "res://assets/ground/%s.%s" % [picture, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


## One soft-edged, uneven patch of another ground picture: solid in the
## middle, fading to nothing at the rim. Like the floor it is lined up with
## the map, so the same patch painted by two chunks matches.
func _litter_patch(ci: CanvasItem, picture: Texture2D, at: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	var spokes := 16
	var per_px := 1.0 / Config.GROUND_TEXTURE_TILE
	var tint: Color = Config.GROUND_LITTER_TINT
	var clear := Color(tint.r, tint.g, tint.b, 0.0)
	var rim := PackedVector2Array()
	for i in spokes:
		rim.append(at + Vector2.from_angle(TAU * float(i) / float(spokes)) * radius * rng.randf_range(0.62, 1.0))
	for i in spokes:
		var a := rim[i]
		var b := rim[(i + 1) % spokes]
		var a_in := at.lerp(a, 0.5)
		var b_in := at.lerp(b, 0.5)
		# The solid middle...
		ci.draw_primitive(PackedVector2Array([at, a_in, b_in]), PackedColorArray([tint, tint, tint]),
				PackedVector2Array([at * per_px, a_in * per_px, b_in * per_px]), picture)
		# ...and the ring around it that fades out.
		ci.draw_primitive(PackedVector2Array([a_in, a, b]), PackedColorArray([tint, clear, clear]),
				PackedVector2Array([a_in * per_px, a * per_px, b * per_px]), picture)
		ci.draw_primitive(PackedVector2Array([a_in, b, b_in]), PackedColorArray([tint, clear, tint]),
				PackedVector2Array([a_in * per_px, b * per_px, b_in * per_px]), picture)


func _shadow_blob(ci: CanvasItem, pos: Vector2, color: Color, near: Rect2) -> void:
	if not near.has_point(pos):
		return
	# (The size comes from the position, so two chunks draw the same blob.)
	var s := 190.0 + 90.0 * fposmod(sin(pos.x * 12.9898 + pos.y * 78.233 + float(_seed % 1000)) * 43758.5453, 1.0)
	ci.draw_texture_rect(_glow, Rect2(pos - Vector2(s, s) * 0.5, Vector2(s, s)), false, color)
