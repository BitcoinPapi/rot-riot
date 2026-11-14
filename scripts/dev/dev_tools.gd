class_name DevTools
extends Node
## Developer helpers, only active when the game is started with extra
## command-line arguments after "--". Players never see this.
##
##   --play             skip the menu and start a run
##   --bot              start a run and let a simple bot play (through GameInput's virtual sticks)
##   --screen=NAME      open a menu screen (shop, settings, pause, gameover) for screenshots
##   --weapon=ID        the bot starts with this weapon (pistol, shotgun, ...)
##   --cycle            the bot is handed each weapon in turn every 6 seconds
##   --wave=N           jump straight to wave N
##   --god              the player cannot die
##   --frames=N         quit after N frames and print a summary
##   --autotest         play through the whole game loop automatically and report PASS/FAIL
##   --bench=N          keep N zombies alive around the player and report simulation time
##   --dump-sfx=DIR     write every generated sound to DIR as .wav files, then quit
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
	if _args.has("autotest"):
		_run_autotest.call_deferred()


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
			print("SUMMARY frames=%d wave=%d kills=%d score=%d coins=%d alive=%d left=%d hp=%.0f rage=%.0f weapon=%s boss=%s state=%d" % [
				_frame, game.director.wave, game.kills, game.score, game.coins_run, game.enemies.alive_count,
				game.director.remaining(), game.player.hp, game.rage, game.player.weapon_id,
				str(game.director.boss_alive()), game.state])
		_quit(0)


func _quit(code: int) -> void:
	set_process(false)
	(main as Main).quit_game(code)


func _bot(game: Game) -> void:
	var p := game.player
	if _args.has("weapon") and _frame == 2:
		p.give_weapon(String(_args["weapon"]))
	if _args.has("cycle") and _frame % 360 == 5:
		var order: Array = Config.WEAPON_ORDER
		p.give_weapon(String(order[int(_frame / 360.0) % order.size()]))
	if game.rage_ready():
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
	if _frame == 3:
		game.player.give_weapon(String(_args.get("weapon", "machinegun")))
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
	# Use a throwaway save file so real progress is never touched.
	SaveData.save_path = "user://autotest_save.json"
	if FileAccess.file_exists(SaveData.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.save_path))
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

	# --- shop ---
	app.open_screen("shop")
	await _frames(3)
	_check(not SaveData.buy_upgrade("damage"), "cannot buy an upgrade with 0 coins")
	SaveData.add_coins(1000)
	var before := SaveData.coins
	_check(SaveData.buy_upgrade("damage") and SaveData.upgrade_level("damage") == 1, "buying an upgrade raises its level")
	_check(SaveData.coins == before - Config.upgrade_cost("damage", 0), "buying an upgrade spends coins")
	for id: String in Config.UPGRADE_ORDER:
		SaveData.buy_upgrade(id)
	app.close_screen()
	await _frames(2)

	# --- start a run ---
	app.start_run()
	await _frames(10)
	var game := app.game
	_check(app.state == Main.State.PLAYING and game != null, "Play starts a run")
	_check(game.player.max_hp > Config.PLAYER_MAX_HP, "max health upgrade applies in the run")
	_check(game.player.up_damage > 1.0, "damage upgrade applies in the run")
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

	# --- save file round trip ---
	var coins_now := SaveData.coins
	var damage_level := SaveData.upgrade_level("damage")
	SaveData.save_game()
	SaveData.coins = 0
	SaveData.upgrades["damage"] = 0
	SaveData.load_game()
	_check(SaveData.coins == coins_now and SaveData.upgrade_level("damage") == damage_level, "save file restores coins and upgrades")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.save_path))

	if _auto_failures.is_empty():
		print("AUTOTEST PASSED")
		_quit(0)
	else:
		print("AUTOTEST FAILED: %d problem(s)" % _auto_failures.size())
		for f: String in _auto_failures:
			print("   - ", f)
		_quit(1)
