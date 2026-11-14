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
	var wid := ""                # weapon id (gets the XP for kills)
	var crit := false
	var keep := 0.7              # damage kept after passing through a zombie
	var flame := false           # a puff of fire: slows down, grows, burns everything it touches
	var radius := 3.0
	var range0 := 1.0            # the range it started with (for fading)
	var burn_dps := 0.0
	var grenade := false
	var hit: Array = []          # zombies already hit (piercing shots)

var game: Game
var shots: Array[Shot] = []
var spawned_total := 0           # how many shots were ever fired (for the benchmark)
var _glow: Texture2D
var _grenade_tex: Texture2D
var _time := 0.0


func _ready() -> void:
	_glow = Art.t("glow")
	_grenade_tex = Art.t("grenade")
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func spawn(from: Vector2, dir: Vector2, w: Dictionary, weapon_id: String, damage: float, knockback: float, crit: bool = false) -> void:
	spawned_total += 1
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
	s.wid = weapon_id
	s.crit = crit
	s.grenade = String(w["kind"]) == "grenade"
	s.keep = float(w.get("pierce_keep", Config.PIERCE_DAMAGE_KEEP))
	s.range0 = s.dist_left
	if s.grenade:
		s.radius = 6.0
	if String(w["kind"]) == "flame":
		s.flame = true
		s.radius = w["flame_size"]
		# Burn damage scales with everything that scales the weapon's damage.
		s.burn_dps = float(w["burn_dps"]) * damage / float(w["damage"])
	shots.append(s)


func tick(dt: float) -> void:
	_time += dt
	var enemies := game.enemies
	var arena := game.arena
	var i := 0
	while i < shots.size():
		var s := shots[i]
		if s.flame:
			s.speed *= maxf(1.0 - float(s.w["flame_drag"]) * dt, 0.0)
			s.radius += float(s.w["flame_grow"]) * dt
		var step := minf(s.speed * dt, s.dist_left)
		var from := s.pos
		var to := from + s.dir * step
		var done := false

		var wall_t := arena.segment_hit(from, to)
		var e := enemies.segment_hit(from, to, s.radius, s.hit)
		# Weapon crates are in the way too: a bullet that reaches one before it
		# reaches a zombie or a rock stops in the wood (and wears the crate down).
		var crate := game.pickups.crate_on_segment(from, to, s.radius, s.hit)
		var crate_t: float = game.pickups.crate_t
		var crate_first := crate != null and crate_t <= wall_t and (e == null or crate_t <= enemies.hit_t)
		if crate_first and not s.flame:
			var crate_at := from.lerp(to, crate_t)
			if s.grenade:
				explode(crate_at, s)
			else:
				game.pickups.damage_crate(crate, float(s.w["damage"]), s.dir)
			to = crate_at
			done = true
		elif s.flame:
			# Fire licks at a crate once per puff and carries on.
			if crate != null and crate_t <= wall_t:
				s.hit.append(crate)
				game.pickups.damage_crate(crate, float(s.w["damage"]), s.dir)
			# Fire washes over everything in its path; each puff burns a zombie once.
			var guard := 0
			while e != null and enemies.hit_t <= wall_t and guard < 8:
				guard += 1
				s.hit.append(e)
				enemies.damage(e, s.damage, s.dir, s.knockback, s.stagger, 0.0, s.wid, s.crit)
				enemies.ignite(e, float(s.w["burn_time"]), s.burn_dps, s.wid)
				e = enemies.segment_hit(from, to, s.radius, s.hit)
			if wall_t <= 1.0:
				to = from.lerp(to, wall_t)
				done = true
		elif e != null and enemies.hit_t <= wall_t:
			var at := from.lerp(to, enemies.hit_t)
			if s.grenade:
				explode(at, s)
				done = true
			else:
				enemies.damage(e, s.damage, s.dir, s.knockback, s.stagger, float(s.w["hitstop_kill"]), s.wid, s.crit)
				if s.pierce > 0:
					s.pierce -= 1
					s.damage *= s.keep
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
		if not done and (s.dist_left <= 0.0 or (s.flame and s.speed < 60.0)):
			if s.grenade:
				explode(s.pos, s)
			done = true
		if s.grenade and not done and randf() < 0.5:
			game.fx.smoke(s.pos, 1, 8.0)

		if done:
			if s.flame and randf() < 0.25:
				game.fx.smoke(s.pos, 1, 14.0)
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
		game.enemies.damage(e, s.damage * lerpf(1.0, edge, f), dir, force * lerpf(1.0, Config.BLAST_EDGE_KNOCKBACK, f), stagger, 0.0, s.wid, s.crit)
	game.pickups.blast_crates(at, radius, float(w["damage"]), edge)
	game.fx.explosion(at, radius)
	game.decals.scorch(at, radius * 0.75)
	game.shake(float(w["blast_shake"]))
	game.hitstop(float(w["blast_hitstop"]), true)
	Sfx.play("explosion")


func _draw() -> void:
	for s: Shot in shots:
		if s.flame:
			# White-hot at the nozzle, orange, then dull red as it thins out.
			var f := clampf(1.0 - s.dist_left / s.range0, 0.0, 1.0)
			var size := s.radius * 3.2
			var color := Color(1.0, 0.95, 0.6, 0.55).lerp(Color(1.0, 0.45, 0.1, 0.5), minf(f * 2.0, 1.0))
			color = color.lerp(Color(0.6, 0.12, 0.05, 0.0), maxf(f * 2.0 - 1.0, 0.0))
			draw_texture_rect(_glow, Rect2(s.pos - Vector2(size, size) * 0.5, Vector2(size, size)), false, color)
		elif s.grenade:
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
