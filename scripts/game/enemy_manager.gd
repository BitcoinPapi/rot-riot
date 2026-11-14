class_name EnemyManager
extends Node2D
## Runs every zombie from one loop.
##
## HOW IT STAYS FAST WITH 200+ ZOMBIES:
##  * No physics engine. Zombies are circles; we do the maths ourselves.
##  * A "spatial grid" sorts zombies into 64px cells each frame, so each one
##    only checks the few neighbours next to it instead of all the others.
##  * Zombies are sprites recycled from a pool (never created mid-fight), and
##    sprites sharing a texture are drawn by the GPU in batches.

const CELL := 64.0
const INV_CELL := 1.0 / 64.0

# Boss states
const B_CHASE := 0
const B_WINDUP := 1
const B_CHARGE := 2
const B_RECOVER := 3
const B_SUMMON := 4

var game: Game
var active: Array[Enemy] = []       # everything spawned (dead ones are removed at the start of the next frame)
var bigs: Array[Enemy] = []         # bosses: too large for the grid, checked directly
var alive_count := 0
var hit_t := 2.0                    # set by segment_hit(): how far along the segment the hit was (0..1)

var _pool: Array[Enemy] = []
var _dead_count := 0
var _origin := Vector2.ZERO
var _gw := 0
var _gh := 0
var _head := PackedInt32Array()     # first zombie in each cell (-1 = empty)
var _next := PackedInt32Array()     # next zombie in the same cell
var _cell_obstacle := PackedInt32Array()   # obstacle near each cell (-1 = none)
var _time := 0.0


func setup(g: Game) -> void:
	game = g
	var pad := Config.SPAWN_DIST_MAX + CELL * 3.0
	_origin = -Vector2(pad, pad)
	var size := Config.ARENA_SIZE + Vector2(pad, pad) * 2.0
	_gw = int(ceil(size.x / CELL)) + 2
	_gh = int(ceil(size.y / CELL)) + 2
	_head.resize(_gw * _gh)
	_head.fill(-1)
	_next.resize(512)
	_build_obstacle_cells()


func _build_obstacle_cells() -> void:
	_cell_obstacle.resize(_gw * _gh)
	_cell_obstacle.fill(-1)
	var arena := game.arena
	for cy in _gh:
		for cx in _gw:
			var cell_rect := Rect2(_origin + Vector2(cx, cy) * CELL, Vector2(CELL, CELL))
			for i in arena.obs_pos.size():
				var c := arena.obs_pos[i]
				var nearest_pt := Vector2(
					clampf(c.x, cell_rect.position.x, cell_rect.end.x),
					clampf(c.y, cell_rect.position.y, cell_rect.end.y))
				if nearest_pt.distance_to(c) <= arena.obs_radius[i] + 36.0:
					_cell_obstacle[cy * _gw + cx] = i
					break


# ----------------------------------------------------------------------------
#  Spawning
# ----------------------------------------------------------------------------
func spawn(kind: int, at: Vector2, hp_mult: float = 1.0, speed_mult: float = 1.0, rising: bool = false) -> Enemy:
	var e: Enemy
	if _pool.is_empty():
		e = Enemy.new()
		add_child(e)
	else:
		e = _pool.pop_back()
	var c: Dictionary = Config.ENEMIES[kind]
	var speed_var: float = c["speed_var"]
	e.kind = kind
	e.variant = randi() % int(Art.ENEMY_VARIANTS[kind])
	e.alive = true
	e.pos = at
	e.kb = Vector2.ZERO
	e.max_hp = float(c["hp"]) * hp_mult
	e.hp = e.max_hp
	e.radius = c["radius"]
	e.speed = float(c["speed"]) * speed_mult * (1.0 + randf_range(-speed_var, speed_var))
	e.damage = c["damage"]
	e.attack_cd = c["attack_cd"]
	e.attack_t = Config.ENEMY_FIRST_ATTACK_DELAY
	e.flash_t = 0.0
	e.stagger_t = 0.0
	e.spawn_t = Config.SUMMON_RISE_TIME if rising else 0.0
	e.phase = randf() * TAU
	e.flank = Vector2.from_angle(randf() * TAU) * (randf() * Config.ENEMY_FLANK_SPREAD)
	e.entered = game.arena.rect.grow(-e.radius).has_point(at)
	e.kb_mult = c["kb_mult"]
	e.stagger_mult = c["stagger_mult"]
	e.inv_mass = 1.0 / float(c["mass"])
	e.push_player = c["push_player"]
	e.score = c["score"]
	e.rage = c["rage"]
	e.hitstop_mult = c["hitstop_mult"]
	e.shake_mult = c["shake_mult"]
	e.blood = c["blood"]
	e.is_big = kind == Config.BOSS
	e.state = B_CHASE
	e.state_t = 0.0
	if e.is_big:
		e.charge_cd = float(c["charge_cooldown"]) * 0.6
		e.summon_cd = float(c["summon_cooldown"]) * 0.5
		bigs.append(e)
	e.tex_normal = Art.enemy_tex(kind, e.variant)
	e.tex_flash = Art.enemy_flash_tex(kind)
	e.texture = e.tex_normal
	e.base_scale = 1.0 / Art.PX
	e.scale = Vector2(e.base_scale, e.base_scale)
	e.modulate = Color.WHITE
	e.z_index = 1 if e.is_big else 0
	e.face = (game.player.pos - at).angle()
	e.position = at
	e.rotation = e.face
	e.visible = true
	active.append(e)
	alive_count += 1
	return e


# ----------------------------------------------------------------------------
#  The main loop
# ----------------------------------------------------------------------------
func tick(dt: float) -> void:
	_time += dt
	if _dead_count > 0:
		_compact()
	var n := active.size()
	if _next.size() < n + 64:
		_next.resize(n + 256)

	# 1) Sort every zombie into the grid.
	_head.fill(-1)
	var ox := _origin.x
	var oy := _origin.y
	var gw := _gw
	var max_cx := _gw - 2
	var max_cy := _gh - 2
	for i in n:
		var e := active[i]
		e.crowd_prev = e.crowd
		e.crowd = 0
		if e.is_big:
			e.cell = -1
			continue
		var cx := clampi(int((e.pos.x - ox) * INV_CELL), 1, max_cx)
		var cy := clampi(int((e.pos.y - oy) * INV_CELL), 1, max_cy)
		var c := cy * gw + cx
		e.cell = c
		_next[i] = _head[c]
		_head[c] = i

	# 2) Move, separate, attack.
	var player := game.player
	var ppos := player.pos
	var pr := player.radius
	var player_alive := player.alive
	var arena := game.arena
	var min_x := arena.rect.position.x
	var min_y := arena.rect.position.y
	var max_x := arena.rect.end.x
	var max_y := arena.rect.end.y
	var kb_keep := maxf(1.0 - Config.KNOCKBACK_DAMPING * dt, 0.0)
	var sep: float = Config.ENEMY_SEPARATION
	var turn := minf(Config.ENEMY_TURN_SPEED * dt, 1.0)
	var reach_pad: float = Config.ENEMY_ATTACK_REACH
	var squash: float = Config.HIT_SQUASH / Config.HIT_FLASH_TIME
	var zig: float = Config.RUNNER_ZIGZAG_AMOUNT
	var zig_speed: float = Config.RUNNER_ZIGZAG_SPEED * dt
	var player_share: float = Config.PLAYER_PUSHED_BY_ENEMIES
	var runner: int = Config.RUNNER
	var crowd_free: int = Config.ENEMY_CROWD_FREE
	var push_total := Vector2.ZERO
	var has_bigs := not bigs.is_empty()

	for i in n:
		var e := active[i]
		if not e.alive:
			continue

		# White hit flash + a little puff-up.
		if e.flash_t > 0.0:
			e.flash_t -= dt
			if e.flash_t <= 0.0:
				e.texture = e.tex_normal
				e.scale = Vector2(e.base_scale, e.base_scale)
			else:
				var fs := e.base_scale * (1.0 + squash * e.flash_t)
				e.scale = Vector2(fs, fs)

		if e.is_big:
			_tick_boss(e, dt)
			continue

		var epos := e.pos
		var er := e.radius
		var to_p := ppos - epos
		var dist := to_p.length()
		var dirp := to_p / maxf(dist, 0.001)
		var reach := er + pr + reach_pad

		if e.spawn_t > 0.0:
			# Clawing up out of the ground.
			e.spawn_t -= dt
			var rs := e.base_scale * (1.0 - 0.7 * maxf(e.spawn_t, 0.0) / Config.SUMMON_RISE_TIME)
			e.scale = Vector2(rs, rs)
		elif e.stagger_t > 0.0:
			e.stagger_t -= dt
		else:
			if dist > reach:
				var d := dirp
				if e.kind == runner:
					e.phase += zig_speed
					if dist > 130.0:
						d = (dirp + Vector2(-dirp.y, dirp.x) * (sin(e.phase) * zig)).normalized()
				else:
					e.phase += dt * 8.0
					if dist > 90.0:
						d = (to_p + e.flank * minf(dist * 0.004, 1.0)).normalized()
				# Zombies jammed in a crowd push less hard, so a horde spreads
				# out around the player instead of squashing into one blob.
				var step := e.speed * dt
				if e.crowd_prev > crowd_free:
					step *= float(crowd_free + 1) / float(e.crowd_prev + 1)
				epos += d * step
				e.face = lerp_angle(e.face, d.angle(), turn)
			else:
				e.face = lerp_angle(e.face, dirp.angle(), turn)
			e.attack_t -= dt
			if dist <= reach and e.attack_t <= 0.0 and player_alive:
				e.attack_t = e.attack_cd
				game.damage_player(e.damage, epos)

		# Knockback slide.
		if e.kb != Vector2.ZERO:
			epos += e.kb * dt
			e.kb *= kb_keep
			if e.kb.length_squared() < 25.0:
				e.kb = Vector2.ZERO

		# Push apart from neighbours (each pair is handled once: j > i).
		var c := e.cell
		var eim := e.inv_mass
		var touching := 0
		for row in 3:
			var base := c + (row - 1) * gw - 1
			for col in 3:
				var j := _head[base + col]
				while j != -1:
					if j > i:
						var o := active[j]
						var diff := o.pos - epos
						var rr := er + o.radius
						var d2 := diff.length_squared()
						if d2 < rr * rr and o.alive:
							if d2 < 0.01:
								diff = Vector2(randf() - 0.5, randf() - 0.5)
								d2 = diff.length_squared() + 0.0001
							var dd := sqrt(d2)
							var corr := diff * ((rr - dd) / dd * sep)
							var share := eim / (eim + o.inv_mass)
							epos -= corr * share
							o.pos += corr * (1.0 - share)
							touching += 1
							o.crowd += 1
					j = _next[j]
		e.crowd += touching

		# Bosses shove everything out of their way.
		if has_bigs:
			for b: Enemy in bigs:
				var bd := epos - b.pos
				var brr := er + b.radius
				var bd2 := bd.length_squared()
				if bd2 < brr * brr and bd2 > 0.01:
					epos = b.pos + bd * (brr / sqrt(bd2))

		# Body-block the player.
		var tp := ppos - epos
		var prr := er + pr
		var tp2 := tp.length_squared()
		if tp2 < prr * prr and player_alive:
			var tpd := sqrt(maxf(tp2, 0.0001))
			var nrm := tp / tpd
			var p_share := minf(player_share * e.push_player, 1.0)
			epos -= nrm * ((prr - tpd) * (1.0 - p_share))
			push_total += nrm * ((prr - tpd) * p_share)

		# Obstacles and arena edge (only once inside the clearing).
		if e.entered:
			var oi := _cell_obstacle[c]
			if oi >= 0:
				epos = arena.push_out_of(oi, epos, er)
			epos.x = clampf(epos.x, min_x + er, max_x - er)
			epos.y = clampf(epos.y, min_y + er, max_y - er)
		elif epos.x > min_x + er and epos.x < max_x - er and epos.y > min_y + er and epos.y < max_y - er:
			e.entered = true

		e.pos = epos
		e.position = epos
		e.rotation = e.face + sin(e.phase) * 0.13

	if push_total != Vector2.ZERO and player_alive:
		player.pos = arena.resolve(player.pos + push_total.limit_length(Config.PLAYER_MAX_PUSH_PER_FRAME), pr)


func _compact() -> void:
	var w := 0
	for r in active.size():
		var e := active[r]
		if e.alive:
			active[w] = e
			w += 1
		else:
			_pool.append(e)
	active.resize(w)
	_dead_count = 0


# ----------------------------------------------------------------------------
#  Boss: chase -> wind up -> charge -> dazed, and now and then summon a pack
# ----------------------------------------------------------------------------
func _tick_boss(e: Enemy, dt: float) -> void:
	var cfg: Dictionary = Config.ENEMIES[Config.BOSS]
	var player := game.player
	var arena := game.arena
	var to_p := player.pos - e.pos
	var dist := to_p.length()
	var dirp := to_p / maxf(dist, 0.001)
	var reach := e.radius + player.radius + Config.ENEMY_ATTACK_REACH
	var turn := minf(Config.ENEMY_TURN_SPEED * 0.6 * dt, 1.0)
	e.modulate = Color.WHITE

	match e.state:
		B_CHASE:
			e.phase += dt * 5.0
			if dist > reach:
				e.pos += dirp * (e.speed * dt)
			e.face = lerp_angle(e.face, dirp.angle(), turn)
			e.attack_t -= dt
			if dist <= reach and e.attack_t <= 0.0 and player.alive:
				e.attack_t = e.attack_cd
				game.damage_player(e.damage, e.pos)
			if e.entered and player.alive:
				e.charge_cd -= dt
				e.summon_cd -= dt
				if e.summon_cd <= 0.0:
					e.state = B_SUMMON
					e.state_t = cfg["summon_windup"]
					Sfx.play("boss_roar")
					game.shake(float(cfg["roar_shake"]))
					game.fx.ring(e.pos, e.radius, 260.0, 0.5, Color(1.0, 0.3, 0.2, 0.7))
				elif e.charge_cd <= 0.0 and dist > float(cfg["charge_range_min"]) and dist < float(cfg["charge_range_max"]):
					e.state = B_WINDUP
					e.state_t = cfg["charge_windup"]
					Sfx.play("boss_charge")
		B_WINDUP:
			# Warning: it shakes and flashes while it locks on.
			e.state_t -= dt
			e.face = lerp_angle(e.face, dirp.angle(), minf(dt * 10.0, 1.0))
			var blink := 0.5 + 0.5 * sin(_time * 40.0)
			e.modulate = Color(1.0, 1.0 - blink * 0.6, 1.0 - blink * 0.6)
			e.phase += dt * 40.0
			if e.state_t <= 0.0:
				e.state = B_CHARGE
				e.state_t = cfg["charge_time"]
				e.charge_dir = Vector2.from_angle(e.face)
				e.charge_hit = false
				game.shake(float(cfg["charge_shake"]))
		B_CHARGE:
			e.state_t -= dt
			var before := e.pos + e.charge_dir * (float(cfg["charge_speed"]) * dt)
			e.pos = arena.clamp_inside(before, e.radius)
			game.fx.dust(e.pos - e.charge_dir * e.radius, 2)
			if not e.charge_hit and dist < e.radius + player.radius + 8.0 and player.alive:
				e.charge_hit = true
				game.damage_player(float(cfg["charge_damage"]), e.pos)
			var hit_wall := e.pos.distance_squared_to(before) > 1.0
			if hit_wall:
				game.shake(float(cfg["wall_slam_shake"]))
				game.fx.ring(e.pos, e.radius, 200.0, 0.35, Color(1, 1, 1, 0.5))
				Sfx.play("sledge_hit")
			if e.state_t <= 0.0 or hit_wall:
				e.state = B_RECOVER
				e.state_t = cfg["charge_recover"]
		B_RECOVER:
			e.state_t -= dt
			e.modulate = Color(0.75, 0.75, 0.85)
			if e.state_t <= 0.0:
				e.state = B_CHASE
				e.charge_cd = cfg["charge_cooldown"]
		B_SUMMON:
			e.state_t -= dt
			e.phase += dt * 30.0
			if e.state_t <= 0.0:
				e.state = B_CHASE
				e.summon_cd = cfg["summon_cooldown"]
				var count: int = cfg["summon_count"]
				for k in count:
					if alive_count >= Config.MAX_ENEMIES_ALIVE:
						break
					var ang := TAU * float(k) / float(count) + randf() * 0.4
					var at := arena.clamp_inside(e.pos + Vector2.from_angle(ang) * (e.radius + 46.0), 16.0)
					spawn(Config.SHAMBLER, at, game.enemy_hp_mult, game.enemy_speed_mult, true)
					game.fx.dust(at, 5)

	if e.kb != Vector2.ZERO:
		e.pos += e.kb * dt
		e.kb *= maxf(1.0 - Config.KNOCKBACK_DAMPING * dt, 0.0)
		if e.kb.length_squared() < 25.0:
			e.kb = Vector2.ZERO

	if e.entered:
		e.pos = arena.resolve(e.pos, e.radius)
	elif arena.rect.grow(-e.radius).has_point(e.pos):
		e.entered = true

	# The boss is a wall: the player is pushed out of it.
	if player.alive:
		var tp := player.pos - e.pos
		var prr := e.radius + player.radius
		if tp.length_squared() < prr * prr:
			var n := tp.normalized() if tp.length_squared() > 0.01 else Vector2.RIGHT
			player.pos = arena.resolve(e.pos + n * prr, player.radius)

	e.position = e.pos
	e.rotation = e.face + sin(e.phase) * 0.06


# ----------------------------------------------------------------------------
#  Damage
# ----------------------------------------------------------------------------
## Hurt a zombie. `dir` is the direction of the hit (for knockback and blood).
## Returns true if this killed it.
func damage(e: Enemy, amount: float, dir: Vector2, knockback: float, stagger: float, kill_hitstop: float) -> bool:
	if not e.alive:
		return false
	e.hp -= amount
	e.flash_t = Config.HIT_FLASH_TIME
	e.texture = e.tex_flash
	if knockback > 0.0:
		e.kb = (e.kb + dir * (knockback * e.kb_mult)).limit_length(Config.KNOCKBACK_MAX)
	var st := stagger * e.stagger_mult
	if st > e.stagger_t:
		e.stagger_t = st
	game.fx.blood_spray(e.pos, dir, Config.BLOOD_PER_HIT, 1.0)
	if e.hp <= 0.0:
		_kill(e, dir, kill_hitstop)
		return true
	Sfx.play("zombie_hit", -6.0)
	return false


func _kill(e: Enemy, dir: Vector2, kill_hitstop: float) -> void:
	e.alive = false
	e.visible = false
	_dead_count += 1
	alive_count -= 1
	if e.is_big:
		bigs.erase(e)
	game.on_enemy_killed(e, dir, kill_hitstop)


## Radial blast: shoves (and optionally hurts) everything within `radius`.
func shockwave(center: Vector2, radius: float, force: float, dmg: float, stagger: float = 0.3) -> int:
	var hits := 0
	for e: Enemy in in_radius(center, radius):
		var away := e.pos - center
		var d := away.length()
		var dir := away / d if d > 0.01 else Vector2.from_angle(randf() * TAU)
		var falloff := 1.0 - 0.5 * clampf(d / radius, 0.0, 1.0)
		if dmg > 0.0:
			damage(e, dmg, dir, force * falloff, stagger, 0.0)
		else:
			e.kb = (e.kb + dir * (force * falloff * e.kb_mult)).limit_length(Config.KNOCKBACK_MAX)
			e.stagger_t = maxf(e.stagger_t, stagger * e.stagger_mult)
		hits += 1
	return hits


## Kill everything (used when a run is reset by tests).
func clear_all() -> void:
	for e: Enemy in active:
		e.alive = false
		e.visible = false
		_pool.append(e)
	active.clear()
	bigs.clear()
	alive_count = 0
	_dead_count = 0
	_head.fill(-1)


# ----------------------------------------------------------------------------
#  Queries used by bullets, explosions, melee and aim assist
# ----------------------------------------------------------------------------
## First zombie touched by a thick line from `from` to `to` (a moving bullet).
## Sets `hit_t` to how far along the line the hit happened.
func segment_hit(from: Vector2, to: Vector2, pad: float, ignore: Array) -> Enemy:
	hit_t = 2.0
	var seg := to - from
	var len2 := seg.length_squared()
	if len2 < 0.0001:
		return null
	var seg_len := sqrt(len2)
	var mid := (from + to) * 0.5
	var cx := clampi(int((mid.x - _origin.x) * INV_CELL), 1, _gw - 2)
	var cy := clampi(int((mid.y - _origin.y) * INV_CELL), 1, _gh - 2)
	var best: Enemy = null
	var check_ignore := not ignore.is_empty()
	var count := active.size()
	for row in 3:
		var base := (cy + row - 1) * _gw + cx - 1
		for col in 3:
			var j := _head[base + col]
			while j != -1:
				if j < count:
					var e := active[j]
					if e.alive and not (check_ignore and ignore.has(e)):
						var r := e.radius + pad
						var t := clampf((e.pos - from).dot(seg) / len2, 0.0, 1.0)
						var d2 := (from + seg * t).distance_squared_to(e.pos)
						if d2 <= r * r:
							var enter := maxf(t - sqrt(r * r - d2) / seg_len, 0.0)
							if enter < hit_t:
								hit_t = enter
								best = e
				j = _next[j]
	for b: Enemy in bigs:
		if b.alive and not (check_ignore and ignore.has(b)):
			var br := b.radius + pad
			var bt := clampf((b.pos - from).dot(seg) / len2, 0.0, 1.0)
			var bd2 := (from + seg * bt).distance_squared_to(b.pos)
			if bd2 <= br * br:
				var b_enter := maxf(bt - sqrt(br * br - bd2) / seg_len, 0.0)
				if b_enter < hit_t:
					hit_t = b_enter
					best = b
	return best


## Every living zombie whose body touches the circle.
func in_radius(center: Vector2, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var reach := radius + 30.0
	var cx0 := clampi(int((center.x - reach - _origin.x) * INV_CELL), 1, _gw - 2)
	var cx1 := clampi(int((center.x + reach - _origin.x) * INV_CELL), 1, _gw - 2)
	var cy0 := clampi(int((center.y - reach - _origin.y) * INV_CELL), 1, _gh - 2)
	var cy1 := clampi(int((center.y + reach - _origin.y) * INV_CELL), 1, _gh - 2)
	var count := active.size()
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var j := _head[cy * _gw + cx]
			while j != -1:
				if j < count:
					var e := active[j]
					var r := radius + e.radius
					if e.alive and e.pos.distance_squared_to(center) <= r * r:
						out.append(e)
				j = _next[j]
	for b: Enemy in bigs:
		var br := radius + b.radius
		if b.alive and b.pos.distance_squared_to(center) <= br * br:
			out.append(b)
	return out


## Closest living zombie to a point (null if none within max_dist).
func nearest(center: Vector2, max_dist: float) -> Enemy:
	var best: Enemy = null
	var best_d2 := max_dist * max_dist
	for e: Enemy in active:
		if e.alive:
			var d2 := e.pos.distance_squared_to(center)
			if d2 < best_d2:
				best_d2 = d2
				best = e
	return best


## Mild aim assist: if a zombie is close to the aim line, bend the shot toward it.
func assist_aim(origin: Vector2, dir: Vector2, cone_deg: float, strength: float, max_range: float) -> Vector2:
	if strength <= 0.0 or cone_deg <= 0.0:
		return dir
	var best: Enemy = null
	var best_cos := cos(deg_to_rad(cone_deg))
	var best_d := 1.0
	var r2 := max_range * max_range
	for e: Enemy in active:
		if not e.alive:
			continue
		var to := e.pos - origin
		var d2 := to.length_squared()
		if d2 > r2 or d2 < 1.0:
			continue
		var d := sqrt(d2)
		var c := to.dot(dir) / d
		if c > best_cos:
			best_cos = c
			best = e
			best_d = d
	if best == null:
		return dir
	var want := (best.pos - origin) / best_d
	# Already pointing at its body? Leave the shot exactly where the player aimed.
	if absf(dir.angle_to(want)) <= atan2(best.radius * 0.6, best_d):
		return dir
	return dir.slerp(want, strength).normalized()
