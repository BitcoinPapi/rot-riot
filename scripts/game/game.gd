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
var player: Player
var projectiles: Projectiles
var fx: Fx
var cam: GameCamera

var state: int = State.PLAYING
var time_alive := 0.0
var kills := 0
var rage := 0.0
var rage_active := false
var enemy_hp_mult := 1.0        # set per wave
var enemy_speed_mult := 1.0

var _hitstop := 0.0
var _hitstop_cooldown := 0.0
var _time_scale := 1.0
var _death_timer := 0.0
var _debug_spawn_t := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

	# Children are added bottom layer first.
	arena = Arena.new()
	decals = Decals.new()
	add_child(decals)          # ground + blood
	add_child(arena)           # rocks and stumps

	player = Player.new()
	player.game = self

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


func _process(delta: float) -> void:
	var real_dt := minf(delta, 1.0 / 30.0)

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
		_simulate(dt)

	if state == State.DYING:
		_death_timer -= real_dt
		if _death_timer <= 0.0:
			state = State.OVER
			run_ended.emit(get_stats())

	var lead := Vector2.ZERO
	if player.alive:
		lead = player.aim * Config.CAM_AIM_LEAD_MAX * GameInput.get_aim_distance_factor(player)
	cam.tick(real_dt, player.pos, lead)


func _simulate(dt: float) -> void:
	if state == State.PLAYING:
		time_alive += dt
	player.tick(dt)
	_debug_spawner(dt)
	enemies.tick(dt)
	projectiles.tick(dt)
	fx.tick(dt)


## Temporary: a trickle of zombies until the wave director arrives.
func _debug_spawner(dt: float) -> void:
	_debug_spawn_t -= dt
	if _debug_spawn_t <= 0.0 and enemies.alive_count < 80:
		_debug_spawn_t = 0.35
		var roll := randf()
		var kind: int = Config.SHAMBLER
		if roll > 0.93:
			kind = Config.BRUTE
		elif roll > 0.7:
			kind = Config.RUNNER
		enemies.spawn(kind, arena.random_spawn_point())


func get_stats() -> Dictionary:
	return {"kills": kills, "time": time_alive}


# ----------------------------------------------------------------------------
#  Events
# ----------------------------------------------------------------------------
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


func damage_player(amount: float, from: Vector2) -> void:
	if state != State.PLAYING or not player.alive or player.invuln > 0.0:
		return
	if rage_active:
		amount *= Config.RAGE_DAMAGE_TAKEN_MULT
	player.hp -= amount
	player.invuln = Config.PLAYER_HURT_INVULN
	player.hurt_flash()
	var away := (player.pos - from).normalized()
	fx.blood_spray(player.pos, away, 8, 1.0)
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


## Freeze the action for `duration` seconds. Small freezes are rate-limited so
## a horde dying at once doesn't make the game stutter; `force` skips that.
func hitstop(duration: float, force: bool = false) -> void:
	if duration <= 0.0:
		return
	if not force and _hitstop <= 0.0 and _hitstop_cooldown > 0.0:
		return
	_hitstop = maxf(_hitstop, minf(duration, Config.HITSTOP_MAX))
