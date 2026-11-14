class_name Game
extends Node2D
## One run of the game. Owns the world (arena, player, zombies, bullets,
## effects, camera) and runs the whole simulation from a single _process -
## which is what makes hit stop (freeze frames) and slow motion trivial.

signal run_ended(stats: Dictionary)

enum State { PLAYING, DYING, WON, OVER }

# Set by Main before the game is added to the scene.
var map_index := 0              # which entry of Config.MAPS
var start_wave := 1             # the first wave of this run (a checkpoint)
var map: Dictionary = Config.MAPS[0]

var arena: Arena
var decals: Decals
var enemies: EnemyManager
var pickups: Pickups
var player: Player
var pet: Pet                    # the companion, if one comes along (null = none)
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
var xp_run := 0                 # XP earned this run (already added to the character as it comes in)
var levels_run := 0             # character levels gained this run
var combo := 0                  # kills in quick succession
var combo_timer := 0.0
var rage := 0.0                 # 0..Config.RAGE_MAX
var rage_active := false
var rage_time := 0.0
var enemy_hp_mult := 1.0        # set per wave (map x wave growth)
var enemy_speed_mult := 1.0
var enemy_damage_mult := 1.0
var enemy_xp_mult := 1.0
var coin_value: int = Config.COIN_VALUE   # what one coin is worth on this map
var victory := false            # the map's last wave was cleared
var new_checkpoint := 0         # a starting wave unlocked during this run (0 = none)
var unlocked_map := -1          # a map unlocked by this run (-1 = none)
var gear_run: Array[String] = []   # gear picked up this run (already in the bag)
var sim_usec := 0               # how long the last simulation step took (for the benchmark)

var _hitstop := 0.0
var _hitstop_cooldown := 0.0
var _time_scale := 1.0
var _end_timer := 0.0           # counts down to the results screen after death or victory
var _slowmo_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	map_index = clampi(map_index, 0, Config.MAPS.size() - 1)
	map = Config.MAPS[map_index]
	coin_value = Config.COIN_VALUE * int(map["coins"])
	enemy_hp_mult = float(map["hp"])
	enemy_speed_mult = float(map["speed"])
	enemy_damage_mult = float(map["damage"])
	enemy_xp_mult = float(map["xp"])

	# Children are added bottom layer first.
	arena = Arena.new()
	arena.tree_tint = map["trees"]
	decals = Decals.new()
	decals.ground_tint = map["ground"]
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
	if player.stats.pet != "":
		_spawn_pet()

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
	director.wave = clampi(start_wave, 1, Config.WAVES_PER_MAP) - 1
	director.cleared = director.wave
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
	GameInput.reload_pressed.connect(_on_reload_pressed)

	# Starting deep into a map: a weapon is waiting beside you.
	if start_wave > 1 and Config.CHECKPOINT_START_CRATE:
		pickups.spawn_crate(player.pos + Vector2(0.0, 80.0))


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

	if state == State.DYING or state == State.WON:
		_end_timer -= real_dt
		if _end_timer <= 0.0:
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
	if pet != null:
		pet.tick(dt)
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
	return {"score": score, "wave": director.wave, "kills": kills, "coins": coins_run, "time": time_alive,
			"xp": xp_run, "levels": levels_run, "map": map_index, "start": start_wave, "cleared": director.cleared,
			"victory": victory, "checkpoint": new_checkpoint, "unlocked": unlocked_map, "gear": gear_run}


# ----------------------------------------------------------------------------
#  Events
# ----------------------------------------------------------------------------
func _on_wave_started(wave: int, is_boss: bool) -> void:
	if is_boss:
		hud.announce("BOSS WAVE", "wave %d - something big is coming" % wave, Color(1.0, 0.3, 0.2), 3.0)
	else:
		hud.announce("WAVE %d" % wave, "", Color(1.0, 0.95, 0.85))


func _on_wave_cleared(wave: int, coin_bonus: int) -> void:
	var xp_bonus := int(round(float(Config.WAVE_CLEAR_XP_BASE + Config.WAVE_CLEAR_XP_PER_WAVE * wave) * float(map["xp"])))
	var opened := SaveData.note_wave_cleared(map_index, wave)
	if int(opened["unlocked"]) >= 0:
		unlocked_map = int(opened["unlocked"])
	if wave >= Config.WAVES_PER_MAP:
		gain_xp(xp_bonus, "")
		_map_cleared()
		return
	if int(opened["checkpoint"]) > 0:
		new_checkpoint = int(opened["checkpoint"])
		hud.announce("CHECKPOINT REACHED", "+%d coins   +%d XP   -   you can now start from wave %d" % [
				coin_bonus, xp_bonus, new_checkpoint], Color(1.0, 0.85, 0.3), 3.2)
	else:
		hud.announce("WAVE %d CLEARED" % wave, "+%d coins   +%d XP" % [coin_bonus, xp_bonus], Color(0.6, 1.0, 0.5))
	gain_xp(xp_bonus, "")


## The last wave of the map is cleared: a moment of glory, then the results.
func _map_cleared() -> void:
	victory = true
	var coins_bonus: int = Config.MAP_CLEAR_COINS * int(map["coins"])
	var xp_bonus := int(round(float(Config.MAP_CLEAR_XP) * float(map["xp"])))
	coins_run += coins_bonus
	gain_xp(xp_bonus, "")
	state = State.WON
	_end_timer = Config.MAP_CLEAR_CELEBRATION
	_time_scale = Config.BOSS_DEATH_SLOWMO
	_slowmo_timer = 0.0
	hud.announce("MAP CLEARED!", "%s is yours   -   +%d coins   +%d XP" % [String(map["name"]), coins_bonus, xp_bonus],
			Color(1.0, 0.85, 0.3), 6.0)
	for k in 3:
		fx.ring(player.pos, 20.0 + 30.0 * k, 320.0 + 140.0 * k, 0.6 + 0.2 * k, Color(1.0, 0.85, 0.3, 0.9))
	fx.light(player.pos, 900.0, 0.6, Color(1.0, 0.8, 0.3, 0.7))
	shake(Config.BOSS_DEATH_SHAKE)
	Sfx.play("level_up")


func _on_boss_spawned(_boss: Enemy) -> void:
	var boss_name: String = Config.ENEMIES[Config.BOSS]["name"]
	hud.announce(boss_name, "", Color(1.0, 0.25, 0.2), 2.6)


func on_enemy_killed(e: Enemy, dir: Vector2, kill_hitstop: float, source: String = "") -> void:
	kills += 1
	gain_xp(e.xp, source)
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
	shake(Config.BOSS_DEATH_SHAKE)
	hitstop(Config.BOSS_DEATH_HITSTOP, true)
	slow_motion(Config.BOSS_DEATH_SLOWMO, Config.BOSS_DEATH_SLOWMO_TIME)
	Sfx.play("explosion")


# ----------------------------------------------------------------------------
#  Experience: the character always gains it; the weapon that made the kill
#  gains the same amount for its own level.
# ----------------------------------------------------------------------------
func gain_xp(amount: int, weapon_id: String) -> void:
	if amount <= 0:
		return
	xp_run += amount
	var levels := SaveData.add_xp(amount)
	if levels > 0:
		levels_run += levels
		player.refresh_stats()
		player.heal(player.max_hp * Config.LEVEL_UP_HEAL)
		hud.announce("LEVEL UP!", "level %d   -   skill point earned" % SaveData.level, Color(1.0, 0.85, 0.3), 2.2)
		fx.ring(player.pos, 14.0, 170.0, 0.45, Color(1.0, 0.85, 0.3, 0.9))
		fx.light(player.pos, 300.0, 0.3, Color(1.0, 0.8, 0.3, 0.6))
		Sfx.play("level_up")
		# The level that opens pets: the first one walks in right away.
		if pet == null and player.stats.pet != "":
			_spawn_pet()
			var joined: Dictionary = Config.PETS[pet.id]
			hud.announce("%s JOINS YOU!" % String(joined["name"]), "%s fights at your side and adds to your damage" % String(joined["title"]),
					Config.PET_RARITIES[String(joined["rarity"])]["color"], 4.0)
			fx.ring(pet.pos, 10.0, 140.0, 0.5, Color(1.0, 0.9, 0.6, 0.9))
			Sfx.play("pet_call")
	# (Kills by the pet or by fire it started carry a source that is not a weapon.)
	if Config.WEAPONS.has(weapon_id) and SaveData.add_weapon_xp(weapon_id, amount) > 0:
		var w: Dictionary = Config.WEAPONS[weapon_id]
		fx.text(player.pos + Vector2(0, -58), "%s LEVEL %d" % [String(w["name"]), SaveData.weapon_level(weapon_id)],
				w["color"], 20, 1.4)
		Sfx.play("weapon_level")


## Bring in the pet named by the player's stats, at the player's heel.
func _spawn_pet() -> void:
	pet = Pet.new()
	pet.setup(self, player.stats.pet, arena.resolve(player.pos + Vector2(-44.0, 30.0), Config.PET_RADIUS))
	add_child(pet)
	move_child(pet, player.get_index())     # drawn just under the player


# ----------------------------------------------------------------------------
#  Rage
# ----------------------------------------------------------------------------
func rage_ready() -> bool:
	return state == State.PLAYING and not rage_active and rage >= Config.RAGE_MAX


func _on_reload_pressed() -> void:
	if state == State.PLAYING and not get_tree().paused:
		player.start_reload()


func try_activate_rage() -> void:
	if get_tree().paused or not rage_ready():
		return
	rage_active = true
	rage_time = Config.RAGE_DURATION
	if Config.RAGE_REFILLS_AMMO:
		player.refill_ammo()
	# The activation itself is a weapon: a blast that throws the horde back.
	enemies.shockwave(player.pos, Config.RAGE_BURST_RADIUS, Config.RAGE_BURST_FORCE, Config.RAGE_BURST_DAMAGE, Config.RAGE_BURST_STAGGER)
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
	coins_run += coin_value
	if with_feedback:
		fx.sparks(at, Vector2.UP, 2)
		Sfx.play_pitched("coin", pickups.next_coin_pitch(), -8.0)


func collect_crate(crate: Pickups.Crate) -> void:
	player.give_weapon(crate.weapon)
	var w: Dictionary = Config.WEAPONS[crate.weapon]
	var rarity: Dictionary = Config.CRATE_RARITIES[String(w["rarity"])]
	var color: Color = rarity["color"]
	fx.text(player.pos + Vector2(0, -42), player.weapon_label(), w["color"], 26, 1.4)
	if String(w["rarity"]) != "common":
		fx.text(player.pos + Vector2(0, -68), String(rarity["name"]), color, 17, 1.4)
	fx.ring(crate.pos, 16.0, 120.0, 0.35, Color(color.r, color.g, color.b, 0.9))
	fx.light(crate.pos, 220.0, 0.25, Color(color.r, color.g, color.b, 0.6))
	shake(Config.CRATE_PICKUP_SHAKE)
	Sfx.play("pickup_weapon")


## A piece of gear goes straight into the bag: it is kept even if you die.
func collect_gear(piece: Pickups.Loot) -> void:
	SaveData.add_gear(piece.key)
	gear_run.append(piece.key)
	var color: Color = Config.gear_tier_def(Config.gear_tier_of(piece.key))["color"]
	fx.text(player.pos + Vector2(0, -72), "GEAR FOUND", Color(1, 1, 1), 16, 2.0)
	fx.text(player.pos + Vector2(0, -46), Config.gear_name(piece.key), color, 26, 2.0)
	fx.ring(piece.pos, 14.0, 150.0, 0.45, Color(color.r, color.g, color.b, 0.95))
	fx.light(piece.pos, 320.0, 0.35, Color(color.r, color.g, color.b, 0.7))
	shake(Config.GEAR_PICKUP_SHAKE)
	Sfx.play("gear_pickup")


func collect_medkit(at: Vector2) -> void:
	player.heal(Config.MEDKIT_HEAL)
	fx.text(player.pos + Vector2(0, -42), "+%d HP" % int(Config.MEDKIT_HEAL), Color(0.45, 1.0, 0.5), 24, 1.1)
	fx.ring(at, 10.0, 90.0, 0.35, Color(0.4, 1.0, 0.5, 0.8))
	Sfx.play("medkit")


func damage_player(amount: float, from: Vector2) -> void:
	if state != State.PLAYING or not player.alive or player.invuln > 0.0:
		return
	# Evasion: the hit misses completely.
	if randf() < player.stats.evasion:
		player.invuln = player.stats.dodge_invuln
		fx.text(player.pos + Vector2(0, -36), "DODGE", Color(0.55, 0.9, 1.0), 18, 0.6)
		Sfx.play("dodge")
		return
	amount *= player.stats.damage_taken_mult      # defense
	if rage_active:
		amount *= Config.RAGE_DAMAGE_TAKEN_MULT
	player.hp -= amount
	player.invuln = Config.PLAYER_HURT_INVULN * player.stats.hurt_invuln_mult
	player.hurt_boost = player.stats.hurt_speed_time
	if pet != null:
		pet.on_owner_hurt()
	player.hurt_flash()
	hud.hurt()
	var away := (player.pos - from).normalized()
	fx.blood_spray(player.pos, away, 8, 1.0)
	combo = 0
	shake(Config.HURT_SHAKE)
	hitstop(Config.HURT_HITSTOP, true)
	Sfx.play("player_hurt")
	# Shove the crowd back so the player gets a chance to break out.
	enemies.shockwave(player.pos, Config.PLAYER_HURT_SHOVE_RADIUS, Config.PLAYER_HURT_SHOVE_FORCE, 0.0, Config.PLAYER_HURT_SHOVE_STAGGER)
	if player.hp <= 0.0:
		if player.stats.second_wind > 0.0 and not player.second_wind_used:
			_second_wind()
			return
		player.hp = 0.0
		_player_died()


## SECOND WIND keystone: the blow that should have killed you does not.
func _second_wind() -> void:
	player.second_wind_used = true
	player.hp = player.max_hp * player.stats.second_wind
	player.invuln = Config.SECOND_WIND_INVULN
	enemies.shockwave(player.pos, Config.RAGE_BURST_RADIUS, Config.RAGE_BURST_FORCE, 0.0, Config.RAGE_BURST_STAGGER)
	fx.ring(player.pos, 20.0, Config.RAGE_BURST_RADIUS, 0.45, Color(0.95, 0.3, 0.3, 0.95))
	fx.light(player.pos, Config.RAGE_BURST_RADIUS * 2.4, 0.35, Color(1.0, 0.3, 0.3, 0.7))
	fx.text(player.pos + Vector2(0, -48), "SECOND WIND!", Color(1.0, 0.45, 0.45), 28, 1.4)
	slow_motion(Config.BOSS_DEATH_SLOWMO, 0.6)
	Sfx.play("rage_start")


func _player_died() -> void:
	state = State.DYING
	player.alive = false
	player.visible = false
	_time_scale = Config.DEATH_SLOWMO
	_end_timer = Config.DEATH_SLOWMO_TIME
	fx.blood_burst(player.pos, 40, 1.6)
	decals.blood_splat(player.pos, 90.0)
	fx.ring(player.pos, 10.0, 220.0, 0.5, Color(1.0, 0.2, 0.15, 0.8))
	shake(Config.DEATH_SHAKE)
	hitstop(Config.DEATH_HITSTOP, true)
	Sfx.play("player_die")


# ----------------------------------------------------------------------------
#  Feel helpers used by everything else
# ----------------------------------------------------------------------------
func shake(amount: float) -> void:
	if rage_active:
		amount *= Config.RAGE_SHAKE_MULT
	cam.add_trauma(amount)


## Run the world at `speed` (1 = normal) for `duration` real seconds.
func slow_motion(speed: float, duration: float) -> void:
	if state != State.PLAYING:
		return
	_time_scale = speed
	_slowmo_timer = duration


## Freeze the action for `duration` seconds. Small freezes are rate-limited so
## a horde dying at once doesn't make the game stutter; `force` skips that.
func hitstop(duration: float, force: bool = false) -> void:
	if duration <= 0.0:
		return
	if not force and _hitstop <= 0.0 and _hitstop_cooldown > 0.0:
		return
	_hitstop = maxf(_hitstop, minf(duration, Config.HITSTOP_MAX))
