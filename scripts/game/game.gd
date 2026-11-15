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

# Co-op (see scripts/game/coop.gd). `net` is empty for a run alone; for a
# run together it holds what both computers must agree on:
# {"host": am I the host, "slots": the numbers of the players in it, and for
#  a joiner what the host decided: "rocks": [...] and "chests": [[x, y], ...]}.
var net: Dictionary = {}
var coop: Coop                  # null when playing alone
var is_client := false          # true on the joiner's computer: the world is the host's, shown here

var arena: Arena
var decals: Decals
var enemies: EnemyManager
var pickups: Pickups
var player: Player
var pet: Pet                    # the companion, if one comes along (null = none)
var projectiles: Projectiles
var enemy_shots: EnemyShots     # what zombies spit and throw
var fx: Fx
var fog: Fog                    # fog of war over the parts of the map not visited yet
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
var enemy_hp_mult := 1.0        # set per wave (map x wave growth)
var enemy_speed_mult := 1.0
var enemy_damage_mult := 1.0
var enemy_xp_mult := 1.0
var coin_value: int = Config.COIN_VALUE   # what one coin is worth on this map
var victory := false            # the map's last wave was cleared
var new_checkpoint := 0         # a starting wave unlocked during this run (0 = none)
var unlocked_map := -1          # a map unlocked by this run (-1 = none)
var gear_run: Array[String] = []   # gear picked up this run (already in the bag)
var chests_run := 0             # treasure chests opened this run
var sim_usec := 0               # how long the last simulation step took (for the benchmark)
# Run perks (Config.RUN_PERKS): every few waves the player chooses one of
# three; they last until the run ends.
var perks: Dictionary = {}      # the perks chosen this run: id -> how many times
var perks_owed := 0             # choices still to make
var perk_offer: Array[String] = []   # the perks on the table right now ([] = no choice is showing)
var perk_time_left := 0.0       # (co-op) seconds before one is taken for you
var perk_panel: PerkChoice
# How far from the middle of the screen "out of sight" is (worked out from
# the size of the window): zombies come out of the ground between spawn_min
# and spawn_max.
var spawn_min := 800.0
var spawn_max := 1040.0
var leash_dist := 2100.0        # a zombie further from the player than this is taken off the field
var boss_leash := 1950.0        # ...and a boss this far away digs its way back

var _hitstop := 0.0
var _hitstop_cooldown := 0.0
var _time_scale := 1.0
var _end_timer := 0.0           # counts down to the results screen after death or victory
var _perks_given := 0           # perk choices earned so far this run (made + still owed)
var _perk_delay := 0.0          # seconds until the next choice appears
var _perk_kills := 0            # kills counted toward the PAYBACK perk's next heal
var _perk_hold := 0.0           # (co-op) how long the next wave has been waiting for another player's choice
var _slowmo_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	map_index = clampi(map_index, 0, Config.MAPS.size() - 1)
	map = Config.MAPS[map_index]
	coin_value = Config.COIN_VALUE * int(map["coins"])
	is_client = not net.is_empty() and not bool(net.get("host", true))
	enemy_hp_mult = float(map["hp"]) * strength_hp()
	enemy_speed_mult = float(map["speed"])
	enemy_damage_mult = float(map["damage"]) * strength_damage()
	enemy_xp_mult = float(map["xp"])

	# Children are added bottom layer first.
	arena = Arena.new(map.get("size", Config.ARENA_SIZE), 0, net.get("rocks") if is_client else null)
	arena.tree_tint = map["trees"]
	decals = Decals.new()
	decals.ground_tint = map["ground"]
	decals.ground_floor = String(map.get("floor", Config.GROUND_FLOOR))
	decals.ground_litter = map.get("litter", Config.GROUND_LITTER)
	decals.setup(arena.rect)
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
	if not net.is_empty():
		# Together: everybody starts in the middle, each on their own spot.
		player.place(arena.rect.get_center() + Config.COOP_START_SPOTS[Net.slot % Config.COOP_START_SPOTS.size()])
		coop = Coop.new()
		coop.setup(self, not is_client)
		add_child(coop)
		coop.add_mates(net.get("slots", []))
		enemies.remote = is_client
		pickups.remote = is_client
	if player.stats.pet != "":
		_spawn_pet()

	projectiles = Projectiles.new()
	projectiles.game = self
	add_child(projectiles)

	enemy_shots = EnemyShots.new()
	enemy_shots.game = self

	fx = Fx.new()
	fx.game = self
	add_child(fx)
	add_child(enemy_shots)     # over the effects: a warning must never be hidden

	arena.canopy.z_index = 50  # tree tops above everything
	add_child(arena.canopy)

	fog = Fog.new()            # ...and the fog above the trees
	fog.setup(arena.rect)
	add_child(fog)
	fog.reveal(player.pos, Config.FOG_START_MULT)
	if is_client:
		pickups.set_chests(net.get("chests", []))
	else:
		pickups.place_chests()

	cam = GameCamera.new()
	cam.bounds = arena.rect
	add_child(cam)
	cam.snap_to(player.pos)
	_measure_view()
	decals.show_area(cam.view_rect().grow(Config.DECAL_CHUNK_AHEAD))

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
	perk_panel = PerkChoice.new()
	perk_panel.game = self
	hud_layer.add_child(perk_panel)
	# A run that starts deep into a map begins with the perks for the waves it skipped.
	_owe_perks(Config.perks_earned(director.cleared), Config.PERK_START_DELAY)

	GameInput.reload_pressed.connect(_on_reload_pressed)

	# Starting deep into a map: a weapon is waiting beside you.
	if start_wave > 1 and Config.CHECKPOINT_START_CRATE and not is_client:
		pickups.spawn_crate(player.pos + Vector2(0.0, 80.0))
		if coop != null:
			for other: int in coop.mates.keys():
				pickups.spawn_crate((coop.mates[other] as Mate).pos + Vector2(0.0, 80.0))


## How many players are in this run right now.
func players_now() -> int:
	if net.is_empty():
		return 1
	if coop == null:
		return maxi((net.get("slots", []) as Array).size(), 1)      # (still being set up)
	return 1 + coop.mates.size()


## How much tougher zombies are than normal: more with every extra player.
func strength_hp() -> float:
	return Config.COOP_ENEMY_HP[clampi(players_now() - 1, 0, Config.COOP_ENEMY_HP.size() - 1)]


func strength_damage() -> float:
	return Config.COOP_ENEMY_DAMAGE[clampi(players_now() - 1, 0, Config.COOP_ENEMY_DAMAGE.size() - 1)]


func strength_count() -> float:
	return Config.COOP_WAVE_COUNT[clampi(players_now() - 1, 0, Config.COOP_WAVE_COUNT.size() - 1)]


## True while at least one other player is in this run.
func together() -> bool:
	return players_now() > 1


func _process(delta: float) -> void:
	var real_dt := minf(delta, 1.0 / 30.0)
	_tick_perks(real_dt)

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
	if coop != null:
		coop.tick(real_dt, dt)
	_measure_view()
	# Ground is made as the screen comes near it (one new piece per frame at most).
	decals.show_area(cam.view_rect().grow(Config.DECAL_CHUNK_AHEAD), 1)
	hud.tick(real_dt)


## "Out of sight" depends on the size of the window: just past its corner.
func _measure_view() -> void:
	var half := get_viewport_rect().size.length() * 0.5 / cam.zoom.x     # the middle of the screen to its corner
	spawn_min = half + Config.CAM_AIM_LEAD_MAX + Config.SPAWN_RING_MARGIN
	spawn_max = spawn_min + Config.SPAWN_RING_DEPTH
	# (Near the map's edge the player is not in the middle of the screen, so
	# the ring can lie up to half a screen further from him than usual.)
	leash_dist = spawn_max + half + Config.ENEMY_LEASH_EXTRA
	boss_leash = spawn_max + half + Config.BOSS_LEASH_EXTRA


## A spot out of sight where zombies can come out of the ground: in the
## direction `angle` from the middle of the screen if the map has room there.
## `extra` pushes it further out (for the middle of a pack); `edge` keeps it
## off the map's edge.
func spawn_point(angle: float, extra: float = 0.0, edge: float = 40.0) -> Vector2:
	# Together: around one of the players who is on their feet, and out of
	# sight of the others too.
	var screens: Array[Vector2] = []
	var others: Array[Mate] = coop.mates_up() if coop != null else ([] as Array[Mate])
	if player.alive or others.is_empty():
		screens.append(cam.center_for(player.pos))
	for other: Mate in others:
		screens.append(cam.center_for(other.pos))
	var around: Vector2 = screens[randi() % screens.size()]
	var spot := arena.spawn_point_around(around, spawn_min + extra, spawn_max + extra, angle, edge)
	if screens.size() > 1:
		for _try in 10:
			var out_of_sight := true
			for screen: Vector2 in screens:
				if spot.distance_to(screen) < spawn_min - 1.0:
					out_of_sight = false
			if out_of_sight:
				break
			spot = arena.spawn_point_around(around, spawn_min + extra, spawn_max + extra, randf() * TAU, edge)
	return spot


func _simulate(dt: float) -> void:
	if state == State.PLAYING:
		time_alive += dt
		_tick_combo(dt)
	if not choosing():                           # (choosing a perk: the character waits)
		player.tick(dt)
	if player.alive:
		fog.reveal(player.pos, 1.0, coop.my_slot if coop != null else 0)
	if coop != null:
		for other: int in coop.mates.keys():      # what the others uncover is uncovered for you too
			var mate: Mate = coop.mates[other]
			if mate.has_state:
				fog.reveal(mate.pos, 1.0, other)
	if pet != null:
		pet.tick(dt)
	if is_client:
		enemies.tick_remote(dt)                  # the zombies are the host's: here they are copies
	else:
		director.tick(dt)
		enemies.tick(dt)
	projectiles.tick(dt)
	enemy_shots.tick(dt)
	pickups.tick(dt)
	fx.tick(dt)


func _tick_combo(dt: float) -> void:
	if combo > 0:
		combo_timer -= dt
		if combo_timer <= 0.0:
			combo = 0


func get_stats() -> Dictionary:
	var stats := {"score": score, "wave": director.wave, "kills": kills, "coins": coins_run, "time": time_alive,
			"xp": xp_run, "levels": levels_run, "map": map_index, "start": start_wave, "cleared": director.cleared,
			"victory": victory, "checkpoint": new_checkpoint, "unlocked": unlocked_map, "gear": gear_run,
			"chests": chests_run, "chests_total": pickups.chests.size(), "explored": fog.explored,
			"coop": not net.is_empty(), "mate": Net.mate_names() if not net.is_empty() else ""}
	# Together, the run's numbers are the host's count - the same for both, so
	# that all gold really is shared.
	if coop != null:
		for key: String in coop.shared.keys():
			stats[key] = coop.shared[key]
	return stats


# ----------------------------------------------------------------------------
#  Events
# ----------------------------------------------------------------------------
func _on_wave_started(wave: int, is_boss: bool) -> void:
	if coop != null and not is_client:
		coop.send([Coop.E_WAVE_START, wave, is_boss])
	if is_boss:
		hud.announce("BOSS WAVE", "wave %d - the gang's boss is coming for you" % wave, Color(1.0, 0.3, 0.2), 3.0)
	else:
		hud.announce("WAVE %d" % wave, "", Color(1.0, 0.95, 0.85))


func _on_wave_cleared(wave: int, coin_bonus: int) -> void:
	if coop != null:
		if not is_client:
			coop.send([Coop.E_WAVE_CLEAR, wave, coin_bonus])
		# A cleared wave puts a fallen player back on their feet.
		revive_local()
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
	# Run perks: FIELD DRESSING patches you up, and every few waves there is a new perk to choose.
	if player.alive and player.stats.wave_heal > 0.0 and player.hp < player.max_hp:
		player.heal(player.max_hp * player.stats.wave_heal)
		fx.text(player.pos + Vector2(0.0, -40.0), "FIELD DRESSING", Color(0.5, 1.0, 0.5), 16, 1.2)
	_owe_perks(Config.perks_earned(wave), Config.PERK_OFFER_DELAY)


# ----------------------------------------------------------------------------
#  Run perks: every Config.PERK_EVERY waves, a choice of three
# ----------------------------------------------------------------------------
## The run has earned `earned` perk choices in all: note the new ones as owed.
func _owe_perks(earned: int, delay: float) -> void:
	if earned <= _perks_given:
		return
	perks_owed += earned - _perks_given
	_perks_given = earned
	_perk_delay = delay


## True while this player's perk choice is on the screen.
func choosing() -> bool:
	return not perk_offer.is_empty()


## The most zombies that may be alive at once. Lower when FEWER EFFECTS is
## switched on (Settings) - here, or on the computer of anybody playing along:
## the host's zombies are shown on every computer, so the slowest one counts.
func max_alive() -> int:
	var fewer := bool(SaveData.get_setting("fewer_effects"))
	if coop != null:
		for other: int in coop.mates.keys():
			fewer = fewer or (coop.mates[other] as Mate).fewer
	return Config.FEWER_ENEMIES_ALIVE if fewer else Config.MAX_ENEMIES_ALIVE


## True while anybody still has a perk to choose: the next wave waits for it.
func perks_pending() -> bool:
	return perks_owed > 0 or (not perk_waiting_for().is_empty() and _perk_hold < Config.PERK_HOLD_MAX)


## (co-op) The names of the other players who are still choosing a perk.
func perk_waiting_for() -> Array[String]:
	var names: Array[String] = []
	if coop != null:
		for other: int in coop.mates.keys():
			var mate: Mate = coop.mates[other]
			if mate.choosing:
				names.append(mate.shown_name)
	return names


func _tick_perks(real_dt: float) -> void:
	_perk_hold = _perk_hold + real_dt if not perk_waiting_for().is_empty() else 0.0
	if perks_owed <= 0 or state != State.PLAYING:
		if perk_panel.visible:
			_close_perk_choice()
		return
	if perk_offer.is_empty():
		_perk_delay -= real_dt
		if _perk_delay <= 0.0 and not player.down:
			_offer_perks()
		return
	# The choice is showing: nothing can hurt the character, the pointer is free.
	player.invuln = maxf(player.invuln, 0.25)
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		GameInput.set_gameplay_mode(false)
	if together():
		perk_time_left -= real_dt
		if perk_time_left <= 0.0:
			choose_perk(randi() % perk_offer.size())


## Which perks could be offered right now, shuffled: not the ones at their
## limit, not the pet perk without a pet.
func roll_perk_offer() -> Array[String]:
	var pool: Array[String] = []
	for id: String in Config.RUN_PERK_ORDER:
		var perk: Dictionary = Config.RUN_PERKS[id]
		if int(perk["max"]) > 0 and int(perks.get(id, 0)) >= int(perk["max"]):
			continue
		if String(perk.get("needs", "")) == "pet" and player.stats.pet == "":
			continue
		pool.append(id)
	pool.shuffle()
	return pool.slice(0, Config.PERK_CHOICES)


func _offer_perks() -> void:
	perk_offer = roll_perk_offer()
	if perk_offer.is_empty():
		perks_owed = 0                    # (every perk is at its limit)
		return
	perk_time_left = Config.PERK_COOP_TIME
	perk_panel.show_offer(perk_offer, perks, perks_owed)
	GameInput.set_gameplay_mode(false)
	Sfx.play("level_up", -5.0)


## Take card number `index` of the choice on the table.
func choose_perk(index: int) -> void:
	if index < 0 or index >= perk_offer.size():
		return
	var id := perk_offer[index]
	var perk: Dictionary = Config.RUN_PERKS[id]
	perks[id] = int(perks.get(id, 0)) + 1
	perks_owed -= 1
	perk_offer = []
	player.refresh_stats()
	var level := int(perks[id])
	var color: Color = perk["color"]
	fx.ring(player.pos, 12.0, 150.0, 0.4, Color(color.r, color.g, color.b, 0.9))
	fx.text(player.pos + Vector2(0.0, -46.0), String(perk["name"]) + ("" if level == 1 else " " + Config.roman(level)), color, 20, 1.6)
	Sfx.play("ui_buy")
	if perks_owed > 0:
		_perk_delay = 0.2                 # (the next one follows at once)
		perk_panel.hide_offer()
	else:
		_close_perk_choice()


func _close_perk_choice() -> void:
	perk_offer = []
	perk_panel.hide_offer()
	if state == State.PLAYING or state == State.WON:
		GameInput.set_gameplay_mode(true)
		player.hold_fire(0.25)            # (the click on the card is not a shot)


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
	hud.announce("ZONE TAKEN BACK!", "%s is free   -   +%d coins   +%d XP" % [String(map["name"]), coins_bonus, xp_bonus],
			Color(1.0, 0.85, 0.3), 6.0)
	for k in 3:
		fx.ring(player.pos, 20.0 + 30.0 * k, 320.0 + 140.0 * k, 0.6 + 0.2 * k, Color(1.0, 0.85, 0.3, 0.9))
	fx.light(player.pos, 900.0, 0.6, Color(1.0, 0.8, 0.3, 0.7))
	shake(Config.BOSS_DEATH_SHAKE)
	Sfx.play("level_up")
	if coop != null and not is_client:
		coop.send_over(true)


func _on_boss_spawned(_boss: Enemy) -> void:
	if coop != null and not is_client:
		coop.send([Coop.E_BOSS])
	# (His own move is named with him: one short hint, like the tip a new kind of zombie gets.)
	var hint := String(Config.boss_move(map_index % Art.BOSS_VARIANTS).get("hint", ""))
	var under := "boss of the %s gang" % String(map.get("gang", ""))
	hud.announce(Config.boss_name(map_index), under if hint == "" else "%s  -  %s" % [under, hint], Color(1.0, 0.25, 0.2), 3.2 if hint != "" else 2.6)


## A zombie died (on the computer that runs the zombies). `killer` = the slot
## of the player who killed it (-1 = the player here). Everybody gets the XP;
## the weapon's own XP goes to whoever made the kill.
func on_enemy_killed(e: Enemy, dir: Vector2, kill_hitstop: float, source: String = "", killer: int = -1) -> void:
	var my_slot := coop.my_slot if coop != null else 0
	if killer < 0:
		killer = my_slot
	var by_mate := killer != my_slot
	kills += 1
	gain_xp(e.xp, "" if by_mate else source)
	_kill_feel(e, dir, 0.0 if by_mate else kill_hitstop, not by_mate)

	# Score with a combo multiplier for fast kills.
	combo += 1
	combo_timer = Config.COMBO_WINDOW
	score += int(round(e.score * Config.combo_multiplier(combo)))

	if coop != null:
		coop.send_kill(e, dir, kill_hitstop, source, killer)
	pickups.drop_from_enemy(e)
	director.on_enemy_killed(e)
	if e.kind == Config.BOSS:
		_boss_killed(e)


## (joiner) The host says a zombie died. `mine` = I killed it.
func on_remote_kill(id: int, at: Vector2, dir: Vector2, kind: int, variant: int, flags: int, xp: int, mine: bool,
		source: String, kill_hitstop: float) -> void:
	var e := enemies.remote_kill(id, at, kind, variant, flags)
	gain_xp(xp, source if mine else "")
	_kill_feel(e, dir, kill_hitstop if mine else 0.0, mine)
	if kind == Config.BOSS:
		_boss_killed(e)


## The gore and the jolt of a kill.
func _kill_feel(e: Enemy, dir: Vector2, kill_hitstop: float, mine: bool) -> void:
	# The PAYBACK perk: every few kills (anybody's) a little health back.
	if player.stats.kill_heal_every > 0 and player.alive and not player.down:
		_perk_kills += 1
		if _perk_kills >= player.stats.kill_heal_every:
			_perk_kills = 0
			player.heal(player.stats.kill_heal)
	# Gore: the body tumbles away, blood sprays and pools.
	if not bool(e.cfg.get("no_corpse", false)):
		fx.corpse(e, dir)
	fx.blood_burst(e.pos, int(Config.BLOOD_PER_KILL * e.blood), 1.0)
	fx.blood_spray(e.pos, dir, int(Config.BLOOD_PER_KILL * e.blood * 0.5), 1.4)
	decals.blood_splat(e.pos, 34.0 * sqrt(e.blood), dir)
	# Feel: freeze frame + shake, bigger for bigger zombies. (A partner's kill
	# far away does not shake your screen.)
	hitstop(kill_hitstop * e.hitstop_mult)
	if mine or e.pos.distance_to(player.pos) < 420.0:
		shake(Config.KILL_SHAKE * e.shake_mult * (1.0 if mine else 0.5))
		Sfx.play("zombie_die")
	else:
		Sfx.play("zombie_die", -10.0)


func _boss_killed(e: Enemy) -> void:
	enemy_shots.sweeps.clear()      # (a dead boss does not finish his swing)
	# A boss death is an event: slow motion, a huge burst, and a reward crate.
	for k in 5:
		var at := e.pos + Vector2.from_angle(randf() * TAU) * randf_range(10.0, 60.0)
		decals.blood_splat(at, randf_range(70.0, 120.0))
		fx.blood_burst(at, 14, 1.8)
	fx.ring(e.pos, 30.0, 420.0, 0.6, Color(1.0, 0.3, 0.2, 0.9))
	fx.ring(e.pos, 20.0, 260.0, 0.45, Color(1.0, 0.9, 0.6, 0.9))
	fx.light(e.pos, 700.0, 0.4, Color(1.0, 0.5, 0.3, 0.8))
	fx.text(e.pos + Vector2(0, -70), "BOSS DOWN!", Color(1.0, 0.85, 0.3), 34, 1.8)
	if not is_client:
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


func _on_reload_pressed() -> void:
	if state == State.PLAYING and not get_tree().paused:
		player.start_reload()


# ----------------------------------------------------------------------------
#  Pickups
# ----------------------------------------------------------------------------
func collect_coin(at: Vector2, with_feedback: bool) -> void:
	if not is_client:
		coins_run += coin_value      # (the joiner's count comes from the host: all gold is shared)
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


## A treasure chest is opened: a piece of gear (straight into the bag, kept
## even if you die) and a fountain of coins.
## (Together, whoever opens it, BOTH players get the piece: `key` is the piece
## the host rolled, handed to the joiner.)
func open_chest(chest: Pickups.Chest, key: String = "") -> void:
	chest.opened = true
	chest.found = true
	chests_run += 1
	SaveData.chests_opened += 1
	if key == "":
		key = pickups.roll_chest_gear()
		pickups.spawn_coins(chest.pos, randi_range(Config.CHEST_COINS_MIN, Config.CHEST_COINS_MAX))
		if coop != null:
			coop.send([Coop.E_CHEST, pickups.chests.find(chest), key])
	SaveData.add_gear(key)
	gear_run.append(key)
	var color: Color = Config.gear_tier_def(Config.gear_tier_of(key))["color"]
	fx.text(player.pos + Vector2(0, -72), "TREASURE!", Color(1.0, 0.85, 0.3), 18, 2.2)
	fx.text(player.pos + Vector2(0, -46), Config.gear_name(key), color, 26, 2.2)
	fx.ring(chest.pos, 16.0, 200.0, 0.5, Color(1.0, 0.85, 0.3, 0.95))
	fx.ring(chest.pos, 10.0, 130.0, 0.4, Color(color.r, color.g, color.b, 0.9))
	fx.light(chest.pos, 380.0, 0.4, Color(1.0, 0.8, 0.3, 0.7))
	fx.sparks(chest.pos, Vector2.UP, 10)
	shake(Config.CHEST_OPEN_SHAKE)
	hitstop(Config.CHEST_OPEN_HITSTOP, true)
	Sfx.play("chest_open")


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
		if coop != null and not coop.mates.is_empty():
			_player_down()        # together: you fall, and another player can pick you up
		else:
			_player_died()


## SECOND WIND keystone: the blow that should have killed you does not.
func _second_wind() -> void:
	player.second_wind_used = true
	player.hp = player.max_hp * player.stats.second_wind
	player.invuln = Config.SECOND_WIND_INVULN
	enemies.shockwave(player.pos, Config.SECOND_WIND_BURST_RADIUS, Config.SECOND_WIND_BURST_FORCE, 0.0, Config.SECOND_WIND_BURST_STAGGER)
	fx.ring(player.pos, 20.0, Config.SECOND_WIND_BURST_RADIUS, 0.45, Color(0.95, 0.3, 0.3, 0.95))
	fx.light(player.pos, Config.SECOND_WIND_BURST_RADIUS * 2.4, 0.35, Color(1.0, 0.3, 0.3, 0.7))
	fx.text(player.pos + Vector2(0, -48), "SECOND WIND!", Color(1.0, 0.45, 0.45), 28, 1.4)
	slow_motion(Config.BOSS_DEATH_SLOWMO, 0.6)
	Sfx.play("second_wind")


# ----------------------------------------------------------------------------
#  Co-op: falling, being picked up, the end of a shared run
# ----------------------------------------------------------------------------
## Out of health with other players still in the game: you lie where you fell
## until one of them picks you up (or the wave is cleared). Zombies leave you alone.
func _player_down() -> void:
	player.alive = false
	player.down = true
	player.reloading = false
	fx.blood_burst(player.pos, 30, 1.5)
	decals.blood_splat(player.pos, 80.0)
	fx.ring(player.pos, 10.0, 200.0, 0.5, Color(1.0, 0.2, 0.15, 0.8))
	shake(Config.DEATH_SHAKE * 0.6)
	hitstop(Config.DEATH_HITSTOP, true)
	hud.announce("YOU ARE DOWN", "%s can pick you up by standing beside you" % coop.names(), Color(1.0, 0.3, 0.25), 4.0)
	Sfx.play("player_die")


## Back on your feet (another player picked you up, or the wave was cleared).
func revive_local() -> void:
	if not player.down or state != State.PLAYING:
		return
	player.down = false
	player.alive = true
	player.hp = player.max_hp * Config.COOP_REVIVE_HP
	player.invuln = Config.COOP_REVIVE_INVULN
	player.hold_fire(0.2)
	fx.ring(player.pos, 12.0, 170.0, 0.45, Color(0.5, 1.0, 0.55, 0.9))
	fx.light(player.pos, 300.0, 0.3, Color(0.5, 1.0, 0.55, 0.6))
	hud.announce("BACK ON YOUR FEET", "", Color(0.5, 1.0, 0.55), 1.8)
	Sfx.play("medkit")


## (host) Every player is down: the run is lost. Everybody gets the same numbers.
func wipe() -> void:
	coop.send_over(false)
	_player_died()


## (joiner) The host says the run has ended.
func finish_from_host(shared: Dictionary) -> void:
	if not bool(shared.get("victory", false)) and state == State.PLAYING:
		_player_died()


## (joiner) Messages from the host about the waves.
func remote_wave_started(wave: int, is_boss: bool) -> void:
	director.wave = wave
	_on_wave_started(wave, is_boss)
	Sfx.play("wave_start")


func remote_wave_cleared(wave: int, coin_bonus: int) -> void:
	director.cleared = wave
	_on_wave_cleared(wave, coin_bonus)
	Sfx.play("wave_clear")


func remote_boss_spawned() -> void:
	_on_boss_spawned(null)
	Sfx.play("boss_roar")


## A player has gone from the run. If it was the host, the world was theirs,
## so the run ends here for everybody else (with everything earned so far).
## Otherwise the rest play on.
func mate_left(who: String, world_gone: bool) -> void:
	if state != State.PLAYING:
		return
	if is_client and world_gone:
		hud.announce("%s HAS LEFT" % who, "the run ends here - you keep what you earned", Color(1.0, 0.6, 0.4), 3.0)
		_player_died()
		return
	hud.announce("%s HAS LEFT" % who, "" if together() else "you are on your own now", Color(1.0, 0.6, 0.4), 3.0)
	if not is_client and player.down and coop.mates.is_empty():
		_player_died()


## The other player paused or resumed: do the same here.
func main_paused_by_mate(paused: bool) -> void:
	var app := get_parent() as Main
	if app != null:
		app.mate_paused(paused)


func _player_died() -> void:
	state = State.DYING
	player.alive = false
	player.visible = player.die_look()          # (he goes down in pictures, if he has them)
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
	cam.add_trauma(amount)


## Run the world at `speed` (1 = normal) for `duration` real seconds.
func slow_motion(speed: float, duration: float) -> void:
	if state != State.PLAYING or coop != null:
		return        # (together there is no slow motion: it would slow the world for one player only)
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
