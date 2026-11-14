class_name Game
extends Node2D
## One run of the game. Owns the world (arena, player, zombies, bullets,
## effects, camera) and runs the whole simulation from a single _process -
## which is what makes hit stop (freeze frames) and slow motion trivial.

signal run_ended(stats: Dictionary)

enum State { PLAYING, DYING, OVER }

var arena: Arena
var decals: Decals
var enemies: EnemyManager
var pickups: Pickups
var player: Player
var projectiles: Projectiles
var fx: Fx
var cam: GameCamera
var director: WaveDirector
var hud: Hud

var state: int = State.PLAYING
var time_alive := 0.0
var kills := 0
var score := 0
var coins_run := 0              # coins earned this run (banked when the run ends)
var combo := 0                  # kills in quick succession
var combo_timer := 0.0
var rage := 0.0                 # 0..Config.RAGE_MAX
var rage_active := false
var rage_time := 0.0
var enemy_hp_mult := 1.0        # set per wave
var enemy_speed_mult := 1.0
var sim_usec := 0               # how long the last simulation step took (for the benchmark)

var _hitstop := 0.0
var _hitstop_cooldown := 0.0
var _time_scale := 1.0
var _death_timer := 0.0
var _slowmo_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

	# Children are added bottom layer first.
	arena = Arena.new()
	decals = Decals.new()
	add_child(decals)          # ground + blood
	add_child(arena)           # rocks and stumps

	player = Player.new()
	player.game = self

	pickups = Pickups.new()
	pickups.game = self
	add_child(pickups)

	enemies = EnemyManager.new()
	add_child(enemies)
	enemies.setup(self)

	add_child(player)
	player.place(arena.rect.get_center())

	projectiles = Projectiles.new()
	projectiles.game = self
	add_child(projectiles)

	fx = Fx.new()
	fx.game = self
	add_child(fx)

	arena.canopy.z_index = 50  # tree tops above everything
	add_child(arena.canopy)

	cam = GameCamera.new()
	add_child(cam)
	cam.snap_to(player.pos)

	director = WaveDirector.new()
	director.game = self
	director.wave_started.connect(_on_wave_started)
	director.wave_cleared.connect(_on_wave_cleared)
	director.boss_spawned.connect(_on_boss_spawned)

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = Hud.new()
	hud.game = self
	hud_layer.add_child(hud)

	GameInput.rage_pressed.connect(try_activate_rage)


func _process(delta: float) -> void:
	var real_dt := minf(delta, 1.0 / 30.0)

	# Short bursts of slow motion (boss kills).
	if _slowmo_timer > 0.0:
		_slowmo_timer -= real_dt
		if _slowmo_timer <= 0.0 and state == State.PLAYING:
			_time_scale = 1.0

	# Hit stop: the world freezes for a few hundredths of a second.
	var dt := real_dt * _time_scale
	if _hitstop > 0.0:
		_hitstop -= real_dt
		dt = 0.0
		if _hitstop <= 0.0:
			_hitstop_cooldown = Config.HITSTOP_MIN_INTERVAL
	else:
		_hitstop_cooldown = maxf(_hitstop_cooldown - real_dt, 0.0)

	if dt > 0.0:
		var started := Time.get_ticks_usec()
		_simulate(dt)
		sim_usec = Time.get_ticks_usec() - started

	if state == State.DYING:
		_death_timer -= real_dt
		if _death_timer <= 0.0:
			state = State.OVER
			run_ended.emit(get_stats())

	var lead := Vector2.ZERO
	if player.alive:
		lead = player.aim * Config.CAM_AIM_LEAD_MAX * GameInput.get_aim_distance_factor(player)
	cam.tick(real_dt, player.pos, lead)
	hud.tick(real_dt)


func _simulate(dt: float) -> void:
	if state == State.PLAYING:
		time_alive += dt
		_tick_combo_and_rage(dt)
	player.tick(dt)
	director.tick(dt)
	enemies.tick(dt)
	projectiles.tick(dt)
	pickups.tick(dt)
	fx.tick(dt)


func _tick_combo_and_rage(dt: float) -> void:
	if combo > 0:
		combo_timer -= dt
		if combo_timer <= 0.0:
			combo = 0
	if rage_active:
		rage_time -= dt
		rage = Config.RAGE_MAX * maxf(rage_time, 0.0) / Config.RAGE_DURATION
		if rage_time <= 0.0:
			rage_active = false
			rage = 0.0
			Sfx.play("rage_end")


func get_stats() -> Dictionary:
	return {"score": score, "wave": director.wave, "kills": kills, "coins": coins_run, "time": time_alive}


# ----------------------------------------------------------------------------
#  Events
# ----------------------------------------------------------------------------
func _on_wave_started(wave: int, is_boss: bool) -> void:
	if is_boss:
		hud.announce("BOSS WAVE", "wave %d - something big is coming" % wave, Color(1.0, 0.3, 0.2), 3.0)
	else:
		hud.announce("WAVE %d" % wave, "", Color(1.0, 0.95, 0.85))


func _on_wave_cleared(wave: int, coin_bonus: int) -> void:
	hud.announce("WAVE %d CLEARED" % wave, "+%d coins" % coin_bonus, Color(0.6, 1.0, 0.5))


func _on_boss_spawned(_boss: Enemy) -> void:
	var boss_name: String = Config.ENEMIES[Config.BOSS]["name"]
	hud.announce(boss_name, "", Color(1.0, 0.25, 0.2), 2.6)


func on_enemy_killed(e: Enemy, dir: Vector2, kill_hitstop: float) -> void:
	kills += 1
	# Gore: the body tumbles away, blood sprays and pools.
	fx.corpse(e, dir)
	fx.blood_burst(e.pos, int(Config.BLOOD_PER_KILL * e.blood), 1.0)
	fx.blood_spray(e.pos, dir, int(Config.BLOOD_PER_KILL * e.blood * 0.5), 1.4)
	decals.blood_splat(e.pos, 34.0 * sqrt(e.blood), dir)
	# Feel: freeze frame + shake, bigger for bigger zombies.
	hitstop(kill_hitstop * e.hitstop_mult)
	shake(Config.KILL_SHAKE * e.shake_mult)
	Sfx.play("zombie_die")

	# Score with a combo multiplier for fast kills.
	combo += 1
	combo_timer = Config.COMBO_WINDOW
	score += int(round(e.score * Config.combo_multiplier(combo)))

	# Rage fills from kills (but not while it is burning).
	if not rage_active and rage < Config.RAGE_MAX:
		rage = minf(rage + e.rage, Config.RAGE_MAX)
		if rage >= Config.RAGE_MAX:
			Sfx.play("rage_ready")
			fx.text(player.pos + Vector2(0, -40), "RAGE READY!", Color(1.0, 0.45, 0.2), 24, 1.2)
			if Config.RAGE_AUTO_ACTIVATE:
				try_activate_rage()

	pickups.drop_from_enemy(e)
	director.on_enemy_killed(e)
	if e.kind == Config.BOSS:
		_boss_killed(e)


func _boss_killed(e: Enemy) -> void:
	# A boss death is an event: slow motion, a huge burst, and a reward crate.
	for k in 5:
		var at := e.pos + Vector2.from_angle(randf() * TAU) * randf_range(10.0, 60.0)
		decals.blood_splat(at, randf_range(70.0, 120.0))
		fx.blood_burst(at, 14, 1.8)
	fx.ring(e.pos, 30.0, 420.0, 0.6, Color(1.0, 0.3, 0.2, 0.9))
	fx.ring(e.pos, 20.0, 260.0, 0.45, Color(1.0, 0.9, 0.6, 0.9))
	fx.light(e.pos, 700.0, 0.4, Color(1.0, 0.5, 0.3, 0.8))
	fx.text(e.pos + Vector2(0, -70), "BOSS DOWN!", Color(1.0, 0.85, 0.3), 34, 1.8)
	pickups.spawn_crate(e.pos)
	shake(1.0)
	hitstop(Config.BOSS_DEATH_HITSTOP, true)
	slow_motion(0.3, 0.9)
	Sfx.play("explosion")


# ----------------------------------------------------------------------------
#  Rage
# ----------------------------------------------------------------------------
func rage_ready() -> bool:
	return state == State.PLAYING and not rage_active and rage >= Config.RAGE_MAX


func try_activate_rage() -> void:
	if get_tree().paused or not rage_ready():
		return
	rage_active = true
	rage_time = Config.RAGE_DURATION
	# The activation itself is a weapon: a blast that throws the horde back.
	enemies.shockwave(player.pos, Config.RAGE_BURST_RADIUS, Config.RAGE_BURST_FORCE, Config.RAGE_BURST_DAMAGE, 0.5)
	fx.ring(player.pos, 20.0, Config.RAGE_BURST_RADIUS, 0.4, Color(1.0, 0.35, 0.15, 0.95))
	fx.ring(player.pos, 10.0, Config.RAGE_BURST_RADIUS * 0.7, 0.3, Color(1.0, 0.8, 0.4, 0.8))
	fx.light(player.pos, Config.RAGE_BURST_RADIUS * 2.6, 0.3, Color(1.0, 0.3, 0.1, 0.8))
	fx.text(player.pos + Vector2(0, -44), "RAGE!", Color(1.0, 0.3, 0.15), 30, 1.0)
	shake(Config.RAGE_BURST_SHAKE)
	hitstop(Config.RAGE_BURST_HITSTOP, true)
	Sfx.play("rage_start")


# ----------------------------------------------------------------------------
#  Pickups
# ----------------------------------------------------------------------------
func collect_coin(at: Vector2, with_feedback: bool) -> void:
	coins_run += Config.COIN_VALUE
	if with_feedback:
		fx.sparks(at, Vector2.UP, 2)
		Sfx.play_pitched("coin", pickups.next_coin_pitch(), -8.0)


func collect_crate(crate: Pickups.Crate) -> void:
	player.give_weapon(crate.weapon)
	var w: Dictionary = Config.WEAPONS[crate.weapon]
	var color: Color = w["color"]
	fx.text(player.pos + Vector2(0, -42), String(w["name"]), color, 26, 1.3)
	fx.ring(crate.pos, 16.0, 120.0, 0.35, Color(color.r, color.g, color.b, 0.9))
	fx.light(crate.pos, 220.0, 0.25, Color(color.r, color.g, color.b, 0.6))
	shake(0.2)
	Sfx.play("pickup_weapon")


func collect_medkit(at: Vector2) -> void:
	player.heal(Config.MEDKIT_HEAL)
	fx.text(player.pos + Vector2(0, -42), "+%d HP" % int(Config.MEDKIT_HEAL), Color(0.45, 1.0, 0.5), 24, 1.1)
	fx.ring(at, 10.0, 90.0, 0.35, Color(0.4, 1.0, 0.5, 0.8))
	Sfx.play("medkit")


func damage_player(amount: float, from: Vector2) -> void:
	if state != State.PLAYING or not player.alive or player.invuln > 0.0:
		return
	if rage_active:
		amount *= Config.RAGE_DAMAGE_TAKEN_MULT
	player.hp -= amount
	player.invuln = Config.PLAYER_HURT_INVULN
	player.hurt_flash()
	hud.hurt()
	var away := (player.pos - from).normalized()
	fx.blood_spray(player.pos, away, 8, 1.0)
	combo = 0
	shake(Config.HURT_SHAKE)
	hitstop(Config.HURT_HITSTOP, true)
	Sfx.play("player_hurt")
	# Shove the crowd back so the player gets a chance to break out.
	enemies.shockwave(player.pos, Config.PLAYER_HURT_SHOVE_RADIUS, Config.PLAYER_HURT_SHOVE_FORCE, 0.0, 0.25)
	if player.hp <= 0.0:
		player.hp = 0.0
		_player_died()


func _player_died() -> void:
	state = State.DYING
	player.alive = false
	player.visible = false
	_time_scale = Config.DEATH_SLOWMO
	_death_timer = Config.DEATH_SLOWMO_TIME
	fx.blood_burst(player.pos, 40, 1.6)
	decals.blood_splat(player.pos, 90.0)
	fx.ring(player.pos, 10.0, 220.0, 0.5, Color(1.0, 0.2, 0.15, 0.8))
	shake(1.0)
	hitstop(0.12, true)
	Sfx.play("player_die")


# ----------------------------------------------------------------------------
#  Feel helpers used by everything else
# ----------------------------------------------------------------------------
func shake(amount: float) -> void:
	cam.add_trauma(amount)


## Run the world at `scale` speed for `duration` real seconds.
func slow_motion(scale: float, duration: float) -> void:
	if state != State.PLAYING:
		return
	_time_scale = scale
	_slowmo_timer = duration


## Freeze the action for `duration` seconds. Small freezes are rate-limited so
## a horde dying at once doesn't make the game stutter; `force` skips that.
func hitstop(duration: float, force: bool = false) -> void:
	if duration <= 0.0:
		return
	if not force and _hitstop <= 0.0 and _hitstop_cooldown > 0.0:
		return
	_hitstop = maxf(_hitstop, minf(duration, Config.HITSTOP_MAX))
