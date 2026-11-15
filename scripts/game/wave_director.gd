class_name WaveDirector
extends RefCounted
## Decides what attacks and when. Waves get bigger, faster and tougher over
## time; zombies arrive in packs so they form hordes; every few waves a boss
## shows up. The map is big, so packs claw out of the ground in a ring around
## the player, just out of sight, wherever the player is. A map ends when its
## last wave is cleared. All the numbers come from Config (MAPS and WAVES).

signal wave_started(wave: int, is_boss: bool)
signal wave_cleared(wave: int, coin_bonus: int)
signal boss_spawned(boss: Enemy)

var game: Game
var wave := 0                     # the wave being fought (0 before the first; set to start_wave - 1 to begin later)
var cleared := 0                  # the last wave that was cleared in this run
var finished := false             # true once the map's last wave is cleared
var in_wave := false
var to_spawn := 0                 # regular zombies still to arrive this wave
var wave_total := 0
var boss: Enemy = null            # the living boss, if any
var intermission: float = Config.WAVE_FIRST_DELAY

var _mix: Dictionary = {}         # this wave's share of each special kind (see Config.wave_mix)
var _mix_wave := -1
var _pack_timer := 0.0
var _boss_delay := -1.0           # > 0 while a boss is on its way


func tick(dt: float) -> void:
	if game.state != Game.State.PLAYING or finished:
		return
	if not in_wave:
		if game.perks_pending():
			return                        # (somebody is choosing a perk: the next wave waits)
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
	wave_total = int(round(float(wave_total) * game.strength_count()))      # more players: more of them...
	to_spawn = wave_total
	# Zombie strength = the map's multiplier times this wave's (...and tougher ones).
	var map: Dictionary = game.map
	game.enemy_hp_mult = float(map["hp"]) * Config.wave_hp_mult(wave) * game.strength_hp()
	game.enemy_speed_mult = float(map["speed"]) * Config.wave_speed_mult(wave)
	game.enemy_damage_mult = float(map["damage"]) * Config.wave_damage_mult(wave) * game.strength_damage()
	game.enemy_xp_mult = float(map["xp"]) * Config.wave_xp_mult(wave)
	_pack_timer = 0.4
	var is_boss := Config.is_boss_wave(wave)
	_boss_delay = float(Config.ENEMIES[Config.BOSS]["arrive_delay"]) if is_boss else -1.0
	wave_started.emit(wave, is_boss)
	Sfx.play("wave_start")


func _end_wave() -> void:
	in_wave = false
	cleared = wave
	finished = wave >= Config.WAVES_PER_MAP
	intermission = Config.WAVE_INTERMISSION
	var bonus: int = (Config.WAVE_CLEAR_COINS_BASE + Config.WAVE_CLEAR_COINS_PER_WAVE * wave) * game.coin_value
	game.coins_run += bonus
	wave_cleared.emit(wave, bonus)
	Sfx.play("wave_clear")


func _spawn_pack() -> void:
	var enemies := game.enemies
	var size := Config.wave_pack_size(wave) + randi_range(-1, 2)
	size = mini(size, to_spawn)
	size = mini(size, game.max_alive() - enemies.alive_count)
	if size <= 0:
		return
	# Now and then a whole pack of runners sprints in together.
	var runner_pack := wave > Config.RUNNER_START_WAVE and randf() < Config.RUNNER_PACK_CHANCE
	# Later waves split each pack over several directions, so hordes close in
	# from all around instead of trailing behind the player.
	var sides := mini(Config.wave_pack_sides(wave), maxi(int(size / 3.0), 1))
	var left := size
	var first_angle := randf() * TAU
	for side in sides:
		var group := left if side == sides - 1 else int(ceil(float(size) / sides))
		group = mini(group, left)
		left -= group
		# The pack's middle is far enough out that none of it pops into view.
		var spread := 50.0 + group * 8.0
		var angle := first_angle + TAU * float(side) / float(sides) + randf_range(-0.4, 0.4)
		var anchor := game.spawn_point(angle, spread)
		for k in group:
			var at := game.arena.clamp_inside(anchor + Vector2.from_angle(randf() * TAU) * (randf() * spread), 30.0)
			var kind: int = Config.RUNNER if runner_pack else _pick_kind()
			enemies.spawn(kind, at, game.enemy_hp_mult, game.enemy_speed_mult, true)
	to_spawn -= size


## Which kind of zombie comes next: by this wave's mix (Config.ENEMY_MIX).
func _pick_kind() -> int:
	if _mix_wave != wave:
		_mix_wave = wave
		_mix = Config.wave_mix(wave)
	var roll := randf()
	for kind: int in _mix.keys():
		roll -= float(_mix[kind])
		if roll < 0.0:
			return kind
	return Config.SHAMBLER


func _spawn_boss() -> void:
	var cfg: Dictionary = Config.ENEMIES[Config.BOSS]
	var boss_number := maxi(int(float(wave) / Config.BOSS_EVERY), 1)
	var hp_mult := game.enemy_hp_mult * (1.0 + float(cfg["hp_growth_per_boss"]) * float(boss_number - 1))
	var at := game.spawn_point(randf() * TAU, 0.0, float(cfg["radius"]) + 12.0)
	# (Each map's gang leader has his own look: the boss's "variant" is the map.)
	boss = game.enemies.spawn(Config.BOSS, at, hp_mult, float(game.map["speed"]), false, game.map_index % Art.BOSS_VARIANTS)
	_boss_delay = -1.0
	boss_spawned.emit(boss)
	Sfx.play("boss_roar")
	game.shake(float(cfg["spawn_shake"]))


func on_enemy_killed(e: Enemy) -> void:
	if e == boss:
		boss = null


## A zombie was left too far behind and taken off the field: one more is owed.
func on_enemy_lost(_e: Enemy) -> void:
	if in_wave:
		to_spawn += 1
