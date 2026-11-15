class_name Player
extends Node2D
## The player character: movement, aiming, firing and its own drawing.
## Movement is instant (no acceleration) - that is deliberate, it feels sharp.


var game: Game
var pos := Vector2.ZERO
var radius: float = Config.PLAYER_RADIUS
var hp: float = Config.PLAYER_MAX_HP
var max_hp: float = Config.PLAYER_MAX_HP
var alive := true
var down := false               # co-op: out of health, lying down until the partner picks you up

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
var hurt_boost := 0.0           # seconds of extra speed left after being hit (BREAKAWAY keystone)
var second_wind_used := false   # the SECOND WIND keystone works once per run
var push_vel := Vector2.ZERO    # recoil shove

# Everything permanent (level, skill points, later gear) arrives through here.
var stats: PlayerStats
var wmods: Dictionary = {}      # the current weapon's own bonuses (see PlayerStats.weapon_mods)

# Visual state
var _flash := 0.0
var _gun_kick := 0.0
var _swing := 0.0               # melee swing animation, 1 -> 0
var _swing_side := 1.0
var _saw_angle := 0.0           # a sweeping blade (the chainsaw): where it is, in radians beside the aim...
var _saw_way := 1.0             # ...which way it is going...
var _saw_bite := 0.0            # ...and for how long it is still held back by the zombie it is cutting
var _dual_side := 1.0           # which hand fired last
var _reload_left := 0.0
var _reload_total := 1.0
var _reload_stage := 0          # which reload sound has played so far
var _walk_phase := 0.0
# Movement in pictures (when the hero has strips, see Art.anim_of; {} = one still picture)
var _death_frames: Array = []   # the frames he goes down in
var _anim_t := 0.0              # how far through walking / standing (goes round and round)
var _anim_hit := 0.0            # seconds left of the flinch
var _anim_fire := 0.0           # seconds left of the shooting movement
var _dying := false             # showing his death (the run is lost)
var _death_t := 0.0
var _time := 0.0
var _gun_tex: Texture2D
var _gun_size := Vector2.ZERO


func _ready() -> void:
	refresh_stats(true)
	_set_weapon(Config.STARTER_WEAPON)
	hold_fire(0.3)


## Re-read the character's stats (at run start, when levelling up mid-run,
## and when a run perk is chosen).
func refresh_stats(full_heal: bool = false) -> void:
	var old_max := max_hp
	stats = PlayerStats.current(game.perks)
	max_hp = stats.max_hp
	if full_heal:
		hp = max_hp
	else:
		hp = minf(hp + maxf(max_hp - old_max, 0.0), max_hp)
	wmods = PlayerStats.weapon_mods(weapon_id, game.perks)
	# A run perk can change the weapon in hand (more rounds, piercing): the
	# extra rounds are in the magazine at once.
	weapon = PlayerStats.weapon_def(weapon_id, game.perks)
	var size_now := int(weapon["mag"]) * (Config.DUAL_MAG_MULT if dual else 1)
	if size_now != mag_size:
		ammo = clampi(ammo + size_now - mag_size, 0, size_now)
		mag_size = size_now


func place(at: Vector2) -> void:
	pos = at
	position = at


# ----------------------------------------------------------------------------
#  Per-frame update (called by Game)
# ----------------------------------------------------------------------------
func tick(delta: float) -> void:
	_time += delta
	if not alive:
		if _dying:
			_death_t += delta
		if down or _dying:
			queue_redraw()
		return

	# --- move: instant, no acceleration ---
	move_input = GameInput.get_move()
	var speed: float = Config.PLAYER_SPEED * stats.speed_mult * float(weapon["move_mult"])
	if hurt_boost > 0.0:
		hurt_boost -= delta
		speed *= 1.0 + stats.hurt_speed
	pos += move_input * speed * delta + push_vel * delta
	push_vel -= push_vel * minf(Config.RECOIL_PUSH_DAMPING * delta, 1.0)
	pos = game.arena.resolve(pos, radius)
	position = pos
	if move_input != Vector2.ZERO:
		_walk_phase += delta * 14.0
		_anim_t += speed * delta / Config.ANIM_HERO_WALK_CYCLE
	else:
		_anim_t += delta / Config.ANIM_IDLE_TIME
	_anim_hit = maxf(_anim_hit - delta, 0.0)
	_anim_fire = maxf(_anim_fire - delta, 0.0)

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
	_tick_sweep(delta)
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
	if stats.combo_fire_rate > 0.0 and game.combo >= stats.combo_fire_at:
		rate *= 1.0 + stats.combo_fire_rate
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
	if fire_cd < -0.05:
		fire_cd = 0.0
	fire_cd += interval / rate

	# Mild aim assist: bend the shot toward a zombie that is nearly lined up.
	var sticks := GameInput.using_sticks()
	var dir := game.enemies.assist_aim(pos, aim,
			Config.AIM_ASSIST_CONE_DEG_GAMEPAD if sticks else Config.AIM_ASSIST_CONE_DEG_MOUSE,
			Config.AIM_ASSIST_STRENGTH_GAMEPAD if sticks else Config.AIM_ASSIST_STRENGTH_MOUSE,
			Config.AIM_ASSIST_RANGE)

	# Each shot leaves from the gun in his hands (dual wielding alternates hands). A gun
	# held beside the aim line shoots slightly inward: its shots cross that line where
	# the player aims.
	if dual:
		_dual_side = -_dual_side
	var held: Vector2 = gun_spot()
	var hand := Vector2(-dir.y, dir.x) * held.y
	var ahead: float = held.x - Config.HERO_GUN_REAR     # (how much further out than where "muzzle_dist" was measured)
	var line := shot_line(dir)
	var shot_dir: Vector2 = line[1]

	var kind := String(w["kind"])
	if kind == "melee":
		_melee(w, dir, dmg, knock)
	else:
		var pellets: int = w["pellets"]
		var spread := deg_to_rad(float(w["spread_deg"])) * spread_mult
		var from: Vector2 = line[0]
		for k in pellets:
			var crit := randf() < stats.crit_chance
			game.projectiles.spawn(from, shot_dir.rotated(randf_range(-0.5, 0.5) * spread), w, weapon_id,
					dmg * (stats.crit_mult if crit else 1.0),
					knock * (Config.CRIT_KNOCKBACK_MULT if crit else 1.0), crit)
		var muzzle := pos + dir * (float(w["muzzle_dist"]) + ahead) + hand
		if kind == "flame":
			game.fx.light(muzzle, 110.0, 0.07, Color(1.0, 0.6, 0.2, 0.45))
		else:
			game.fx.muzzle_flash(muzzle, shot_dir, float(w["flash_size"]), w["tracer_color"])
		var casing_kind := String(w["casing"])
		if casing_kind != "":
			game.fx.casing(pos + dir * (12.0 + ahead) + hand, dir, casing_kind)

	# Feel: recoil, camera jolt, shake, sound. All numbers come from Config.WEAPONS.
	_gun_kick = float(w["recoil_gun"])
	if _anim_fire <= 0.0:
		_anim_fire = Config.ANIM_FIRE_TIME
	push_vel -= dir * (float(w["recoil_push"]) * recoil_mult)
	game.shake(float(w["shake"]))
	game.cam.kick(-dir, float(w["kick"]) * recoil_mult)
	game.hud.fired(float(w["recoil_gun"]))
	Sfx.play(String(w["sound"]))
	if game.coop != null:
		game.coop.send_fire(weapon_id, pos + hand + dir * ahead, shot_dir, dual)      # so the other player sees it

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
		for held: Vector2 in Art.hero_guns(dual, weapon):
			game.fx.mag_drop(pos + aim * (5.0 + held.x) + side * held.y, aim, debris)


## Reloads get faster with the DEXTERITY passive and the weapon's own RELOAD SPEED upgrade.
func _reload_speed() -> float:
	return stats.fire_rate_mult * float(wmods["reload"])


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


## Top the magazine up instantly.
func refill_ammo() -> void:
	ammo = mag_size
	reloading = false


## A sweeping blade (the chainsaw, "sweep" in its config) goes from side to side across
## its arc while the trigger is held - slowly while it is cutting through a zombie - and
## comes back to the middle when the trigger is let go.
func _tick_sweep(delta: float) -> void:
	if not bool(weapon.get("sweep", false)):
		_saw_angle = 0.0
		return
	var half := deg_to_rad(float(weapon["arc_deg"])) * 0.5
	var speed := deg_to_rad(float(weapon["sweep_speed"]))
	_saw_bite = maxf(_saw_bite - delta, 0.0)
	if GameInput.is_firing() and alive:
		_saw_angle += _saw_way * speed * delta * (float(weapon["sweep_slow"]) if _saw_bite > 0.0 else 1.0)
		if absf(_saw_angle) >= half:
			_saw_angle = clampf(_saw_angle, -half, half)
			_saw_way = -_saw_way
	else:
		_saw_angle = move_toward(_saw_angle, 0.0, speed * delta)


## Melee: hits every zombie under the blade. The chainsaw's blade sweeps from side to
## side (see _tick_sweep) and bites many times a second whatever it is passing over.
## (A weapon with "swing": true would strike once across its whole arc instead; none
## does since the sledgehammer was taken out of the game.)
func _melee(w: Dictionary, dir: Vector2, dmg: float, knock: float) -> void:
	var swings: bool = w["swing"]
	var sweeps := bool(w.get("sweep", false))
	if swings:
		_swing = 1.0
		_swing_side = -_swing_side
	if sweeps:
		dir = dir.rotated(_saw_angle)
	var reach: float = w["range"]
	var cos_half := cos(deg_to_rad(float(w["blade_deg"]) if sweeps else float(w["arc_deg"])) * 0.5)
	var extra_blood: int = w["hit_blood"]
	var hits := 0
	for e: Enemy in game.enemies.in_radius(pos, reach):
		var to := e.pos - pos
		var d := to.length()
		var n := to / maxf(d, 0.001)
		# (A zombie right against you is hit whichever way a blade without a sweep points;
		# a sweeping blade has to come round to it.)
		if n.dot(dir) >= cos_half or (not sweeps and d < radius + e.radius + 4.0):
			var crit := randf() < stats.crit_chance
			var push := (n * 0.7 + dir * 0.3).normalized()
			if extra_blood > 0:
				game.fx.blood_spray(e.pos, push, extra_blood, 1.3)
			game.enemies.damage(e, dmg * (stats.crit_mult if crit else 1.0), push,
					knock * (Config.CRIT_KNOCKBACK_MULT if crit else 1.0), float(w["stagger"]), 0.0, weapon_id, crit)
			hits += 1
	if swings:
		game.fx.swing_arc(pos, dir, float(w["arc_deg"]), reach, _swing_side)
	if hits > 0:
		if sweeps:
			_saw_bite = float(w["sweep_hold"])
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
	mag_size = int(weapon["mag"]) * (Config.DUAL_MAG_MULT if dual else 1)
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
	weapon = PlayerStats.weapon_def(id, game.perks)     # the weapon's numbers, with its perks
	weapon_time = 0.0
	weapon_time_max = 0.0
	dual = false
	mag_size = int(weapon["mag"])
	ammo = mag_size
	reloading = false
	wmods = PlayerStats.weapon_mods(id, game.perks)
	_gun_tex = Art.t("gun_" + id)
	_gun_size = Art.size_of("gun_" + id)


## Block shooting briefly (so the click on PLAY / RESUME doesn't fire a shot).
func hold_fire(seconds: float) -> void:
	fire_cd = maxf(fire_cd, seconds)


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)


func muzzle_position() -> Vector2:
	var held := gun_spot()
	return pos + aim * (float(weapon["muzzle_dist"]) + held.x - Config.HERO_GUN_REAR) + Vector2(-aim.y, aim.x) * held.y


## A shot from the gun in his hands, for the aim `dir`: [where it starts, which way it
## flies]. It starts beside the aim line, where the gun is, and flies slightly inward,
## so it crosses that line where the player aims (Config: HERO_AIM_MEET...).
func shot_line(dir: Vector2) -> Array:
	var beside := clampf(gun_spot().y, -Config.HERO_SHOT_SIDE_MAX, Config.HERO_SHOT_SIDE_MAX)
	var from := pos + dir * (radius + 2.0) + Vector2(-dir.y, dir.x) * beside
	if beside == 0.0:
		return [from, dir]
	var meet := clampf(GameInput.get_aim_reach(self, Config.HERO_AIM_MEET), Config.HERO_AIM_MEET_MIN, Config.HERO_AIM_MEET_MAX)
	return [from, (pos + dir * meet - from).normalized()]


## Where the rear end of the gun that fires next (or fired last) sits in his hands: game
## px from the middle of his sprite, x ahead, y to his right (Config: THE HERO'S HANDS).
func gun_spot() -> Vector2:
	var spots := Art.hero_guns(dual, weapon)
	return spots[1 if dual and _dual_side > 0.0 else 0]


## His picture's name for what he holds: "player", or "player_twin" with a gun in each hand.
func body_sprite() -> String:
	return "player" + Art.hero_pose(dual)


func hurt_flash() -> void:
	_flash = 0.12
	_anim_hit = Config.ANIM_HIT_TIME


## The run is lost: show him going down, if he has pictures for it. False = he has none
## (the game then simply takes him off the field, as it always did).
func die_look() -> bool:
	var anims := Art.anim_of(body_sprite())
	if not anims.has("death"):
		return false
	_death_frames = anims["death_hurt"]
	_dying = true
	_death_t = 0.0
	queue_redraw()
	return true


## The frame of his movement to show now (null = his one still picture).
func _body_frame() -> Texture2D:
	var anims := Art.anim_of(body_sprite())
	if anims.is_empty():
		return null
	var tail := "_hurt" if wounded else ""
	if _anim_hit > 0.0 and anims.has("hit"):
		return Art.frame_at(anims["hit" + tail], clampf(1.0 - _anim_hit / Config.ANIM_HIT_TIME, 0.0, 0.999))
	if _anim_fire > 0.0 and anims.has("attack"):
		return Art.frame_at(anims["attack" + tail], clampf(1.0 - _anim_fire / Config.ANIM_FIRE_TIME, 0.0, 0.999))
	if move_input != Vector2.ZERO and anims.has("walk"):
		return Art.frame_at(anims["walk" + tail], _anim_t)
	if anims.has("idle"):
		return Art.frame_at(anims["idle" + tail], _anim_t)
	return null


# ----------------------------------------------------------------------------
#  Drawing (the node is rotated to face the aim direction, so +X is "forward")
# ----------------------------------------------------------------------------
func _draw() -> void:
	if down:
		# Fallen: lying still. The ring fills while your partner stands beside you.
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		var reach: float = Config.COOP_REVIVE_RADIUS
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
		draw_arc(Vector2.ZERO, reach, 0.0, TAU, 48, Color(1.0, 0.3, 0.25, 0.3 + 0.3 * pulse), 3.0)
		var progress := game.coop.helped if game.coop != null else 0.0
		if progress > 0.0:
			draw_arc(Vector2.ZERO, reach, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, Color(0.5, 1.0, 0.55), 6.0)
		draw_set_transform(Vector2.ZERO, 1.3, Vector2(1.0, 0.86))
		Art.draw(self, "player_hurt", Vector2.ZERO, 1.0, Color(0.6, 0.5, 0.5))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if _dying:
		# Going down: his death frames once, then he lies where he fell.
		var falling: Array = _death_frames
		var fallen: Texture2D = falling[clampi(int(_death_t / Config.ANIM_DEATH_TIME * falling.size()), 0, falling.size() - 1)]
		var lying := Vector2(fallen.get_size()) / Art.PX
		var settle := clampf(_death_t / Config.ANIM_DEATH_TIME, 0.0, 1.0)
		draw_texture_rect(fallen, Rect2(-lying * 0.5, lying), false, Color.WHITE.lerp(Color(0.6, 0.5, 0.5), settle))
		return
	if not alive:
		return
	var alpha := 1.0
	if invuln > 0.0 and fmod(_time, 0.12) < 0.06:
		alpha = 0.45

	# Body: a frame of his movement, or his one picture with a small squash while walking.
	# (The painted hero's arms are part of his picture: with the swinging chainsaw his
	# whole body turns with the saw, so it stays in his hands.)
	var tint := Color(1, 1, 1, alpha)
	var is_melee := String(weapon["kind"]) == "melee"
	var sweeping := is_melee and bool(weapon.get("sweep", false))
	var body_turn := _saw_angle if sweeping and Art.hero_painted() else 0.0
	var moving := _body_frame() if _flash <= 0.0 else null
	if moving != null:
		var frame_size := Vector2(moving.get_size()) / Art.PX
		draw_set_transform(Vector2.ZERO, body_turn, Vector2.ONE)
		draw_texture_rect(moving, Rect2(-frame_size * 0.5, frame_size), false, tint)
	else:
		var bob := 1.0 + sin(_walk_phase) * 0.035
		draw_set_transform(Vector2.ZERO, body_turn, Vector2(1.0, bob))
		var body := body_sprite() + ("_flash" if _flash > 0.0 else ("_hurt" if wounded else ""))
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

	# Weapon in hand: at the spot(s) where his hands are (Config: THE HERO'S HANDS).
	var gun_tint := Color(1, 1, 1, alpha)
	var spots := Art.hero_guns(dual, weapon)
	if is_melee and bool(weapon["swing"]):
		# Rest on the shoulder, sweep across when swinging.
		var rest := -0.9 * _swing_side
		var sweep := lerpf(1.4, -1.4, 1.0 - _swing) * _swing_side
		var angle := sweep if _swing > 0.0 else rest
		draw_set_transform(Vector2.ZERO, angle, Vector2.ONE)
		draw_texture_rect(_gun_tex, Rect2(Vector2(8.0, -_gun_size.y * 0.5), _gun_size), false, gun_tint)
	elif dual:
		# One in each hand; only the one that just fired kicks back.
		for i in 2:
			var side := -1.0 if i == 0 else 1.0           # (his left hand, his right hand)
			var kick := _gun_kick if (side == _dual_side or reloading) else 0.0
			var fist: Vector2 = spots[i]
			draw_set_transform(Vector2(fist.x - kick - reload_pull, fist.y), reload_tilt * side, Vector2.ONE)
			draw_texture_rect(_gun_tex, Rect2(Vector2(0.0, -_gun_size.y * 0.5), _gun_size), false, gun_tint)
	else:
		# A running chainsaw shudders in the hands - and swings round him from side to side.
		var held: Vector2 = spots[0]
		var shudder := Vector2(0.0, sin(_time * 95.0) * 0.9) if is_melee else Vector2.ZERO
		if sweeping:
			draw_set_transform(Vector2.ZERO, _saw_angle, Vector2.ONE)
			draw_texture_rect(_gun_tex, Rect2(Vector2(held.x - _gun_kick, held.y - _gun_size.y * 0.5) + shudder, _gun_size), false, gun_tint)
		else:
			draw_set_transform(Vector2(held.x - _gun_kick - reload_pull, held.y) + shudder, reload_tilt, Vector2.ONE)
			draw_texture_rect(_gun_tex, Rect2(Vector2(0.0, -_gun_size.y * 0.5), _gun_size), false, gun_tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
