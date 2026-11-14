class_name Pickups
extends Node2D
## Things lying on the ground that the player walks over:
##   coins    - dropped by kills, fly to the player when close, spent in the shop
##   crates   - appear on a timer, give a weapon for a limited time
##   medkits  - rare drops that heal
## Coins are plain data in arrays (there can be hundreds); all of it is drawn
## by this one node.

class Crate:
	var pos := Vector2.ZERO
	var weapon := ""
	var life := 0.0
	var age := 0.0

class Medkit:
	var pos := Vector2.ZERO
	var life := 0.0
	var age := 0.0

var game: Game
var crates: Array[Crate] = []
var medkits: Array[Medkit] = []
var coin_count := 0

var _coin_pos := PackedVector2Array()
var _coin_vel := PackedVector2Array()
var _coin_life := PackedFloat32Array()
var _crate_timer: float = Config.CRATE_FIRST_DELAY
var _time := 0.0
var _coin_streak := 0
var _coin_streak_t := 0.0

var _coin_tex: Texture2D
var _crate_tex: Texture2D
var _medkit_tex: Texture2D
var _glow: Texture2D


func _ready() -> void:
	_coin_tex = Art.t("coin")
	_crate_tex = Art.t("crate")
	_medkit_tex = Art.t("medkit")
	_glow = Art.t("glow")
	var cap: int = Config.MAX_COINS_ON_FIELD
	_coin_pos.resize(cap)
	_coin_vel.resize(cap)
	_coin_life.resize(cap)


# ----------------------------------------------------------------------------
#  Spawning
# ----------------------------------------------------------------------------
func drop_from_enemy(e: Enemy) -> void:
	var c: Dictionary = Config.ENEMIES[e.kind]
	if randf() < float(c["coin_chance"]):
		spawn_coins(e.pos, randi_range(int(c["coins_min"]), int(c["coins_max"])))
	if randf() < float(c["medkit_chance"]) and medkits.size() < Config.MEDKIT_MAX_ON_FIELD:
		spawn_medkit(e.pos)


func spawn_coins(at: Vector2, count: int) -> void:
	for k in count:
		if coin_count >= _coin_pos.size():
			# Field is full: hand the coin over directly so nothing is lost.
			game.collect_coin(at, false)
			continue
		var i := coin_count
		coin_count += 1
		_coin_pos[i] = at
		_coin_vel[i] = Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0) * Config.COIN_SCATTER_SPEED
		_coin_life[i] = Config.COIN_LIFETIME


func spawn_crate(at: Vector2, weapon: String = "") -> void:
	var c := Crate.new()
	c.pos = game.arena.resolve(at, 20.0)
	c.weapon = weapon if weapon != "" else _pick_crate_weapon()
	c.life = Config.CRATE_LIFETIME
	crates.append(c)
	game.fx.dust(c.pos, 8)
	game.fx.ring(c.pos, 10.0, 90.0, 0.4, Color(1, 1, 1, 0.6))
	Sfx.play("crate_spawn")


func spawn_medkit(at: Vector2) -> void:
	var m := Medkit.new()
	m.pos = game.arena.resolve(at, 14.0)
	m.life = Config.MEDKIT_LIFETIME
	medkits.append(m)


func _pick_crate_weapon() -> String:
	# Avoid the weapon the player already holds and ones already on the field.
	var options: Array = []
	for id: String in Config.CRATE_WEAPONS:
		var taken := id == game.player.weapon_id
		for c: Crate in crates:
			if c.weapon == id:
				taken = true
		if not taken:
			options.append(id)
	if options.is_empty():
		options = Config.CRATE_WEAPONS.duplicate()
	return options[randi() % options.size()]


func _random_crate_spot() -> Vector2:
	var ppos := game.player.pos
	var best := game.arena.random_free_point(26.0, 110.0)
	for _i in 24:
		var p := game.arena.random_free_point(26.0, 110.0)
		var d := p.distance_to(ppos)
		if d >= Config.CRATE_MIN_DIST_FROM_PLAYER and d <= Config.CRATE_MAX_DIST_FROM_PLAYER:
			return p
		best = p
	return best


# ----------------------------------------------------------------------------
#  Update
# ----------------------------------------------------------------------------
func tick(dt: float) -> void:
	_time += dt
	var player := game.player
	var ppos := player.pos
	var can_collect := player.alive

	# --- coins ---
	_coin_streak_t -= dt
	if _coin_streak_t <= 0.0:
		_coin_streak = 0
	var magnet2: float = Config.COIN_MAGNET_RADIUS * Config.COIN_MAGNET_RADIUS
	var pick2: float = Config.COIN_PICKUP_RADIUS * Config.COIN_PICKUP_RADIUS
	var magnet_speed: float = Config.COIN_MAGNET_SPEED
	var keep := maxf(1.0 - 5.0 * dt, 0.0)
	var i := 0
	while i < coin_count:
		var p := _coin_pos[i]
		var life := _coin_life[i] - dt
		var gone := life <= 0.0
		if not gone:
			var v := _coin_vel[i]
			p += v * dt
			_coin_vel[i] = v * keep
			if can_collect:
				var to := ppos - p
				var d2 := to.length_squared()
				if d2 < pick2:
					gone = true
					game.collect_coin(p, true)
				elif d2 < magnet2:
					p += to * (magnet_speed * dt / sqrt(d2))
			_coin_pos[i] = p
			_coin_life[i] = life
		if gone:
			coin_count -= 1
			if i < coin_count:
				_coin_pos[i] = _coin_pos[coin_count]
				_coin_vel[i] = _coin_vel[coin_count]
				_coin_life[i] = _coin_life[coin_count]
		else:
			i += 1

	# --- crates ---
	if game.state == Game.State.PLAYING:
		_crate_timer -= dt
		if _crate_timer <= 0.0:
			_crate_timer = randf_range(Config.CRATE_INTERVAL_MIN, Config.CRATE_INTERVAL_MAX)
			if crates.size() < Config.CRATE_MAX_ON_FIELD:
				spawn_crate(_random_crate_spot())
	i = 0
	while i < crates.size():
		var c := crates[i]
		c.life -= dt
		c.age += dt
		var taken := can_collect and c.pos.distance_to(ppos) < Config.CRATE_PICKUP_RADIUS + player.radius
		if taken:
			game.collect_crate(c)
		if taken or c.life <= 0.0:
			crates[i] = crates[crates.size() - 1]
			crates.pop_back()
		else:
			i += 1

	# --- medkits ---
	i = 0
	while i < medkits.size():
		var m := medkits[i]
		m.life -= dt
		m.age += dt
		var used := can_collect and player.hp < player.max_hp \
				and m.pos.distance_to(ppos) < Config.MEDKIT_PICKUP_RADIUS + player.radius
		if used:
			game.collect_medkit(m.pos)
		if used or m.life <= 0.0:
			medkits[i] = medkits[medkits.size() - 1]
			medkits.pop_back()
		else:
			i += 1

	queue_redraw()


## Each coin grabbed in quick succession plays a slightly higher note.
func next_coin_pitch() -> float:
	_coin_streak = mini(_coin_streak + 1, 14)
	_coin_streak_t = 0.6
	return 1.0 + 0.045 * float(_coin_streak)


# ----------------------------------------------------------------------------
#  Drawing
# ----------------------------------------------------------------------------
func _draw() -> void:
	# Coins: a little pulse, and they blink before they vanish.
	var blink_on := fmod(_time, 0.2) < 0.12
	for i in coin_count:
		var life := _coin_life[i]
		if life < 3.0 and not blink_on:
			continue
		var s := 18.0 * (1.0 + 0.12 * sin(_time * 7.0 + float(i)))
		draw_texture_rect(_coin_tex, Rect2(_coin_pos[i] - Vector2(s, s) * 0.5, Vector2(s, s)), false)

	for m: Medkit in medkits:
		if m.life < 4.0 and not blink_on:
			continue
		var s := 28.0 * (1.0 + 0.08 * sin(_time * 5.0)) * minf(m.age * 5.0, 1.0)
		draw_texture_rect(_glow, Rect2(m.pos - Vector2(60, 60) * 0.5, Vector2(60, 60)), false, Color(1.0, 0.3, 0.3, 0.35))
		draw_texture_rect(_medkit_tex, Rect2(m.pos - Vector2(s, s) * 0.5, Vector2(s, s)), false)

	for c: Crate in crates:
		if c.life < 5.0 and not blink_on:
			continue
		var w: Dictionary = Config.WEAPONS[c.weapon]
		var color: Color = w["color"]
		# Drops in with a bounce, then bobs gently.
		var drop := 1.0 + maxf(0.3 - c.age, 0.0) * 2.5
		var s := 38.0 * drop * (1.0 + 0.05 * sin(_time * 4.0))
		var halo := 110.0 + 14.0 * sin(_time * 5.0)
		draw_texture_rect(_glow, Rect2(c.pos - Vector2(halo, halo) * 0.5, Vector2(halo, halo)), false, Color(color.r, color.g, color.b, 0.4))
		draw_texture_rect(_crate_tex, Rect2(c.pos - Vector2(s, s) * 0.5, Vector2(s, s)), false)
		# The weapon inside is shown on the lid.
		var gun: Texture2D = Art.t("gun_" + c.weapon)
		var gsize := Art.size_of("gun_" + c.weapon) * 0.62 * drop
		draw_set_transform(c.pos, -0.6, Vector2.ONE)
		draw_texture_rect(gun, Rect2(-gsize * 0.5, gsize), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
