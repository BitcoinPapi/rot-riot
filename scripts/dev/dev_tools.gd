class_name DevTools
extends Node
## Developer helpers, only active when the game is started with extra
## command-line arguments after "--". Players never see this.
##
##   --play             skip the menu and start a run
##   --bot              start a run and let a simple bot play (through GameInput's virtual sticks)
##   --screen=NAME      open a menu screen (character, armory, settings, pause, gameover) for screenshots
##   --level=N          start as a level N character with points to spend (for screenshots)
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
		_:
			app.open_screen(screen)


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
	_check(Config.weapon_tracks("pistol").size() == 3 and Config.weapon_tracks("shotgun").size() == 5,
			"the pistol has no crate-only upgrades")
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
	await _frames(5)
	_check(pl.weapon_id == "pistol" and not pl.dual and pl.weapon_time <= 0.0, "dual pistols run out back to one pistol")

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
	game.rage = Config.RAGE_MAX
	GameInput.press_rage()
	await _frames(2)
	_check(game.rage_active, "rage activates when the meter is full")
	# Hit stops freeze game time, so rage lasts a little longer in real frames.
	var waited := 0
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
		waited = 0
		while boss.alive and boss.hp >= boss.max_hp and waited < 1500:
			game.player.hp = game.player.max_hp
			await _frames(1)
			waited += 1
		_check(boss.hp < boss.max_hp, "bullets hurt the boss")
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
