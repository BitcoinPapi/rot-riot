class_name Projectiles
extends Node2D
## All bullets and grenades. They are plain data moved by one loop and drawn
## as glowing tracer lines - no nodes or physics bodies per bullet.

class Shot:
	var pos := Vector2.ZERO
	var dir := Vector2.RIGHT
	var speed := 0.0
	var dist_left := 0.0
	var travelled := 0.0
	var damage := 0.0
	var knockback := 0.0
	var stagger := 0.0
	var pierce := 0
	var w: Dictionary            # weapon config (for feel values)
	var grenade := false
	var hit: Array = []          # zombies already hit (piercing shots)

var game: Game
var shots: Array[Shot] = []
var _glow: Texture2D
var _grenade_tex: Texture2D
var _time := 0.0


func _ready() -> void:
	_glow = Art.t("glow")
	_grenade_tex = Art.t("grenade")
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func spawn(from: Vector2, dir: Vector2, w: Dictionary, damage: float, knockback: float) -> void:
	var s := Shot.new()
	var speed_var: float = w["speed_var"]
	s.pos = from
	s.dir = dir
	s.speed = float(w["bullet_speed"]) * (1.0 + randf_range(-speed_var, speed_var))
	s.dist_left = float(w["range"]) * randf_range(0.92, 1.0)
	s.damage = damage
	s.knockback = knockback
	s.stagger = w["stagger"]
	s.pierce = w["pierce"]
	s.w = w
	s.grenade = String(w["kind"]) == "grenade"
	shots.append(s)


func tick(dt: float) -> void:
	_time += dt
	var enemies := game.enemies
	var arena := game.arena
	var i := 0
	while i < shots.size():
		var s := shots[i]
		var step := minf(s.speed * dt, s.dist_left)
		var from := s.pos
		var to := from + s.dir * step
		var done := false

		var wall_t := arena.segment_hit(from, to)
		var e := enemies.segment_hit(from, to, 6.0 if s.grenade else 3.0, s.hit)
		if e != null and enemies.hit_t <= wall_t:
			var at := from.lerp(to, enemies.hit_t)
			if s.grenade:
				explode(at, s)
				done = true
			else:
				enemies.damage(e, s.damage, s.dir, s.knockback, s.stagger, float(s.w["hitstop_kill"]))
				if s.pierce > 0:
					s.pierce -= 1
					s.damage *= 0.7
					s.hit.append(e)
				else:
					to = at
					done = true
		elif wall_t <= 1.0:
			var wall_at := from.lerp(to, wall_t)
			if s.grenade:
				explode(wall_at, s)
			else:
				game.fx.sparks(wall_at, -s.dir, 5)
				Sfx.play("ricochet", -10.0, 0.2)
			to = wall_at
			done = true

		s.pos = to
		s.travelled += step
		s.dist_left -= step
		if not done and s.dist_left <= 0.0:
			if s.grenade:
				explode(s.pos, s)
			done = true
		if s.grenade and not done and randf() < 0.5:
			game.fx.smoke(s.pos, 1, 8.0)

		if done:
			shots[i] = shots[shots.size() - 1]
			shots.pop_back()
		else:
			i += 1
	queue_redraw()


## Grenade blast: damage falls off toward the edge, everything is thrown outward.
func explode(at: Vector2, s: Shot) -> void:
	var w := s.w
	var radius: float = w["blast_radius"]
	var edge: float = w["blast_edge_damage"]
	var force: float = w["blast_knockback"]
	var stagger: float = w["blast_stagger"]
	if game.rage_active:
		force *= Config.RAGE_KNOCKBACK_MULT
	for e: Enemy in game.enemies.in_radius(at, radius):
		var away := e.pos - at
		var d := away.length()
		var dir := away / d if d > 0.01 else s.dir
		var f := clampf(d / radius, 0.0, 1.0)
		game.enemies.damage(e, s.damage * lerpf(1.0, edge, f), dir, force * (1.0 - 0.4 * f), stagger, 0.0)
	game.fx.explosion(at, radius)
	game.decals.scorch(at, radius * 0.75)
	game.shake(float(w["blast_shake"]))
	game.hitstop(float(w["blast_hitstop"]), true)
	Sfx.play("explosion")


func _draw() -> void:
	for s: Shot in shots:
		if s.grenade:
			# Drawn additively: a bright core with a pulsing glow.
			var pulse := 26.0 + sin(_time * 40.0) * 6.0
			draw_texture_rect(_glow, Rect2(s.pos - Vector2(pulse, pulse) * 0.5, Vector2(pulse, pulse)), false, Color(1.0, 0.5, 0.15, 0.9))
			draw_texture_rect(_grenade_tex, Rect2(s.pos - Vector2(8, 8), Vector2(16, 16)), false, Color(1, 1, 1, 1))
		else:
			var w := s.w
			var color: Color = w["tracer_color"]
			var length := minf(float(w["tracer_len"]), s.travelled)
			var width: float = w["tracer_width"]
			draw_line(s.pos - s.dir * length, s.pos, color, width)
			draw_texture_rect(_glow, Rect2(s.pos - Vector2(7, 7), Vector2(14, 14)), false, color)
