class_name Player
extends Node2D
## The player character: movement, aiming, firing and its own drawing.
## Movement is instant (no acceleration) - that is deliberate, it feels sharp.

const DUAL_HAND_OFFSET := 7.5   # how far each gun sits from the middle when dual wielding (drawing only)

var game: Game
var pos := Vector2.ZERO
var radius: float = Config.PLAYER_RADIUS
var hp: float = Config.PLAYER_MAX_HP
var max_hp: float = Config.PLAYER_MAX_HP
var alive := true

var aim := Vector2.RIGHT
var move_input := Vector2.ZERO
var weapon_id: String = Config.STARTER_WEAPON
var weapon: Dictionary = Config.WEAPONS[Config.STARTER_WEAPON]
var weapon_time := 0.0          # seconds left on a crate weapon
var weapon_time_max := 0.0      # what it started with (for the HUD bar)
var dual := false               # holding one in each hand
var ammo := 0                   # shots left in the magazine
var mag_size := 0               # 0 = this weapon never reloads
var reloading := false
var wounded := false            # below Config.PLAYER_WOUNDED_AT health: bloodied, bandaged, dripping
var reload_progress := 0.0      # 0..1 while reloading (HUD ring + animation)
var fire_cd := 0.0
var invuln := 0.0               # seconds of safety left after being hit
var push_vel := Vector2.ZERO    # recoil shove

# Everything permanent (level, skill points, later gear) arrives through here.
var stats: PlayerStats
var wmods: Dictionary = {}      # the current weapon's own bonuses (see PlayerStats.weapon_mods)

# Visual state
var _flash := 0.0
var _gun_kick := 0.0
var _swing := 0.0               # melee swing animation, 1 -> 0
var _swing_side := 1.0
var _dual_side := 1.0           # which hand fired last
var _reload_left := 0.0
var _reload_total := 1.0
var _reload_stage := 0          # which reload sound has played so far
var _walk_phase := 0.0
var _time := 0.0
var _gun_tex: Texture2D
var _gun_size := Vector2.ZERO


func _ready() -> void:
	refresh_stats(true)
	_set_weapon(Config.STARTER_WEAPON)
	hold_fire(0.3)


## Re-read the character's stats (at run start, and when levelling up mid-run).
func refresh_stats(full_heal: bool = false) -> void:
	var old_max := max_hp
	stats = PlayerStats.current()
	max_hp = stats.max_hp
	if full_heal:
		hp = max_hp
	else:
		hp = minf(hp + maxf(max_hp - old_max, 0.0), max_hp)
	wmods = PlayerStats.weapon_mods(weapon_id)


func place(at: Vector2) -> void:
	pos = at
	position = at


# ----------------------------------------------------------------------------
#  Per-frame update (called by Game)
# ----------------------------------------------------------------------------
func tick(delta: float) -> void:
	_time += delta
	if not alive:
		return

	# --- move: instant, no acceleration ---
	move_input = GameInput.get_move()
	var speed: float = Config.PLAYER_SPEED * stats.speed_mult * float(weapon["move_mult"])
	if game.rage_active:
		speed *= Config.RAGE_SPEED_MULT
	pos += move_input * speed * delta + push_vel * delta
	push_vel -= push_vel * minf(Config.RECOIL_PUSH_DAMPING * delta, 1.0)
	pos = game.arena.resolve(pos, radius)
	position = pos
	if move_input != Vector2.ZERO:
		_walk_phase += delta * 14.0

	# Badly hurt: the sprite changes and you leave drops of your own blood.
	wounded = hp < max_hp * Config.PLAYER_WOUNDED_AT
	if wounded and randf() < Config.PLAYER_DRIP_RATE * delta:
		game.decals.blood_dot(pos + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)), randf_range(3.0, 6.0))

	# --- aim ---
	aim = GameInput.get_aim_direction(self)
	rotation = aim.angle()

	# --- timers ---
	invuln = maxf(invuln - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	_gun_kick = lerpf(_gun_kick, 0.0, minf(delta * 22.0, 1.0))
	_swing = maxf(_swing - delta / 0.16, 0.0)
	if weapon_time > 0.0:
		weapon_time -= delta
		if weapon_time <= 0.0:
			_set_weapon(Config.STARTER_WEAPON)
			Sfx.play("weapon_expire")

	# --- reload and fire ---
	if reloading:
		_tick_reload(delta)
	fire_cd -= delta
	if GameInput.is_firing() and fire_cd <= 0.0:
		if mag_size > 0 and ammo <= 0:
			start_reload()
		elif reloading:
			# Loading shells one by one can be cut short by firing; a magazine swap cannot.
			if String(weapon["reload_kind"]) == "shell" and ammo > 0:
				reloading = false
				_fire()
		else:
			_fire()

	queue_redraw()


func _fire() -> void:
	var w := weapon
	var rate: float = stats.fire_rate_mult * float(wmods["fire_rate"])
	var dmg: float = float(w["damage"]) * stats.damage_mult * float(wmods["damage"])
	var knock: float = w["knockback"]
	var steady: float = wmods["steady"]      # 1 = normal spread/recoil, lower = tighter
	var interval: float = w["interval"]
	var spread_mult := steady
	var recoil_mult := steady
	if dual:
		# One in each hand: nearly twice the rate of fire, but wilder.
		interval *= Config.DUAL_INTERVAL_MULT
		spread_mult *= Config.DUAL_SPREAD_MULT
		recoil_mult *= Config.DUAL_RECOIL_MULT
	if game.rage_active:
		rate *= Config.RAGE_FIRE_RATE_MULT
		dmg *= Config.RAGE_DAMAGE_MULT
		knock *= Config.RAGE_KNOCKBACK_MULT
	if fire_cd < -0.05:
		fire_cd = 0.0
	fire_cd += interval / rate

	# Mild aim assist: bend the shot toward a zombie that is nearly lined up.
	var sticks := GameInput.using_sticks()
	var dir := game.enemies.assist_aim(pos, aim,
			Config.AIM_ASSIST_CONE_DEG_GAMEPAD if sticks else Config.AIM_ASSIST_CONE_DEG_MOUSE,
			Config.AIM_ASSIST_STRENGTH_GAMEPAD if sticks else Config.AIM_ASSIST_STRENGTH_MOUSE,
			Config.AIM_ASSIST_RANGE)

	# Dual wielding alternates hands; each shot leaves from that hand's gun.
	var hand := Vector2.ZERO
	if dual:
		_dual_side = -_dual_side
		hand = Vector2(-dir.y, dir.x) * (DUAL_HAND_OFFSET * _dual_side)

	var kind := String(w["kind"])
	if kind == "melee":
		_melee(w, dir, dmg, knock)
	else:
		var pellets: int = w["pellets"]
		var spread := deg_to_rad(float(w["spread_deg"])) * spread_mult
		var from := pos + dir * (radius + 2.0) + hand
		for k in pellets:
			var crit := randf() < stats.crit_chance
			game.projectiles.spawn(from, dir.rotated(randf_range(-0.5, 0.5) * spread), w, weapon_id,
					dmg * (Config.CRIT_DAMAGE_MULT if crit else 1.0),
					knock * (Config.CRIT_KNOCKBACK_MULT if crit else 1.0), crit)
		var muzzle := pos + dir * float(w["muzzle_dist"]) + hand
		if kind == "flame":
			game.fx.light(muzzle, 110.0, 0.07, Color(1.0, 0.6, 0.2, 0.45))
		else:
			game.fx.muzzle_flash(muzzle, dir, float(w["flash_size"]), w["tracer_color"])
		var casing_kind := String(w["casing"])
		if casing_kind != "":
			game.fx.casing(pos + dir * 12.0 + hand, dir, casing_kind)

	# Feel: recoil, camera jolt, shake, sound. All numbers come from Config.WEAPONS.
	_gun_kick = float(w["recoil_gun"])
	push_vel -= dir * (float(w["recoil_push"]) * recoil_mult)
	game.shake(float(w["shake"]))
	game.cam.kick(-dir, float(w["kick"]) * recoil_mult)
	game.hud.fired(float(w["recoil_gun"]))
	Sfx.play(String(w["sound"]))

	# Magazine: when the last round is gone the reload starts by itself.
	if mag_size > 0:
		ammo -= 1
		if ammo <= 0:
			start_reload()


# ----------------------------------------------------------------------------
#  Reloading
# ----------------------------------------------------------------------------
## Begin a reload (R / gamepad X, or automatically when the magazine is empty).
func start_reload() -> void:
	if not alive or mag_size <= 0 or reloading or ammo >= mag_size:
		return
	var w := weapon
	reloading = true
	reload_progress = 0.0
	_reload_stage = 0
	_reload_total = float(w["reload_time"]) / _reload_speed()
	if String(w["reload_kind"]) == "shell":
		_reload_left = _reload_total + Config.SHELL_FIRST_DELAY
		return
	_reload_left = _reload_total
	Sfx.play_pitched(String(w.get("reload_start", "mag_out")), float(w["reload_pitch"]))
	# The empty magazine falls and stays on the ground for the rest of the run.
	var debris := String(w["mag_debris"])
	if debris != "":
		var side := Vector2(-aim.y, aim.x)
		if dual:
			game.fx.mag_drop(pos + aim * 10.0 + side * DUAL_HAND_OFFSET, aim, debris)
			game.fx.mag_drop(pos + aim * 10.0 - side * DUAL_HAND_OFFSET, aim, debris)
		else:
			game.fx.mag_drop(pos + aim * 12.0, aim, debris)


## Reloads get faster with the DEXTERITY passive and the weapon's own RELOAD SPEED upgrade.
func _reload_speed() -> float:
	var speed: float = stats.fire_rate_mult * float(wmods["reload"])
	if game.rage_active:
		speed *= Config.RELOAD_RAGE_MULT
	return speed


func _tick_reload(delta: float) -> void:
	var w := weapon
	var pitch: float = w["reload_pitch"]
	_reload_left -= delta
	if String(w["reload_kind"]) == "shell":
		# One shell at a time; the pump is racked after the last one.
		reload_progress = float(ammo) / float(mag_size)
		if _reload_left <= 0.0:
			ammo += 1
			_gun_kick = 3.0
			Sfx.play_pitched("shell_in", pitch * randf_range(0.95, 1.05))
			if ammo >= mag_size:
				reloading = false
				_gun_kick = 7.0
				Sfx.play_pitched("rack", pitch * 0.85)
			else:
				_reload_left = float(w["reload_time"]) / _reload_speed()
		return
	# Magazine swap: out (at the start), in, rack - then it is ready.
	reload_progress = clampf(1.0 - _reload_left / _reload_total, 0.0, 1.0)
	if _reload_stage == 0 and reload_progress >= Config.RELOAD_MAG_IN_AT:
		_reload_stage = 1
		_gun_kick = 3.0
		Sfx.play_pitched(String(w.get("reload_mid", "mag_in")), pitch)
	if _reload_stage == 1 and reload_progress >= Config.RELOAD_RACK_AT:
		_reload_stage = 2
		_gun_kick = 7.0
		Sfx.play_pitched(String(w.get("reload_end", "rack")), pitch)
	if _reload_left <= 0.0:
		ammo = mag_size
		reloading = false


## Top the magazine up instantly (used when rage is activated).
func refill_ammo() -> void:
	ammo = mag_size
	reloading = false


## Melee: hits every zombie inside the arc in front of the player. The
## sledgehammer swings (slow, huge); the chainsaw is held out and bites
## many times a second.
func _melee(w: Dictionary, dir: Vector2, dmg: float, knock: float) -> void:
	var swings: bool = w["swing"]
	if swings:
		_swing = 1.0
		_swing_side = -_swing_side
	var reach: float = w["range"]
	var cos_half := cos(deg_to_rad(float(w["arc_deg"])) * 0.5)
	var extra_blood: int = w["hit_blood"]
	var hits := 0
	for e: Enemy in game.enemies.in_radius(pos, reach):
		var to := e.pos - pos
		var d := to.length()
		var n := to / maxf(d, 0.001)
		if n.dot(dir) >= cos_half or d < radius + e.radius + 4.0:
			var crit := randf() < stats.crit_chance
			var push := (n * 0.7 + dir * 0.3).normalized()
			if extra_blood > 0:
				game.fx.blood_spray(e.pos, push, extra_blood, 1.3)
			game.enemies.damage(e, dmg * (Config.CRIT_DAMAGE_MULT if crit else 1.0), push,
					knock * (Config.CRIT_KNOCKBACK_MULT if crit else 1.0), float(w["stagger"]), 0.0, weapon_id, crit)
			hits += 1
	if swings:
		game.fx.swing_arc(pos, dir, float(w["arc_deg"]), reach, _swing_side)
	if hits > 0:
		game.shake(float(w["shake_hit"]))
		game.hitstop(float(w["hitstop_hit"]), true)
		Sfx.play(String(w["hit_sound"]))


# ----------------------------------------------------------------------------
#  Weapons, health
# ----------------------------------------------------------------------------
## Equip a weapon from a crate; it lasts for the weapon's "duration".
## DUAL WIELDING: picking up the weapon you are already holding (or a pistol
## crate, since you always carry a pistol) puts one in each hand - if that
## weapon allows it ("dual" in Config.WEAPONS).
func give_weapon(id: String) -> void:
	var cfg: Dictionary = Config.WEAPONS[id]
	var make_dual: bool = bool(cfg["dual"]) and (id == weapon_id or id == Config.STARTER_WEAPON)
	_set_weapon(id)
	dual = make_dual
	mag_size = int(cfg["mag"]) * (Config.DUAL_MAG_MULT if dual else 1)
	ammo = mag_size
	var duration: float = float(cfg["duration"]) * float(wmods["duration"])
	if id == Config.STARTER_WEAPON:
		duration = Config.DUAL_PISTOL_DURATION
	weapon_time = duration
	weapon_time_max = duration
	fire_cd = minf(fire_cd, 0.1)


## Would picking up this weapon right now give one in each hand?
func would_dual(id: String) -> bool:
	return bool(Config.WEAPONS[id]["dual"]) and (id == weapon_id or id == Config.STARTER_WEAPON)


## The weapon's name as shown on the HUD ("DUAL SHOTGUN", "DUAL PISTOLS").
func weapon_label() -> String:
	var weapon_name := String(weapon["name"])
	if not dual:
		return weapon_name
	return "DUAL PISTOLS" if weapon_id == Config.STARTER_WEAPON else "DUAL " + weapon_name


func _set_weapon(id: String) -> void:
	weapon_id = id
	weapon = Config.WEAPONS[id]
	weapon_time = 0.0
	weapon_time_max = 0.0
	dual = false
	mag_size = int(weapon["mag"])
	ammo = mag_size
	reloading = false
	wmods = PlayerStats.weapon_mods(id)
	_gun_tex = Art.t("gun_" + id)
	_gun_size = Art.size_of("gun_" + id)


## Block shooting briefly (so the click on PLAY / RESUME doesn't fire a shot).
func hold_fire(seconds: float) -> void:
	fire_cd = maxf(fire_cd, seconds)


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)


func muzzle_position() -> Vector2:
	return pos + aim * float(weapon["muzzle_dist"])


func hurt_flash() -> void:
	_flash = 0.12


# ----------------------------------------------------------------------------
#  Drawing (the node is rotated to face the aim direction, so +X is "forward")
# ----------------------------------------------------------------------------
func _draw() -> void:
	if not alive:
		return
	var alpha := 1.0
	if invuln > 0.0 and fmod(_time, 0.12) < 0.06:
		alpha = 0.45

	if game.rage_active:
		var pulse := 2.4 + sin(_time * 18.0) * 0.25
		Art.draw(self, "glow", Vector2.ZERO, pulse, Color(1.0, 0.25, 0.1, 0.55))

	# Body, with a small squash while walking.
	var bob := 1.0 + sin(_walk_phase) * 0.035
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, bob))
	var body := "player_flash" if _flash > 0.0 else ("player_hurt" if wounded else "player")
	var tint := Color(1.0, 0.75, 0.7, alpha) if game.rage_active else Color(1, 1, 1, alpha)
	Art.draw(self, body, Vector2.ZERO, 1.0, tint)

	# Reload animation: the gun is pulled in and tipped over while the magazine
	# is swapped, then snaps back out (the snap is the _gun_kick on the rack).
	var reload_tilt := 0.0
	var reload_pull := 0.0
	if reloading:
		if String(weapon["reload_kind"]) == "shell":
			reload_tilt = 0.34
			reload_pull = 2.0
		else:
			var ease_in_out := clampf(minf(reload_progress / 0.15, (1.0 - reload_progress) / 0.15), 0.0, 1.0)
			reload_tilt = 0.8 * ease_in_out
			reload_pull = 5.0 * ease_in_out

	# Weapon in hand.
	var gun_tint := Color(1, 1, 1, alpha)
	var is_melee := String(weapon["kind"]) == "melee"
	if is_melee and bool(weapon["swing"]):
		# Rest on the shoulder, sweep across when swinging.
		var rest := -0.9 * _swing_side
		var sweep := lerpf(1.4, -1.4, 1.0 - _swing) * _swing_side
		var angle := sweep if _swing > 0.0 else rest
		draw_set_transform(Vector2.ZERO, angle, Vector2.ONE)
		draw_texture_rect(_gun_tex, Rect2(Vector2(8.0, -_gun_size.y * 0.5), _gun_size), false, gun_tint)
	elif dual:
		# One in each hand; only the one that just fired kicks back.
		for side: float in [-1.0, 1.0]:
			var kick := _gun_kick if (side == _dual_side or reloading) else 0.0
			draw_set_transform(Vector2(7.0 - kick - reload_pull, DUAL_HAND_OFFSET * side), reload_tilt * side, Vector2.ONE)
			draw_texture_rect(_gun_tex, Rect2(Vector2(0.0, -_gun_size.y * 0.5), _gun_size), false, gun_tint)
	else:
		# A running chainsaw shudders in the hands.
		var shudder := Vector2(0.0, sin(_time * 95.0) * 0.9) if is_melee else Vector2.ZERO
		draw_set_transform(Vector2(7.0 - _gun_kick - reload_pull, 0.0) + shudder, reload_tilt, Vector2.ONE)
		draw_texture_rect(_gun_tex, Rect2(Vector2(0.0, -_gun_size.y * 0.5), _gun_size), false, gun_tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
