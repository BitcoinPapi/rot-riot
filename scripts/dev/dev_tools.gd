class_name DevTools
extends Node
## Developer helpers, only active when the game is started with extra
## command-line arguments after "--". Players never see this.
##
##   --play             skip the menu and start a run
##   --bot              start a run and let a simple bot play (through GameInput's virtual sticks)
##   --screen=NAME      open a menu screen (maps, character, armory, settings, pause, gameover, victory) for screenshots
##   --map=N            play map N (unlocks it); --best=W sets the best wave cleared there, --start=W the starting wave
##   --level=N          start as a level N character with points to spend (for screenshots)
##   --armory-weapon=ID with --screen=armory: show this weapon
##   --weapon=ID        the bot starts with this weapon (pistol, shotgun, ...)
##   --dual             ...one in each hand (if that weapon allows it)
##   --keep-weapon      ...and it never runs out
##   --cycle            the bot is handed each weapon in turn every 6 seconds
##   --wave=N           jump straight to wave N
##   --god              the player cannot die
##   --frames=N         quit after N frames and print a summary
##   --autotest         play through the whole game loop automatically and report PASS/FAIL
##   --inputtest        feed fake keyboard / mouse / gamepad events through GameInput and check them
##   --bench=N          keep N zombies alive around the player and report simulation time
##                      (add --weapon=ID --no-crates --no-rage to compare weapons fairly)
##   --no-crates        no weapon crates appear (works with --bot too)
##   --no-rage          the bot never uses rage
##   --gallery=PREFIX   show every generated sprite whose name starts with PREFIX, enlarged
##                      (--gallery-scale=N to change the size) - for checking art
##   --dump-sfx=DIR     write every generated sound to DIR as .wav files, then quit
##   --coins=N          start with N coins (dev runs use a throwaway save file,
##                      never the player's real one, unless --real-save is given)
##   --shot=PATH        save a screenshot to PATH ...
##   --shot-frame=N     ... on frame N (default 30), then quit

var main: Node
var _args := {}
var _frame := 0
var _bench_samples := PackedInt32Array()
var _auto_bot := false
var _auto_failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	# Developer runs never touch the player's real save file.
	if not _args.has("real-save"):
		SaveData.save_path = "user://dev_save.json"
		if FileAccess.file_exists(SaveData.save_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.save_path))
		SaveData.call("_reset_to_defaults")
		SaveData.apply_settings()
		if _args.has("coins"):
			SaveData.add_coins(int(_args["coins"]))
		if _args.has("level"):
			for i in int(_args["level"]) - 1:
				SaveData.add_xp(SaveData.xp_needed())
			SaveData.add_xp(int(SaveData.xp_needed() * 0.4))
			for i in 3:
				SaveData.raise_passive("vitality")
				SaveData.raise_passive("strength")
			SaveData.raise_passive("evasion")
			SaveData.add_weapon_xp("pistol", 2500)
			SaveData.add_weapon_xp("shotgun", 900)
			SaveData.add_weapon_xp("launcher", 200)
			SaveData.raise_weapon_track("pistol", "power")
			SaveData.raise_weapon_track("pistol", "power")
			SaveData.raise_weapon_track("shotgun", "spawn")
		if _args.has("map"):
			var map_index := clampi(int(_args["map"]) - 1, 0, Config.MAPS.size() - 1)
			SaveData.maps_unlocked = maxi(SaveData.maps_unlocked, map_index + 1)
			for i in map_index:
				SaveData.map_best[i] = Config.WAVES_PER_MAP
			SaveData.map_best[map_index] = clampi(int(_args.get("best", "0")), 0, Config.WAVES_PER_MAP)
			SaveData.select_map(map_index, int(_args.get("start", "1")))
	if _args.has("gallery"):
		_show_gallery.call_deferred()
	if _args.has("autotest"):
		_run_autotest.call_deferred()
	if _args.has("inputtest"):
		_run_inputtest.call_deferred()


func _process(_delta: float) -> void:
	_frame += 1
	var app: Main = main
	if _frame == 1 and (_args.has("bot") or _args.has("play") or _args.has("bench")):
		app.start_run()
	if _args.has("screen") and _frame == int(_args.get("screen-frame", "10")):
		_open_screen(app, String(_args["screen"]))
	if _args.has("dump-sfx") and Sfx.ready_to_play:
		var streams: Dictionary = Sfx.get_streams()
		for sound: String in streams.keys():
			var wav := streams[sound] as AudioStreamWAV
			if wav != null:
				wav.save_to_wav("%s/%s.wav" % [String(_args["dump-sfx"]), sound])
		print("dumped %d sounds at frame %d" % [streams.size(), _frame])
		_quit(0)
		return
	var game: Game = app.game
	if game != null and is_instance_valid(game):
		if _args.has("wave") and _frame == 2:
			game.director.wave = int(_args["wave"]) - 1
			game.director.intermission = 0.1
		if _args.has("god"):
			game.player.hp = game.player.max_hp
		if _args.has("bot") or _auto_bot:
			_bot(game)
		if _args.has("bench"):
			_bench(game)
	if _args.has("shot") and _frame == int(_args.get("shot-frame", "30")):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(String(_args["shot"]))
		print("screenshot saved: ", _args["shot"], " ", img.get_size())
		_quit(0)
	if _args.has("frames") and _frame >= int(_args["frames"]):
		if game != null and is_instance_valid(game):
			print("SUMMARY frames=%d time=%.0fs wave=%d kills=%d score=%d coins=%d alive=%d left=%d hp=%.0f rage=%.0f weapon=%s boss=%s state=%d" % [
				_frame, game.time_alive, game.director.wave, game.kills, game.score, game.coins_run, game.enemies.alive_count,
				game.director.remaining(), game.player.hp, game.rage, game.player.weapon_id,
				str(game.director.boss_alive()), game.state])
			var weapon_levels: Array = []
			for id: String in Config.WEAPON_ORDER:
				weapon_levels.append("%s %d" % [id, SaveData.weapon_level(id)])
			print("PROGRESS xp_run=%d level=%d skill_points=%d weapons=[%s]" % [
				game.xp_run, SaveData.level, SaveData.skill_points, ", ".join(weapon_levels)])
		_quit(0)


func _quit(code: int) -> void:
	set_process(false)
	(main as Main).quit_game(code)


func _bot(game: Game) -> void:
	var p := game.player
	if _args.has("weapon") and _frame == 2:
		var wanted := String(_args["weapon"])
		if wanted != Config.STARTER_WEAPON:
			p.give_weapon(wanted)
		if _args.has("dual"):
			p.give_weapon(wanted)
	if _args.has("keep-weapon") and p.weapon_time_max > 0.0:
		p.weapon_time = p.weapon_time_max
	if _args.has("no-crates"):
		game.pickups.crates.clear()
		game.pickups.set("_crate_timer", 9999.0)
	if _args.has("cycle") and _frame % 360 == 5:
		var order: Array = Config.WEAPON_ORDER
		p.give_weapon(String(order[int(_frame / 360.0) % order.size()]))
	if game.rage_ready() and not _args.has("no-rage"):
		GameInput.press_rage()
	var target := game.enemies.nearest(p.pos, 900.0)
	var aim := Vector2.RIGHT
	var fire := false
	var move := Vector2.from_angle(_frame * 0.013)
	var hunting_boss := false
	if game.director.boss_alive():
		# Go and fight the boss, but deal with anything that gets too close first.
		var boss := game.director.boss
		var close := game.enemies.nearest(p.pos, 120.0)
		target = close if close != null else boss
		if boss.pos.distance_to(p.pos) > 420.0:
			move = (boss.pos - p.pos).normalized()
			hunting_boss = true
	if target != null:
		aim = (target.pos - p.pos).normalized()
		fire = true
		if target.pos.distance_to(p.pos) < 170.0:
			move = ((p.pos - target.pos).normalized() + move * 0.5).normalized()
		elif not hunting_boss and not game.pickups.crates.is_empty():
			move = (game.pickups.crates[0].pos - p.pos).normalized()
	GameInput.set_virtual_input(move, aim, fire)


func _open_screen(app: Main, screen: String) -> void:
	match screen:
		"pause":
			app.pause_game()
		"gameover":
			if app.game != null:
				app.game.player.invuln = 0.0
				app.game.damage_player(99999.0, app.game.player.pos + Vector2.RIGHT)
		"victory":
			if app.game != null:
				_finish_wave(app.game, Config.WAVES_PER_MAP)
		_:
			app.open_screen(screen)
			if screen == "armory" and _args.has("armory-weapon"):
				var screens: Dictionary = app.get("_screens")
				(screens["armory"] as ArmoryScreen).call("_select", String(_args["armory-weapon"]))


## Pretend the player just killed the last zombie of `wave`.
func _finish_wave(game: Game, wave: int) -> void:
	game.enemies.clear_all()
	game.director.wave = wave
	game.director.in_wave = true
	game.director.to_spawn = 0
	game.director.set("_boss_delay", -1.0)


## Performance test: hold a fixed horde around the player while the bot shoots.
func _bench(game: Game) -> void:
	var target := int(_args["bench"])
	game.director.intermission = 99999.0
	game.director.in_wave = false
	game.player.hp = game.player.max_hp
	if _frame == 3 and not _args.has("weapon"):
		game.player.give_weapon("machinegun")     # (--weapon is handled by the bot)
	if game.player.weapon_time_max > 0.0:
		game.player.weapon_time = 99.0
	var p := game.player.pos
	while game.enemies.alive_count < target:
		var roll := randf()
		var kind: int = Config.SHAMBLER
		if roll > 0.93:
			kind = Config.BRUTE
		elif roll > 0.7:
			kind = Config.RUNNER
		var at := p + Vector2.from_angle(randf() * TAU) * randf_range(260.0, 620.0)
		game.enemies.spawn(kind, game.arena.clamp_inside(at, 30.0))
	if not _args.has("bot"):
		_bot(game)
	if _frame > 240:
		_bench_samples.append(game.sim_usec)
	if _frame == 240 + int(_args.get("bench-frames", "900")):
		var sorted := Array(_bench_samples)
		sorted.sort()
		var total := 0
		for v: int in sorted:
			total += v
		print("BENCH enemies=%d frames=%d sim avg=%.2fms p95=%.2fms max=%.2fms (60 fps budget is 16.6 ms) kills=%d fps=%d" % [
			target, sorted.size(), total / float(sorted.size()) / 1000.0,
			sorted[int(sorted.size() * 0.95)] / 1000.0, sorted[sorted.size() - 1] / 1000.0,
			game.kills, Engine.get_frames_per_second()])
		print("BENCH weapon=%s dual=%s shots=%d time_alive=%.1fs" % [game.player.weapon_id, str(game.player.dual),
			game.projectiles.spawned_total, game.time_alive])
		print("BENCH draw_calls=%d objects=%d primitives=%d" % [
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
		_quit(0)


# ----------------------------------------------------------------------------
#  Automated playthrough: menu -> shop -> settings -> run (every weapon, rage,
#  pause, boss) -> death -> game over -> play again -> quit to menu -> save file.
# ----------------------------------------------------------------------------
func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Wait until `condition` is true (or `max_frames` pass), keeping the player
## alive meanwhile. Game updates can be held up for a few frames by hit stop,
## so checks on game state wait for it instead of counting frames.
func _until(condition: Callable, max_frames: int = 90) -> void:
	var app: Main = main
	for i in max_frames:
		if condition.call():
			return
		if app.game != null and is_instance_valid(app.game) and app.game.player.alive:
			app.game.player.hp = maxf(app.game.player.hp, app.game.player.max_hp * 0.5)
		await get_tree().process_frame


func _check(condition: bool, what: String) -> void:
	if condition:
		print("  ok   - ", what)
	else:
		print("  FAIL - ", what)
		_auto_failures.append(what)


func _run_autotest() -> void:
	var app: Main = main
	print("AUTOTEST start")
	# (DevTools already switched to a throwaway save file, so real progress is never touched.)
	SaveData.call("_reset_to_defaults")
	await _frames(5)
	_check(app.state == Main.State.MENU and app.game == null, "starts on the main menu")

	# --- settings ---
	app.open_screen("settings")
	await _frames(3)
	SaveData.set_setting("master_volume", 0.5)
	SaveData.set_setting("screen_shake", 0.5)
	app.close_screen()
	await _frames(2)
	_check(is_equal_approx(float(SaveData.get_setting("master_volume")), 0.5), "settings change is stored")

	# --- character screen: skill points and passive stats ---
	app.open_screen("character")
	await _frames(3)
	_check(not SaveData.raise_passive("strength"), "cannot raise a stat with 0 skill points")
	_check(not SaveData.buy_skill_point(), "cannot buy a skill point with 0 coins")
	SaveData.add_coins(1000)
	var before := SaveData.coins
	var price := SaveData.skill_point_price()
	_check(SaveData.buy_skill_point() and SaveData.skill_points == 1, "coins buy a skill point")
	_check(SaveData.coins == before - price and SaveData.skill_point_price() > price, "the price is paid and the next point costs more")
	_check(SaveData.raise_passive("vitality") and SaveData.passive_rank("vitality") == 1 and SaveData.skill_points == 0,
			"a skill point raises a passive stat")
	SaveData.buy_skill_point()
	SaveData.raise_passive("strength")
	_check(SaveData.spent_points() == 2, "spent points are counted")
	app.close_screen()
	await _frames(2)

	# --- armory screen: weapon levels and weapon points ---
	app.open_screen("armory")
	await _frames(3)
	_check(not SaveData.raise_weapon_track("shotgun", "power"), "cannot upgrade a weapon with 0 weapon points")
	var shotgun_levels := SaveData.add_weapon_xp("shotgun", SaveData.weapon_xp_needed("shotgun"))
	_check(shotgun_levels == 1 and SaveData.weapon_level("shotgun") == 2 and SaveData.weapon_points("shotgun") == 1,
			"weapon XP gives a weapon level and a weapon point")
	_check(SaveData.raise_weapon_track("shotgun", "power") and float(PlayerStats.weapon_mods("shotgun")["damage"]) > 1.0,
			"a weapon point raises that weapon's power")
	_check(is_equal_approx(float(PlayerStats.weapon_mods("pistol")["damage"]), 1.0), "other weapons are not affected")
	_check(Config.weapon_tracks("pistol") == ["power", "speed", "stability", "reload"], "the pistol has no crate-only upgrades")
	_check(Config.weapon_tracks("shotgun").size() == 6, "crate guns have all six upgrades")
	_check(Config.weapon_tracks("sledge") == ["power", "speed", "spawn", "duration"], "melee weapons have no stability or reload upgrade")
	_check(Config.weapon_tracks("launcher") == ["power", "stability", "reload", "spawn", "duration"],
			"the launcher's rate of fire is its reload upgrade")
	app.close_screen()
	await _frames(2)

	# --- start a run ---
	app.start_run()
	await _frames(10)
	var game := app.game
	_check(app.state == Main.State.PLAYING and game != null, "Play starts a run")
	_check(game.player.max_hp > Config.PLAYER_MAX_HP, "vitality applies in the run")
	_check(game.player.stats.damage_mult > 1.0, "strength applies in the run")

	# --- defense, evasion, level up (checked directly, before the fighting starts) ---
	game.director.intermission = 99999.0
	var hp_before := game.player.hp
	SaveData.passives["defense"] = 50          # 50 ranks = 40% less damage
	game.player.refresh_stats()
	game.damage_player(10.0, game.player.pos + Vector2.RIGHT)
	_check(is_equal_approx(hp_before - game.player.hp, 6.0), "defense reduces damage taken (10 -> %.1f)" % (hp_before - game.player.hp))
	SaveData.passives["defense"] = 0
	game.player.refresh_stats()
	game.player.stats.evasion = 1.0
	game.player.invuln = 0.0
	hp_before = game.player.hp
	game.damage_player(50.0, game.player.pos + Vector2.RIGHT)
	_check(is_equal_approx(game.player.hp, hp_before), "evasion dodges the hit completely")
	game.player.refresh_stats()
	game.player.invuln = 0.0
	var level_before := SaveData.level
	var points_before := SaveData.skill_points
	var max_hp_before := game.player.max_hp
	game.gain_xp(SaveData.xp_needed() - SaveData.xp, "")
	_check(SaveData.level == level_before + 1 and SaveData.skill_points == points_before + Config.SKILL_POINTS_PER_LEVEL,
			"enough XP levels the character up and gives a skill point")
	_check(game.player.max_hp > max_hp_before, "a level up raises max health straight away")
	game.director.intermission = 0.5
	_auto_bot = true
	await _frames(240)
	_check(game.director.wave >= 1, "first wave starts")

	# --- every weapon fires without errors ---
	for id: String in Config.WEAPON_ORDER:
		game.player.give_weapon(id)
		game.player.hp = game.player.max_hp
		await _frames(200)
		print("  ...  - used weapon '%s' (kills so far: %d)" % [id, game.kills])
	_check(game.kills > 0, "zombies were killed (%d)" % game.kills)

	# --- dual wielding ---
	var pl := game.player
	pl.give_weapon("shotgun")
	_check(pl.weapon_id == "shotgun" and not pl.dual, "the first shotgun is held alone")
	pl.give_weapon("shotgun")
	_check(pl.dual and pl.weapon_label() == "DUAL SHOTGUN", "a second shotgun gives dual shotguns")
	pl.give_weapon("rifle")
	pl.give_weapon("rifle")
	_check(pl.weapon_id == "rifle" and not pl.dual, "two-handed weapons cannot be dual wielded")
	pl.give_weapon("pistol")
	_check(pl.weapon_id == "pistol" and pl.dual and pl.weapon_time > 0.0, "a pistol crate gives dual pistols for a while")
	pl.hp = pl.max_hp
	await _frames(60)
	pl.weapon_time = 0.02
	await _until(func() -> bool: return not pl.dual)
	_check(pl.weapon_id == "pistol" and not pl.dual and pl.weapon_time <= 0.0, "dual pistols run out back to one pistol")

	# --- reloading ---
	var waited := 0
	_auto_bot = false
	GameInput.set_virtual_input(Vector2.ZERO, Vector2.RIGHT, false)
	pl.give_weapon("smg")
	var smg_mag: int = Config.WEAPONS["smg"]["mag"]
	_check(pl.mag_size == smg_mag and pl.ammo == smg_mag, "a picked-up gun has a full magazine")
	pl.ammo = 2
	GameInput.set_virtual_input(Vector2.ZERO, Vector2.RIGHT, true)
	waited = 0
	while not pl.reloading and waited < 120:
		pl.hp = pl.max_hp
		await _frames(1)
		waited += 1
	_check(pl.reloading and pl.ammo == 0, "an empty magazine starts a reload by itself")
	var shots_before := game.projectiles.spawned_total
	await _frames(10)
	_check(game.projectiles.spawned_total == shots_before, "the gun cannot fire during a magazine swap")
	waited = 0
	while pl.reloading and waited < 300:
		pl.hp = pl.max_hp
		await _frames(1)
		waited += 1
	_check(not pl.reloading and pl.ammo > 0, "the reload finishes with a fresh magazine (%d frames)" % waited)
	GameInput.set_virtual_input(Vector2.ZERO, Vector2.RIGHT, false)
	await _frames(3)
	pl.ammo = 5
	pl.reloading = false
	GameInput.press_reload()
	await _frames(2)
	_check(pl.reloading, "the reload button reloads a part-used magazine")
	pl.refill_ammo()
	GameInput.press_reload()
	await _frames(2)
	_check(not pl.reloading, "a full magazine is not reloaded")
	pl.give_weapon("shotgun")
	pl.ammo = 0
	pl.start_reload()
	waited = 0
	while pl.ammo < 2 and waited < 200:
		pl.hp = pl.max_hp
		await _frames(1)
		waited += 1
	_check(pl.reloading and pl.ammo == 2, "the shotgun loads one shell at a time")
	GameInput.set_virtual_input(Vector2.ZERO, Vector2.RIGHT, true)
	pl.fire_cd = 0.0
	await _until(func() -> bool: return not pl.reloading or pl.ammo < 2)
	_check(not pl.reloading or pl.ammo < 2, "firing cuts a shell-by-shell reload short")
	GameInput.set_virtual_input(Vector2.ZERO, Vector2.RIGHT, false)
	pl.give_weapon("sledge")
	_check(pl.mag_size == 0 and not pl.reloading, "melee weapons never reload")
	pl.give_weapon("pistol")
	pl.give_weapon("pistol")
	var pistol_mag: int = Config.WEAPONS["pistol"]["mag"]
	_check(pl.mag_size == pistol_mag * Config.DUAL_MAG_MULT, "dual wielding has two magazines")
	# The RELOAD SPEED upgrade shortens that weapon's reload (and only that weapon's).
	pl.give_weapon("smg")
	pl.ammo = 1
	pl.start_reload()
	var slow_reload: float = pl.get("_reload_total")
	SaveData.add_weapon_xp("smg", 100000)
	for i in 5:
		SaveData.raise_weapon_track("smg", "reload")
	pl.give_weapon("smg")
	pl.ammo = 1
	pl.start_reload()
	var fast_reload: float = pl.get("_reload_total")
	_check(SaveData.weapon_rank("smg", "reload") == 5 and fast_reload < slow_reload * 0.9,
			"the RELOAD SPEED upgrade shortens the reload (%.2fs -> %.2fs)" % [slow_reload, fast_reload])
	_check(is_equal_approx(float(PlayerStats.weapon_mods("rifle")["reload"]), 1.0), "other weapons keep their own reload speed")
	pl.refill_ammo()
	_auto_bot = true

	# --- wounded looks ---
	var hurt := game.enemies.spawn(Config.BRUTE, game.arena.clamp_inside(pl.pos + Vector2(-400, 0), 40.0))
	_check(not hurt.wounded, "a fresh zombie is not wounded")
	game.enemies.damage(hurt, hurt.max_hp * 0.75, Vector2.RIGHT, 0.0, 0.0, 0.0)
	_check(hurt.alive and hurt.wounded and hurt.tex_normal == hurt.tex_hurt, "a zombie under 30% health shows its wounds")
	pl.hp = pl.max_hp * 0.2
	pl.invuln = 5.0
	for i in 60:
		if pl.wounded:
			break
		pl.hp = pl.max_hp * 0.2
		pl.invuln = 5.0
		await _frames(1)
	_check(pl.wounded, "the player looks battle-worn under 30% health")
	pl.hp = pl.max_hp
	pl.invuln = 0.0
	await _until(func() -> bool: return not pl.wounded)
	_check(not pl.wounded, "and recovers the normal look when healed")

	# --- crate rarity ---
	_check(Config.crate_weight("launcher") < Config.crate_weight("machinegun")
			and Config.crate_weight("machinegun") < Config.crate_weight("shotgun"), "rarer weapons are less likely to be in a crate")

	# --- burning ---
	var torch := game.enemies.spawn(Config.BRUTE, game.arena.clamp_inside(pl.pos + Vector2(400, 0), 40.0))
	var torch_hp := torch.hp
	game.enemies.ignite(torch, 2.0, 30.0, "flamethrower")
	for i in 30:
		pl.hp = pl.max_hp
		await _frames(1)
	_check(not torch.alive or torch.hp < torch_hp - 5.0, "a burning zombie keeps losing health")
	_check(game.score > 0, "score went up (%d)" % game.score)

	# --- pause / resume ---
	GameInput.press_pause()
	await _frames(3)
	_check(app.state == Main.State.PAUSED and get_tree().paused, "Esc pauses the game")
	var kills_at_pause := game.kills
	app.open_screen("settings")
	await _frames(20)
	GameInput.back_pressed.emit()
	await _frames(3)
	_check(app.state == Main.State.PAUSED, "Back from settings returns to the pause menu")
	_check(game.kills == kills_at_pause, "nothing happens while paused")
	GameInput.press_pause()
	await _frames(3)
	_check(app.state == Main.State.PLAYING and not get_tree().paused, "Esc again resumes")

	# --- rage ---
	game.player.hp = game.player.max_hp
	game.rage_active = false          # (the bot may have triggered rage itself a moment ago)
	game.rage = Config.RAGE_MAX
	game.player.give_weapon("smg")
	game.player.ammo = 1
	GameInput.press_rage()
	await _frames(2)
	_check(game.rage_active, "rage activates when the meter is full")
	_check(game.player.ammo >= game.player.mag_size - 3, "activating rage refills the magazine")
	# Hit stops freeze game time, so rage lasts a little longer in real frames.
	waited = 0
	while game.rage_active and waited < int(Config.RAGE_DURATION * 60.0) * 2:
		game.player.hp = game.player.max_hp
		await _frames(1)
		waited += 1
	_check(not game.rage_active and waited >= int(Config.RAGE_DURATION * 60.0) - 5, "rage ends after its duration (%d frames)" % waited)

	# --- boss wave ---
	game.player.hp = game.player.max_hp
	game.enemies.clear_all()
	game.director.to_spawn = 0
	game.director.wave = Config.BOSS_EVERY - 1
	waited = 0
	while not game.director.boss_alive() and waited < 900:
		game.player.hp = game.player.max_hp
		await _frames(1)
		waited += 1
	_check(game.director.boss_alive(), "boss appears on wave %d" % Config.BOSS_EVERY)
	if game.director.boss_alive():
		var boss := game.director.boss
		# Fire one bullet straight at it from close by (bosses are too big for
		# the zombie grid and are hit through a separate check).
		var boss_hp := boss.hp
		var muzzle := boss.pos + Vector2(boss.radius + 60.0, 0.0)
		game.projectiles.spawn(muzzle, Vector2.LEFT, Config.WEAPONS["pistol"], "pistol", 25.0, 0.0)
		await _frames(6)
		_check(boss.hp < boss_hp, "bullets hurt the boss")
		# Let it run its charge / summon logic for a while, then finish it off.
		for i in 600:
			game.player.hp = game.player.max_hp
			await _frames(1)
		if boss.alive and boss.is_big:
			game.enemies.damage(boss, boss.hp + 1.0, Vector2.RIGHT, 0.0, 0.0, 0.0)
		await _frames(5)
		_check(not game.director.boss_alive(), "boss can be killed")
		_check(not game.pickups.crates.is_empty() or game.player.weapon_id != Config.STARTER_WEAPON, "boss drops a weapon crate")

	# --- death and game over ---
	_auto_bot = false
	GameInput.clear_virtual_input()
	var coins_in_run := game.coins_run
	var saved_coins := SaveData.coins
	game.player.invuln = 0.0     # (a zombie may have just hit the bot; skip the safety window)
	game.damage_player(99999.0, game.player.pos + Vector2.RIGHT)
	_check(game.state == Game.State.DYING, "player dies at 0 health")
	waited = 0
	while app.state != Main.State.GAME_OVER and waited < 600:
		await _frames(1)
		waited += 1
	_check(app.state == Main.State.GAME_OVER, "game-over screen appears")
	_check(SaveData.coins == saved_coins + coins_in_run, "coins from the run are banked (%d)" % coins_in_run)
	_check(SaveData.runs_played == 1 and SaveData.best_score > 0, "run is recorded")
	await _frames(60)

	# --- play again, then quit to menu from pause ---
	app.start_run()
	await _frames(30)
	_check(app.state == Main.State.PLAYING and app.game != game, "Play Again starts a fresh run")
	app.pause_game()
	await _frames(3)
	app.quit_to_menu()
	await _frames(5)
	_check(app.state == Main.State.MENU and app.game == null and not get_tree().paused, "Quit to Menu returns to the main menu")
	_check(SaveData.runs_played == 2, "abandoned run is still recorded")

	# --- maps: checkpoints, clearing a map, the next and tougher map ---
	var every: int = Config.CHECKPOINT_EVERY
	var last_wave: int = Config.WAVES_PER_MAP
	_check(Config.checkpoint_waves(0) == [1] and Config.checkpoint_waves(every - 1) == [1], "no later starting wave before a boss is beaten")
	_check(Config.checkpoint_waves(every) == [1, every + 1] and Config.checkpoint_waves(every * 2 + 2) == [1, every + 1, every * 2 + 1],
			"each boss beaten unlocks the next starting wave")
	var all_starts := Config.checkpoint_waves(last_wave)
	_check(all_starts[all_starts.size() - 1] == last_wave - every + 1, "the last starting wave is just before the final boss")
	SaveData.map_best[0] = 0
	SaveData.maps_unlocked = 1
	SaveData.select_map(0, 1)
	_check(not SaveData.map_unlocked(1) and not SaveData.select_map(1, 1), "map 2 starts locked")
	_check(not SaveData.select_map(0, every + 1), "a starting wave that is not unlocked is refused")
	app.open_screen("maps")
	await _frames(3)
	app.start_run(0, 1)
	await _frames(10)
	game = app.game
	_check(app.state == Main.State.PLAYING and game.map_index == 0 and game.start_wave == 1, "the map screen starts a run on map 1")
	game.director.intermission = 99999.0
	_finish_wave(game, every)
	await _until(func() -> bool: return game.director.cleared == every)
	_check(SaveData.map_best_wave(0) == every and game.new_checkpoint == every + 1, "clearing a boss wave is a checkpoint")
	_check(SaveData.map_checkpoints(0) == [1, every + 1], "...which unlocks the next starting wave")
	game.director.intermission = 99999.0
	var coins_before_win := game.coins_run
	_finish_wave(game, last_wave)
	await _until(func() -> bool: return game.state == Game.State.WON)
	_check(game.victory and game.coins_run >= coins_before_win + Config.MAP_CLEAR_COINS, "clearing wave %d wins the map and pays a bonus" % last_wave)
	_check(SaveData.maps_unlocked == 2 and SaveData.map_cleared(0) and game.unlocked_map == 1, "...and unlocks the next map")
	await _until(func() -> bool: return app.state == Main.State.GAME_OVER, 900)
	_check(app.state == Main.State.GAME_OVER, "the results screen follows a victory")
	await _frames(5)
	app.start_run(0, every + 1)
	await _frames(10)
	game = app.game
	_check(game.start_wave == every + 1 and not game.pickups.crates.is_empty(), "a checkpoint run starts with a weapon crate beside you")
	game.director.intermission = 0.05
	await _until(func() -> bool: return game.director.in_wave, 300)
	_check(game.director.wave == every + 1, "...and begins at wave %d" % (every + 1))
	app.start_run(1, 1)
	await _frames(10)
	game = app.game
	_check(game.map_index == 1 and game.coin_value == int(Config.MAPS[1]["coins"]), "map 2 can be played once unlocked, and its coins are worth more")
	game.director.intermission = 0.05
	await _until(func() -> bool: return game.enemies.alive_count > 0, 600)
	var tough := game.enemies.nearest(game.player.pos, 99999.0)
	if tough != null:
		var base: Dictionary = Config.ENEMIES[tough.kind]
		_check(is_equal_approx(tough.max_hp, float(base["hp"]) * float(Config.MAPS[1]["hp"]))
				and is_equal_approx(tough.damage, float(base["damage"]) * float(Config.MAPS[1]["damage"])),
				"map 2 zombies are tougher (%.0f health, %.0f damage)" % [tough.max_hp, tough.damage])
	else:
		_check(false, "map 2 zombies arrive")
	app.pause_game()
	await _frames(3)
	app.quit_to_menu()
	await _frames(5)

	# --- XP earned in play ---
	_check(SaveData.weapon_xp("pistol") > 0 or SaveData.weapon_level("pistol") > 1, "kills give the weapon that made them XP")
	_check(SaveData.level > 2 or SaveData.xp > 0, "kills give the character XP")

	# --- level cap ---
	var real_level := SaveData.level
	var real_xp := SaveData.xp
	var real_points := SaveData.skill_points
	SaveData.level = Config.LEVEL_CAP - 1
	SaveData.xp = 0
	_check(SaveData.add_xp(999999999) == 1 and SaveData.level == Config.LEVEL_CAP and SaveData.xp == 0,
			"the character stops at level %d" % Config.LEVEL_CAP)
	_check(SaveData.add_xp(5000) == 0 and SaveData.level == Config.LEVEL_CAP, "no XP is gained at the level cap")
	SaveData.level = real_level
	SaveData.xp = real_xp
	SaveData.skill_points = real_points

	# --- respec ---
	SaveData.add_coins(100000)
	var spent := SaveData.spent_points()
	var unspent := SaveData.skill_points
	_check(spent > 0 and SaveData.respec() and SaveData.skill_points == unspent + spent and SaveData.passive_rank("vitality") == 0,
			"resetting gives every spent skill point back")
	SaveData.raise_passive("evasion")

	# --- save file round trip ---
	var coins_now := SaveData.coins
	var level_now := SaveData.level
	var xp_now := SaveData.xp
	var points_now := SaveData.skill_points
	var shotgun_power := SaveData.weapon_rank("shotgun", "power")
	var pistol_level := SaveData.weapon_level("pistol")
	SaveData.save_game()
	SaveData.call("_reset_to_defaults")
	SaveData.load_game()
	_check(SaveData.coins == coins_now and SaveData.level == level_now and SaveData.xp == xp_now and SaveData.skill_points == points_now,
			"save file restores coins, level, XP and skill points")
	_check(SaveData.passive_rank("evasion") == 1 and SaveData.weapon_rank("shotgun", "power") == shotgun_power
			and SaveData.weapon_level("pistol") == pistol_level, "save file restores passive ranks and weapon levels")
	_check(SaveData.maps_unlocked == 2 and SaveData.map_cleared(0) and SaveData.selected_map == 1,
			"save file restores map progress")

	# --- points in an upgrade a weapon no longer has are given back ---
	var sledge_entry: Dictionary = SaveData.weapons["sledge"]
	var sledge_points := int(sledge_entry["points"])
	(sledge_entry["ranks"] as Dictionary)["stability"] = 3
	SaveData.save_game()
	SaveData.load_game()
	_check(SaveData.weapon_rank("sledge", "stability") == 0 and SaveData.weapon_points("sledge") == sledge_points + 3,
			"points spent on an upgrade a weapon no longer has are refunded")

	# --- an old (version 1) save: coins and upgrades are wiped once, records kept ---
	var old_file := FileAccess.open(SaveData.save_path, FileAccess.WRITE)
	old_file.store_string(JSON.stringify({"version": 1, "coins": 777, "upgrades": {"damage": 3}, "best_score": 4321,
			"best_wave": 9, "total_kills": 50, "runs_played": 2, "settings": {"master_volume": 0.3}}))
	old_file.close()
	SaveData.call("_reset_to_defaults")
	SaveData.load_game()
	_check(SaveData.coins == 0 and SaveData.level == 1 and SaveData.was_reset_by_update, "an old save has its coins and upgrades reset")
	_check(SaveData.best_score == 4321 and is_equal_approx(float(SaveData.get_setting("master_volume")), 0.3),
			"an old save keeps its records and settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.save_path))

	if _auto_failures.is_empty():
		print("AUTOTEST PASSED")
		_quit(0)
	else:
		print("AUTOTEST FAILED: %d problem(s)" % _auto_failures.size())
		for f: String in _auto_failures:
			print("   - ", f)
		_quit(1)


# ----------------------------------------------------------------------------
#  Input test: real keyboard, mouse and gamepad events, as the OS would send
#  them, pushed through the engine to check every binding in GameInput.
# ----------------------------------------------------------------------------
func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _mouse_move(to: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = to
	e.global_position = to
	e.relative = Vector2(30, 30)
	Input.parse_input_event(e)


func _mouse_button(button: MouseButton, pressed: bool, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)


func _pad_axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _pad_button(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _run_inputtest() -> void:
	var app: Main = main
	print("INPUTTEST start")
	SaveData.call("_reset_to_defaults")
	await _frames(5)
	app.start_run()
	await _frames(10)
	var game := app.game
	var p := game.player
	game.director.intermission = 99999.0     # no zombies: we only test controls
	var view := get_viewport().get_visible_rect().size

	# --- keyboard movement (WASD + arrows) ---
	for pair: Array in [[KEY_D, Vector2.RIGHT], [KEY_A, Vector2.LEFT], [KEY_W, Vector2.UP], [KEY_S, Vector2.DOWN],
			[KEY_RIGHT, Vector2.RIGHT], [KEY_UP, Vector2.UP]]:
		var start := p.pos
		_key(pair[0], true)
		await _frames(12)
		_key(pair[0], false)
		await _frames(2)
		var moved := p.pos - start
		var want: Vector2 = pair[1]
		_check(moved.length() > 30.0 and moved.normalized().dot(want) > 0.95,
				"key %s moves %s (moved %s)" % [OS.get_keycode_string(pair[0]), str(want), str(moved.round())])
	_check(GameInput.device == GameInput.Device.KEYBOARD_MOUSE, "keyboard selects keyboard+mouse mode")
	var still := p.pos
	await _frames(5)
	_check(p.pos.distance_to(still) < 0.01, "player stops instantly when keys are released")

	# --- mouse aim ---
	for target: Vector2 in [Vector2(view.x * 0.9, view.y * 0.5), Vector2(view.x * 0.5, view.y * 0.1), Vector2(view.x * 0.1, view.y * 0.5)]:
		_mouse_move(target)
		await _frames(20)
		var want_dir := (p.get_global_mouse_position() - p.global_position).normalized()
		_check(p.aim.dot(want_dir) > 0.99 and (p.get_global_mouse_position() - p.global_position).length() > 50.0,
				"mouse at %s aims the player there (aim %s)" % [str(target.round()), str(p.aim.snapped(Vector2(0.01, 0.01)))])

	# --- mouse fire ---
	_check(not GameInput.is_firing(), "not firing by default")
	_mouse_button(MOUSE_BUTTON_LEFT, true, Vector2(view.x * 0.9, view.y * 0.5))
	await _frames(20)
	_check(GameInput.is_firing() and not game.projectiles.shots.is_empty(), "left mouse button fires bullets")
	_mouse_button(MOUSE_BUTTON_LEFT, false, Vector2(view.x * 0.9, view.y * 0.5))
	await _frames(3)
	_check(not GameInput.is_firing(), "releasing the button stops firing")

	# --- reload on R ---
	p.ammo = 3
	_key(KEY_R, true)
	await _frames(2)
	_key(KEY_R, false)
	_check(p.reloading, "R reloads")
	p.refill_ammo()

	# --- rage on Space ---
	game.rage = Config.RAGE_MAX
	_key(KEY_SPACE, true)
	await _frames(2)
	_key(KEY_SPACE, false)
	_check(game.rage_active, "Space activates rage")

	# --- pause on Escape / P ---
	_key(KEY_ESCAPE, true)
	await _frames(2)
	_key(KEY_ESCAPE, false)
	await _frames(2)
	_check(app.state == Main.State.PAUSED, "Escape pauses")
	_key(KEY_ESCAPE, true)
	await _frames(2)
	_key(KEY_ESCAPE, false)
	await _frames(2)
	_check(app.state == Main.State.PLAYING, "Escape resumes")
	_key(KEY_P, true)
	await _frames(2)
	_key(KEY_P, false)
	await _frames(2)
	_check(app.state == Main.State.PAUSED, "P pauses")
	app.resume_game()
	await _frames(3)

	# --- gamepad ---
	var start_pad := p.pos
	_pad_axis(JOY_AXIS_LEFT_X, 1.0)
	await _frames(12)
	_check(GameInput.device == GameInput.Device.GAMEPAD, "stick input switches to gamepad mode")
	_check((p.pos - start_pad).x > 30.0, "left stick moves the player")
	_pad_axis(JOY_AXIS_LEFT_X, 0.4)
	await _frames(2)
	var slow := GameInput.get_move().length()
	_check(slow > 0.1 and slow < 0.7, "left stick is analog (half tilt = %.2f speed)" % slow)
	_pad_axis(JOY_AXIS_LEFT_X, 0.0)
	await _frames(3)
	_pad_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _frames(4)
	_check(p.aim.dot(Vector2.UP) > 0.99, "right stick aims (up)")
	_pad_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_pad_axis(JOY_AXIS_RIGHT_X, -1.0)
	await _frames(4)
	_check(p.aim.dot(Vector2.LEFT) > 0.99, "right stick aims (left)")
	_pad_axis(JOY_AXIS_RIGHT_X, 0.0)
	await _frames(4)
	_check(p.aim.dot(Vector2.LEFT) > 0.99, "aim direction is kept when the stick is released")
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(4)
	_check(GameInput.is_firing(), "right trigger fires")
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _frames(3)
	_check(not GameInput.is_firing(), "releasing the trigger stops firing")
	game.rage_active = false
	game.rage = Config.RAGE_MAX
	p.ammo = 3
	_pad_button(JOY_BUTTON_X, true)
	await _frames(2)
	_pad_button(JOY_BUTTON_X, false)
	_check(p.reloading and not game.rage_active, "X reloads (and no longer triggers rage)")
	p.refill_ammo()
	_pad_button(JOY_BUTTON_LEFT_SHOULDER, true)
	await _frames(2)
	_pad_button(JOY_BUTTON_LEFT_SHOULDER, false)
	_check(game.rage_active, "left bumper activates rage")
	_pad_button(JOY_BUTTON_START, true)
	await _frames(2)
	_pad_button(JOY_BUTTON_START, false)
	await _frames(2)
	_check(app.state == Main.State.PAUSED, "Start pauses")
	_pad_button(JOY_BUTTON_B, true)
	await _frames(2)
	_pad_button(JOY_BUTTON_B, false)
	await _frames(2)
	_check(app.state == Main.State.PLAYING, "B closes the pause menu")

	# --- menu buttons react to accept (keyboard Enter / gamepad A) ---
	app.pause_game()
	await _frames(3)
	_pad_button(JOY_BUTTON_A, true)
	await _frames(2)
	_pad_button(JOY_BUTTON_A, false)
	await _frames(3)
	_check(app.state == Main.State.PLAYING, "A on the focused RESUME button resumes")

	# --- mouse wakes keyboard+mouse mode again ---
	_mouse_move(view * 0.3)
	await _frames(3)
	_check(GameInput.device == GameInput.Device.KEYBOARD_MOUSE, "moving the mouse switches back to keyboard+mouse")

	if _auto_failures.is_empty():
		print("INPUTTEST PASSED")
		_quit(0)
	else:
		print("INPUTTEST FAILED: %d problem(s)" % _auto_failures.size())
		_quit(1)


# ----------------------------------------------------------------------------
#  Art gallery: lays out generated sprites on a plain background.
# ----------------------------------------------------------------------------
func _show_gallery() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var board := DrawLayer.new()
	board.painter = _paint_gallery
	layer.add_child(board)


func _paint_gallery(ci: CanvasItem) -> void:
	var prefixes := String(_args["gallery"]).split(",")
	var zoom := float(_args.get("gallery-scale", "1.5"))
	var view := get_viewport().get_visible_rect().size
	ci.draw_rect(Rect2(Vector2.ZERO, view), Color("5d5646"))
	var names: Array = Art.tex.keys()
	names.sort()
	var font := ThemeDB.fallback_font
	var x := 16.0
	var y := 16.0
	var row_h := 0.0
	for sprite: String in names:
		var wanted := false
		for prefix: String in prefixes:
			if sprite.begins_with(prefix):
				wanted = true
		if not wanted or sprite.ends_with("_flash"):
			continue
		var s: Vector2 = Art.size_of(sprite) * zoom
		if x + s.x > view.x - 16.0:
			x = 16.0
			y += row_h + 26.0
			row_h = 0.0
		ci.draw_texture_rect(Art.t(sprite), Rect2(Vector2(x, y), s), false)
		ci.draw_string(font, Vector2(x, y + s.y + 14.0), sprite, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
		x += maxf(s.x, 90.0) + 18.0
		row_h = maxf(row_h, s.y)
