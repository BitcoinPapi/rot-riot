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

var aim := Vector2.RIGHT
var move_input := Vector2.ZERO
var weapon_id: String = Config.STARTER_WEAPON
var weapon: Dictionary = Config.WEAPONS[Config.STARTER_WEAPON]
var weapon_time := 0.0          # seconds left on a crate weapon
var fire_cd := 0.0
var invuln := 0.0               # seconds of safety left after being hit
var push_vel := Vector2.ZERO    # recoil shove

# Permanent upgrades bought in the shop (read once when the run starts).
var up_damage := 1.0
var up_fire_rate := 1.0
var up_speed := 1.0

# Visual state
var _flash := 0.0
var _gun_kick := 0.0
var _swing := 0.0               # melee swing animation, 1 -> 0
var _swing_side := 1.0
var _walk_phase := 0.0
var _time := 0.0
var _gun_tex: Texture2D
var _gun_size := Vector2.ZERO


func _ready() -> void:
	up_damage = 1.0 + SaveData.upgrade_bonus("damage")
	up_fire_rate = 1.0 + SaveData.upgrade_bonus("fire_rate")
	up_speed = 1.0 + SaveData.upgrade_bonus("move_speed")
	max_hp = Config.PLAYER_MAX_HP + SaveData.upgrade_bonus("max_health")
	hp = max_hp
	_set_weapon(Config.STARTER_WEAPON)
	hold_fire(0.3)


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
	var speed: float = Config.PLAYER_SPEED * up_speed * float(weapon["move_mult"])
	if game.rage_active:
		speed *= Config.RAGE_SPEED_MULT
	pos += move_input * speed * delta + push_vel * delta
	push_vel -= push_vel * minf(Config.RECOIL_PUSH_DAMPING * delta, 1.0)
	pos = game.arena.resolve(pos, radius)
	position = pos
	if move_input != Vector2.ZERO:
		_walk_phase += delta * 14.0

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

	# --- fire ---
	fire_cd -= delta
	if GameInput.is_firing() and fire_cd <= 0.0:
		_fire()

	queue_redraw()


func _fire() -> void:
	var w := weapon
	var rate := up_fire_rate
	var dmg: float = float(w["damage"]) * up_damage
	var knock: float = w["knockback"]
	if game.rage_active:
		rate *= Config.RAGE_FIRE_RATE_MULT
		dmg *= Config.RAGE_DAMAGE_MULT
		knock *= Config.RAGE_KNOCKBACK_MULT
	if fire_cd < -0.05:
		fire_cd = 0.0
	fire_cd += float(w["interval"]) / rate

	# Mild aim assist: bend the shot toward a zombie that is nearly lined up.
	var sticks := GameInput.using_sticks()
	var dir := game.enemies.assist_aim(pos, aim,
			Config.AIM_ASSIST_CONE_DEG_GAMEPAD if sticks else Config.AIM_ASSIST_CONE_DEG_MOUSE,
			Config.AIM_ASSIST_STRENGTH_GAMEPAD if sticks else Config.AIM_ASSIST_STRENGTH_MOUSE,
			Config.AIM_ASSIST_RANGE)

	if String(w["kind"]) == "melee":
		_melee(w, dir, dmg, knock)
	else:
		var pellets: int = w["pellets"]
		var spread := deg_to_rad(float(w["spread_deg"]))
		var from := pos + dir * (radius + 2.0)
		for k in pellets:
			game.projectiles.spawn(from, dir.rotated(randf_range(-0.5, 0.5) * spread), w, dmg, knock)
		var muzzle := pos + dir * float(w["muzzle_dist"])
		game.fx.muzzle_flash(muzzle, dir, float(w["flash_size"]), w["tracer_color"])
		var casing_kind := String(w["casing"])
		if casing_kind != "":
			game.fx.casing(pos + dir * 12.0, dir, casing_kind)

	# Feel: recoil, camera jolt, shake, sound. All numbers come from Config.WEAPONS.
	_gun_kick = float(w["recoil_gun"])
	push_vel -= dir * float(w["recoil_push"])
	game.shake(float(w["shake"]))
	game.cam.kick(-dir, float(w["kick"]))
	game.hud.fired(float(w["recoil_gun"]))
	Sfx.play(String(w["sound"]))


## Melee swing: hits every zombie inside the arc in front of the player.
func _melee(w: Dictionary, dir: Vector2, dmg: float, knock: float) -> void:
	_swing = 1.0
	_swing_side = -_swing_side
	var reach: float = w["range"]
	var cos_half := cos(deg_to_rad(float(w["arc_deg"])) * 0.5)
	var hits := 0
	for e: Enemy in game.enemies.in_radius(pos, reach):
		var to := e.pos - pos
		var d := to.length()
		var n := to / maxf(d, 0.001)
		if n.dot(dir) >= cos_half or d < radius + e.radius + 4.0:
			game.enemies.damage(e, dmg, (n * 0.7 + dir * 0.3).normalized(), knock, float(w["stagger"]), 0.0)
			hits += 1
	game.fx.swing_arc(pos, dir, float(w["arc_deg"]), reach, _swing_side)
	if hits > 0:
		game.shake(float(w["shake_hit"]))
		game.hitstop(float(w["hitstop_hit"]), true)
		Sfx.play("sledge_hit")


# ----------------------------------------------------------------------------
#  Weapons, health
# ----------------------------------------------------------------------------
## Equip a weapon from a crate. It lasts for the weapon's "duration".
func give_weapon(id: String) -> void:
	_set_weapon(id)
	weapon_time = float(weapon["duration"])
	fire_cd = minf(fire_cd, 0.1)


func _set_weapon(id: String) -> void:
	weapon_id = id
	weapon = Config.WEAPONS[id]
	weapon_time = 0.0
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
	var body := "player_flash" if _flash > 0.0 else "player"
	var tint := Color(1.0, 0.75, 0.7, alpha) if game.rage_active else Color(1, 1, 1, alpha)
	Art.draw(self, body, Vector2.ZERO, 1.0, tint)

	# Weapon in hand.
	if String(weapon["kind"]) == "melee":
		# Rest on the shoulder, sweep across when swinging.
		var rest := -0.9 * _swing_side
		var sweep := lerpf(1.4, -1.4, 1.0 - _swing) * _swing_side
		var angle := sweep if _swing > 0.0 else rest
		draw_set_transform(Vector2.ZERO, angle, Vector2.ONE)
		draw_texture_rect(_gun_tex, Rect2(Vector2(8.0, -_gun_size.y * 0.5), _gun_size), false, Color(1, 1, 1, alpha))
	else:
		draw_set_transform(Vector2(7.0 - _gun_kick, 0.0), 0.0, Vector2.ONE)
		draw_texture_rect(_gun_tex, Rect2(Vector2(0.0, -_gun_size.y * 0.5), _gun_size), false, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
