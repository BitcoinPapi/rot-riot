class_name EnemyShots
extends Node2D
## What zombies throw at the player:
##   spit   - a Gobber's glob: flies straight, slow enough to sidestep; rocks
##            and weapon crates stop it
##   lobs   - a Chucker's lump of rubble: sails over everything and lands
##            where the player stood when it was thrown; a red ring on the
##            ground shows where, and how soon
## Plain data moved by one loop and drawn by this one node, like the
## player's bullets.

class Spit:
	var pos := Vector2.ZERO
	var dir := Vector2.RIGHT
	var speed := 0.0
	var dist_left := 0.0
	var damage := 0.0
	var radius := 8.0
	var age := 0.0

class Lob:
	var from := Vector2.ZERO
	var target := Vector2.ZERO
	var t := 0.0
	var time := 1.0
	var radius := 70.0
	var damage := 0.0
	var shake := 0.3
	var spin := 0.0

var game: Game
var spits: Array[Spit] = []
var lobs: Array[Lob] = []

var _time := 0.0
var _glow: Texture2D
var _dot: Texture2D
var _ring: Texture2D
var _rubble: Texture2D

const SPIT_COLOR := Color(0.62, 0.9, 0.2)
const SPIT_STAIN := Color(0.42, 0.55, 0.12, 0.6)


func _ready() -> void:
	_glow = Art.t("glow")
	_dot = Art.t("dot")
	_ring = Art.t("ring")
	_rubble = Art.t("rubble")


# ----------------------------------------------------------------------------
#  Launching
# ----------------------------------------------------------------------------
## A glob of spit from `from` toward `dir`. `c` is the spitter's config.
func spit(from: Vector2, dir: Vector2, c: Dictionary, damage: float) -> void:
	var s := Spit.new()
	s.pos = from
	s.dir = dir
	s.speed = c["shot_speed"]
	s.dist_left = c["shot_range"]
	s.radius = c["shot_radius"]
	s.damage = damage
	spits.append(s)
	Sfx.play("spit", -3.0, 0.15)


## A lump of rubble from `from`, to land on `target`. `c` is the thrower's config.
func lob(from: Vector2, target: Vector2, c: Dictionary, damage: float) -> void:
	var l := Lob.new()
	l.from = from
	l.target = game.arena.clamp_inside(target, 20.0)
	l.time = c["lob_time"]
	l.radius = c["lob_radius"]
	l.shake = c["lob_shake"]
	l.damage = damage
	l.spin = randf_range(-9.0, 9.0)
	lobs.append(l)
	Sfx.play("lob_throw", -2.0, 0.12)


# ----------------------------------------------------------------------------
#  Update
# ----------------------------------------------------------------------------
func tick(dt: float) -> void:
	_time += dt
	var player := game.player
	var arena := game.arena
	var i := 0
	while i < spits.size():
		var s := spits[i]
		s.age += dt
		var step := minf(s.speed * dt, s.dist_left)
		var from := s.pos
		var to := from + s.dir * step
		var done := false

		# Whatever comes first along its path: a rock, a weapon crate, the player.
		var stop_t := arena.segment_hit(from, to)
		var crate := game.pickups.crate_on_segment(from, to, s.radius, [])
		var crate_t: float = game.pickups.crate_t
		if crate != null and crate_t < stop_t:
			stop_t = crate_t
		else:
			crate = null
		var hit_t := 2.0
		if player.alive:
			hit_t = _circle_on_segment(from, to, player.pos, s.radius + player.radius)
		if hit_t <= 1.0 and hit_t <= stop_t:
			to = from.lerp(to, hit_t)
			game.damage_player(s.damage, to - s.dir * 30.0)
			done = true
		elif stop_t <= 1.0:
			to = from.lerp(to, stop_t)
			if crate != null:
				game.pickups.damage_crate(crate, Config.ENEMY_SHOT_CRATE_DAMAGE, s.dir)
			done = true

		s.pos = to
		s.dist_left -= step
		if s.dist_left <= 0.0:
			done = true
		# Drops of it fall along the way.
		if not done and randf() < dt * 9.0:
			game.decals.stamp(_dot, s.pos + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)), 0.0,
					Vector2.ONE * randf_range(3.0, 6.0), SPIT_STAIN)
		if done:
			_splash(s.pos, s.dir)
			spits[i] = spits[spits.size() - 1]
			spits.pop_back()
		else:
			i += 1

	i = 0
	while i < lobs.size():
		var l := lobs[i]
		l.t += dt
		if l.t >= l.time:
			_land(l)
			lobs[i] = lobs[lobs.size() - 1]
			lobs.pop_back()
		else:
			i += 1
	queue_redraw()


## Where along the segment a->b (0..1) a moving dot first comes within `reach`
## of `center`; 2.0 if it never does.
func _circle_on_segment(a: Vector2, b: Vector2, center: Vector2, reach: float) -> float:
	var f := a - center
	if f.length_squared() <= reach * reach:
		return 0.0
	var d := b - a
	var len2 := d.length_squared()
	if len2 <= 0.0001:
		return 2.0
	var half_b := f.dot(d)
	var disc := half_b * half_b - len2 * (f.length_squared() - reach * reach)
	if disc < 0.0:
		return 2.0
	var t := (-half_b - sqrt(disc)) / len2
	return t if t >= 0.0 and t <= 1.0 else 2.0


## A glob of spit bursts: a splash, and a stain that stays.
func _splash(at: Vector2, dir: Vector2) -> void:
	game.fx.cloud(at, 5, 12.0, Color(SPIT_COLOR.r, SPIT_COLOR.g, SPIT_COLOR.b, 0.55), 70.0)
	game.decals.stamp(_glow, at, 0.0, Vector2(46.0, 46.0), Color(0.3, 0.42, 0.08, 0.55))
	for k in 5:
		var p := at + dir.rotated(randf_range(-1.2, 1.2)) * randf_range(6.0, 26.0)
		game.decals.stamp(_dot, p, 0.0, Vector2.ONE * randf_range(3.0, 8.0), SPIT_STAIN)
	Sfx.play("spit_hit", -5.0, 0.2)


## A lump of rubble comes down: whoever stands in the ring is hit.
func _land(l: Lob) -> void:
	var player := game.player
	if player.alive and player.pos.distance_to(l.target) < l.radius + player.radius:
		game.damage_player(l.damage, l.target)
	game.pickups.blast_crates(l.target, l.radius, Config.LOB_CRATE_DAMAGE / Config.CRATE_BLAST_MULT, 0.5)
	game.fx.dust(l.target, 14)
	game.fx.cloud(l.target, 6, 26.0, Color(0.5, 0.47, 0.42, 0.45), 110.0)
	game.fx.ring(l.target, 12.0, l.radius, 0.3, Color(0.85, 0.8, 0.7, 0.7))
	# A dent in the ground and the pieces it broke into.
	game.decals.stamp(_glow, l.target, 0.0, Vector2(l.radius, l.radius) * 1.5, Color(0.08, 0.07, 0.05, 0.6))
	game.decals.stamp(_rubble, l.target, randf() * TAU, Vector2(26.0, 26.0), Color(0.75, 0.75, 0.75))
	for k in 8:
		var p := l.target + Vector2.from_angle(randf() * TAU) * randf_range(10.0, l.radius * 0.9)
		var grey := randf_range(0.38, 0.55)
		game.decals.stamp(_dot, p, 0.0, Vector2.ONE * randf_range(4.0, 9.0), Color(grey, grey, grey * 0.97, 0.9))
	if player.pos.distance_to(l.target) < 700.0:
		game.shake(l.shake)
	Sfx.play("lob_land", -1.0, 0.12)


# ----------------------------------------------------------------------------
#  Drawing
# ----------------------------------------------------------------------------
func _draw() -> void:
	# Where rubble is about to land: a red ring that fills up as it comes down.
	for l: Lob in lobs:
		var f := clampf(l.t / l.time, 0.0, 1.0)
		var size := Vector2(l.radius, l.radius) * 2.0
		var blink := 0.75 + 0.25 * sin(_time * 18.0)
		draw_texture_rect(_ring, Rect2(l.target - size * 0.53, size * 1.06), false, Color(1.0, 0.2, 0.15, (0.45 + 0.45 * f) * blink))
		var fill := size * f
		draw_texture_rect(_dot, Rect2(l.target - fill * 0.5, fill), false, Color(1.0, 0.15, 0.1, 0.16 + 0.14 * f))

	for s: Spit in spits:
		var wobble := 1.0 + 0.15 * sin(s.age * 30.0)
		var halo := s.radius * 5.0
		draw_texture_rect(_glow, Rect2(s.pos - Vector2(halo, halo) * 0.5, Vector2(halo, halo)), false, Color(0.5, 0.9, 0.1, 0.5))
		# A stretched blob with a tail, and a bright wet highlight.
		var tail := s.pos - s.dir * s.radius * 1.3
		var ts := s.radius * 1.5
		draw_texture_rect(_dot, Rect2(tail - Vector2(ts, ts) * 0.5, Vector2(ts, ts)), false, Color(0.4, 0.62, 0.1))
		var bs := s.radius * 2.3 * wobble
		draw_texture_rect(_dot, Rect2(s.pos - Vector2(bs, bs) * 0.5, Vector2(bs, bs)), false, Color(0.16, 0.24, 0.04))
		bs = s.radius * 1.9 * wobble
		draw_texture_rect(_dot, Rect2(s.pos - Vector2(bs, bs) * 0.5, Vector2(bs, bs)), false, SPIT_COLOR)
		var hs := s.radius * 0.7
		draw_texture_rect(_dot, Rect2(s.pos + Vector2(-s.radius * 0.35, -s.radius * 0.4) - Vector2(hs, hs) * 0.5, Vector2(hs, hs)), false,
				Color(0.92, 1.0, 0.7))

	# The lumps in the air (over everything): a shadow on the ground, the lump above it.
	for l: Lob in lobs:
		var f := clampf(l.t / l.time, 0.0, 1.0)
		var ground := l.from.lerp(l.target, f)
		var up := sin(f * PI)
		var ss := 20.0 + 14.0 * (1.0 - up)
		draw_texture_rect(_dot, Rect2(ground - Vector2(ss, ss * 0.7) * 0.5, Vector2(ss, ss * 0.7)), false, Color(0, 0, 0, 0.2 + 0.25 * (1.0 - up)))
		var rs := 26.0 * (1.0 + 0.55 * up)
		draw_set_transform(ground + Vector2(0.0, -Config.LOB_ARC_HEIGHT * up), l.spin * l.t, Vector2.ONE)
		draw_texture_rect(_rubble, Rect2(-Vector2(rs, rs) * 0.5, Vector2(rs, rs)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
