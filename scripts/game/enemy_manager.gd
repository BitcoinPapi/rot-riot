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

# States of a zombie with an attack of its own (the boss, shooters, the
# Gasbag, the Lunger): coming at you -> winding up (the warning) -> attacking
# -> getting over it.
const B_CHASE := 0
const B_WINDUP := 1
const B_CHARGE := 2
const B_RECOVER := 3
const B_SUMMON := 4
# A boss's own move (Config.BOSS_MOVES). Only the lowest two bits of a state travel to
# joining players, so both of these are shown there as a wind-up (1): the boss blinks.
const B_SWEEP := 5     # Machwè Fè: feet planted while the red fan fills, then the blade comes round
const B_THROW := 9     # Papa Zo: about to throw his shovel-loads of grave dirt

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
var _bursts: Array = []             # Gasbags about to go off: [seconds left, where]
var _in_burst := false              # true while a burst is hurting what is around it
var _view := Rect2()                # what the screen shows this frame (zombies only use their special attacks in sight)
var _tip_owed: Array[bool] = []     # per kind: its one-time tip has not been shown yet

# Co-op.
var remote := false                 # true on the joiner's computer: every zombie here is a copy of the host's
var _by_id: Dictionary = {}         # (joiner) net_id -> its copy
var _next_id := 1                   # (host) the number the next zombie gets
var _from_slot := -1                # (host) the slot of the joiner whose hit is being applied right now (-1 = nobody's: the player here)


func setup(g: Game) -> void:
	game = g
	var pad := CELL * 3.0
	_origin = game.arena.rect.position - Vector2(pad, pad)
	var size := game.arena.rect.size + Vector2(pad, pad) * 2.0
	_gw = int(ceil(size.x / CELL)) + 2
	_gh = int(ceil(size.y / CELL)) + 2
	_head.resize(_gw * _gh)
	_head.fill(-1)
	_next.resize(512)
	_build_obstacle_cells()
	# The first time a new kind of zombie comes into view, the player is told what it does.
	for kind in Art.ENEMY_SPRITE.size():
		_tip_owed.append(Config.ENEMIES[kind].has("tip") and not SaveData.enemies_seen.has(Art.ENEMY_SPRITE[kind]))


func _build_obstacle_cells() -> void:
	_cell_obstacle.resize(_gw * _gh)
	_cell_obstacle.fill(-1)
	# (Walks the obstacles, not the cells: a big map has thousands of cells.)
	var arena := game.arena
	for i in arena.obs_pos.size():
		var c := arena.obs_pos[i]
		var reach := arena.obs_radius[i] + 36.0
		var x0 := clampi(int((c.x - reach - _origin.x) * INV_CELL), 0, _gw - 1)
		var x1 := clampi(int((c.x + reach - _origin.x) * INV_CELL), 0, _gw - 1)
		var y0 := clampi(int((c.y - reach - _origin.y) * INV_CELL), 0, _gh - 1)
		var y1 := clampi(int((c.y + reach - _origin.y) * INV_CELL), 0, _gh - 1)
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				if _cell_obstacle[cy * _gw + cx] != -1:
					continue
				var cell_rect := Rect2(_origin + Vector2(cx, cy) * CELL, Vector2(CELL, CELL))
				var nearest_pt := Vector2(
					clampf(c.x, cell_rect.position.x, cell_rect.end.x),
					clampf(c.y, cell_rect.position.y, cell_rect.end.y))
				if nearest_pt.distance_to(c) <= reach:
					_cell_obstacle[cy * _gw + cx] = i


# ----------------------------------------------------------------------------
#  Spawning
# ----------------------------------------------------------------------------
func spawn(kind: int, at: Vector2, hp_mult: float = 1.0, speed_mult: float = 1.0, rising: bool = false, variant: int = -1) -> Enemy:
	var e: Enemy
	if _pool.is_empty():
		e = Enemy.new()
		add_child(e)
	else:
		e = _pool.pop_back()
	var c: Dictionary = Config.ENEMIES[kind]
	var speed_var: float = c["speed_var"]
	e.kind = kind
	e.variant = variant if variant >= 0 else randi() % int(Art.ENEMY_VARIANTS[kind])
	e.alive = true
	e.net_id = _next_id
	_next_id = _next_id % 65535 + 1
	e.net_hit = false
	e.burn_slot = -1
	if not remote:
		_by_id[e.net_id] = e
	e.pos = at
	e.kb = Vector2.ZERO
	e.max_hp = float(c["hp"]) * hp_mult
	e.hp = e.max_hp
	e.radius = c["radius"]
	e.speed = float(c["speed"]) * speed_mult * (1.0 + randf_range(-speed_var, speed_var))
	e.damage = float(c["damage"]) * game.enemy_damage_mult
	e.attack_cd = c["attack_cd"]
	e.attack_t = Config.ENEMY_FIRST_ATTACK_DELAY
	e.flash_t = 0.0
	e.stagger_t = 0.0
	e.spawn_t = Config.SUMMON_RISE_TIME if rising else 0.0
	e.burn_t = 0.0
	e.burn_dps = 0.0
	e.wounded = false
	e.pet_marked = false
	e.sway = 0.06 if kind == Config.BOSS else 0.13
	e.phase = randf() * TAU
	e.stride = float(c.get("stride", 0.0))
	e.stride_t = randf() * e.stride
	e.flip_v = false
	e.flank = Vector2.from_angle(randf() * TAU) * (randf() * Config.ENEMY_FLANK_SPREAD)
	e.entered = game.arena.rect.grow(-e.radius).has_point(at)
	e.kb_mult = c["kb_mult"]
	e.stagger_mult = c["stagger_mult"]
	e.inv_mass = 1.0 / float(c["mass"])
	e.push_player = c["push_player"]
	e.score = c["score"]
	e.xp = maxi(int(round(float(c["xp"]) * game.enemy_xp_mult)), 1)
	e.hitstop_mult = c["hitstop_mult"]
	e.shake_mult = c["shake_mult"]
	e.blood = c["blood"]
	e.is_big = kind == Config.BOSS
	e.ai = int(c.get("ai", Config.AI_WALKER))
	e.cfg = c
	e.state = B_CHASE
	e.state_t = 0.0
	e.melee_t = Config.ENEMY_FIRST_ATTACK_DELAY
	e.warn = c.get("warn_color", Color.WHITE)
	if e.ai == Config.AI_SHOOTER:
		e.shoot_range = float(c["range"]) * randf_range(0.82, 1.0)
		e.attack_t = randf_range(Config.SHOOTER_FIRST_SHOT_MIN, Config.SHOOTER_FIRST_SHOT_MAX)
	elif e.ai == Config.AI_LEAPER:
		e.charge_cd = float(c["leap_cooldown"]) * randf_range(0.15, 0.6)
	if e.is_big:
		var own: Dictionary = Config.boss_move(e.variant)
		e.charge_cd = float(c["charge_cooldown"]) * 0.6
		e.summon_cd = float(own.get("summon_cooldown", c["summon_cooldown"])) * 0.5
		e.move_cd = float(own.get("sweep_cooldown", own.get("dirt_cooldown", 0.0))) * 0.6
		e.combo = 0
		bigs.append(e)
	e.tex_normal = Art.enemy_tex(kind, e.variant)
	e.tex_flash = Art.enemy_flash_tex(kind, e.variant)
	e.tex_hurt = Art.enemy_hurt_tex(kind, e.variant)
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
	_view = game.cam.view_rect().grow(-24.0)
	var n := active.size()

	# 1) Sort every zombie into the grid.
	_sort_grid(n)
	var gw := _gw

	# Gasbags that are due go off (now that the grid knows where everybody is).
	if not _bursts.is_empty():
		_tick_bursts(dt)

	# 2) Move, separate, attack.
	var player := game.player
	var ppos := player.pos
	var pr := player.radius
	var player_alive := player.alive
	# Co-op: the other players' figures are something to chase too.
	var ups: Array[Mate] = game.coop.mates_up() if game.coop != null else ([] as Array[Mate])
	var some_up := not ups.is_empty()
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
	var drip: float = Config.WOUNDED_DRIP_RATE * dt
	var decals := game.decals
	var push_total := Vector2.ZERO
	var has_bigs := not bigs.is_empty()
	var leash := game.leash_dist

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

		# On fire: steady damage, a few flames, and a charred body if it dies.
		if e.burn_t > 0.0:
			e.hp -= e.burn_dps * dt
			if not e.wounded and e.hp < e.max_hp * Config.WOUNDED_AT:
				_wound(e)
			if randf() < dt * 7.0:
				game.fx.ember(e.pos, e.radius)
			if e.hp <= 0.0:
				_kill(e, Vector2.from_angle(randf() * TAU), 0.0, e.burn_src, e.burn_slot)
				continue
			e.burn_t -= dt
			if e.burn_t <= 0.0:
				e.modulate = Color.WHITE

		if e.is_big:
			_tick_boss(e, dt)
			continue

		var epos := e.pos
		var er := e.radius
		# Who it is after: the nearer player who is still on their feet.
		var tpos := ppos
		var t_ok := player_alive
		var t_mate: Mate = null
		if some_up:
			var closest := epos.distance_squared_to(ppos) if player_alive else 1.0e12
			for other: Mate in ups:
				var gap := epos.distance_squared_to(other.pos)
				if gap < closest:
					closest = gap
					tpos = other.pos
					t_ok = true
					t_mate = other
		var to_p := tpos - epos
		var dist := to_p.length()
		# Left far behind on the big map: it gives up, and comes back with a later pack.
		if dist > leash:
			_lose(e)
			continue
		var dirp := to_p / maxf(dist, 0.001)
		var reach := er + pr + reach_pad

		if e.spawn_t > 0.0:
			# Clawing up out of the ground.
			e.spawn_t -= dt
			var rs := e.base_scale * (1.0 - 0.7 * maxf(e.spawn_t, 0.0) / Config.SUMMON_RISE_TIME)
			e.scale = Vector2(rs, rs)
		elif e.stagger_t > 0.0:
			e.stagger_t -= dt
			if e.state != B_CHASE:
				_knocked(e)
		elif e.ai != 0:
			epos = _tick_special(e, epos, dt, to_p, dist, turn, t_ok, t_mate)
			if not e.alive:
				continue
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
				if e.stride > 0.0:
					_stride(e, dt)
				e.face = lerp_angle(e.face, d.angle(), turn)
			else:
				e.face = lerp_angle(e.face, dirp.angle(), turn)
			e.attack_t -= dt
			if dist <= reach and e.attack_t <= 0.0 and t_ok:
				e.attack_t = e.attack_cd
				_hurt(t_mate, e.damage, epos)

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
		e.rotation = e.face + sin(e.phase) * e.sway
		# A badly hurt zombie leaves a trail of blood behind it.
		if e.wounded and randf() < drip:
			decals.blood_dot(epos + Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0)), randf_range(3.0, 6.5))

	if push_total != Vector2.ZERO and player_alive:
		player.pos = arena.resolve(player.pos + push_total.limit_length(Config.PLAYER_MAX_PUSH_PER_FRAME), pr)


## Sort every zombie into the grid of cells, so each one only has to look at
## its neighbours (and bullets only at the zombies near them).
func _sort_grid(n: int) -> void:
	if _next.size() < n + 64:
		_next.resize(n + 256)
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
	var move: Dictionary = Config.boss_move(e.variant)     # (what this map's boss does besides charging and summoning)
	var own := String(move.get("move", ""))
	var player := game.player
	var arena := game.arena
	# Who it is after: the nearer player who is still on their feet.
	var tpos := player.pos
	var t_ok := player.alive
	var t_mate: Mate = null
	if game.coop != null:
		var closest := e.pos.distance_squared_to(player.pos) if player.alive else 1.0e12
		for other: Mate in game.coop.mates_up():
			var gap := e.pos.distance_squared_to(other.pos)
			if gap < closest:
				closest = gap
				tpos = other.pos
				t_ok = true
				t_mate = other
	var to_p := tpos - e.pos
	var dist := to_p.length()
	var dirp := to_p / maxf(dist, 0.001)
	var reach := e.radius + player.radius + Config.ENEMY_ATTACK_REACH
	var turn := minf(Config.ENEMY_TURN_SPEED * 0.6 * dt, 1.0)
	e.modulate = Config.BURN_TINT if e.burn_t > 0.0 else Color.WHITE

	match e.state:
		B_CHASE:
			e.phase += dt * 5.0
			if dist > game.boss_leash and t_ok:
				_relocate_boss(e)
				return
			if dist > reach:
				e.pos += dirp * (e.speed * dt)
			e.face = lerp_angle(e.face, dirp.angle(), turn)
			e.attack_t -= dt
			if dist <= reach and e.attack_t <= 0.0 and t_ok:
				e.attack_t = e.attack_cd
				_hurt(t_mate, e.damage, e.pos)
			if e.entered and t_ok:
				e.charge_cd -= dt
				e.summon_cd -= dt
				e.move_cd -= dt
				if e.summon_cd <= 0.0:
					e.state = B_SUMMON
					e.state_t = cfg["summon_windup"]
					Sfx.play("boss_roar")
					game.shake(float(cfg["roar_shake"]))
					game.fx.ring(e.pos, e.radius, 260.0, 0.5, Color(1.0, 0.3, 0.2, 0.7))
				elif own == "sweep" and e.move_cd <= 0.0 and dist < float(move["sweep_range"]):
					# The red fan is the warning; it opens where he looks NOW and does not follow the player.
					e.state = B_SWEEP
					e.state_t = move["sweep_windup"]
					e.face = dirp.angle()
					game.enemy_shots.sweep(e.pos, e.face, move, float(move["sweep_damage"]) * game.enemy_damage_mult)
					Sfx.play("boss_charge")
				elif own == "dirt" and e.move_cd <= 0.0 and dist > float(move["dirt_range_min"]) and dist < float(move["dirt_range_max"]):
					e.state = B_THROW
					e.state_t = move["dirt_windup"]
					Sfx.play("boss_charge")
				elif e.charge_cd <= 0.0 and dist > float(cfg["charge_range_min"]) and dist < float(cfg["charge_range_max"]):
					e.state = B_WINDUP
					e.state_t = cfg["charge_windup"]
					e.combo = int(move.get("charges", 1)) - 1
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
			if not e.charge_hit and dist < e.radius + player.radius + 8.0 and t_ok:
				e.charge_hit = true
				_hurt(t_mate, float(cfg["charge_damage"]) * game.enemy_damage_mult, e.pos)
			var hit_wall := e.pos.distance_squared_to(before) > 1.0
			if hit_wall:
				game.shake(float(cfg["wall_slam_shake"]))
				game.fx.ring(e.pos, e.radius, 200.0, 0.35, Color(1, 1, 1, 0.5))
				Sfx.play("boss_slam")
			if e.state_t <= 0.0 or hit_wall:
				if e.combo > 0 and not hit_wall:
					# (Kòk Batay) no rest: he turns on you and charges again.
					e.combo -= 1
					e.state = B_WINDUP
					e.state_t = move["again_windup"]
					Sfx.play("boss_charge")
				else:
					e.combo = 0
					e.state = B_RECOVER
					e.state_t = float(cfg["charge_recover"]) * float(move.get("recover_mult", 1.0))
		B_RECOVER:
			e.state_t -= dt
			e.modulate = Color(0.75, 0.75, 0.85)
			if e.state_t <= 0.0:
				e.state = B_CHASE
				e.charge_cd = cfg["charge_cooldown"]
		B_SWEEP:
			# (Machwè Fè) He stands where he is while the fan fills; the cutting is done by
			# EnemyShots, on every computer for its own player.
			e.state_t -= dt
			var glare := 0.5 + 0.5 * sin(_time * 40.0)
			e.modulate = Color(1.0, 1.0 - glare * 0.6, 1.0 - glare * 0.6)
			e.phase += dt * 40.0
			if e.state_t <= 0.0:
				e.state = B_RECOVER
				e.state_t = move["sweep_recover"]
				e.move_cd = move["sweep_cooldown"]
		B_THROW:
			# (Papa Zo) A moment of warning, then shovel-loads of grave dirt: one on the
			# player's spot and the others beside it, so stepping sideways is not enough.
			e.state_t -= dt
			e.face = lerp_angle(e.face, dirp.angle(), minf(dt * 10.0, 1.0))
			var flush := 0.5 + 0.5 * sin(_time * 40.0)
			e.modulate = Color(1.0, 1.0 - flush * 0.6, 1.0 - flush * 0.6)
			e.phase += dt * 40.0
			if e.state_t <= 0.0:
				e.state = B_CHASE
				e.move_cd = move["dirt_cooldown"]
				var lump: Dictionary = Config.ENEMIES[Config.CHUCKER]      # (they fly and land like a Chucker's rubble)
				var side := Vector2(-dirp.y, dirp.x)
				var lumps := int(move["dirt_lumps"])
				for k in lumps:
					var beside := side * (float(move["dirt_spread"]) * (float(k) - float(lumps - 1) * 0.5))
					var off := Vector2.from_angle(randf() * TAU) * (randf() * float(lump["lob_aim_error"]))
					game.enemy_shots.lob(e.pos + dirp * e.radius, tpos + beside + off, lump,
							float(move["dirt_damage"]) * game.enemy_damage_mult)
		B_SUMMON:
			e.state_t -= dt
			e.phase += dt * 30.0
			if e.state_t <= 0.0:
				e.state = B_CHASE
				e.summon_cd = float(move.get("summon_cooldown", cfg["summon_cooldown"]))
				var count := int(move.get("summon_count", cfg["summon_count"]))
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
	e.rotation = e.face + sin(e.phase) * e.sway
	if e.wounded and randf() < Config.WOUNDED_DRIP_RATE * 3.0 * dt:
		game.decals.blood_dot(e.pos + Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0)), randf_range(6.0, 13.0))


# ----------------------------------------------------------------------------
#  Damage
# ----------------------------------------------------------------------------
## A zombie lands a blow on whoever it was after.
func _hurt(mate: Mate, amount: float, from: Vector2) -> void:
	if mate != null:
		game.coop.hurt_mate(mate, amount, from)
	else:
		game.damage_player(amount, from)


## Hurt a zombie. `dir` is the direction of the hit (for knockback and blood).
## `source` is the weapon id that did it (it earns the XP), "" for anything else.
## Returns true if this killed it.
func damage(e: Enemy, amount: float, dir: Vector2, knockback: float, stagger: float, kill_hitstop: float,
		source: String = "", crit: bool = false) -> bool:
	if not e.alive:
		return false
	if e.wounded and _from_slot < 0:
		amount *= 1.0 + game.player.stats.wounded_damage      # EXECUTIONER keystone (the other player's is already in their number)
	if remote:
		# (joiner) Show the hit at once; the host's computer applies it for real.
		if crit:
			game.fx.crit_spark(e.pos, dir)
			Sfx.play("crit", -4.0)
		e.flash_t = Config.HIT_FLASH_TIME
		e.texture = e.tex_flash
		game.fx.blood_spray(e.pos, dir, Config.BLOOD_PER_HIT, 1.0)
		Sfx.play("zombie_hit", -6.0)
		game.coop.send_hit(e, amount, dir, knockback, stagger, crit, source, kill_hitstop)
		return false
	e.net_hit = true
	e.hp -= amount
	if not e.wounded and e.hp > 0.0 and e.hp < e.max_hp * Config.WOUNDED_AT:
		_wound(e)
	if crit:
		game.fx.crit_spark(e.pos, dir)
		Sfx.play("crit", -4.0)
	e.flash_t = Config.HIT_FLASH_TIME
	e.texture = e.tex_flash
	if knockback > 0.0:
		e.kb = (e.kb + dir * (knockback * e.kb_mult)).limit_length(Config.KNOCKBACK_MAX)
	var st := stagger * e.stagger_mult
	if st > e.stagger_t:
		e.stagger_t = st
	game.fx.blood_spray(e.pos, dir, Config.BLOOD_PER_HIT, 1.0)
	if e.hp <= 0.0:
		_kill(e, dir, kill_hitstop, source)
		return true
	Sfx.play("zombie_hit", -6.0)
	return false


## One picture, two steps: a zombie with a "stride" (config) is shown mirrored on every
## other step - left foot forward, right foot forward - so a single picture runs.
## Only how it looks: nothing in the fight depends on it.
func _stride(e: Enemy, dt: float) -> void:
	e.stride_t += dt * (Config.WOUNDED_STRIDE if e.wounded else 1.0)
	if e.stride_t >= e.stride:
		e.stride_t = fmod(e.stride_t, e.stride)
		e.flip_v = not e.flip_v


## The zombie is badly hurt: from now on it shows its wounds, limps and bleeds.
func _wound(e: Enemy) -> void:
	e.wounded = true
	e.tex_normal = e.tex_hurt
	if e.flash_t <= 0.0:
		e.texture = e.tex_hurt
	e.speed *= Config.WOUNDED_SPEED_MULT
	e.sway *= Config.WOUNDED_LIMP


## Set a zombie on fire (flamethrower). Refreshes the timer if it already burns.
func ignite(e: Enemy, seconds: float, dps: float, source: String) -> void:
	if not e.alive:
		return
	if remote:
		e.modulate = Config.BURN_TINT
		game.coop.send_ignite(e, seconds, dps, source)
		return
	e.burn_slot = _from_slot
	e.burn_t = maxf(e.burn_t, seconds)
	e.burn_dps = maxf(e.burn_dps, dps)
	e.burn_src = source
	e.modulate = Config.BURN_TINT


func _kill(e: Enemy, dir: Vector2, kill_hitstop: float, source: String, killer: int = -1) -> void:
	e.alive = false
	e.visible = false
	_dead_count += 1
	alive_count -= 1
	if e.is_big:
		bigs.erase(e)
	_by_id.erase(e.net_id)
	# A Gasbag goes off however it dies (a moment later if another burst set it off).
	if e.ai == Config.AI_BURSTER:
		_bursts.append([float(e.cfg["burst_chain_delay"]) if _in_burst else 0.0, e.pos])
	game.on_enemy_killed(e, dir, kill_hitstop, source, killer if killer >= 0 else _from_slot)


# ----------------------------------------------------------------------------
#  Zombies with an attack of their own. Each of them warns before it attacks:
#  it stops, swells and flushes with colour for a moment.
# ----------------------------------------------------------------------------
## One step for a shooter, a Gasbag or a Lunger. Returns where it now stands.
func _tick_special(e: Enemy, epos: Vector2, dt: float, to_p: Vector2, dist: float, turn: float, t_ok: bool, t_mate: Mate) -> Vector2:
	var c := e.cfg
	var player := game.player
	var dirp := to_p / maxf(dist, 0.001)
	var reach := e.radius + player.radius + Config.ENEMY_ATTACK_REACH

	if e.state == B_CHASE:
		e.phase += dt * 8.0
		if _tip_owed[e.kind] and _view.has_point(epos) and game.fog.is_clear(epos):
			_tip(e)
		var walk := true
		match e.ai:
			Config.AI_SHOOTER:
				# It attacks from where it can see the player: close enough, on
				# screen, and not hidden in the fog.
				if dist < e.shoot_range and _view.has_point(epos) and game.fog.is_clear(epos):
					walk = false
					e.attack_t -= dt
					if e.attack_t <= 0.0 and t_ok:
						_wind_up(e, float(c["shot_windup"]), "gobber_windup" if e.kind == Config.GOBBER else "chucker_windup")
				# A player who walks into it gets hit the plain way.
				if dist <= reach:
					e.melee_t -= dt
					if e.melee_t <= 0.0 and t_ok:
						e.melee_t = e.attack_cd
						_hurt(t_mate, e.damage, epos)
			Config.AI_BURSTER:
				if dist <= reach + float(c["burst_trigger"]) and t_ok:
					walk = false
					_wind_up(e, float(c["burst_fuse"]), "gasbag_fuse")
			Config.AI_LEAPER:
				e.charge_cd -= dt
				if e.charge_cd <= 0.0 and dist > float(c["leap_range_min"]) and dist < float(c["leap_range_max"]) \
						and t_ok and _view.has_point(epos):
					walk = false
					_wind_up(e, float(c["leap_windup"]), "lunger_shriek")
				elif dist <= reach:
					walk = false
					e.attack_t -= dt
					if e.attack_t <= 0.0 and t_ok:
						e.attack_t = e.attack_cd
						_hurt(t_mate, e.damage, epos)
		if walk and dist > reach:
			var d := dirp
			if dist > 90.0:
				d = (to_p + e.flank * minf(dist * 0.004, 1.0)).normalized()
			var step := e.speed * dt
			if e.crowd_prev > Config.ENEMY_CROWD_FREE:
				step *= float(Config.ENEMY_CROWD_FREE + 1) / float(e.crowd_prev + 1)
			epos += d * step
			e.face = lerp_angle(e.face, d.angle(), turn)
		else:
			e.face = lerp_angle(e.face, dirp.angle(), turn)
		return epos

	e.state_t -= dt
	match e.state:
		B_WINDUP:
			# The warning: it swells and flushes, and keeps its eyes on the player.
			var total := float(c["burst_fuse"]) if e.ai == Config.AI_BURSTER else (
					float(c["leap_windup"]) if e.ai == Config.AI_LEAPER else float(c["shot_windup"]))
			_windup_look(e, clampf(1.0 - e.state_t / total, 0.0, 1.0))
			e.phase += dt * 30.0
			e.face = lerp_angle(e.face, dirp.angle(), minf(dt * 10.0, 1.0))
			if e.state_t <= 0.0:
				match e.ai:
					Config.AI_SHOOTER:
						_shoot(e, epos, dirp, epos + to_p)
						_settle(e)
						e.attack_t = float(c["shot_cooldown"]) * randf_range(0.85, 1.2)
					Config.AI_BURSTER:
						_kill(e, dirp, 0.0, "")
					Config.AI_LEAPER:
						e.state = B_CHARGE
						e.state_t = c["leap_time"]
						e.charge_dir = dirp
						e.charge_hit = false
						e.modulate = Config.BURN_TINT if e.burn_t > 0.0 else Color.WHITE
						game.fx.dust(epos, 3)
		B_CHARGE:
			# In the air, in a straight line at where the player was.
			epos += e.charge_dir * (float(c["leap_speed"]) * dt)
			var air := e.base_scale * 1.22
			e.scale = Vector2(air, air)
			e.face = e.charge_dir.angle()
			if not e.charge_hit and dist < e.radius + player.radius + 6.0 and t_ok:
				e.charge_hit = true
				_hurt(t_mate, float(c["leap_damage"]) * game.enemy_damage_mult, epos)
			if e.state_t <= 0.0 or e.charge_hit:
				e.state = B_RECOVER
				e.state_t = c["leap_recover"]
				e.scale = Vector2(e.base_scale, e.base_scale)
				game.fx.dust(epos, 4)
		B_RECOVER:
			# Dazed after landing: the moment to shoot it.
			e.modulate = Color(0.72, 0.72, 0.8)
			if e.state_t <= 0.0:
				_settle(e)
				e.charge_cd = float(c["leap_cooldown"]) * randf_range(0.85, 1.2)
	return epos


## The one-time introduction of a new kind of zombie: its name, what it does,
## and a ring around it so it is clear which one is meant.
func _tip(e: Enemy) -> void:
	_tip_owed[e.kind] = false
	SaveData.enemies_seen.append(Art.ENEMY_SPRITE[e.kind])
	game.hud.show_tip(String(e.cfg["name"]).to_upper(), String(e.cfg["tip"]), e.warn, Config.ENEMY_TIP_TIME)
	game.fx.ring(e.pos, 90.0, e.radius + 8.0, 0.7, e.warn)
	game.fx.ring(e.pos, 130.0, e.radius + 8.0, 1.0, e.warn)


## How a zombie looks while it winds up (`f` = how far along, 0..1): it
## swells and flushes with its warning colour.
func _windup_look(e: Enemy, f: float) -> void:
	var blink := 0.5 + 0.5 * sin(_time * 34.0)
	var puff := e.base_scale * (1.0 + Config.SPECIAL_SWELL * f * (1.6 if e.ai == Config.AI_BURSTER else 1.0))
	if e.ai == Config.AI_LEAPER:
		puff = e.base_scale * (1.0 - 0.16 * f)        # (it crouches instead)
	e.scale = Vector2(puff, puff)
	e.modulate = Color.WHITE.lerp(e.warn, f * (0.55 + 0.45 * blink))


## Start the warning before an attack.
func _wind_up(e: Enemy, seconds: float, sound: String) -> void:
	e.state = B_WINDUP
	e.state_t = seconds
	if _view.has_point(e.pos):
		Sfx.play(sound, -4.0, 0.15)


## Back to walking, looking normal again.
func _settle(e: Enemy) -> void:
	e.state = B_CHASE
	e.scale = Vector2(e.base_scale, e.base_scale)
	e.modulate = Config.BURN_TINT if e.burn_t > 0.0 else Color.WHITE


## A hit staggered it in the middle of its attack.
func _knocked(e: Enemy) -> void:
	match e.ai:
		Config.AI_SHOOTER:
			# A Gobber swallows its spit and has to start again; a Chucker just waits.
			if e.state == B_WINDUP and bool(e.cfg["shot_interrupt"]):
				_settle(e)
				e.attack_t = float(e.cfg["shot_cooldown"]) * 0.5
		Config.AI_LEAPER:
			# Shot out of the air (or out of its crouch): it drops, dazed.
			if e.state == B_CHARGE or e.state == B_WINDUP:
				e.state = B_RECOVER
				e.state_t = float(e.cfg["leap_recover"]) * 0.6
				e.scale = Vector2(e.base_scale, e.base_scale)


## A shooter lets fly: a Gobber spits straight at the player, a Chucker lobs
## rubble onto the spot where the player stands right now.
func _shoot(e: Enemy, epos: Vector2, dirp: Vector2, target: Vector2) -> void:
	var c := e.cfg
	if e.kind == Config.GOBBER:
		var dir := dirp.rotated(deg_to_rad(randf_range(-1.0, 1.0) * float(c["shot_spread_deg"])))
		game.enemy_shots.spit(epos + dirp * (e.radius + 4.0), dir, c, float(c["shot_damage"]) * game.enemy_damage_mult)
	else:
		var off := Vector2.from_angle(randf() * TAU) * (randf() * float(c["lob_aim_error"]))
		game.enemy_shots.lob(epos + dirp * e.radius, target + off, c, float(c["lob_damage"]) * game.enemy_damage_mult)


## Gasbags that are due go off.
func _tick_bursts(dt: float) -> void:
	var i := 0
	while i < _bursts.size():
		var b: Array = _bursts[i]
		b[0] = float(b[0]) - dt
		if float(b[0]) <= 0.0:
			_bursts.remove_at(i)
			_burst(b[1])
		else:
			i += 1


## A Gasbag bursts: everything around it is hurt and thrown back - zombies
## (the kills are the player's), the player, weapon crates.
func _burst(at: Vector2) -> void:
	var c: Dictionary = Config.ENEMIES[Config.GASBAG]
	var radius: float = c["burst_radius"]
	var edge: float = c["burst_edge_damage"]
	var hurt: float = float(c["burst_zombie_damage"]) * game.enemy_hp_mult
	_in_burst = true
	for e: Enemy in in_radius(at, radius):
		var away := e.pos - at
		var d := away.length()
		var dir := away / d if d > 0.01 else Vector2.from_angle(randf() * TAU)
		var f := clampf(d / radius, 0.0, 1.0)
		damage(e, hurt * lerpf(1.0, edge, f), dir, float(c["burst_knockback"]) * lerpf(1.0, 0.5, f), float(c["burst_stagger"]), 0.0)
	_in_burst = false
	var player := game.player
	if player.alive and player.pos.distance_to(at) < radius + player.radius:
		game.damage_player(float(c["burst_damage"]) * game.enemy_damage_mult, at)
	if game.coop != null:
		for other: Mate in game.coop.mates_up():
			if other.pos.distance_to(at) < radius + other.radius:
				game.coop.hurt_mate(other, float(c["burst_damage"]) * game.enemy_damage_mult, at)
		game.coop.send([Coop.E_BURST, at.x, at.y])
	game.pickups.blast_crates(at, radius, float(c["burst_crate_damage"]) / Config.CRATE_BLAST_MULT, edge)
	burst_fx(at)


## What a Gasbag going off looks and sounds like: a wet bang and a cloud of foul gas.
func burst_fx(at: Vector2) -> void:
	var c: Dictionary = Config.ENEMIES[Config.GASBAG]
	var radius: float = c["burst_radius"]
	var fx := game.fx
	fx.blood_burst(at, 26, 1.7)
	fx.cloud(at, 16, 46.0, Color(0.62, 0.72, 0.2, 0.5), 150.0)
	fx.ring(at, 16.0, radius, 0.32, Color(0.85, 0.95, 0.35, 0.85))
	fx.light(at, radius * 2.4, 0.25, Color(0.8, 0.95, 0.3, 0.6))
	for k in 4:
		game.decals.blood_splat(at + Vector2.from_angle(randf() * TAU) * randf_range(8.0, radius * 0.5), randf_range(44.0, 80.0))
	game.decals.stamp(Art.t("glow"), at, 0.0, Vector2(radius, radius) * 1.7, Color(0.36, 0.42, 0.08, 0.4))
	game.shake(float(c["burst_shake"]))
	game.hitstop(float(c["burst_hitstop"]), true)
	Sfx.play("gas_burst", 0.0, 0.12)


## A zombie that was left far behind is taken off the field without a reward;
## the wave director sends another in its place.
func _lose(e: Enemy) -> void:
	_by_id.erase(e.net_id)
	e.alive = false
	e.visible = false
	_dead_count += 1
	alive_count -= 1
	game.director.on_enemy_lost(e)


## A boss that was left far behind digs through the ground and bursts out
## near the player: on a big map there is no running away from it.
func _relocate_boss(e: Enemy) -> void:
	var cfg: Dictionary = Config.ENEMIES[Config.BOSS]
	game.fx.dust(e.pos, 14)
	e.pos = game.spawn_point(randf() * TAU, 0.0, e.radius + 12.0)
	e.kb = Vector2.ZERO
	e.entered = true
	e.charge_cd = maxf(e.charge_cd, float(cfg["charge_cooldown"]) * 0.5)
	e.position = e.pos
	game.fx.dust(e.pos, 14)
	game.fx.ring(e.pos, e.radius, 260.0, 0.5, Color(1.0, 0.3, 0.2, 0.7))
	Sfx.play("boss_roar")
	game.shake(float(cfg["roar_shake"]))


## Radial blast: shoves (and optionally hurts) everything within `radius`.
func shockwave(center: Vector2, radius: float, force: float, dmg: float, stagger: float = 0.3) -> int:
	if remote and dmg <= 0.0:
		game.coop.send_knock(center, radius, force, stagger)      # (joiner) the host does the shoving
		return 0
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
	_bursts.clear()
	_by_id.clear()
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


# ----------------------------------------------------------------------------
#  Co-op, on the host: the other player's hits arrive as messages
# ----------------------------------------------------------------------------
func by_id(id: int) -> Enemy:
	var e: Enemy = _by_id.get(id)
	return e if e != null and e.alive else null


func apply_mate_hit(from: int, id: int, amount: float, dir: Vector2, knockback: float, stagger: float, crit: bool, source: String,
		kill_hitstop: float) -> void:
	var e := by_id(id)
	if e == null or is_nan(amount) or amount <= 0.0:
		return
	_from_slot = from
	damage(e, amount, dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT,
			clampf(knockback, 0.0, Config.KNOCKBACK_MAX), clampf(stagger, 0.0, 2.0), clampf(kill_hitstop, 0.0, Config.HITSTOP_MAX), source, crit)
	_from_slot = -1


func apply_mate_ignite(from: int, id: int, seconds: float, dps: float, source: String) -> void:
	var e := by_id(id)
	if e == null or is_nan(dps):
		return
	_from_slot = from
	ignite(e, clampf(seconds, 0.0, 20.0), maxf(dps, 0.0), source)
	_from_slot = -1


# ----------------------------------------------------------------------------
#  Co-op, on the joiner's computer: every zombie is a copy of the host's.
#  A copy has no mind of its own - it glides to where the host last said it
#  was and looks the way the host says it looks. Bullets, blasts and the
#  player's own body still meet it here, which is why it lives in the same
#  grid as real zombies.
# ----------------------------------------------------------------------------
## A piece of the host's list of every living zombie. `serial` is the number
## of the list it belongs to.
func apply_snapshot(buf: StreamPeerBuffer, count: int, serial: int) -> void:
	for i in count:
		var id := buf.get_u16()
		var kind_variant := buf.get_u8()
		var at := Vector2(buf.get_16(), buf.get_16())
		var face := float(buf.get_u8()) / 256.0 * TAU
		var bits := buf.get_u8()
		var health := float(buf.get_u8()) / 255.0
		var kind := kind_variant & 15
		if kind >= Art.ENEMY_SPRITE.size():
			continue
		var e: Enemy = _by_id.get(id)
		if e == null or not e.alive or e.kind != kind:
			if e != null and e.alive:
				_drop(e)
			e = spawn(kind, at, 1.0, 1.0, false, (kind_variant >> 4) % int(Art.ENEMY_VARIANTS[kind]))
			e.net_id = id
			_by_id[id] = e
			e.net_from = at
			e.net_to = at
			e.net_t = 1.0
			e.face = face
		else:
			e.net_from = e.pos
			e.net_to = at
			e.net_t = 0.0
		e.net_face = face
		e.net_seen = serial
		e.max_hp = 1.0
		e.hp = health
		if bits & 1 != 0 and e.flash_t <= 0.0:
			e.flash_t = Config.HIT_FLASH_TIME
			e.texture = e.tex_flash
		if bits & 2 != 0 and not e.wounded:
			_wound(e)
		e.burn_t = 1.0 if bits & 4 != 0 else 0.0
		e.spawn_t = 1.0 if bits & 8 != 0 else 0.0
		var state := (bits >> 4) & 3
		if state != e.state:
			e.state = state
			e.state_t = _warning_time(e)


## The whole list number `serial` has arrived: whatever it did not mention is gone.
func drop_unseen(serial: int) -> void:
	for e: Enemy in active:
		if e.alive and e.net_seen != serial:
			_drop(e)


## How long this kind's warning lasts (for showing it on a copy).
func _warning_time(e: Enemy) -> float:
	match e.ai:
		Config.AI_SHOOTER:
			return float(e.cfg["shot_windup"])
		Config.AI_BURSTER:
			return float(e.cfg["burst_fuse"])
		Config.AI_LEAPER:
			return float(e.cfg["leap_windup"])
	return float(e.cfg.get("charge_windup", 1.0))


## Take a copy off the field without any fuss.
func _drop(e: Enemy) -> void:
	_by_id.erase(e.net_id)
	e.alive = false
	e.visible = false
	_dead_count += 1
	alive_count -= 1
	if e.is_big:
		bigs.erase(e)


## The host says this zombie died: take its copy off the field and hand it
## back, so the death can be shown (if the copy is already gone, one is made
## for the purpose).
func remote_kill(id: int, at: Vector2, kind: int, variant: int, flags: int) -> Enemy:
	kind = clampi(kind, 0, Art.ENEMY_SPRITE.size() - 1)
	var e: Enemy = _by_id.get(id)
	if e == null or not e.alive:
		e = spawn(kind, at, 1.0, 1.0, false, variant % int(Art.ENEMY_VARIANTS[kind]))
		e.rotation = randf() * TAU
	if flags & 1 != 0 and not e.wounded:
		_wound(e)
	e.burn_t = 1.0 if flags & 2 != 0 else 0.0
	_drop(e)
	return e


## One step for the copies: glide, look right, and stand in the player's way.
func tick_remote(dt: float) -> void:
	_time += dt
	if _dead_count > 0:
		_compact()
	_view = game.cam.view_rect().grow(-24.0)
	var n := active.size()
	_sort_grid(n)
	var player := game.player
	var pr := player.radius
	var arena := game.arena
	var glide: float = dt * Config.NET_SNAPSHOT_RATE
	var squash: float = Config.HIT_SQUASH / Config.HIT_FLASH_TIME
	var drip: float = Config.WOUNDED_DRIP_RATE * dt
	var turn := minf(dt * 12.0, 1.0)
	var push_total := Vector2.ZERO
	for i in n:
		var e := active[i]
		if not e.alive:
			continue
		var flashing := e.flash_t > 0.0
		if flashing:
			e.flash_t -= dt
			if e.flash_t <= 0.0:
				e.texture = e.tex_normal
		# Glide to where the host last said it was (and a little beyond, so a
		# late message does not make it stutter).
		e.net_t = minf(e.net_t + glide, 1.25)
		var epos := e.net_from.lerp(e.net_to, e.net_t)
		e.face = lerp_angle(e.face, e.net_face, turn)
		e.phase += dt * 8.0
		if e.stride > 0.0 and e.spawn_t <= 0.0 and e.net_from.distance_squared_to(e.net_to) > 1.0:
			_stride(e, dt)

		# How it looks: rising out of the ground, warning, leaping, dazed, on fire.
		var size := e.base_scale
		var tint := Config.BURN_TINT if e.burn_t > 0.0 else Color.WHITE
		if e.spawn_t > 0.0:
			size *= 0.55
		elif e.state == B_WINDUP:
			e.state_t = maxf(e.state_t - dt, 0.0)
			e.phase += dt * 22.0
			if e.is_big:
				var blink := 0.5 + 0.5 * sin(_time * 40.0)
				tint = Color(1.0, 1.0 - blink * 0.6, 1.0 - blink * 0.6)
			else:
				_windup_look(e, clampf(1.0 - e.state_t / maxf(_warning_time(e), 0.01), 0.0, 1.0))
				size = e.scale.x
				tint = e.modulate
		elif e.state == B_CHARGE and not e.is_big:
			size *= 1.22
		elif e.state == B_RECOVER:
			tint = Color(0.72, 0.72, 0.8)
		if flashing and e.flash_t > 0.0:
			size *= 1.0 + squash * e.flash_t
		e.scale = Vector2(size, size)
		e.modulate = tint

		# It stands in the player's way (it does not budge: the host moves it).
		if player.alive:
			var tp := player.pos - epos
			var prr := e.radius + pr
			var tp2 := tp.length_squared()
			if tp2 < prr * prr:
				var tpd := sqrt(maxf(tp2, 0.0001))
				if e.is_big:
					player.pos = arena.resolve(epos + (tp / tpd) * prr, pr)
				else:
					push_total += (tp / tpd) * (prr - tpd)

		e.pos = epos
		e.position = epos
		e.rotation = e.face + sin(e.phase) * e.sway
		if e.wounded and randf() < drip:
			game.decals.blood_dot(epos + Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0)), randf_range(3.0, 6.5))
		if e.burn_t > 0.0 and randf() < dt * 7.0:
			game.fx.ember(epos, e.radius)
		if e.ai != 0 and _tip_owed[e.kind] and _view.has_point(epos) and game.fog.is_clear(epos):
			_tip(e)
	if push_total != Vector2.ZERO and player.alive:
		player.pos = arena.resolve(player.pos + push_total.limit_length(Config.PLAYER_MAX_PUSH_PER_FRAME), pr)
