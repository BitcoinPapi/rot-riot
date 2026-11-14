class_name Decals
extends Node2D
## The ground, plus everything that stays on it forever: blood, bodies, shell
## casings, scorch marks.
##
## HOW IT STAYS FAST: nothing here is a node. The ground is one big picture
## (an off-screen SubViewport that is never cleared). A new decal is "stamped"
## onto that picture once and then costs nothing, so the arena can hold tens
## of thousands of decals at the same speed as zero.

const T_GROUND := 0
const T_TEX := 1
const T_RECT := 2

var _viewport: SubViewport
var _stamper: DrawLayer
var _sprite: Sprite2D
var _queue: Array = []       # stamps waiting for the next frame
var _drawing: Array = []     # stamps being painted this frame
var _margin: float
var _res: float
var _splats: Array[Texture2D] = []
var _dot: Texture2D
var _glow: Texture2D


func _ready() -> void:
	_margin = Config.ARENA_OUTER_MARGIN
	_res = Config.DECAL_RESOLUTION
	_splats = [Art.t("splat_0"), Art.t("splat_1"), Art.t("splat_2")]
	_dot = Art.t("dot")
	_glow = Art.t("glow")

	var world_size := Config.ARENA_SIZE + Vector2(_margin, _margin) * 2.0
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(world_size * _res)
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	_stamper = DrawLayer.new()
	_stamper.painter = _paint
	_stamper.position = Vector2(_margin, _margin) * _res
	_stamper.scale = Vector2(_res, _res)
	_viewport.add_child(_stamper)

	_sprite = Sprite2D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.centered = false
	_sprite.position = -Vector2(_margin, _margin)
	_sprite.scale = Vector2.ONE / _res
	add_child(_sprite)

	_queue.append([T_GROUND])


func _process(_delta: float) -> void:
	if _queue.is_empty():
		return
	# Paint this frame's stamps exactly once, then the viewport goes back to sleep.
	_drawing = _queue
	_queue = []
	_stamper.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


# ----------------------------------------------------------------------------
#  Public API
# ----------------------------------------------------------------------------
## Stamp any texture onto the ground.
func stamp(texture: Texture2D, pos: Vector2, rot: float, size: Vector2, color: Color) -> void:
	_queue.append([T_TEX, texture, pos, rot, size, color])


func stamp_rect(pos: Vector2, rot: float, size: Vector2, color: Color) -> void:
	_queue.append([T_RECT, pos, rot, size, color])


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
	stamp(_glow, pos, 0.0, Vector2(radius, radius) * 2.6, Color(0.03, 0.02, 0.02, 0.75))
	stamp(_splats[2], pos, randf() * TAU, Vector2(radius, radius) * 2.0, Color(0.05, 0.04, 0.03, 0.55))


## A dead zombie lying on the ground (darkened so it reads as dead).
func body(kind: int, variant: int, pos: Vector2, rot: float, scale: float = 1.0) -> void:
	var sprite := "%s_%d" % [Art.ENEMY_SPRITE[kind], variant]
	stamp(Art.t(sprite), pos, rot, Art.size_of(sprite) * scale, Color(0.5, 0.42, 0.42, 1.0))


# ----------------------------------------------------------------------------
#  Painting (runs inside the off-screen viewport)
# ----------------------------------------------------------------------------
func _paint(ci: CanvasItem) -> void:
	for s: Array in _drawing:
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
				_paint_ground(ci)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_ground(ci: CanvasItem) -> void:
	var m := _margin
	var arena := Rect2(Vector2.ZERO, Config.ARENA_SIZE)
	var full := arena.grow(m)
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Dusty dirt base.
	ci.draw_rect(full, Color("4b4538"))

	# Big soft patches of darker / lighter dirt and grass.
	var patch_colors := [
		Color(0.22, 0.20, 0.15, 0.30), Color(0.38, 0.35, 0.27, 0.22),
		Color(0.25, 0.31, 0.17, 0.30), Color(0.29, 0.36, 0.20, 0.24),
		Color(0.18, 0.17, 0.13, 0.22),
	]
	for i in 420:
		var p := Vector2(rng.randf_range(full.position.x, full.end.x), rng.randf_range(full.position.y, full.end.y))
		var s := rng.randf_range(150.0, 460.0)
		var size := Vector2(s, s * rng.randf_range(0.6, 1.0))
		ci.draw_set_transform(p, rng.randf() * TAU, Vector2.ONE)
		ci.draw_texture_rect(_glow, Rect2(-size * 0.5, size), false, patch_colors[rng.randi() % patch_colors.size()])
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Grass tufts.
	for i in 1500:
		var p := Vector2(rng.randf_range(full.position.x, full.end.x), rng.randf_range(full.position.y, full.end.y))
		var c := Color(0.30, 0.38, 0.20, rng.randf_range(0.35, 0.8)) if rng.randf() < 0.7 else Color(0.40, 0.44, 0.24, 0.6)
		var s := rng.randf_range(3.0, 7.0)
		ci.draw_texture_rect(_dot, Rect2(p, Vector2(s * rng.randf_range(1.0, 2.2), s)), false, c)

	# Pebbles with a tiny shadow.
	for i in 320:
		var p := Vector2(rng.randf_range(full.position.x, full.end.x), rng.randf_range(full.position.y, full.end.y))
		var s := rng.randf_range(3.0, 8.0)
		ci.draw_texture_rect(_dot, Rect2(p + Vector2(1.0, 1.5), Vector2(s, s)), false, Color(0.1, 0.09, 0.07, 0.5))
		var grey := rng.randf_range(0.42, 0.6)
		ci.draw_texture_rect(_dot, Rect2(p, Vector2(s, s)), false, Color(grey, grey, grey * 0.96, 0.9))

	# Darken the ground outside the playable clearing (under the trees).
	var shade := Color(0.02, 0.04, 0.02, 0.62)
	ci.draw_rect(Rect2(full.position, Vector2(full.size.x, m)), shade)
	ci.draw_rect(Rect2(Vector2(full.position.x, arena.end.y), Vector2(full.size.x, m)), shade)
	ci.draw_rect(Rect2(Vector2(full.position.x, 0.0), Vector2(m, arena.size.y)), shade)
	ci.draw_rect(Rect2(Vector2(arena.end.x, 0.0), Vector2(m, arena.size.y)), shade)
	# Soft shadow creeping in from the tree line.
	var edge_shadow := Color(0.02, 0.04, 0.02, 0.4)
	var step := 90.0
	var x := 0.0
	while x <= arena.size.x:
		_shadow_blob(ci, Vector2(x, 0.0), edge_shadow, rng)
		_shadow_blob(ci, Vector2(x, arena.size.y), edge_shadow, rng)
		x += step
	var y := 0.0
	while y <= arena.size.y:
		_shadow_blob(ci, Vector2(0.0, y), edge_shadow, rng)
		_shadow_blob(ci, Vector2(arena.size.x, y), edge_shadow, rng)
		y += step


func _shadow_blob(ci: CanvasItem, pos: Vector2, color: Color, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(190.0, 280.0)
	ci.draw_texture_rect(_glow, Rect2(pos - Vector2(s, s) * 0.5, Vector2(s, s)), false, color)
