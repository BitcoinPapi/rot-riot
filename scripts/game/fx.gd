class_name Fx
extends Node2D
## Every short-lived visual effect: blood spray, sparks, smoke, muzzle
## flashes, shell casings, tumbling corpses, shockwave rings, swing arcs and
## floating text. All of it is plain data drawn by two canvases (one normal,
## one additive "glow"), so thousands of particles cost almost nothing.
## When blood drops, casings and corpses come to rest they are stamped onto
## the ground (Decals) and stay there for the rest of the run.

const P_BLOOD := 0     # lands as a permanent blood dot
const P_SMOKE := 1     # fades out
const P_SPARK := 2     # additive, fades
const P_FIRE := 3      # additive, fades and shrinks

class Casing:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var rot := 0.0
	var spin := 0.0
	var life := 0.0
	var size := Vector2(2, 5)
	var color := Color.WHITE

class Corpse:
	var kind := 0
	var variant := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var rot := 0.0
	var spin := 0.0
	var life := 0.0
	var max_life := 0.0
	var blood := 1.0
	var charred := false         # burned to death: settles as a black husk
	var tex: Texture2D
	var size := Vector2.ZERO

var game: Game

var _layer: DrawLayer
var _glow_layer: DrawLayer
var _dot: Texture2D
var _glow: Texture2D
var _flash_tex: Texture2D
var _ring_tex: Texture2D
var _font: Font

# Particles, stored as parallel arrays (fast to update, no objects).
var _cap := 0
var _n := 0
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
var _max := PackedFloat32Array()
var _size := PackedFloat32Array()
var _grow := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _col := PackedColorArray()
var _kind := PackedByteArray()

var _casings: Array[Casing] = []
var _corpses: Array[Corpse] = []
var _flashes: Array = []     # [pos, angle, size, life, color]
var _rings: Array = []       # [pos, r_from, r_to, life, max_life, color]
var _arcs: Array = []        # [pos, angle, arc, radius, life, side]
var _lights: Array = []      # [pos, size, life, max_life, color]
var _texts: Array = []       # [pos, text, color, life, max_life, font_size]


func _ready() -> void:
	_dot = Art.t("dot")
	_glow = Art.t("glow")
	_flash_tex = Art.t("flash")
	_ring_tex = Art.t("ring")
	_font = ThemeDB.fallback_font

	_cap = Config.MAX_PARTICLES
	_pos.resize(_cap)
	_vel.resize(_cap)
	_life.resize(_cap)
	_max.resize(_cap)
	_size.resize(_cap)
	_grow.resize(_cap)
	_drag.resize(_cap)
	_col.resize(_cap)
	_kind.resize(_cap)

	_layer = DrawLayer.new()
	_layer.painter = _paint
	add_child(_layer)
	_glow_layer = DrawLayer.new()
	_glow_layer.painter = _paint_glow
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_layer.material = mat
	add_child(_glow_layer)


# ----------------------------------------------------------------------------
#  Emitters (called by weapons, enemies, pickups...)
# ----------------------------------------------------------------------------
func _emit(kind: int, pos: Vector2, vel: Vector2, life: float, size: float, grow: float, drag: float, color: Color) -> void:
	if _n >= _cap:
		return
	var i := _n
	_n += 1
	_pos[i] = pos
	_vel[i] = vel
	_life[i] = life
	_max[i] = life
	_size[i] = size
	_grow[i] = grow
	_drag[i] = drag
	_col[i] = color
	_kind[i] = kind


## Blood flying in the direction of a hit. Each drop leaves a permanent dot.
func blood_spray(pos: Vector2, dir: Vector2, count: int, power: float) -> void:
	for k in count:
		var d := dir.rotated(randf_range(-0.65, 0.65))
		var color := Config.BLOOD_COLOR_DARK.lerp(Config.BLOOD_COLOR, randf())
		_emit(P_BLOOD, pos + d * randf_range(2.0, 10.0), d * randf_range(70.0, 430.0) * power,
				randf_range(0.12, 0.38), randf_range(3.0, 7.5), 0.0, 5.0, color)


## Blood bursting out in all directions.
func blood_burst(pos: Vector2, count: int, power: float) -> void:
	for k in count:
		var d := Vector2.from_angle(randf() * TAU)
		var color := Config.BLOOD_COLOR_DARK.lerp(Config.BLOOD_COLOR, randf())
		_emit(P_BLOOD, pos + d * randf_range(2.0, 12.0), d * randf_range(60.0, 380.0) * power,
				randf_range(0.15, 0.45), randf_range(3.0, 9.0), 0.0, 4.5, color)


func sparks(pos: Vector2, dir: Vector2, count: int) -> void:
	for k in count:
		var d := dir.rotated(randf_range(-0.9, 0.9))
		_emit(P_SPARK, pos, d * randf_range(120.0, 520.0), randf_range(0.08, 0.25),
				randf_range(2.0, 4.0), 0.0, 6.0, Color(1.0, randf_range(0.7, 0.95), 0.4))


## A lick of flame rising off something that is burning.
func ember(pos: Vector2, radius: float) -> void:
	var at := pos + Vector2.from_angle(randf() * TAU) * (randf() * radius)
	_emit(P_FIRE, at, Vector2(randf_range(-20.0, 20.0), randf_range(-70.0, -20.0)), randf_range(0.2, 0.4),
			randf_range(14.0, 24.0), -20.0, 1.0, Color(1.0, randf_range(0.45, 0.75), 0.15, 0.8))


## A critical hit: a burst of bright yellow sparks.
func crit_spark(pos: Vector2, dir: Vector2) -> void:
	_lights.append([pos, 70.0, 0.09, 0.09, Color(1.0, 0.9, 0.3, 0.6)])
	for k in 6:
		var d := dir.rotated(randf_range(-1.4, 1.4))
		_emit(P_SPARK, pos, d * randf_range(160.0, 480.0), randf_range(0.1, 0.22),
				randf_range(3.0, 5.0), 0.0, 6.0, Color(1.0, 0.92, 0.35))


func smoke(pos: Vector2, count: int, size: float) -> void:
	for k in count:
		var d := Vector2.from_angle(randf() * TAU)
		var grey := randf_range(0.18, 0.34)
		_emit(P_SMOKE, pos + d * randf() * size * 0.3, d * randf_range(8.0, 50.0), randf_range(0.35, 0.9),
				size * randf_range(0.8, 1.3), size * 1.4, 2.0, Color(grey, grey, grey, 0.5))


func dust(pos: Vector2, count: int) -> void:
	for k in count:
		var d := Vector2.from_angle(randf() * TAU)
		_emit(P_SMOKE, pos + d * randf() * 10.0, d * randf_range(20.0, 90.0), randf_range(0.25, 0.6),
				randf_range(8.0, 16.0), 22.0, 3.0, Color(0.55, 0.5, 0.4, 0.4))


func muzzle_flash(pos: Vector2, dir: Vector2, size: float, color: Color) -> void:
	_flashes.append([pos, dir.angle(), size, Config.MUZZLE_FLASH_TIME, color])
	_lights.append([pos, size * 3.2, 0.07, 0.07, Color(color.r, color.g, color.b, 0.45)])
	for k in 3:
		var d := dir.rotated(randf_range(-0.5, 0.5))
		_emit(P_SPARK, pos, d * randf_range(200.0, 600.0), randf_range(0.05, 0.14), randf_range(2.0, 3.5), 0.0, 7.0, color)


## A spent shell flung sideways out of the gun. `kind` is "brass" or "shell".
func casing(pos: Vector2, aim: Vector2, kind: String) -> void:
	var c := Casing.new()
	var side := Vector2(-aim.y, aim.x) * (1.0 if randf() < 0.85 else -1.0)
	c.pos = pos
	c.vel = (side * randf_range(150.0, 280.0) - aim * randf_range(20.0, 110.0))
	c.rot = randf() * TAU
	c.spin = randf_range(-30.0, 30.0)
	c.life = Config.CASING_LIFETIME * randf_range(0.8, 1.1)
	if kind == "shell":
		c.size = Vector2(3.4, 7.5)
		c.color = Color(0.82, 0.16, 0.13)
	else:
		c.size = Vector2(2.4, 5.4)
		c.color = Color(0.93, 0.74, 0.28)
	_casings.append(c)


## An empty magazine (or ammo box, clip, shell case, fuel can) dropped during
## a reload. Like casings, it comes to rest and stays on the ground.
func mag_drop(pos: Vector2, aim: Vector2, kind: String) -> void:
	var c := Casing.new()
	c.pos = pos
	c.vel = Vector2.from_angle(randf() * TAU) * randf_range(25.0, 80.0) - aim * randf_range(10.0, 45.0)
	c.rot = randf() * TAU
	c.spin = randf_range(-14.0, 14.0)
	c.life = Config.CASING_LIFETIME * 0.8
	match kind:
		"box":
			c.size = Vector2(8.0, 10.5)
			c.color = Color(0.33, 0.37, 0.24)
		"clip":
			c.size = Vector2(2.6, 9.0)
			c.color = Color(0.9, 0.72, 0.3)
		"shellcase":
			c.size = Vector2(6.0, 10.0)
			c.color = Color(0.85, 0.68, 0.28)
		"can":
			c.size = Vector2(7.0, 11.0)
			c.color = Color(0.7, 0.2, 0.15)
		_:
			c.size = Vector2(4.6, 9.0)
			c.color = Color(0.2, 0.21, 0.25)
	_casings.append(c)


## A dead zombie tumbling away from the hit before it settles on the ground.
func corpse(e: Enemy, dir: Vector2) -> void:
	var c := Corpse.new()
	c.kind = e.kind
	c.variant = e.variant
	c.pos = e.pos
	c.vel = dir * randf_range(130.0, 260.0) + e.kb * 0.75
	c.rot = e.rotation
	c.spin = randf_range(-9.0, 9.0)
	c.life = Config.CORPSE_SLIDE_TIME * randf_range(0.8, 1.2)
	c.max_life = c.life
	c.blood = e.blood
	c.charred = e.burn_t > 0.0
	c.tex = e.tex_normal
	c.size = Vector2(e.tex_normal.get_size()) / Art.PX
	_corpses.append(c)


func ring(pos: Vector2, r_from: float, r_to: float, life: float, color: Color) -> void:
	_rings.append([pos, r_from, r_to, life, life, color])


func light(pos: Vector2, size: float, life: float, color: Color) -> void:
	_lights.append([pos, size, life, life, color])


func swing_arc(pos: Vector2, dir: Vector2, arc_deg: float, radius: float, side: float) -> void:
	_arcs.append([pos, dir.angle(), deg_to_rad(arc_deg), radius, 0.14, side])


func text(pos: Vector2, message: String, color: Color, font_size: int = 20, life: float = 0.9) -> void:
	_texts.append([pos, message, color, life, life, font_size])


func explosion(pos: Vector2, radius: float) -> void:
	_lights.append([pos, radius * 3.4, 0.22, 0.22, Color(1.0, 0.75, 0.35, 0.9)])
	_rings.append([pos, radius * 0.25, radius * 1.15, 0.28, 0.28, Color(1.0, 0.85, 0.6, 0.9)])
	for k in 16:
		var d := Vector2.from_angle(randf() * TAU)
		_emit(P_FIRE, pos + d * randf() * radius * 0.25, d * randf_range(40.0, radius * 2.4),
				randf_range(0.2, 0.5), randf_range(26.0, 54.0), -40.0, 4.0,
				Color(1.0, randf_range(0.45, 0.8), randf_range(0.1, 0.3), 0.85))
	for k in 18:
		var d := Vector2.from_angle(randf() * TAU)
		_emit(P_SPARK, pos, d * randf_range(200.0, 760.0), randf_range(0.15, 0.45),
				randf_range(2.5, 5.0), 0.0, 4.0, Color(1.0, 0.85, 0.5))
	for k in 10:
		var d := Vector2.from_angle(randf() * TAU)
		var grey := randf_range(0.12, 0.26)
		_emit(P_SMOKE, pos + d * randf() * radius * 0.5, d * randf_range(10.0, 70.0),
				randf_range(0.6, 1.3), randf_range(30.0, 56.0), 34.0, 1.5, Color(grey, grey, grey, 0.55))


# ----------------------------------------------------------------------------
#  Update
# ----------------------------------------------------------------------------
func tick(dt: float) -> void:
	var decals := game.decals

	# Particles (swap-remove keeps the arrays packed).
	var i := 0
	while i < _n:
		var life := _life[i] - dt
		if life <= 0.0:
			if _kind[i] == P_BLOOD:
				decals.blood_dot(_pos[i], _size[i] * 1.35)
			_n -= 1
			if i < _n:
				_pos[i] = _pos[_n]
				_vel[i] = _vel[_n]
				_life[i] = _life[_n]
				_max[i] = _max[_n]
				_size[i] = _size[_n]
				_grow[i] = _grow[_n]
				_drag[i] = _drag[_n]
				_col[i] = _col[_n]
				_kind[i] = _kind[_n]
			continue
		_life[i] = life
		var v := _vel[i]
		_pos[i] += v * dt
		_vel[i] = v * maxf(1.0 - _drag[i] * dt, 0.0)
		_size[i] = maxf(_size[i] + _grow[i] * dt, 0.5)
		i += 1

	# Shell casings: bounce out, spin, then stay on the ground forever.
	i = 0
	while i < _casings.size():
		var c := _casings[i]
		c.life -= dt
		c.pos += c.vel * dt
		c.vel *= maxf(1.0 - 6.5 * dt, 0.0)
		c.rot += c.spin * dt
		c.spin *= maxf(1.0 - 4.0 * dt, 0.0)
		if c.life <= 0.0:
			decals.stamp_rect(c.pos, c.rot, c.size, c.color.darkened(0.25))
			_casings[i] = _casings[_casings.size() - 1]
			_casings.pop_back()
		else:
			i += 1

	# Corpses: slide, spin, then become a permanent body + blood pool.
	i = 0
	while i < _corpses.size():
		var b := _corpses[i]
		b.life -= dt
		b.pos += b.vel * dt
		b.vel *= maxf(1.0 - 7.0 * dt, 0.0)
		b.rot += b.spin * dt
		b.spin *= maxf(1.0 - 5.0 * dt, 0.0)
		if b.charred:
			if randf() < 0.3:
				smoke(b.pos, 1, 12.0)
		elif randf() < 0.35:
			decals.blood_dot(b.pos + Vector2(randf_range(-8, 8), randf_range(-8, 8)), randf_range(4.0, 9.0) * sqrt(b.blood))
		if b.life <= 0.0:
			if b.charred:
				decals.scorch(b.pos, 16.0 * sqrt(b.blood))
				decals.stamp(b.tex, b.pos, b.rot, b.size, Color(Config.CHARRED_TINT, 1.0))
			else:
				decals.blood_splat(b.pos, randf_range(40.0, 58.0) * sqrt(b.blood))
				decals.stamp(b.tex, b.pos, b.rot, b.size, Color(0.5, 0.42, 0.42, 1.0))
			_corpses[i] = _corpses[_corpses.size() - 1]
			_corpses.pop_back()
		else:
			i += 1

	_age(_flashes, 3, dt)
	_age(_rings, 3, dt)
	_age(_arcs, 4, dt)
	_age(_lights, 2, dt)
	_age(_texts, 3, dt)
	for t: Array in _texts:
		t[0] += Vector2(0.0, -46.0) * dt

	_layer.queue_redraw()
	_glow_layer.queue_redraw()


## Count down the life stored at `life_index` of every entry and drop expired ones.
func _age(list: Array, life_index: int, dt: float) -> void:
	var i := 0
	while i < list.size():
		var item: Array = list[i]
		item[life_index] -= dt
		if item[life_index] <= 0.0:
			list[i] = list[list.size() - 1]
			list.pop_back()
		else:
			i += 1


# ----------------------------------------------------------------------------
#  Drawing
# ----------------------------------------------------------------------------
func _paint(ci: CanvasItem) -> void:
	# Corpses still tumbling (they darken as they settle so there is no pop).
	for b: Corpse in _corpses:
		var f := 1.0 - b.life / b.max_life
		var tint := Color(Config.CHARRED_TINT, 1.0) if b.charred else Color.WHITE.lerp(Color(0.5, 0.42, 0.42), f)
		ci.draw_set_transform(b.pos, b.rot, Vector2.ONE)
		ci.draw_texture_rect(b.tex, Rect2(-b.size * 0.5, b.size), false, tint)

	for c: Casing in _casings:
		ci.draw_set_transform(c.pos, c.rot, Vector2.ONE)
		ci.draw_rect(Rect2(-c.size * 0.5, c.size), c.color)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for i in _n:
		var kind := _kind[i]
		if kind > P_SMOKE:
			continue
		var s := _size[i]
		var color := _col[i]
		if kind == P_SMOKE:
			color.a *= _life[i] / _max[i]
		ci.draw_texture_rect(_dot, Rect2(_pos[i] - Vector2(s, s) * 0.5, Vector2(s, s)), false, color)

	for t: Array in _texts:
		var font_size: int = t[5]
		var message: String = t[1]
		var color: Color = t[2]
		color.a = clampf(float(t[3]) / (float(t[4]) * 0.4), 0.0, 1.0)
		var width := _font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var at: Vector2 = t[0] - Vector2(width * 0.5, 0.0)
		ci.draw_string_outline(_font, at, message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, color.a * 0.85))
		ci.draw_string(_font, at, message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _paint_glow(ci: CanvasItem) -> void:
	for l: Array in _lights:
		var size: float = l[1]
		var color: Color = l[4]
		color.a *= float(l[2]) / float(l[3])
		ci.draw_texture_rect(_glow, Rect2(l[0] - Vector2(size, size) * 0.5, Vector2(size, size)), false, color)

	for i in _n:
		var kind := _kind[i]
		if kind < P_SPARK:
			continue
		var s := _size[i]
		var color := _col[i]
		color.a *= _life[i] / _max[i]
		ci.draw_texture_rect(_glow if kind == P_FIRE else _dot, Rect2(_pos[i] - Vector2(s, s) * 0.5, Vector2(s, s)), false, color)

	for r: Array in _rings:
		var f := 1.0 - float(r[3]) / float(r[4])
		var radius := lerpf(float(r[1]), float(r[2]), 1.0 - (1.0 - f) * (1.0 - f))
		var color: Color = r[5]
		color.a *= 1.0 - f
		var size := Vector2(radius, radius) * (128.0 / 58.0)
		ci.draw_texture_rect(_ring_tex, Rect2(r[0] - size * 0.5, size), false, color)

	for a: Array in _arcs:
		var f := float(a[4]) / 0.14
		var radius: float = a[3]
		var half: float = float(a[2]) * 0.5
		var angle: float = a[1]
		ci.draw_arc(a[0], radius * 0.72, angle - half, angle + half, 18, Color(1, 1, 1, 0.5 * f), radius * 0.42)
		ci.draw_arc(a[0], radius * 0.95, angle - half, angle + half, 18, Color(1, 1, 1, 0.9 * f), 4.0)

	for fl: Array in _flashes:
		var size: float = fl[2]
		var color: Color = fl[4]
		var k := size / 64.0
		ci.draw_set_transform(fl[0], fl[1], Vector2(k * 1.5, k * 0.9))
		ci.draw_texture_rect(_flash_tex, Rect2(Vector2(-20, -32), Vector2(64, 64)), false, color)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
