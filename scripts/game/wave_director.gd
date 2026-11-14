class_name WaveDirector
extends RefCounted
## Decides what attacks and when. Waves get bigger, faster and tougher over
## time; zombies arrive in packs from one side so they form hordes; every few
## waves a boss shows up. All the numbers come from Config (WAVES section).

signal wave_started(wave: int, is_boss: bool)
signal wave_cleared(wave: int, coin_bonus: int)
signal boss_spawned(boss: Enemy)

var game: Game
var wave := 0
var in_wave := false
var to_spawn := 0                 # regular zombies still to arrive this wave
var wave_total := 0
var boss: Enemy = null            # the living boss, if any
var intermission: float = Config.WAVE_FIRST_DELAY

var _pack_timer := 0.0
var _boss_delay := -1.0           # > 0 while a boss is on its way


func tick(dt: float) -> void:
	if game.state != Game.State.PLAYING:
		return
	if not in_wave:
		intermission -= dt
		if intermission <= 0.0:
			_start_wave()
		return

	var enemies := game.enemies
	if _boss_delay > 0.0:
		_boss_delay -= dt
		if _boss_delay <= 0.0:
			_spawn_boss()

	if to_spawn > 0:
		_pack_timer -= dt
		# Never leave the player waiting around on an empty field.
		if enemies.alive_count < 5:
			_pack_timer = minf(_pack_timer, 0.25)
		if _pack_timer <= 0.0:
			_pack_timer = Config.wave_pack_interval(wave) * randf_range(0.8, 1.25)
			_spawn_pack()
	elif _boss_delay <= 0.0 and enemies.alive_count == 0:
		_end_wave()


## Zombies left in this wave (still to arrive + alive).
func remaining() -> int:
	return to_spawn + game.enemies.alive_count + (1 if _boss_delay > 0.0 else 0)


func boss_alive() -> bool:
	return boss != null and boss.alive and boss.is_big


func _start_wave() -> void:
	wave += 1
	in_wave = true
	wave_total = Config.wave_enemy_count(wave)
	to_spawn = wave_total
	game.enemy_hp_mult = Config.wave_hp_mult(wave)
	game.enemy_speed_mult = Config.wave_speed_mult(wave)
	_pack_timer = 0.4
	var is_boss := Config.is_boss_wave(wave)
	_boss_delay = 3.0 if is_boss else -1.0
	wave_started.emit(wave, is_boss)
	Sfx.play("wave_start")


func _end_wave() -> void:
	in_wave = false
	intermission = Config.WAVE_INTERMISSION
	var bonus: int = Config.WAVE_CLEAR_COINS_BASE + Config.WAVE_CLEAR_COINS_PER_WAVE * wave
	game.coins_run += bonus
	wave_cleared.emit(wave, bonus)
	Sfx.play("wave_clear")


func _spawn_pack() -> void:
	var enemies := game.enemies
	var size := Config.wave_pack_size(wave) + randi_range(-1, 2)
	size = mini(size, to_spawn)
	size = mini(size, Config.MAX_ENEMIES_ALIVE - enemies.alive_count)
	if size <= 0:
		return
	var anchor := game.arena.random_spawn_point()
	var safe_zone := game.arena.rect.grow(Config.SPAWN_DIST_MIN * 0.7)
	var spread := 50.0 + size * 8.0
	# Now and then a whole pack of runners sprints in together.
	var runner_pack := wave > Config.RUNNER_START_WAVE and randf() < 0.14
	for k in size:
		var at := anchor + Vector2.from_angle(randf() * TAU) * (randf() * spread)
		if safe_zone.has_point(at):
			at = anchor      # never pop into view inside the clearing
		var kind: int = Config.RUNNER if runner_pack else _pick_kind()
		enemies.spawn(kind, at, game.enemy_hp_mult, game.enemy_speed_mult)
	to_spawn -= size


func _pick_kind() -> int:
	var runner_w := 0.0
	if wave >= Config.RUNNER_START_WAVE:
		runner_w = minf(float(wave - Config.RUNNER_START_WAVE + 1) * Config.RUNNER_WEIGHT_PER_WAVE, Config.RUNNER_WEIGHT_MAX)
	var brute_w := 0.0
	if wave >= Config.BRUTE_START_WAVE:
		brute_w = minf(float(wave - Config.BRUTE_START_WAVE + 1) * Config.BRUTE_WEIGHT_PER_WAVE, Config.BRUTE_WEIGHT_MAX)
	var roll := randf()
	if roll < brute_w:
		return Config.BRUTE
	if roll < brute_w + runner_w:
		return Config.RUNNER
	return Config.SHAMBLER


func _spawn_boss() -> void:
	var cfg: Dictionary = Config.ENEMIES[Config.BOSS]
	var boss_number := maxi(int(float(wave) / Config.BOSS_EVERY), 1)
	var hp_mult := 1.0 + float(cfg["hp_growth_per_boss"]) * float(boss_number - 1)
	boss = game.enemies.spawn(Config.BOSS, game.arena.random_spawn_point(), hp_mult, 1.0)
	_boss_delay = -1.0
	boss_spawned.emit(boss)
	Sfx.play("boss_roar")
	game.shake(0.5)


func on_enemy_killed(e: Enemy) -> void:
	if e == boss:
		boss = null
