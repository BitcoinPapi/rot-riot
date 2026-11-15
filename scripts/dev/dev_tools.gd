class_name DevTools
extends Node
## Developer helpers, only active when the game is started with extra
## command-line arguments after "--". Players never see this.
##
##   --play             skip the menu and start a run
##   --bot              start a run and let a simple bot play (through GameInput's virtual sticks)
##   --screen=NAME      open a menu screen (maps, character, skills, armory, pets, settings, pause, gameover, victory) for screenshots
##   --forge            with --screen=character: open the forge
##   --gear=N           start with N random pieces of gear, some of them worn
##   --pets=N           own the first N pets and take the last of them along (use with --level=18 or more)
##   --drop-gear        one second into a run, drop a piece of every tier around the player (and one on top of them)
##   --drop-crates      one second into a run, drop four weapon crates around the player (two of them damaged)
##   --map=N            play map N (unlocks it); --best=W sets the best wave cleared there, --start=W the starting wave
##   --level=N          start as a level N character with points to spend (for screenshots)
##   --armory-weapon=ID with --screen=armory: show this weapon
##   --weapon=ID        the bot starts with this weapon (pistol, shotgun, ...)
##   --dual             ...one in each hand (if that weapon allows it)
##   --keep-weapon      ...and it never runs out
##   --cycle            the bot is handed each weapon in turn every 6 seconds
##   --wave=N           jump straight to wave N
##   --at=X,Y           start the run at this spot of the map (the middle is 1500,1000)
##   --perk=ID:N,ID:N   start the run with these run perks (Config.RUN_PERKS), N times each
##   --perks=N          owe N perk choices half a second into the run (to look at the choice)
##   --no-fog           the whole map is uncovered from the start
##   --show-chests      one second into a run, put a closed treasure chest beside the player and open another
##   --coop=host        host a co-op game on this computer and start a run as soon as the other copies have joined
##                      (--players=N: how many copies in all, 2 or 3; default 2)
##   --coop=join        ...and the other copies: join the game hosted on this same computer (or --coop=join:ADDRESS)
##                      Run both WITHOUT --fixed-fps (the two copies must share real time) and end
##                      them with --seconds=N instead of --frames=N. Combine with --bot / --god.
##   --cooptest         with --coop=host on one copy and --coop=join on one or two others: all play through
##                      a scripted co-op session (about 45 s) and each prints COOPTEST PASSED / FAILED
##   --horde=K:N,K:N    one second into a run, put N zombies of kind K around the player
##                      (shambler, runner, brute, boss, gobber, chucker, gasbag, lunger), e.g. --horde=gobber:3,gasbag:2
##   --god              the player cannot die
##   --frames=N         quit after N frames and print a summary
##   --autotest         play through the whole game loop automatically and report PASS/FAIL
##   --inputtest        feed fake keyboard / mouse / gamepad events through GameInput and check them
##   --bench=N          keep N zombies alive around the player and report simulation time
##                      (add --weapon=ID --no-crates to compare weapons fairly)
##   --no-crates        no weapon crates appear (works with --bot too)
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
var _coop_started := false
var _coop_code_said := ""        # (co-op) the code this copy has printed, for the script that passes it on
var _coop_let_in := 0            # (co-op host) how many lines of --letin-file have been typed in already
var _wave_set := false
var _coop_t0 := 0                # (co-op test) when this copy's first run began, in milliseconds
var _coop_testing := false
var _keep_alive := false
var _auto_bot := false
var _auto_perks := true          # automatic runs take the first perk offered (the perk tests switch this off)
var _auto_failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	# Developer runs never touch the player's real save file.
	if not _args.has("real-save"):
		SaveData.save_path = "user://dev_save.json"
		if String(_args.get("coop", "")).begins_with("join"):
			SaveData.save_path = "user://dev_save_join.json"      # (two copies on one computer: one save file each)
		if FileAccess.file_exists(SaveData.save_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.save_path))
		SaveData.call("_reset_to_defaults")
		SaveData.apply_settings()
		if _args.has("coop"):
			Engine.max_fps = 60          # (headless would otherwise spin as fast as it can)
			# Copies on one computer find each other directly. --stun=IP:PORT,IP:PORT
			# makes them go the long way round, as over the internet (tools/nattest.sh).
			Net.use_upnp = false
			Net.online = _args.has("stun")
			if _args.has("stun"):
				Net.stun_servers = Array(String(_args["stun"]).split(","))
			SaveData.settings["player_name"] = String(_args.get("name", "HOSTY" if String(_args["coop"]) == "host" else "JOINY"))
		if _args.has("coins"):
			SaveData.add_coins(int(_args["coins"]))
		if _args.has("level"):
			for i in int(_args["level"]) - 1:
				SaveData.add_xp(SaveData.xp_needed())
			SaveData.add_xp(int(SaveData.xp_needed() * 0.4))
			for id: String in ["vitality", "vitality", "vitality", "vitality", "vitality", "vitality", "defense", "defense",
					"strength", "strength", "strength", "strength", "critical", "agility", "agility", "bond", "bond"]:
				SaveData.raise_skill(id)
			SaveData.add_weapon_xp("pistol", 2500)
			SaveData.add_weapon_xp("shotgun", 900)
			SaveData.add_weapon_xp("launcher", 200)
			for i in 3:
				SaveData.raise_weapon_track("pistol", "power")
			SaveData.raise_weapon_track("pistol", "speed")
			SaveData.buy_weapon_perk("pistol", 0)
			SaveData.raise_weapon_track("shotgun", "spawn")
		if _args.has("gear"):
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			for i in int(_args["gear"]):
				var item: String = Config.GEAR_ORDER[rng.randi() % Config.GEAR_ORDER.size()]
				SaveData.add_gear(Config.gear_key(item, 1 + int(rng.randf() * rng.randf() * 3.5)))
			for key: String in SaveData.gear_bag.keys().duplicate():
				if rng.randf() < 0.45:
					SaveData.wear_gear(key)
		if _args.has("pets"):
			for i in mini(int(_args["pets"]), Config.PET_ORDER.size()):
				var pet_id: String = Config.PET_ORDER[i]
				if not SaveData.has_pet(pet_id):
					SaveData.pets_owned.append(pet_id)
				SaveData.pet_active = pet_id
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
	if _args.has("coop"):
		_coop_connect(app)
	elif _frame == 1 and (_args.has("bot") or _args.has("play") or _args.has("bench")):
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
		if _args.has("wave") and not _wave_set and not game.is_client and (_frame == 2 or game.coop != null):
			_wave_set = true
			game.director.wave = int(_args["wave"]) - 1
			game.director.intermission = 0.1
		if _args.has("at") and _frame == 2:
			var spot := String(_args["at"]).split(",")
			game.player.place(game.arena.resolve(Vector2(float(spot[0]), float(spot[1])), game.player.radius))
			game.cam.snap_to(game.player.pos)
		if _args.has("no-fog") and _frame == 2:
			game.fog.reveal_all()
		# --perk=ID:N,ID:N  start with these run perks;  --perks=N  owe N perk choices (to look at the choice)
		if _args.has("perk") and _frame == 2:
			for part: String in String(_args["perk"]).split(","):
				if Config.RUN_PERKS.has(part.get_slice(":", 0)):
					game.perks[part.get_slice(":", 0)] = maxi(int(part.get_slice(":", 1)), 1)
			game.player.refresh_stats(true)
		if _args.has("perks") and _frame == 30:
			game.call("_owe_perks", int(game.get("_perks_given")) + int(_args["perks"]), 0.1)
		if _auto_perks and game.choosing() and (_args.has("bot") or _args.has("bench") or _args.has("autotest")
				or _args.has("inputtest") or _args.has("cooptest")):
			game.choose_perk(0)
		if _args.has("horde") and _frame == 60:
			for part: String in String(_args["horde"]).split(","):
				var bits := part.split(":")
				var which := Art.ENEMY_SPRITE.find(bits[0])
				if which < 0:
					continue
				for i in (int(bits[1]) if bits.size() > 1 else 1):
					var at := game.player.pos + Vector2.from_angle(randf() * TAU) * randf_range(230.0, 290.0)
					game.enemies.spawn(which, game.arena.clamp_inside(at, 40.0), game.enemy_hp_mult, game.enemy_speed_mult)
		if _args.has("show-chests") and _frame == 60 and game.pickups.chests.size() >= 2:
			game.pickups.chests[0].pos = game.player.pos + Vector2(190.0, -60.0)
			game.pickups.chests[1].pos = game.player.pos + Vector2(-200.0, 70.0)
			game.open_chest(game.pickups.chests[1])
		if _args.has("drop-gear") and _frame == 60:
			var drops := ["hard_hat:1", "work_gloves:2", "iron_band:3", "combat_boots:4", "gorger_fang:5"]
			for i in drops.size():
				game.pickups.spawn_gear(game.player.pos + Vector2.from_angle(-2.4 + 0.75 * i) * 190.0, drops[i])
			game.pickups.spawn_gear(game.player.pos + Vector2(4.0, 0.0), "lucky_ring:2")
		if _args.has("drop-crates") and _frame == 60:
			var boxes := ["shotgun", "rifle", "launcher", "pistol"]
			for i in boxes.size():
				game.pickups.spawn_crate(game.player.pos + Vector2.from_angle(-2.6 + 0.9 * i) * 200.0, boxes[i])
			game.pickups.damage_crate(game.pickups.crates[1], Config.CRATE_HP * 0.45, Vector2.RIGHT)
			game.pickups.damage_crate(game.pickups.crates[2], Config.CRATE_HP * 0.75, Vector2.RIGHT)
		if _args.has("god") or _keep_alive:
			game.player.hp = game.player.max_hp
		if _args.has("cooptest") and not _coop_testing and game.coop != null:
			_coop_testing = true
			_coop_t0 = Time.get_ticks_msec()
			_run_cooptest.call_deferred()
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
	if (_args.has("frames") and _frame >= int(_args["frames"])) \
			or (_args.has("seconds") and Time.get_ticks_msec() >= int(float(_args["seconds"]) * 1000.0)):
		if game != null and is_instance_valid(game):
			if game.coop != null:
				var others: Array[String] = []
				for other: int in game.coop.mates.keys():
					var mate: Mate = game.coop.mates[other]
					others.append("%d:%s@%s%s" % [other, mate.shown_name, str(Vector2i(mate.pos)), " DOWN" if mate.down else ""])
				print("COOP slot=%d me_at=%s others=[%s] zombies=%d crates=%d xp=%d gear=%d down=%s" % [
					game.coop.my_slot, str(Vector2i(game.player.pos)), ", ".join(others), game.enemies.alive_count,
					game.pickups.crates.size(), game.xp_run, game.gear_run.size(), str(game.player.down)])
			print("SUMMARY frames=%d time=%.0fs wave=%d kills=%d score=%d coins=%d alive=%d left=%d hp=%.0f weapon=%s boss=%s state=%d" % [
				_frame, game.time_alive, game.director.wave, game.kills, game.score, game.coins_run, game.enemies.alive_count,
				game.director.remaining(), game.player.hp, game.player.weapon_id,
				str(game.director.boss_alive()), game.state])
			var weapon_levels: Array = []
			for id: String in Config.WEAPON_ORDER:
				weapon_levels.append("%s %d" % [id, SaveData.weapon_level(id)])
			print("PROGRESS xp_run=%d level=%d skill_points=%d weapons=[%s]" % [
				game.xp_run, SaveData.level, SaveData.skill_points, ", ".join(weapon_levels)])
			print("GEAR found=%d [%s]" % [game.gear_run.size(), ", ".join(game.gear_run)])
		_quit(0)


# ----------------------------------------------------------------------------
#  The co-op test: two copies of the game (one --coop=host, one --coop=join)
#  each run this script. The steps are timed in real seconds from the start
#  of the run, so both copies do their part of each step at the same moment.
# ----------------------------------------------------------------------------
## Wait until `seconds` after the run began.
func _at(seconds: float) -> void:
	while float(Time.get_ticks_msec() - _coop_t0) / 1000.0 < seconds:
		await get_tree().process_frame


func _run_cooptest() -> void:
	var app: Main = main
	var game := app.game
	var host := not game.is_client
	var slot := game.coop.my_slot                 # 0 = the host, 1 and 2 = the joiners
	var count := game.players_now()               # 2 or 3 copies are playing
	var three := count >= 3
	var me := game.player
	var middle := game.arena.rect.get_center()
	var spots: Array = Config.COOP_START_SPOTS
	print("COOPTEST start (slot %d of %d players)" % [slot, count])
	game.director.intermission = 99999.0
	game.pickups.set("_crate_timer", 99999.0)
	GameInput.set_virtual_input(Vector2.ZERO, Vector2.RIGHT, false)

	# --- everybody is in the same world ---
	await _at(1.0)
	var mates := game.coop.mates
	var all_here := mates.size() == count - 1
	var in_place := me.pos.distance_to(middle + spots[slot]) < 6.0
	for other: int in mates.keys():
		var mate: Mate = mates[other]
		if not mate.has_state:
			all_here = false
		if mate.pos.distance_to(middle + spots[other]) > 6.0:
			in_place = false
	_check(all_here, "the other %d player(s) are here" % (count - 1))
	_check(in_place, "everybody starts on their own spot in the middle")
	if not all_here:
		_cooptest_done()
		return
	var first: Mate = mates.get(1)                # (for everybody but slot 1) the first joiner's figure
	var names_ok := true
	for other: int in mates.keys():
		if (mates[other] as Mate).shown_name != ("HOSTY" if other == 0 else "JOIN%d" % other):
			names_ok = false
	_check(names_ok, "everybody's name arrives (%s)" % game.coop.names())
	var rocks := 0
	for i in game.arena.obs_pos.size():
		rocks = (rocks * 31 + int(game.arena.obs_pos[i].x) * 7 + int(game.arena.obs_pos[i].y) + int(game.arena.obs_radius[i])) % 1000000007
	var chest_sum := 0
	for chest: Pickups.Chest in game.pickups.chests:
		chest_sum += int(chest.pos.x) * 3 + int(chest.pos.y)
	print("SAME world rocks=%d chests=%d count=%d" % [rocks, chest_sum, game.pickups.chests.size()])
	_check(is_equal_approx(game.strength_hp(), Config.COOP_ENEMY_HP[count - 1]) and game.strength_hp() > 1.0,
			"zombies are tougher with %d players (health x%.2f)" % [count, game.strength_hp()])

	# --- the host's zombies show on every screen; the first joiner's bullets kill them ---
	await _at(2.0)
	if host:
		for i in 6:
			# (Weak ones, so that the test does not depend on how well the bot shoots.)
			game.enemies.spawn(Config.SHAMBLER, middle + Vector2(-100.0 + 40.0 * i, -260.0), 0.4, game.enemy_speed_mult)
	await _at(3.0)
	_check(game.enemies.alive_count == 6, "six zombies on every computer (%d here)" % game.enemies.alive_count)
	if not host:
		var near_right_place := true
		for e: Enemy in game.enemies.active:
			if e.alive and e.pos.distance_to(middle + Vector2(0.0, -230.0)) > 220.0:
				near_right_place = false
		_check(near_right_place, "...and the copies are where the host put them")
	_keep_alive = true
	if slot == 1:
		_auto_bot = true          # the first joiner does the shooting
	await _at(10.2)
	_auto_bot = false
	_keep_alive = false
	GameInput.set_virtual_input(Vector2.ZERO, Vector2.RIGHT, false)
	await _at(11.0)        # (a moment for the last counts to arrive everywhere)
	_check(game.kills == 6 and game.enemies.alive_count == 0, "the first joiner's bullets killed all six (%d kills counted here)" % game.kills)
	_check(game.xp_run > 0, "every player gets the XP (%d)" % game.xp_run)
	if slot == 1:
		_check(SaveData.weapon_xp("pistol") > 0 or SaveData.weapon_level("pistol") > 1, "...and the weapon's own XP goes to whoever fired")
	else:
		_check(SaveData.weapon_xp("pistol") == 0 and SaveData.weapon_level("pistol") == 1, "...but the weapon's own XP goes only to whoever fired")
	print("SAME after the fight kills=%d score=%d xp=%d" % [game.kills, game.score, game.xp_run])

	# --- all gold is shared ---
	# (Each step below starts a moment after the check before it, so that one
	# copy never acts at the very instant another one is checking.)
	var coins_before := game.coins_run
	await _at(11.4)
	if host:
		me.place(middle + Vector2(-500.0, 0.0))       # (out of the way: the first joiner picks these up)
		game.pickups.spawn_coins(first.pos, 10)
	elif slot == 2:
		me.place(middle + Vector2(500.0, 300.0))
	await _at(13.5)
	_check(game.coins_run >= coins_before + 10 * game.coin_value, "coins one player picks up count for everybody (%d -> %d)" % [coins_before, game.coins_run])
	print("SAME coins=%d" % game.coins_run)

	# --- a weapon crate goes to whoever walks into it ---
	await _at(13.9)
	if host:
		game.pickups.spawn_crate(first.pos + Vector2(26.0, 0.0), "shotgun")
		if three:
			game.pickups.spawn_crate((mates[2] as Mate).pos + Vector2(26.0, 0.0), "rifle")
	await _at(15.0)
	var holds := "shotgun" if slot == 1 else ("rifle" if slot == 2 else "pistol")
	_check(game.pickups.crates.is_empty() and me.weapon_id == holds, "each crate went to the player who walked into it (I hold the %s)" % me.weapon_id)

	# --- the host's zombies hurt a joiner; everybody sees it ---
	await _at(15.4)
	if host:
		game.enemies.spawn(Config.BRUTE, first.pos + Vector2(70.0, 0.0), game.enemy_hp_mult, game.enemy_speed_mult)
	await _at(18.0)
	if slot == 1:
		_check(me.hp < me.max_hp, "a zombie on the host's computer hurt the first joiner (%d of %d health left)" % [int(me.hp), int(me.max_hp)])
	else:
		_check(first.hp_frac < 0.999, "everybody else sees the first joiner's health go down (%d%%)" % int(first.hp_frac * 100.0))
	if host:
		game.enemies.clear_all()

	# --- falling, and being picked up (with three players: by the other joiner, through the host) ---
	await _at(18.6)
	if slot == 1:
		me.invuln = 0.0
		game.damage_player(99999.0, me.pos + Vector2.RIGHT)
		_check(me.down and not me.alive and game.state == Game.State.PLAYING, "out of health with others still up: the first joiner falls, the run goes on")
	await _at(19.6)
	var helper := 2 if three else 0
	if slot != 1:
		_check(first.down, "everybody sees that the first joiner is down")
		if slot == helper:
			me.place(first.pos + Vector2(24.0, 0.0))        # stand beside them
	await _at(24.0)
	if slot == 1:
		_check(not me.down and me.alive and is_equal_approx(me.hp, me.max_hp * Config.COOP_REVIVE_HP),
				"the first joiner is back up with %d%% health (picked up by player %d)" % [int(Config.COOP_REVIVE_HP * 100.0), helper])
	else:
		_check(not first.down, "standing beside them picked the first joiner up")

	# --- gear: a piece any player picks up goes to everybody ---
	var gear_before := game.gear_run.size()
	await _at(24.4)
	if host:
		game.pickups.spawn_gear(me.pos + Vector2(6.0, 0.0), "hard_hat:1")
	await _at(25.2)
	_check(game.gear_run.size() == gear_before + 1 and game.gear_run.has("hard_hat:1") and SaveData.gear_count("hard_hat:1") >= 1,
			"a piece of gear the host picks up goes into everybody's bag")

	# --- treasure chests: whoever opens it, everybody gets the piece ---
	# (Counted from here: on a small map somebody may have walked into a chest already.)
	var chests_before := game.chests_run
	var chest_gear_before := game.gear_run.size()
	await _at(25.6)
	if host:
		for hidden: Pickups.Chest in game.pickups.chests:
			if not hidden.opened:
				me.place(hidden.pos + Vector2(8.0, 0.0))
				break
	await _at(27.0)
	_check(game.chests_run == chests_before + 1 and game.gear_run.size() == chest_gear_before + 1,
			"a chest the host opens gives everybody the piece (%s; chests %d -> %d, gear %d -> %d)" % [
			game.gear_run[-1] if not game.gear_run.is_empty() else "-", chests_before, game.chests_run, chest_gear_before,
			game.gear_run.size()])
	print("SAME gear=%s" % ",".join(game.gear_run))

	# --- pausing pauses everybody ---
	await _at(27.4)
	if slot == 1:
		app.pause_game()
	await _at(28.2)
	_check(app.state == Main.State.PAUSED and get_tree().paused, "when one player pauses, every game pauses")
	await _at(28.6)
	if host:
		app.resume_game()
	await _at(29.2)
	_check(app.state == Main.State.PLAYING and not get_tree().paused, "...and when one resumes, all go on")

	# --- perks: each player chooses their own; the next wave waits until everybody has ---
	var perk_wave: int = Config.PERK_EVERY
	await _at(29.4)
	if slot == 1:
		_auto_perks = false               # the first joiner takes their time over it
	if host:
		_finish_wave(game, perk_wave)
	await _at(30.2)
	_check(game.perks_owed == 1 and game.perks.is_empty(), "clearing wave %d earns every player a perk choice" % perk_wave)
	if host:
		game.director.intermission = 0.3  # (the next wave would start at once - if nobody were choosing)
	await _at(32.6)
	if slot == 1:
		_check(game.choosing() and game.perks.is_empty(), "my perk choice is open (and I take my time)")
	else:
		_check(game.perks.size() == 1 and game.perks_owed == 0 and not game.choosing(), "I have chosen my perk (%s)" % ", ".join(game.perks.keys()))
		_check(game.perks_pending() and game.perk_waiting_for() == (["JOIN1"] as Array[String]), "...and see that JOIN1 is still choosing")
	if host:
		_check(not game.director.in_wave and game.director.wave == perk_wave, "the next wave waits for the player who is still choosing")
	await _at(33.0)
	if slot == 1:
		game.choose_perk(0)
		_auto_perks = true
	await _at(34.4)
	_check(not game.perks_pending() and game.perks.size() == 1, "everybody has a perk of their own")
	if host:
		_check(game.director.in_wave and game.director.wave == perk_wave + 1, "...and then the next wave starts")
	await _at(35.0)
	if host:
		_finish_wave(game, perk_wave + 1)
	await _at(35.6)
	if host:
		game.director.intermission = 99999.0
	_coop_t0 += 6400                      # (the rest of the session follows, 6.4 seconds later than its times say)

	# --- everybody down: the run is over, with the same numbers for all ---
	var bank_before := SaveData.coins
	await _at(29.6 + 0.7 * slot)
	if slot == count - 1:
		var others_down := true
		for other: int in mates.keys():
			if not (mates[other] as Mate).down:
				others_down = false
		_check(others_down, "the last one standing sees that the others are down")
	me.invuln = 0.0
	game.damage_player(99999.0, me.pos + Vector2.RIGHT)
	if slot < count - 1:
		_check(me.down and game.state == Game.State.PLAYING, "I fall; the run goes on while somebody stands")
	await _at(37.0)
	_check(app.state == Main.State.GAME_OVER, "everybody down: the run ends for all")
	var final_coins := int(game.get_stats()["coins"])
	_check(SaveData.coins == bank_before + final_coins and final_coins >= 10, "each player banks all the gold of the run (%d)" % final_coins)
	print("SAME final coins=%d score=%d kills=%d wave=%d" % [final_coins, int(game.get_stats()["score"]), int(game.get_stats()["kills"]),
			int(game.get_stats()["wave"])])

	# --- the host starts the next run for everybody ---
	var old_game := app.game
	if not host:
		app.start_run()        # (a joiner cannot start one: this must do nothing)
		_check(app.state == Main.State.GAME_OVER, "only the host can start the next run")
	await _at(37.6)
	if host:
		app.start_run()
	await _at(39.5)
	_check(app.state == Main.State.PLAYING and app.game != old_game and app.game.coop != null and app.game.coop.mates.size() == count - 1,
			"the host starts the next run and everybody is in it")
	await _at(40.5)
	var see_all := app.game != null and app.game.coop != null
	if see_all:
		for other: int in app.game.coop.mates.keys():
			if not (app.game.coop.mates[other] as Mate).has_state:
				see_all = false
	_check(see_all, "...and they all see each other again")

	# --- one player leaves the run: the others play on ---
	await _at(40.9)
	if slot == 1:
		app.quit_to_menu()
	await _at(42.0)
	if slot == 1:
		_check(app.state == Main.State.MENU and Net.playing_together(), "the first joiner is back in the menu, still connected")
	else:
		_check(app.state == Main.State.PLAYING and app.game.coop.mates.size() == count - 2 and not app.game.coop.mates.has(1),
				"when the first joiner leaves the run, the others play on (%d left with me)" % app.game.coop.mates.size())
		_check(Net.mates.size() == count - 1, "...and everybody stays connected for the next run")
		if host:
			_check(is_equal_approx(app.game.strength_hp(), Config.COOP_ENEMY_HP[count - 2]), "...and the zombies are sized for the players who are left")
	_cooptest_done()


func _cooptest_done() -> void:
	if _auto_failures.is_empty():
		print("COOPTEST PASSED")
	else:
		print("COOPTEST FAILED: %d problem(s)" % _auto_failures.size())
	await _frames(20)
	_quit(0 if _auto_failures.is_empty() else 1)


## --coop: host or join, and (as host) start a run once the other copy is in.
func _coop_connect(app: Main) -> void:
	var what := String(_args["coop"])
	# What a player would read off the screen and pass on, printed for the test
	# script: the host's game code, a joiner's reply code.
	var shown := Net.code if Net.role == Net.Role.HOST else Net.reply_code
	if shown != "" and shown != _coop_code_said:
		_coop_code_said = shown
		print("%s %s" % ["CODE" if Net.role == Net.Role.HOST else "REPLY", shown])
		if Net.strict:
			print("STRICT (this router gives every conversation a new door)")
	# --letin-file=PATH: reply codes "typed in" by the host, one per line.
	if what == "host" and _args.has("letin-file") and _frame % 15 == 0 and FileAccess.file_exists(String(_args["letin-file"])):
		var lines := FileAccess.get_file_as_string(String(_args["letin-file"])).split("\n", false)
		while _coop_let_in < lines.size():
			print("LET IN %s -> %s" % [lines[_coop_let_in], Net.let_in(lines[_coop_let_in])])
			_coop_let_in += 1
	if _frame == 3:
		if what == "host":
			Net.host()
		else:
			Net.join(what.substr(5) if what.begins_with("join:") else "127.0.0.1")
	elif what == "host" and Net.mates.size() >= int(_args.get("players", "2")) - 1 and app.game == null and not _coop_started and _frame > 20:
		_coop_started = true
		if _args.has("map"):
			SaveData.maps_unlocked = Config.MAPS.size()
		app.start_run(int(_args.get("map", "1")) - 1, int(_args.get("start", "1")))


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
			if screen == "character" and _args.has("forge"):
				var sheet: CharacterScreen = (app.get("_screens") as Dictionary)["character"]
				sheet.call("_open_forge")
				for key: String in SaveData.gear_bag.keys():
					if SaveData.gear_count(key) >= 2 and Config.gear_tier_of(key) < Config.GEAR_TIERS.size():
						sheet.call("_choose_forge", key)
						break
			if screen == "coop" and _args.has("coop-view"):
				# Pretend states, to look at the screen without a second computer:
				# --coop-view=host | full | reply
				var view := String(_args["coop-view"])
				if view == "reply":
					Net.role = Net.Role.CLIENT
					Net.reply_code = Net.make_code("91.44.2.17", 51234, Net.CODE_REPLY)
					Net.status = "ALMOST THERE.  Send this reply code to your host.  They type it in on this screen and press LET IN."
				else:
					Net.role = Net.Role.HOST
					Net.code = Net.make_code("84.25.133.7", 24565, Net.CODE_GAME)
					Net.lan_code = "192.168.0.119"
					Net.status = "Waiting for your friends to join..."
					if view == "full":
						Net.mates = {1: {"name": "TATONI", "level": 12, "worn": {}, "pet": ""}, 2: {"name": "KOSTA", "level": 7, "worn": {}, "pet": ""}}
						Net.status = "KOSTA has joined."
				Net.changed.emit()
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
		elif roll > 0.63:
			kind = Config.GOBBER
		elif roll > 0.57:
			kind = Config.LUNGER
		elif roll > 0.53:
			kind = Config.GASBAG
		elif roll > 0.5:
			kind = Config.CHUCKER
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
#  Automated playthrough: menu -> shop -> settings -> run (every weapon,
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

	# --- co-op: game codes, reply codes, and reading an address finder's answer ---
	var game_code: String = Net.make_code("84.25.133.7", 24565, Net.CODE_GAME)
	var read_back: Dictionary = Net.read_code(game_code)
	_check(game_code.length() == 14 and int(read_back["kind"]) == Net.CODE_GAME and String(read_back["ip"]) == "84.25.133.7"
			and int(read_back["port"]) == 24565, "a game code carries the host's address (%s)" % game_code)
	var sloppy: Dictionary = Net.read_code("  " + game_code.to_lower().replace("-", " ").replace("0", "o").replace("1", "l") + " ")
	_check(int(sloppy["kind"]) == Net.CODE_GAME and String(sloppy["ip"]) == "84.25.133.7" and int(sloppy["port"]) == 24565,
			"...however it is typed: small letters, spaces, the letter O for a zero")
	var reply_code: String = Net.make_code("84.25.133.7", 51234, Net.CODE_REPLY)
	var reply_back: Dictionary = Net.read_code(reply_code)
	_check(int(reply_back["kind"]) == Net.CODE_REPLY and int(reply_back["port"]) == 51234 and reply_code != game_code,
			"a reply code is told apart from a game code (%s)" % reply_code)
	var typos := 0
	var caught := 0
	for i in game_code.length():
		if game_code[i] == "-":
			continue
		for wrong_sign: String in ["0", "7", "K", "Z", "D"]:
			if wrong_sign != game_code[i]:
				typos += 1
				var wrong: Dictionary = Net.read_code(game_code.substr(0, i) + wrong_sign + game_code.substr(i + 1))
				if int(wrong["kind"]) == Net.CODE_BAD and bool(wrong["typo"]):
					caught += 1
	_check(caught >= typos - 1, "a typing mistake in a code is noticed at once (%d of %d)" % [caught, typos])
	var plain: Dictionary = Net.read_code("192.168.0.12")
	var with_door: Dictionary = Net.read_code("84.25.133.7:5000")
	_check(int(plain["kind"]) == Net.CODE_ADDRESS and int(plain["port"]) == Config.NET_PORT and int(with_door["port"]) == 5000
			and String(with_door["ip"]) == "84.25.133.7" and int(Net.read_code("hello")["kind"]) == Net.CODE_BAD
			and int(Net.read_code("")["kind"]) == Net.CODE_BAD, "a plain address still works as a code (same house)")
	# The example answer from the STUN standard's own test sheet (RFC 5769, 2.2):
	# "your message came from 192.0.2.1, door 32853".
	var stun_id := PackedByteArray([0xb7, 0xe7, 0xa7, 0x01, 0xbc, 0x34, 0xd6, 0x86, 0xfa, 0x87, 0xdf, 0xae])
	var stun_answer := PackedByteArray([0x01, 0x01, 0x00, 0x3c, 0x21, 0x12, 0xa4, 0x42])
	stun_answer.append_array(stun_id)
	stun_answer.append_array(PackedByteArray([0x80, 0x22, 0x00, 0x0b, 0x74, 0x65, 0x73, 0x74, 0x20, 0x76, 0x65, 0x63, 0x74, 0x6f, 0x72, 0x20,
			0x00, 0x20, 0x00, 0x08, 0x00, 0x01, 0xa1, 0x47, 0xe1, 0x12, 0xa6, 0x43]))
	var stun_rest := PackedByteArray()
	stun_rest.resize(32)                  # (a signature and a checksum follow; the game does not read them)
	stun_answer.append_array(stun_rest)
	var seen: Array = Stun.parse(stun_answer, stun_id)
	_check(seen.size() == 2 and String(seen[0]) == "192.0.2.1" and int(seen[1]) == 32853,
			"an address finder's answer is read correctly (the standard's own example: %s)" % str(seen))
	var other_id := stun_id.duplicate()
	other_id[0] = 0
	var old_style := PackedByteArray([0x01, 0x01, 0x00, 0x0c, 0x21, 0x12, 0xa4, 0x42])
	old_style.append_array(stun_id)
	old_style.append_array(PackedByteArray([0x00, 0x01, 0x00, 0x08, 0x00, 0x01, 0x5f, 0xf5, 84, 25, 133, 7]))
	var old_seen: Array = Stun.parse(old_style, stun_id)
	var question := Stun.request(stun_id)
	_check(Stun.parse(stun_answer, other_id).is_empty() and Stun.parse(PackedByteArray([1, 2, 3]), stun_id).is_empty()
			and old_seen.size() == 2 and String(old_seen[0]) == "84.25.133.7" and int(old_seen[1]) == 24565
			and question.size() == 20 and question.slice(0, 8) == PackedByteArray([0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xa4, 0x42])
			and question.slice(8) == stun_id, "...an answer to somebody else's question is ignored; old-style answers are understood")

	# --- recordings in assets/sfx replace generated sounds; several of one sound are picked from ---
	# (The generated sounds are built in the background; that takes real time, not frames.)
	var sound_wait := Time.get_ticks_msec()
	while not Sfx.ready_to_play and Time.get_ticks_msec() - sound_wait < 60000:
		await get_tree().process_frame
	var streams: Dictionary = Sfx.get_streams()
	var all_sounds := true
	for sound_name: String in Sfx.RECIPES.keys():
		if not streams.has(sound_name) or streams[sound_name] == null:
			all_sounds = false
	_check(all_sounds, "every sound of the game is there, generated or recorded (%d)" % streams.size())
	var recorded: Array[String] = []
	var recordings_ok := true
	var dir := DirAccess.open("res://assets/sfx")
	if dir != null:
		for file_name: String in dir.get_files():
			# (In an exported game only the ".import" notes are listed, so take either.)
			var base := file_name.trim_suffix(".import")
			if not (base.get_extension() in ["ogg", "wav", "mp3"]):
				continue
			base = base.get_basename()
			var sound_name := base
			var cut := base.rfind("_")
			if cut > 0 and base.substr(cut + 1).is_valid_int():
				sound_name = base.substr(0, cut)
			if not Sfx.RECIPES.has(sound_name):
				recordings_ok = false          # (a file no sound of the game is called: a typing mistake in its name)
			elif not recorded.has(sound_name):
				recorded.append(sound_name)
	for sound_name: String in recorded:
		if not Sfx.is_recording(sound_name):
			recordings_ok = false
	_check(recordings_ok, "the recordings in assets/sfx are all used (%s)" % ", ".join(recorded))
	if recorded.has("zombie_hit"):
		_check(Sfx.recording_count("zombie_hit") >= 3 and Sfx.is_recording("ui_click") and not Sfx.is_recording("pistol"),
				"a sound with several recordings picks from them (%d zombie hits); sounds without a file stay generated" % Sfx.recording_count("zombie_hit"))

	# --- skills screen: skill points and the plain list of stats ---
	app.open_screen("skills")
	await _frames(3)
	var skills: SkillScreen = (app.get("_screens") as Dictionary)["skills"]
	_check(not SaveData.raise_skill("strength"), "cannot buy a rank with 0 skill points")
	_check(not SaveData.buy_skill_point(), "cannot buy a skill point with 0 coins")
	SaveData.add_coins(1000)
	var before := SaveData.coins
	var price := SaveData.skill_point_price()
	_check(SaveData.buy_skill_point() and SaveData.skill_points == 1, "coins buy a skill point")
	_check(SaveData.coins == before - price and SaveData.skill_point_price() > price, "the price is paid and the next point costs more")
	skills.call("_on_raise", "vitality")
	_check(SaveData.skill_rank("vitality") == 1 and SaveData.passive_rank("vitality") == 1 and SaveData.passive_rank("defense") == 0
			and SaveData.skill_points == 0, "the +1 button on a row buys a rank of that stat (and only that one)")
	SaveData.buy_skill_point()
	SaveData.raise_skill("strength")
	_check(SaveData.spent_points() == 2, "spent points are counted")
	await _frames(3)

	# The page itself: every stat has a row, in one of the three groups, and a special power.
	var listed: Array = []
	for group: Dictionary in Config.SKILL_GROUPS:
		listed.append_array(group["stats"])
	var rows: Dictionary = skills.get("_rows")
	var all_listed := listed.size() == Config.PASSIVE_ORDER.size() and Config.SKILL_GROUPS.size() == 3
	for stat: String in Config.PASSIVE_ORDER:
		if not listed.has(stat) or not rows.has(stat) or not Config.KEYSTONES.has(stat):
			all_listed = false
	_check(all_listed, "the skills page is a plain list: %d stats in three groups, one row each" % Config.PASSIVE_ORDER.size())

	# Prices, the level gate, special powers and pet tricks (on a borrowed, richer character).
	var keep_skills := SaveData.skills.duplicate()
	var keep_points := SaveData.skill_points
	SaveData.skill_points = 500
	for i in Config.SKILL_RANK_COST_STEP - 1:
		SaveData.raise_skill("vitality")
	_check(SaveData.skill_rank("vitality") == Config.SKILL_RANK_COST_STEP and SaveData.skill_cost("vitality") == 2
			and SaveData.spent_points() == Config.SKILL_RANK_COST_STEP + 1,
			"a rank costs 1 point, and one more for every %d ranks of that stat already bought" % Config.SKILL_RANK_COST_STEP)
	_check(SaveData.skill_status("bond") == "level" and not SaveData.raise_skill("bond"), "the pet's stat needs level %d" % Config.PET_UNLOCK_LEVEL)
	SaveData.level = 30
	_check(SaveData.raise_skill("bond") and SaveData.has_pet_trick(0) and not SaveData.has_pet_trick(1),
			"...and opens at that level; its first rank teaches the pet its first trick")
	_check(not SaveData.has_keystone("strength") and is_zero_approx(PlayerStats.current().wounded_damage), "a stat's special power is not there from the start")
	while SaveData.skill_rank("strength") < Config.KEYSTONE_RANK - 1:
		SaveData.raise_skill("strength")
	_check(not SaveData.has_keystone("strength"), "...nor one rank short of rank %d" % Config.KEYSTONE_RANK)
	SaveData.raise_skill("strength")
	_check(SaveData.has_keystone("strength") and PlayerStats.current().wounded_damage > 0.0,
			"rank %d of a stat gives its special power" % Config.KEYSTONE_RANK)
	while SaveData.skill_rank("critical") < Config.KEYSTONE_RANK + 12:
		if not SaveData.raise_skill("critical"):
			break
	_check(SaveData.skill_rank("critical") == Config.KEYSTONE_RANK + 12, "ranks have no upper limit")
	_check(SaveData.spent_points() == 500 - SaveData.skill_points + 2, "every point spent is accounted for")
	await _frames(3)
	SaveData.skills = keep_skills
	SaveData.skill_points = keep_points
	SaveData.level = 1
	app.close_screen()
	await _frames(2)

	# --- armory screen: weapon levels, upgrades and perks ---
	app.open_screen("armory")
	await _frames(3)
	var armory: ArmoryScreen = (app.get("_screens") as Dictionary)["armory"]
	_check(not SaveData.raise_weapon_track("shotgun", "power"), "cannot upgrade a weapon with 0 weapon points")
	var shotgun_levels := SaveData.add_weapon_xp("shotgun", SaveData.weapon_xp_needed("shotgun"))
	_check(shotgun_levels == 1 and SaveData.weapon_level("shotgun") == 2 and SaveData.weapon_points("shotgun") == 1,
			"weapon XP gives a weapon level and a weapon point")
	armory.call("_select", "shotgun")
	armory.call("_on_raise", "power")
	_check(SaveData.weapon_rank("shotgun", "power") == 1 and SaveData.weapon_points("shotgun") == 0
			and float(PlayerStats.weapon_mods("shotgun")["damage"]) > 1.0, "a weapon point buys a rank of one of that weapon's upgrades")
	_check(is_equal_approx(float(PlayerStats.weapon_mods("pistol")["damage"]), 1.0), "other weapons are not affected")
	_check(Config.weapon_tracks("pistol") == ["power", "speed", "stability", "reload"], "the pistol has no crate-only upgrades")
	_check(Config.weapon_tracks("shotgun").size() == 6, "crate guns have all six upgrades")
	_check(Config.weapon_tracks("sledge") == ["power", "speed", "spawn", "duration"], "melee weapons have no stability or reload upgrade")
	_check(Config.weapon_tracks("launcher") == ["power", "stability", "reload", "spawn", "duration"],
			"the launcher's rate of fire is its reload upgrade")
	(SaveData.weapons["sledge"] as Dictionary)["points"] = 3
	_check(not SaveData.raise_weapon_track("sledge", "stability") and SaveData.weapon_points("sledge") == 3,
			"a weapon cannot buy an upgrade it does not have")
	(SaveData.weapons["sledge"] as Dictionary)["points"] = 0
	var perks_ok := true
	for id: String in Config.WEAPON_ORDER:
		var perk_list: Array = Config.WEAPON_PERKS[id]
		if perk_list.size() != Config.WEAPON_PERK_COST.size() or perk_list.size() != Config.WEAPON_PERK_LEVELS.size():
			perks_ok = false
		for perk: Dictionary in perk_list:
			for key: String in (perk["mods"] as Dictionary).keys():
				if not (Config.WEAPONS[id] as Dictionary).has(key):
					perks_ok = false
	_check(perks_ok, "every weapon has three perks, and each changes numbers that weapon really has")
	await _frames(3)

	# Rising prices, perks and the reset (on a borrowed, richer shotgun).
	var keep_shotgun: Dictionary = (SaveData.weapons["shotgun"] as Dictionary).duplicate(true)
	var shotgun: Dictionary = SaveData.weapons["shotgun"]
	shotgun["points"] = 200
	for i in Config.WEAPON_RANK_COST_STEP:
		SaveData.raise_weapon_track("shotgun", "power")
	_check(SaveData.weapon_rank("shotgun", "power") == 1 + Config.WEAPON_RANK_COST_STEP and SaveData.weapon_rank_cost("shotgun", "power") == 2,
			"after %d ranks of an upgrade the next ranks cost one point more" % Config.WEAPON_RANK_COST_STEP)
	_check(SaveData.weapon_perk_status("shotgun", 0) == "locked" and not SaveData.buy_weapon_perk("shotgun", 0),
			"a perk needs its weapon level (%d)" % int(Config.WEAPON_PERK_LEVELS[0]))
	shotgun["level"] = 30
	var pellets_before: int = PlayerStats.weapon_def("shotgun")["pellets"]
	armory.call("_on_perk", 0)
	_check(SaveData.weapon_has_perk("shotgun", 0) and int(PlayerStats.weapon_def("shotgun")["pellets"]) == pellets_before + 3
			and int(Config.WEAPONS["shotgun"]["pellets"]) == pellets_before,
			"a perk changes how the weapon works (%d -> %d pellets)" % [pellets_before, int(PlayerStats.weapon_def("shotgun")["pellets"])])
	_check(SaveData.weapon_spent("shotgun") == 200 - SaveData.weapon_points("shotgun") + 1 and int(shotgun["spent"]) == SaveData.weapon_spent("shotgun"),
			"every weapon point spent is accounted for")
	var coins_keep := SaveData.coins
	SaveData.add_coins(100000)
	_check(SaveData.respec_weapon("shotgun") and SaveData.weapon_points("shotgun") == 201 and SaveData.weapon_rank("shotgun", "power") == 0
			and not SaveData.weapon_has_perk("shotgun", 0), "taking the points back empties the upgrades and returns every point")
	SaveData.coins = coins_keep
	SaveData.weapons["shotgun"] = keep_shotgun
	app.close_screen()
	await _frames(2)

	# --- pets: unlocking, rarity caps, buying, the BOND branch ---
	app.open_screen("pets")
	await _frames(3)
	_check(not SaveData.pets_unlocked() and SaveData.pets_owned.is_empty() and SaveData.pet_status("scraps") == "locked",
			"there are no pets before level %d" % Config.PET_UNLOCK_LEVEL)
	_check(not SaveData.buy_pet("soot") and not SaveData.choose_pet("scraps"), "a locked pet cannot be bought or taken along")
	var caps_ok := true
	var last_cap := 0.0
	for rarity: String in Config.PET_RARITY_ORDER:
		var cap := float(Config.PET_RARITIES[rarity]["damage"])
		if cap <= last_cap:
			caps_ok = false
		last_cap = cap
	_check(caps_ok and is_equal_approx(last_cap, 0.15), "rarer pets add more damage, and legendary tops out at 15%")
	_check(is_equal_approx(Config.pet_damage_bonus("cinder", Config.PET_BOND_FULL), 0.15) and is_equal_approx(Config.pet_damage_bonus("cinder", 999), 0.15)
			and Config.pet_damage_bonus("cinder", 0) < 0.15 and Config.pet_damage_bonus("scraps", 999) < Config.pet_damage_bonus("soot", 999),
			"BOND raises a pet's bonus up to its rarity's cap and no further")
	var pet_keep_skills := SaveData.skills.duplicate()
	var pet_keep_points := SaveData.skill_points
	var pet_keep_coins := SaveData.coins
	SaveData.level = Config.PET_UNLOCK_LEVEL - 1
	SaveData.xp = 0
	SaveData.add_xp(SaveData.xp_needed())
	_check(SaveData.pets_unlocked() and SaveData.has_pet("scraps") and SaveData.pet_active == "scraps",
			"the first pet joins by itself at level %d" % Config.PET_UNLOCK_LEVEL)
	var with_pet := PlayerStats.current()
	_check(with_pet.pet == "scraps" and is_equal_approx(with_pet.pet_damage, 0.03 * Config.PET_BOND_BASE) and with_pet.pet_bite > 0.0,
			"a pet adds to the character's damage (+%.1f%%)" % (with_pet.pet_damage * 100.0))
	SaveData.choose_pet("")
	_check(PlayerStats.current().pet == "" and PlayerStats.current().damage_mult < with_pet.damage_mult, "leaving the pet at home removes its bonus")
	SaveData.choose_pet("scraps")
	SaveData.bonus_ranks["bond"] = Config.PET_BOND_FULL
	_check(is_equal_approx(PlayerStats.current().pet_damage, 0.03), "full BOND gives a common pet its whole 3%")
	SaveData.bonus_ranks.erase("bond")
	_check(SaveData.pet_status("soot") == "locked", "the next pet has its own condition")
	SaveData.level = 25
	SaveData.coins = 100
	_check(SaveData.pet_status("soot") == "poor" and not SaveData.buy_pet("soot"), "a pet has to be paid for")
	SaveData.coins = 2000
	_check(SaveData.buy_pet("soot") and SaveData.coins == 2000 - int(Config.PETS["soot"]["price"]) and SaveData.pet_active == "soot"
			and SaveData.pets_owned.size() == 2, "buying a pet takes the coins and brings it along")
	_check(PlayerStats.current().pet_damage > with_pet.pet_damage, "a rarer pet adds more damage")
	SaveData.skill_points = 50
	SaveData.raise_skill("bond")
	SaveData.raise_skill("bond")
	_check(SaveData.has_pet_trick(0) and PlayerStats.current().pet_fetch and not PlayerStats.current().pet_maul
			and SaveData.passive_rank("bond") == 2, "PET BOND on the skills page raises the pet's bonus and teaches it tricks")
	await _frames(3)
	SaveData.skills = pet_keep_skills
	SaveData.skill_points = pet_keep_points
	SaveData.coins = pet_keep_coins
	SaveData.level = 1
	SaveData.xp = 0
	SaveData.pets_owned.clear()
	SaveData.pet_active = ""
	app.close_screen()
	await _frames(2)

	# --- character screen: the bag, wearing, forging, how the hero looks ---
	app.open_screen("character")
	await _frames(3)
	var sheet: CharacterScreen = (app.get("_screens") as Dictionary)["character"]
	_check(SaveData.gear_bag.is_empty() and not SaveData.wear_gear("hard_hat:1"), "cannot wear a piece that is not in the bag")
	SaveData.add_gear("hard_hat:1", 2)
	_check(SaveData.gear_count("hard_hat:1") == 2 and SaveData.gear_new == 2, "found gear goes into the bag")
	var defense_before := SaveData.passive_rank("defense")
	var bare_top := Art.t("player")
	var bare_front := Art.t("hero_front")
	sheet.call("_on_bag_pressed", "hard_hat:1")
	_check(SaveData.gear_in_slot("helmet") == "hard_hat:1" and SaveData.gear_count("hard_hat:1") == 1
			and SaveData.passive_rank("defense") == defense_before + 2, "clicking a piece in the inventory wears it and adds its stat ranks")
	_check(Art.t("player") != bare_top and Art.t("hero_front") != bare_front and Art.t("player_flash") != null,
			"the hero is redrawn with what he wears, in the menu and in the game")
	_check(PlayerStats.current().damage_taken_mult < 1.0, "gear reaches the numbers the game uses")
	SaveData.add_gear("gas_mask:1")
	SaveData.wear_gear("gas_mask:1")
	_check(SaveData.gear_in_slot("helmet") == "gas_mask:1" and SaveData.gear_count("hard_hat:1") == 2
			and SaveData.passive_rank("defense") == defense_before, "a new piece swaps with the one already in its slot")
	SaveData.add_gear("iron_band:1", 2)
	SaveData.add_gear("lucky_ring:2")
	SaveData.wear_gear("iron_band:1")
	SaveData.wear_gear("iron_band:1")
	_check(SaveData.gear_in_slot("ring1") == "iron_band:1" and SaveData.gear_in_slot("ring2") == "iron_band:1", "two rings can be worn")
	SaveData.wear_gear("lucky_ring:2")
	_check(SaveData.gear_in_slot("ring1") == "lucky_ring:2" and SaveData.gear_count("iron_band:1") == 1, "a third ring replaces one of them")
	_check(not SaveData.wear_gear("lucky_ring:2", "helmet") and not SaveData.wear_gear("gas_mask:1", "boots"), "a piece only fits its own slot")
	sheet.call("_on_slot_pressed", "ring2")
	_check(SaveData.gear_in_slot("ring2") == "" and SaveData.gear_count("iron_band:1") == 2, "clicking a slot takes the piece off again")
	# Forging, with the dice fixed.
	var odds: Array = []
	for tier in range(2, 6):
		odds.append(float(Config.gear_tier_def(tier)["chance"]))
	_check(odds == [1.0, 0.9, 0.4, 0.1], "the forging odds are 100% / 90% / 40% / 10%")
	_check(not SaveData.can_forge("gas_mask", 2) and SaveData.forge_gear("gas_mask", 2) == "", "forging needs two identical pieces")
	_check(SaveData.forge_gear("hard_hat", 2, 0.99) == "success" and SaveData.gear_count("hard_hat:2") == 1
			and SaveData.gear_count("hard_hat:1") == 0, "two COMMON pieces always forge into a STURDY one")
	SaveData.add_gear("hard_hat:2", 3, false)
	_check(SaveData.forge_gear("hard_hat", 3, 0.95) == "fail" and SaveData.gear_count("hard_hat:2") == 3 and SaveData.gear_count("hard_hat:3") == 0,
			"a failed forging uses up one of the two pieces")
	_check(SaveData.forge_gear("hard_hat", 3, 0.5) == "success" and SaveData.gear_count("hard_hat:3") == 1 and SaveData.gear_count("hard_hat:2") == 1,
			"a successful forging turns two pieces into one of the next tier")
	SaveData.add_gear("hard_hat:3", 4, false)
	_check(SaveData.forge_gear("hard_hat", 4, 0.9, 0.1) == "broke" and SaveData.gear_count("hard_hat:3") == 3,
			"a failed SUPERIOR forging can destroy both pieces")
	_check(SaveData.forge_gear("hard_hat", 4, 0.9, 0.9) == "fail" and SaveData.gear_count("hard_hat:3") == 2, "...or only one")
	_check(SaveData.forge_gear("hard_hat", 4, 0.3) == "success" and SaveData.gear_count("hard_hat:4") == 1 and SaveData.gear_count("hard_hat:3") == 0,
			"SUPERIOR forges at 40%")
	_check(not SaveData.can_forge("hard_hat", 6) and SaveData.gear_seen.has("hard_hat:4"), "LEGENDARY is the last tier; forged pieces are remembered")
	# Through the forge menu of the inventory.
	SaveData.add_gear("tool_belt:1", 2, false)
	SaveData.add_gear("work_gloves:2", 2, false)
	sheet.call("_open_forge")
	sheet.call("_choose_forge", "tool_belt:1")
	sheet.call("_on_forge_pressed")
	_check(SaveData.gear_count("tool_belt:2") == 1 and SaveData.gear_count("tool_belt:1") == 0, "the forge menu merges a pair that cannot fail at once")
	sheet.call("_choose_forge", "work_gloves:2")
	sheet.call("_on_forge_pressed")
	_check(SaveData.gear_count("work_gloves:2") == 2, "a forging that can fail asks before it is done")
	sheet.call("_on_forge_pressed")
	_check(SaveData.gear_count("work_gloves:2") < 2, "...and happens on the second press")
	sheet.call("_close_forge")
	await _frames(3)
	# The catalogue itself.
	var gear_ok := Config.GEAR_ORDER.size() == Config.GEAR_ITEMS.size()
	var per_type := {}
	for item: String in Config.GEAR_ORDER:
		var gdef: Dictionary = Config.GEAR_ITEMS[item]
		per_type[String(gdef["type"])] = int(per_type.get(String(gdef["type"]), 0)) + 1
		for stat: String in (gdef["stats"] as Dictionary).keys():
			if not Config.PASSIVES.has(stat):
				gear_ok = false
		var boss_only := String(gdef["from"]) == "bosses"
		if boss_only != (String(gdef["type"]) == "ring" or String(gdef["type"]) == "amulet"):
			gear_ok = false
		if not (gdef["look"] as Dictionary).has("style") or not Art.tex.has("gear_" + String(gdef["type"])):
			gear_ok = false
	for type: String in Config.GEAR_TYPE_ORDER:
		if int(per_type.get(type, 0)) < 3:
			gear_ok = false
	_check(gear_ok, "%d pieces of gear in 8 kinds, each with its own look; rings and amulets are boss-only" % Config.GEAR_ORDER.size())
	# Start the fighting with nothing worn, so the stat checks below are exact.
	SaveData.gear_bag.clear()
	for slot: String in Config.GEAR_SLOTS:
		SaveData.gear_worn[slot] = ""
	SaveData.call("_recount_gear")
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
	SaveData.bonus_ranks["defense"] = 50       # 50 ranks = 40% less damage
	game.player.refresh_stats()
	game.damage_player(10.0, game.player.pos + Vector2.RIGHT)
	var taken := 10.0 * (1.0 - SaveData.passive_value("defense"))
	_check(taken < 6.2 and is_equal_approx(hp_before - game.player.hp, taken), "defense reduces damage taken (10 -> %.1f)" % (hp_before - game.player.hp))
	SaveData.bonus_ranks.erase("defense")
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

	# --- gear drops ---
	var pool_ok := true
	for i in 300:
		var common: String = game.pickups.call("_pick_gear", "zombies")
		var common_def: Dictionary = Config.GEAR_ITEMS[Config.gear_item_of(common)]
		var from_boss: String = game.pickups.call("_pick_gear", "bosses")
		if String(common_def["from"]) != "zombies" or int(common_def["map"]) > 1 or Config.gear_tier_of(common) != 1 \
				or String(Config.GEAR_ITEMS[Config.gear_item_of(from_boss)]["from"]) != "bosses":
			pool_ok = false
	_check(pool_ok, "ordinary zombies never drop boss-only or later-map gear")
	game.pickups.spawn_gear(game.player.pos + Vector2(6.0, 0.0), "running_shoes:1")
	await _until(func() -> bool: return game.gear_run.has("running_shoes:1"))
	_check(game.gear_run.has("running_shoes:1") and SaveData.gear_count("running_shoes:1") == 1, "walking over a piece of gear puts it in the bag")

	# --- every weapon fires without errors ---
	for id: String in Config.WEAPON_ORDER:
		game.player.give_weapon(id)
		game.player.hp = game.player.max_hp
		await _frames(200)
		print("  ...  - used weapon '%s' (kills so far: %d)" % [id, game.kills])
	_check(game.kills > 0, "zombies were killed (%d)" % game.kills)

	# --- dual wielding ---
	var pl := game.player
	pl.give_weapon("rifle")       # (whatever the bot was holding: a shotgun already in hand would make the next one dual)
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
	# (No crates for the bot to walk into while the pistols run out.)
	game.pickups.crates.clear()
	game.pickups.set("_crate_timer", 20.0)
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
	for k in 5:
		SaveData.raise_weapon_track("smg", "reload")
	pl.give_weapon("smg")
	pl.ammo = 1
	pl.start_reload()
	var fast_reload: float = pl.get("_reload_total")
	_check(SaveData.weapon_rank("smg", "reload") >= 5 and fast_reload < slow_reload * 0.9,
			"the RELOAD SPEED upgrade shortens the reload (%.2fs -> %.2fs)" % [slow_reload, fast_reload])
	_check(is_equal_approx(float(PlayerStats.weapon_mods("rifle")["reload"]), 1.0), "other weapons keep their own reload speed")
	# A magazine perk shows up in the gun the player is handed.
	((SaveData.weapons["smg"] as Dictionary)["perks"] as Array)[0] = 1
	pl.give_weapon("rifle")      # (put the SMG down first: a second SMG would be dual wielded)
	pl.give_weapon("smg")
	_check(pl.mag_size == int(round(smg_mag * 1.5)) and pl.ammo == pl.mag_size, "a magazine perk gives a bigger magazine (%d -> %d)" % [smg_mag, pl.mag_size])
	((SaveData.weapons["smg"] as Dictionary)["perks"] as Array)[0] = 0
	pl.give_weapon("rifle")
	pl.give_weapon("smg")
	pl.refill_ammo()

	# --- weapon crates can be shot to pieces ---
	# (On a clear patch of ground with no zombies about, so nothing else can
	# stop the test shots.)
	game.pickups.crates.clear()
	game.enemies.clear_all()
	game.pickups.spawn_crate(game.arena.random_free_point(110.0, 160.0), "shotgun")
	var box: Pickups.Crate = game.pickups.crates[0]
	_check(is_equal_approx(box.hp, Config.CRATE_HP), "a fresh crate is undamaged")
	game.projectiles.spawn(box.pos + Vector2(-50.0, 0.0), Vector2.RIGHT, Config.WEAPONS["pistol"], "pistol", 9999.0, 0.0)
	await _until(func() -> bool: return box.hp < Config.CRATE_HP, 30)
	_check(is_equal_approx(box.hp, Config.CRATE_HP - float(Config.WEAPONS["pistol"]["damage"])),
			"a bullet stops in a weapon crate and damages it (by the weapon's plain damage, not yours)")
	var box_hp := box.hp
	game.projectiles.spawn(box.pos + Vector2(-50.0, 0.0), Vector2.RIGHT, Config.WEAPONS["launcher"], "launcher", 1.0, 0.0)
	await _until(func() -> bool: return box.hp < box_hp, 60)
	_check(box.hp <= 0.0, "a grenade blows a weapon crate apart")
	await _until(func() -> bool: return not game.pickups.crates.has(box), 30)
	_check(not game.pickups.crates.has(box) and pl.weapon_id == "smg", "a destroyed crate is gone, and its weapon with it")
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

	# --- there is no rage in the game any more: Space, the right mouse button and LB do nothing ---
	_check(not InputMap.has_action("rage") and not game.has_method("try_activate_rage"), "rage is gone from the game")

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
		# (From three sides, in case a rock or a zombie is in the way of one.)
		var boss_hp := boss.hp
		for side: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP]:
			game.projectiles.spawn(boss.pos + side * (boss.radius + 60.0), -side, Config.WEAPONS["pistol"], "pistol", 25.0, 0.0)
		await _until(func() -> bool: return boss.hp < boss_hp, 60)
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
		var boss_piece := ""
		for piece: Pickups.Loot in game.pickups.loot:
			if String(Config.GEAR_ITEMS[Config.gear_item_of(piece.key)]["from"]) == "bosses":
				boss_piece = piece.key
		for key: String in game.gear_run:
			if String(Config.GEAR_ITEMS[Config.gear_item_of(key)]["from"]) == "bosses":
				boss_piece = key
		_check(boss_piece != "", "a boss always drops a ring or an amulet (%s)" % boss_piece)

	# --- run perks: every 5 waves a choice of three, kept until the run ends ---
	_auto_bot = false
	_auto_perks = false
	GameInput.set_virtual_input(Vector2.ZERO, Vector2.RIGHT, false)
	# (A clean slate, whatever the fight above left behind.)
	game.perks = {}
	game.perks_owed = 0
	game.perk_offer = [] as Array[String]
	game.set("_perks_given", 0)
	game.perk_panel.hide_offer()
	pl.refresh_stats(true)
	_check(Config.perks_earned(0) == 0 and Config.perks_earned(4) == 0 and Config.perks_earned(5) == 1 and Config.perks_earned(9) == 1
			and Config.perks_earned(10) == 2 and Config.perks_earned(25) == 5, "one perk is earned for every %d waves behind you" % Config.PERK_EVERY)
	_finish_wave(game, Config.PERK_EVERY - 1)
	await _until(func() -> bool: return not game.director.in_wave, 30)
	_check(game.perks_owed == 0 and not game.perks_pending(), "clearing wave %d earns no perk yet" % (Config.PERK_EVERY - 1))
	_finish_wave(game, Config.PERK_EVERY)
	await _until(func() -> bool: return game.perks_owed == 1, 30)
	_check(game.perks_owed == 1 and not game.choosing(), "clearing wave %d earns a perk choice (after a moment for the boss)" % Config.PERK_EVERY)
	game.director.intermission = 0.05
	await _until(func() -> bool: return game.choosing(), int(Config.PERK_OFFER_DELAY * 60.0) + 60)
	var offered: Array[String] = game.perk_offer.duplicate()
	var offer_ok := offered.size() == Config.PERK_CHOICES and game.perk_panel.visible
	for i in offered.size():
		if not Config.RUN_PERKS.has(offered[i]) or offered.count(offered[i]) != 1:
			offer_ok = false
	_check(offer_ok, "three different perks are offered (%s)" % ", ".join(offered))
	_check(not game.director.in_wave and game.director.wave == Config.PERK_EVERY and game.perks_pending(),
			"the next wave waits while the choice is open")
	# The character waits too, and cannot be hurt meanwhile.
	var waiting_at := pl.pos
	var waiting_ammo := pl.ammo
	var waiting_hp := pl.hp
	GameInput.set_virtual_input(Vector2.RIGHT, Vector2.RIGHT, true)
	await _frames(20)
	game.damage_player(30.0, pl.pos + Vector2.RIGHT * 40.0)
	await _frames(3)
	GameInput.set_virtual_input(Vector2.ZERO, Vector2.RIGHT, false)
	_check(pl.pos.distance_to(waiting_at) < 0.5 and pl.ammo == waiting_ammo and is_equal_approx(pl.hp, waiting_hp),
			"while choosing, the character stands still, does not shoot and cannot be hurt")
	# Take one (a known one, to check what it does).
	game.perk_offer = ["power", "tough", "mags"] as Array[String]
	var damage_before := pl.stats.damage_mult
	game.choose_perk(0)
	_check(int(game.perks.get("power", 0)) == 1 and game.perks_owed == 0 and not game.choosing() and not game.perk_panel.visible
			and is_equal_approx(pl.stats.damage_mult, damage_before * (1.0 + float(Config.RUN_PERKS["power"]["value"]))),
			"taking HARD HITTER raises damage by %d%% and closes the choice" % int(round(float(Config.RUN_PERKS["power"]["value"]) * 100.0)))
	game.director.intermission = 0.05
	await _until(func() -> bool: return game.director.in_wave, 60)
	_check(game.director.in_wave and game.director.wave == Config.PERK_EVERY + 1, "...and the next wave starts")
	game.enemies.clear_all()
	game.director.to_spawn = 0
	# Every perk does what its card says (each one taken twice, against a character without perks).
	var no_perks := PlayerStats.current({})
	var twice := {}
	for perk_id: String in Config.RUN_PERK_ORDER:
		twice[perk_id] = 2
	var perked := PlayerStats.current(twice)
	var perk_values := {}
	for perk_id: String in Config.RUN_PERK_ORDER:
		perk_values[perk_id] = Config.run_perk_value(perk_id, 2)
	_check(is_equal_approx(perked.max_hp, no_perks.max_hp + float(perk_values["tough"]))
			and is_equal_approx(perked.damage_mult, no_perks.damage_mult * (1.0 + float(perk_values["power"])))
			and is_equal_approx(perked.fire_rate_mult, no_perks.fire_rate_mult * (1.0 + float(perk_values["rapid"])))
			and is_equal_approx(perked.speed_mult, no_perks.speed_mult * (1.0 + float(perk_values["swift"])))
			and is_equal_approx(perked.crit_chance, no_perks.crit_chance + float(perk_values["crit"])),
			"perks: THICK SKIN, HARD HITTER, QUICK TRIGGER, LIGHT FEET and SHARP EYE change health, damage, attack speed, move speed and critical hits")
	_check(is_equal_approx(perked.damage_taken_mult, no_perks.damage_taken_mult * (1.0 - float(perk_values["armor"])))
			and float(perk_values["armor"]) < 2.0 * float(Config.RUN_PERKS["armor"]["value"])
			and is_equal_approx(perked.evasion, no_perks.evasion + float(perk_values["dodge"]))
			and is_equal_approx(perked.wave_heal, float(perk_values["medic"])) and perked.kill_heal_every == int(round(float(perk_values["leech"])))
			and perked.kill_heal_every < int(round(Config.run_perk_value("leech", 1))) and no_perks.kill_heal_every == 0,
			"perks: PADDED VEST, SLIPPERY, FIELD DRESSING and PAYBACK keep you alive (the vest never reaches 100%)")
	_check(is_equal_approx(perked.coin_luck, no_perks.coin_luck + float(perk_values["greed"])) and perked.magnet_mult > no_perks.magnet_mult
			and is_equal_approx(perked.crate_rate, no_perks.crate_rate + float(perk_values["crates"])),
			"perks: FAT PURSE and SUPPLY LINE bring more coins and more crates")
	var gun_plain: Dictionary = PlayerStats.weapon_def("pistol", {})
	var gun_perked: Dictionary = PlayerStats.weapon_def("pistol", twice)
	var mods_plain: Dictionary = PlayerStats.weapon_mods("smg", {})
	var mods_perked: Dictionary = PlayerStats.weapon_mods("smg", twice)
	_check(int(gun_perked["mag"]) == int(ceil(float(int(gun_plain["mag"])) * (1.0 + float(perk_values["mags"]))))
			and int(gun_perked["pierce"]) == int(gun_plain["pierce"]) + 2
			and int(PlayerStats.weapon_def("launcher", twice)["mag"]) == int(Config.WEAPONS["launcher"]["mag"])
			and int(PlayerStats.weapon_def("sledge", twice)["mag"]) == 0
			and is_equal_approx(float(mods_perked["reload"]), float(mods_plain["reload"]) * (1.0 + float(perk_values["reload"])))
			and is_equal_approx(float(mods_perked["duration"]), float(mods_plain["duration"]) * (1.0 + float(perk_values["long"]))),
			"perks: BIG MAGAZINES, PIERCING SHOTS, SLICK RELOAD and FIRM GRIP change the weapons (the launcher keeps its one round)")
	# In the hand right away: more rounds in the magazine being used.
	game.perks = {}
	pl.refresh_stats()
	var rounds_before := pl.mag_size
	var loaded_before := pl.ammo
	game.perks = {"mags": 2}
	pl.refresh_stats()
	_check(pl.mag_size > rounds_before and pl.ammo - loaded_before == pl.mag_size - rounds_before,
			"BIG MAGAZINES puts the extra rounds into the magazine in your hands at once (%d -> %d rounds)" % [rounds_before, pl.mag_size])
	# A perk at its limit, or the pet perk without a pet, is not offered again.
	game.perks = {"pierce": int(Config.RUN_PERKS["pierce"]["max"]), "dodge": int(Config.RUN_PERKS["dodge"]["max"])}
	var limits_ok := true
	for i in 60:
		var rolled := game.roll_perk_offer()
		if rolled.size() != Config.PERK_CHOICES or rolled.has("pierce") or rolled.has("dodge") or (pl.stats.pet == "" and rolled.has("pack")):
			limits_ok = false
	_check(limits_ok, "a perk at its limit is not offered again, and the pet perk only with a pet")
	# FIELD DRESSING and PAYBACK in play.
	game.perks = {"medic": 1, "leech": 1}
	pl.refresh_stats()
	pl.hp = pl.max_hp * 0.4
	_finish_wave(game, Config.PERK_EVERY + 1)
	await _until(func() -> bool: return pl.hp > pl.max_hp * 0.5, 30)
	# (At least that much: the wave's XP can bring a level, which heals as well.)
	_check(pl.hp >= pl.max_hp * (0.4 + Config.run_perk_value("medic", 1)) - 0.5, "FIELD DRESSING heals when a wave is cleared (to %d of %d)" % [int(pl.hp), int(pl.max_hp)])
	pl.hp = pl.max_hp * 0.4
	var payback_hp := pl.hp
	for i in int(Config.run_perk_value("leech", 1)):
		var fodder := game.enemies.spawn(Config.SHAMBLER, pl.pos + Vector2(300.0 + i * 30.0, -260.0))
		game.enemies.damage(fodder, fodder.hp + 1.0, Vector2.RIGHT, 0.0, 0.0, 0.0)
	await _frames(3)
	_check(is_equal_approx(pl.hp, payback_hp + Config.PERK_LEECH_HEAL), "PAYBACK heals %d health every %d kills" % [int(Config.PERK_LEECH_HEAL),
			int(Config.run_perk_value("leech", 1))])
	game.perks = {}
	game.perks_owed = 0
	game.set("_perks_given", Config.perks_earned(game.director.cleared))
	pl.refresh_stats(true)
	game.director.intermission = 99999.0
	game.enemies.clear_all()
	_auto_perks = true

	# --- the pet in a run ---
	_auto_bot = false
	GameInput.set_virtual_input(Vector2.ZERO, Vector2.RIGHT, false)
	game.enemies.clear_all()
	game.director.to_spawn = 0
	await _frames(4)
	game.director.intermission = 99999.0
	_check(game.pet == null, "no pet comes along before level %d" % Config.PET_UNLOCK_LEVEL)
	var run_level := SaveData.level
	var run_xp := SaveData.xp
	var run_points := SaveData.skill_points
	SaveData.level = Config.PET_UNLOCK_LEVEL - 1
	SaveData.xp = 0
	game.gain_xp(SaveData.xp_needed(), "")
	_check(game.pet != null and game.pet.id == "scraps" and pl.stats.pet_damage > 0.0, "reaching level %d mid-run brings the first pet in at once" % Config.PET_UNLOCK_LEVEL)
	var chew := game.enemies.spawn(Config.BRUTE, game.arena.clamp_inside(pl.pos + Vector2(150.0, 0.0), 40.0))
	var chew_hp := chew.hp
	await _until(func() -> bool: return chew.hp < chew_hp or not chew.alive, 300)
	_check(chew.pet_marked and chew.hp < chew_hp, "the pet bites zombies that come close")
	game.enemies.clear_all()
	pl.stats.pet_fetch = true
	var toward := game.arena.rect.get_center() - pl.pos
	var far := game.arena.clamp_inside(pl.pos + (toward.normalized() if toward.length() > 1.0 else Vector2.RIGHT) * 420.0, 60.0)
	game.pickups.spawn_gear(far, "cargo_pants:1")
	await _until(func() -> bool: return game.gear_run.has("cargo_pants:1"), 400)
	_check(game.gear_run.has("cargo_pants:1") and pl.pos.distance_to(far) > 200.0, "a pet that knows FETCH brings dropped gear")
	game.pet.queue_free()
	game.pet = null
	SaveData.level = run_level
	SaveData.xp = run_xp
	SaveData.skill_points = run_points
	SaveData.pets_owned.clear()
	SaveData.pet_active = ""
	pl.refresh_stats()

	# --- the big map: ground in pieces, fog of war, treasure chests, zombies around the player ---
	game.enemies.clear_all()
	var field := game.arena.rect
	var middle := field.get_center()
	# (What a real screen shows; a test without a window has a square one.)
	var screen_size: Vector2 = Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")),
			float(ProjectSettings.get_setting("display/window/size/viewport_height"))) / Config.CAM_ZOOM
	_check(field.size.x >= screen_size.x * 2.5 and field.size.y >= screen_size.y * 2.5,
			"the map is several screens wide and high (%d x %d)" % [int(field.size.x), int(field.size.y)])
	_check(game.decals.chunks_made > 0 and game.decals.chunks_made <= game.decals.chunk_count() and game.decals.has_ground(pl.pos),
			"the ground is made in pieces, as the player gets near them (%d of %d so far)" % [game.decals.chunks_made, game.decals.chunk_count()])
	var chests := game.pickups.chests
	_check(chests.size() == Config.CHEST_COUNT, "%d treasure chests are hidden on the map" % Config.CHEST_COUNT)
	var chests_ok := true
	for hidden: Pickups.Chest in chests:
		if not field.grow(1.0 - Config.CHEST_EDGE_MARGIN).has_point(hidden.pos) or hidden.pos.distance_to(middle) < Config.CHEST_MIN_DIST_FROM_START - 1.0:
			chests_ok = false
	_check(chests_ok, "the chests lie inside the map, away from the starting spot")
	var chest_pool_ok := true
	var chest_wave := game.director.wave
	game.director.wave = 0             # (a late wave can add a tier; see below)
	for i in 300:
		var held: String = game.pickups.roll_chest_gear()
		if String(Config.GEAR_ITEMS[Config.gear_item_of(held)]["from"]) == "bosses" or Config.gear_tier_of(held) > Config.CHEST_TIER_WEIGHTS.size():
			chest_pool_ok = false
	_check(chest_pool_ok, "a chest holds a COMMON to FINE piece, never a boss-only one")
	var early_tiers := 0
	var late_tiers := 0
	for i in 400:
		game.director.wave = 0
		early_tiers += Config.gear_tier_of(game.pickups.roll_chest_gear())
		game.director.wave = 60
		late_tiers += Config.gear_tier_of(game.pickups.roll_chest_gear())
	game.director.wave = chest_wave
	_check(late_tiers > early_tiers, "a chest opened deep into a run holds better gear (average tier %.2f at the start, %.2f at wave 60)" % [
			early_tiers / 400.0, late_tiers / 400.0])
	# (Set the scene, whatever the bot has found by now: the player in the
	# middle, the whole map under fog again, one chest closed and unseen.)
	pl.place(middle)
	game.cam.snap_to(pl.pos)
	game.fog.cover_all()
	game.fog.reveal(pl.pos)
	if not chests.is_empty():
		chests[0].opened = false
		chests[0].found = false
	var chest: Pickups.Chest = null
	for hidden: Pickups.Chest in chests:
		if not hidden.opened and not hidden.found:
			chest = hidden
	if chest != null:
		# Walk up to a chest nobody has seen yet: the fog clears, it shows, it opens.
		_check(not game.fog.is_clear(chest.pos), "the map is under fog where the player has not been")
		var seen_before := game.fog.explored
		var gear_before := game.gear_run.size()
		var opened_before := SaveData.chests_opened
		var coins_before := game.pickups.coin_count + game.coins_run
		var away := (middle - chest.pos).normalized()
		# (A spot that is under fog now and too far from the chest to be uncovered by going there.)
		var still_hidden := chest.pos
		for i in 200:
			var probe := game.arena.random_free_point(20.0, 100.0)
			if not game.fog.is_clear(probe) and probe.distance_to(chest.pos) > Config.FOG_EDGE_RADIUS + 400.0:
				still_hidden = probe
				break
		pl.place(chest.pos + away * (Config.CHEST_OPEN_RADIUS + pl.radius + 80.0))
		game.cam.snap_to(pl.pos)
		await _until(func() -> bool: return chest.found, 30)
		_check(game.fog.is_clear(pl.pos) and game.fog.explored > seen_before, "the fog clears around the player (%.1f%% of the map explored)" % (game.fog.explored * 100.0))
		_check(still_hidden != chest.pos and not game.fog.is_clear(still_hidden), "...and only around the player")
		_check(chest.found and not chest.opened, "a chest shows up once the fog over it has cleared")
		await _until(func() -> bool: return game.decals.has_ground(pl.pos), 30)
		_check(game.decals.has_ground(pl.pos), "there is ground wherever the player goes")
		# (Blood on a part of the map nobody has seen yet makes the ground there.)
		var bare := pl.pos
		for i in 300:
			var probe := game.arena.random_free_point(20.0, 100.0)
			if not game.decals.has_ground(probe):
				bare = probe
				break
		if bare != pl.pos:
			var pieces_before := game.decals.chunks_made
			game.decals.blood_splat(bare, 40.0)
			# (One piece, or two if the splash lies across the line between them.)
			_check(game.decals.has_ground(bare) and game.decals.chunks_made > pieces_before, "ground is made the moment something needs it")
		pl.place(chest.pos + away * 10.0)
		await _until(func() -> bool: return chest.opened, 30)
		_check(chest.opened and game.chests_run >= 1 and SaveData.chests_opened == opened_before + 1, "walking into a chest opens it")
		_check(game.gear_run.size() == gear_before + 1 and SaveData.gear_count(game.gear_run[-1]) >= 1,
				"a chest gives a piece of gear (%s)" % (game.gear_run[-1] if not game.gear_run.is_empty() else "nothing"))
		await _until(func() -> bool: return game.pickups.coin_count + game.coins_run > coins_before, 30)
		_check(game.pickups.coin_count + game.coins_run > coins_before, "...and coins")
		var opened_now := game.chests_run
		await _frames(6)
		_check(game.chests_run == opened_now, "an opened chest stays open")
	else:
		_check(false, "there is a chest left that the bot has not found")

	# Zombies come out of the ground in a ring around the screen, never in view.
	var was_wave := game.director.wave
	var was_in_wave := game.director.in_wave
	game.cam.snap_to(pl.pos)
	await _frames(2)
	game.enemies.clear_all()
	game.director.wave = 8
	game.director.in_wave = true
	game.director.to_spawn = 40
	game.director.call("_spawn_pack")
	var screen_middle := game.cam.center_for(pl.pos)
	var ring_ok := game.enemies.alive_count > 0
	var nearest_new := 99999.0
	for e: Enemy in game.enemies.active:
		var gap := e.pos.distance_to(screen_middle)
		nearest_new = minf(nearest_new, gap)
		if gap < game.spawn_min - 1.0 or not field.has_point(e.pos) or e.spawn_t <= 0.0:
			ring_ok = false
	_check(ring_ok, "a pack claws out of the ground around the player, out of sight (%d zombies, the nearest %d px away, the screen ends at %d)" % [
			game.enemies.alive_count, int(nearest_new), int(game.spawn_min - Config.CAM_AIM_LEAD_MAX - Config.SPAWN_RING_MARGIN)])

	# A zombie left far behind is taken off the field and owed back; a boss digs its way back.
	game.enemies.clear_all()
	game.director.to_spawn = 0
	game.director.set("_pack_timer", 30.0)
	var kills_before := game.kills
	# (Only from one corner of the map to the opposite one is it far enough.)
	pl.place(game.arena.clamp_inside(field.position, pl.radius + 4.0))
	game.cam.snap_to(pl.pos)
	var far_corner := game.arena.clamp_inside(field.end, 90.0)
	_check(far_corner.distance_to(pl.pos) > game.leash_dist + 50.0, "(the map is wide enough to leave a zombie behind: %d px, it gives up at %d)" % [
			int(far_corner.distance_to(pl.pos)), int(game.leash_dist)])
	var straggler := game.enemies.spawn(Config.SHAMBLER, far_corner)
	await _until(func() -> bool: return not straggler.alive, 30)
	_check(not straggler.alive and game.director.to_spawn == 1 and game.kills == kills_before,
			"a zombie left far behind gives up and comes back with a later pack (no reward)")
	var digger := game.enemies.spawn(Config.BOSS, far_corner)
	await _until(func() -> bool: return digger.pos.distance_to(pl.pos) < game.boss_leash, 30)
	_check(digger.alive and digger.pos.distance_to(pl.pos) < game.boss_leash, "a boss left far behind digs its way back to the player")
	game.enemies.clear_all()
	game.director.to_spawn = 0
	game.director.wave = was_wave
	game.director.in_wave = was_in_wave

	# Weapon crates land near the player, wherever that is.
	var crate_spots_ok := true
	for i in 30:
		var spot: Vector2 = game.pickups.call("_random_crate_spot")
		if spot.distance_to(pl.pos) > Config.CRATE_MAX_DIST_FROM_PLAYER + 1.0 or not field.has_point(spot):
			crate_spots_ok = false
	_check(crate_spots_ok, "weapon crates land near the player, wherever on the map that is")

	# --- the zombies with an attack of their own: Gobber, Chucker, Gasbag, Lunger ---
	# (In the middle of the map, where there are no rocks, with nothing else about.)
	var shots := game.enemy_shots
	var new_kinds := [Config.GOBBER, Config.CHUCKER, Config.GASBAG, Config.LUNGER]
	var kinds_ok := true
	for kind: int in new_kinds:
		for v in int(Art.ENEMY_VARIANTS[kind]):
			if Art.enemy_tex(kind, v) == null or Art.enemy_hurt_tex(kind, v) == null:
				kinds_ok = false
		if Art.enemy_flash_tex(kind) == null or not Config.GEAR_DROP_CHANCE.has(kind) or not Config.ENEMIES[kind].has("tip"):
			kinds_ok = false
	_check(kinds_ok, "every new kind of zombie has its pictures (a wounded one too), a tip and a gear drop chance")
	game.enemies.clear_all()
	game.pickups.crates.clear()
	game.pickups.set("_crate_timer", 9999.0)
	var stand := middle + Vector2(110.0, 0.0)
	pl.place(stand)
	game.cam.snap_to(pl.pos)
	game.fog.reveal(pl.pos, 1.5)
	pl.stats.evasion = 0.0
	pl.hp = pl.max_hp
	await _frames(3)

	# The Gobber: stops in range, swells (the warning), spits; a hit while it swells stops it.
	SaveData.enemies_seen.clear()
	game.enemies.set("_tip_owed", [false, false, false, false, true, true, true, true] as Array[bool])
	var gob := game.enemies.spawn(Config.GOBBER, middle + Vector2(-110.0, 0.0))
	gob.attack_t = 0.05
	await _until(func() -> bool: return gob.state == EnemyManager.B_WINDUP, 60)
	_check(gob.state == EnemyManager.B_WINDUP and shots.spits.is_empty(), "a Gobber in range stops and swells up before it spits")
	_check(SaveData.enemies_seen.has("gobber"), "the first Gobber ever seen is introduced with a tip")
	var gob_at := gob.pos
	await _until(func() -> bool: return not shots.spits.is_empty(), 90)
	_check(not shots.spits.is_empty() and gob.pos.distance_to(gob_at) < 12.0, "...then spits a glob at the player")
	var hp_spit := pl.hp
	pl.invuln = 0.0
	await _until(func() -> bool: return pl.hp < hp_spit or shots.spits.is_empty(), 120)
	_check(pl.hp < hp_spit, "the spit hurts a player who stands still (%.0f damage)" % (hp_spit - pl.hp))
	gob.attack_t = 0.05
	await _until(func() -> bool: return gob.state == EnemyManager.B_WINDUP, 90)
	game.enemies.damage(gob, 1.0, Vector2.LEFT, 0.0, 0.3, 0.0)
	await _until(func() -> bool: return gob.state == EnemyManager.B_CHASE, 30)
	_check(gob.alive and gob.state == EnemyManager.B_CHASE and gob.attack_t > 0.5 and shots.spits.is_empty(),
			"shooting a Gobber while it swells makes it swallow its spit")
	game.enemies.clear_all()
	var lurker := game.enemies.spawn(Config.GOBBER, game.arena.clamp_inside(pl.pos + Vector2(-900.0, 0.0), 40.0))
	lurker.attack_t = 0.0
	var lurk_from := lurker.pos.distance_to(pl.pos)
	await _frames(40)
	_check(lurker.state == EnemyManager.B_CHASE and shots.spits.is_empty() and lurker.pos.distance_to(pl.pos) < lurk_from - 10.0,
			"a Gobber that is out of sight does not spit: it comes closer first")
	game.enemies.clear_all()
	# Spit is stopped by a rock and by a weapon crate (and wears the crate down).
	var rock := game.arena.obs_pos[0]
	var rock_r := game.arena.obs_radius[0]
	pl.place(rock + Vector2(rock_r + 70.0, 0.0))
	game.cam.snap_to(pl.pos)
	var hp_rock := pl.hp
	pl.invuln = 0.0
	shots.spit(rock + Vector2(-rock_r - 50.0, 0.0), Vector2.RIGHT, Config.ENEMIES[Config.GOBBER], 10.0)
	await _until(func() -> bool: return shots.spits.is_empty(), 90)
	_check(shots.spits.is_empty() and is_equal_approx(pl.hp, hp_rock), "a rock stops spit")
	pl.place(stand)
	game.cam.snap_to(pl.pos)
	game.pickups.spawn_crate(middle + Vector2(0.0, -150.0), "shotgun")
	var spat_on: Pickups.Crate = game.pickups.crates[0]
	shots.spit(spat_on.pos + Vector2(-80.0, 0.0), Vector2.RIGHT, Config.ENEMIES[Config.GOBBER], 10.0)
	await _until(func() -> bool: return shots.spits.is_empty(), 90)
	_check(is_equal_approx(spat_on.hp, Config.CRATE_HP - Config.ENEMY_SHOT_CRATE_DAMAGE), "spit that hits a weapon crate damages it")
	game.pickups.crates.clear()

	# The Chucker: lobs rubble onto the spot where the player stands.
	var chuck := game.enemies.spawn(Config.CHUCKER, middle + Vector2(-120.0, 0.0))
	chuck.attack_t = 0.05
	await _until(func() -> bool: return not shots.lobs.is_empty(), 150)
	_check(shots.lobs.size() == 1 and shots.lobs[0].target.distance_to(pl.pos) <= float(Config.ENEMIES[Config.CHUCKER]["lob_aim_error"]) + 1.0,
			"a Chucker lobs rubble at the spot where the player stands")
	var hp_lob := pl.hp
	pl.invuln = 0.0
	await _until(func() -> bool: return shots.lobs.is_empty(), 150)
	_check(pl.hp < hp_lob, "rubble hurts a player who stays in the red ring (%.0f damage)" % (hp_lob - pl.hp))
	game.enemies.clear_all()
	shots.lob(pl.pos + Vector2(-200.0, 0.0), pl.pos, Config.ENEMIES[Config.CHUCKER], 20.0)
	pl.place(stand + Vector2(0.0, 170.0))
	hp_lob = pl.hp
	pl.invuln = 0.0
	await _until(func() -> bool: return shots.lobs.is_empty(), 150)
	_check(is_equal_approx(pl.hp, hp_lob), "...and misses one who steps out of it")

	# The Gasbag: bursts when it dies, takes zombies along, sets off the next one.
	pl.place(stand)
	var bag := game.enemies.spawn(Config.GASBAG, middle + Vector2(-190.0, 0.0))
	var beside_a := game.enemies.spawn(Config.SHAMBLER, bag.pos + Vector2(40.0, 30.0))
	var beside_b := game.enemies.spawn(Config.SHAMBLER, bag.pos + Vector2(-40.0, -30.0))
	var next_bag := game.enemies.spawn(Config.GASBAG, bag.pos + Vector2(0.0, 90.0))
	next_bag.hp = 10.0
	var kills_gas := game.kills
	var hp_gas := pl.hp
	pl.invuln = 0.0
	game.enemies.damage(bag, bag.hp + 1.0, Vector2.RIGHT, 0.0, 0.0, 0.0)
	await _until(func() -> bool: return not beside_a.alive and not beside_b.alive, 30)
	_check(not beside_a.alive and not beside_b.alive, "a Gasbag that is shot bursts and takes the zombies around it along")
	await _until(func() -> bool: return not next_bag.alive and game.kills >= kills_gas + 4, 60)
	_check(not next_bag.alive and game.kills >= kills_gas + 4, "...and sets off the next Gasbag (all of them the player's kills)")
	_check(is_equal_approx(pl.hp, hp_gas), "the burst does not reach a player who keeps away")
	game.enemies.clear_all()
	await _frames(20)
	var creeper := game.enemies.spawn(Config.GASBAG, pl.pos + Vector2(-70.0, 0.0))
	await _until(func() -> bool: return creeper.state == EnemyManager.B_WINDUP, 150)
	_check(creeper.alive and creeper.state == EnemyManager.B_WINDUP, "a Gasbag that reaches the player swells up")
	hp_gas = pl.hp
	await _until(func() -> bool: return not creeper.alive, 90)
	pl.invuln = 0.0
	await _until(func() -> bool: return pl.hp < hp_gas, 30)
	_check(not creeper.alive and pl.hp < hp_gas, "...and bursts in the player's face (%.0f damage)" % (hp_gas - pl.hp))
	game.enemies.clear_all()
	await _frames(20)

	# The Lunger: crouches, leaps in a straight line, lands dazed.
	pl.hp = pl.max_hp
	var lun := game.enemies.spawn(Config.LUNGER, middle + Vector2(-110.0, 0.0))
	lun.charge_cd = 0.05
	await _until(func() -> bool: return lun.state == EnemyManager.B_WINDUP, 60)
	_check(lun.state == EnemyManager.B_WINDUP, "a Lunger crouches before it leaps")
	var crouched_at := lun.pos
	await _until(func() -> bool: return lun.state == EnemyManager.B_CHARGE, 60)
	var hp_leap := pl.hp
	pl.invuln = 0.0
	await _until(func() -> bool: return lun.state == EnemyManager.B_RECOVER, 90)
	_check(lun.state == EnemyManager.B_RECOVER and lun.pos.distance_to(crouched_at) > 120.0 and pl.hp < hp_leap,
			"...then leaps at the player and hits one who stands still (%.0f damage)" % (hp_leap - pl.hp))
	game.enemies.clear_all()
	var lun2 := game.enemies.spawn(Config.LUNGER, middle + Vector2(-110.0, 0.0))
	lun2.charge_cd = 0.05
	await _until(func() -> bool: return lun2.state == EnemyManager.B_CHARGE, 120)
	pl.place(stand + Vector2(0.0, 170.0))
	hp_leap = pl.hp
	pl.invuln = 0.0
	await _until(func() -> bool: return lun2.state == EnemyManager.B_RECOVER, 90)
	_check(lun2.state == EnemyManager.B_RECOVER and is_equal_approx(pl.hp, hp_leap), "...and flies past one who steps aside, landing dazed")
	game.enemies.clear_all()
	_check(SaveData.enemies_seen.size() == 4, "each new kind is introduced once (%s)" % ", ".join(SaveData.enemies_seen))

	# Who is in a wave.
	var mix_wave := game.director.wave
	var counted := {}
	game.director.wave = 1
	for i in 300:
		counted[game.director.call("_pick_kind")] = true
	_check(counted.size() == 1 and counted.has(Config.SHAMBLER), "wave 1 is all Shamblers")
	counted = {}
	game.director.wave = 30
	for i in 4000:
		var picked: int = game.director.call("_pick_kind")
		counted[picked] = int(counted.get(picked, 0)) + 1
	_check(counted.size() == 7, "by wave 30 every kind of zombie is in the horde")
	_check(int(counted.get(Config.SHAMBLER, 0)) > 4000 * (Config.ENEMY_MIX_SHAMBLERS - 0.04), "...and Shamblers are still a good part of it (%d of 4000)" % int(counted.get(Config.SHAMBLER, 0)))
	game.director.wave = mix_wave
	shots.spits.clear()
	shots.lobs.clear()
	pl.refresh_stats()
	pl.hp = pl.max_hp

	# --- death and game over ---
	_auto_bot = false
	GameInput.clear_virtual_input()
	var coins_in_run := game.coins_run
	var saved_coins := SaveData.coins
	# The SECOND WIND keystone turns the first killing blow into a second chance.
	game.player.stats.second_wind = 0.3
	game.player.stats.evasion = 0.0
	game.player.invuln = 0.0     # (a zombie may have just hit the bot; skip the safety window)
	game.damage_player(99999.0, game.player.pos + Vector2.RIGHT)
	_check(game.state == Game.State.PLAYING and game.player.second_wind_used and is_equal_approx(game.player.hp, game.player.max_hp * 0.3),
			"SECOND WIND survives one killing blow")
	game.player.invuln = 0.0
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
	_check(game.perks_owed == Config.perks_earned(every) and game.perks_owed >= 1 and game.perks.is_empty(),
			"...and with the perk choices for the waves it skipped (%d)" % game.perks_owed)
	game.director.intermission = 0.05
	await _until(func() -> bool: return game.director.in_wave, 300)
	_check(game.director.wave == every + 1 and game.perks.size() == 1 and game.perks_owed == 0,
			"...and begins at wave %d once the perk is chosen" % (every + 1))
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
	_check(spent > 0 and SaveData.respec() and SaveData.skill_points == unspent + spent and SaveData.passive_rank("vitality") == 0
			and SaveData.skills.is_empty(), "resetting gives every spent skill point back")
	SaveData.raise_skill("evasion")

	# --- save file round trip ---
	var coins_now := SaveData.coins
	var level_now := SaveData.level
	var xp_now := SaveData.xp
	var points_now := SaveData.skill_points
	var shotgun_power := SaveData.weapon_rank("shotgun", "power")
	var pistol_level := SaveData.weapon_level("pistol")
	SaveData.gear_bag.clear()
	SaveData.add_gear("snake_ring:2", 3)
	SaveData.wear_gear("snake_ring:2")
	SaveData.pets_owned = ["scraps", "soot"]
	SaveData.pet_active = "soot"
	SaveData.save_game()
	SaveData.call("_reset_to_defaults")
	SaveData.load_game()
	_check(SaveData.gear_in_slot("ring1") == "snake_ring:2" and SaveData.gear_count("snake_ring:2") == 2
			and SaveData.gear_seen.has("snake_ring:2") and SaveData.gear_rank("evasion") == 6, "save file restores gear, worn and in the bag")
	_check(SaveData.pets_owned == ["scraps", "soot"] and SaveData.pet_active == "soot", "save file restores the pets")
	_check(SaveData.coins == coins_now and SaveData.level == level_now and SaveData.xp == xp_now and SaveData.skill_points == points_now,
			"save file restores coins, level, XP and skill points")
	_check(SaveData.skill_rank("evasion") == 1 and SaveData.passive_rank("evasion") == 7
			and SaveData.weapon_rank("shotgun", "power") == shotgun_power
			and SaveData.weapon_level("pistol") == pistol_level, "save file restores the bought ranks and weapon levels")
	_check(SaveData.maps_unlocked == 2 and SaveData.map_cleared(0) and SaveData.selected_map == 1,
			"save file restores map progress")

	# --- weapon upgrades saved by older versions are handed back as weapon points ---
	SaveData.weapons["sledge"] = {"level": 4, "xp": 0, "points": 1, "ranks": {"power": 12, "stability": 3}}
	SaveData.save_game()
	SaveData.load_game()
	_check(SaveData.weapon_points("sledge") == 1 + 10 + 2 * 2 + 3 and SaveData.weapon_rank("sledge", "power") == 0
			and SaveData.weapon_points_returned >= 17, "the oldest plain weapon ranks are handed back as weapon points")
	SaveData.weapons["sledge"] = {"level": 4, "xp": 0, "points": 0, "tree": {"power.5": 1}, "spent": 7}
	SaveData.save_game()
	SaveData.load_game()
	_check(SaveData.weapon_points("sledge") == 7 and SaveData.weapon_spent("sledge") == 0, "points spent in the old weapon trees are handed back")
	# ...and ranks in an upgrade a weapon does not have (any more) are refunded.
	SaveData.weapons["sledge"] = {"level": 4, "xp": 0, "points": 0, "upgrades": {"stability": 3, "power": 2}, "perks": [0, 1, 0], "spent": 9}
	SaveData.save_game()
	SaveData.load_game()
	_check(SaveData.weapon_rank("sledge", "power") == 2 and SaveData.weapon_rank("sledge", "stability") == 0 and SaveData.weapon_has_perk("sledge", 1)
			and SaveData.weapon_points("sledge") == 3 and SaveData.weapon_spent("sledge") == 2 + int(Config.WEAPON_PERK_COST[1]),
			"an upgrade a weapon no longer has is dropped and its points refunded")

	# --- saves from before the plain skills page: whatever was spent on the older skill screens comes back ---
	var flat_file := FileAccess.open(SaveData.save_path, FileAccess.WRITE)
	flat_file.store_string(JSON.stringify({"version": 2, "coins": 55, "level": 9, "skill_points": 3,
			"passives": {"vitality": 12, "strength": 4}}))
	flat_file.close()
	SaveData.call("_reset_to_defaults")
	SaveData.load_game()
	_check(SaveData.points_returned == 10 + 2 * 2 + 4 and SaveData.skill_points == 3 + SaveData.points_returned and SaveData.skills.is_empty(),
			"a save from the very first stat list gets its spent points back (%d)" % SaveData.points_returned)
	# ...and so does one from the time of the skill tree (which the owner had removed).
	var tree_file := FileAccess.open(SaveData.save_path, FileAccess.WRITE)
	tree_file.store_string(JSON.stringify({"version": 2, "coins": 55, "level": 9, "skill_points": 2,
			"tree": {"grit.root": 3, "vitality.1": 5, "vitality.2": 2, "fury.root": 1}, "tree_spent": 13}))
	tree_file.close()
	SaveData.call("_reset_to_defaults")
	SaveData.load_game()
	_check(SaveData.skills.is_empty() and SaveData.points_returned == 13 and SaveData.skill_points == 2 + 13 and SaveData.passive_rank("vitality") == 0,
			"points spent in the old skill tree are handed back (%d)" % SaveData.points_returned)
	# Once spent on the new page and saved, they stay spent.
	SaveData.raise_skill("vitality")
	SaveData.raise_skill("vitality")
	SaveData.save_game()
	SaveData.call("_reset_to_defaults")
	SaveData.load_game()
	_check(SaveData.skill_rank("vitality") == 2 and SaveData.skill_points == 13 and SaveData.points_returned == 0,
			"...and are not handed back a second time")

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
	p.ammo = 3
	_pad_button(JOY_BUTTON_X, true)
	await _frames(2)
	_pad_button(JOY_BUTTON_X, false)
	_check(p.reloading, "X reloads")
	p.refill_ammo()
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

	# --- the perk choice: keys, gamepad and mouse ---
	var run: Game = app.game
	var lock_frames := int(Config.PERK_CLICK_LOCK * 60.0) + 6
	_auto_perks = false
	GameInput.set_virtual_input(Vector2.ZERO, Vector2.RIGHT, false)
	run.director.intermission = 99999.0
	run.enemies.clear_all()
	run.perks = {}
	run.call("_owe_perks", int(run.get("_perks_given")) + 3, 0.05)
	await _until(func() -> bool: return run.choosing(), 60)
	# (The very first moment the cards ignore everything, so nothing is taken by accident.)
	_key(KEY_ENTER, true)
	await _frames(2)
	_key(KEY_ENTER, false)
	await _frames(2)
	_check(run.choosing() and run.perks.is_empty(), "a key pressed the very moment the perk choice appears takes nothing")
	await _frames(lock_frames)
	var cards: Array = run.perk_panel.get("_cards")
	_check(run.perk_panel.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and (cards[1] as Button).has_focus(),
			"the perk choice opens with a card highlighted and the mouse pointer showing")
	var third_perk := run.perk_offer[2]
	_key(KEY_RIGHT, true)
	await _frames(2)
	_key(KEY_RIGHT, false)
	await _frames(2)
	_key(KEY_ENTER, true)
	await _frames(2)
	_key(KEY_ENTER, false)
	await _frames(2)
	_check(int(run.perks.get(third_perk, 0)) == 1 and run.perks_owed == 2, "the arrow keys and Enter take a perk (%s)" % third_perk)
	await _until(func() -> bool: return run.choosing(), 60)
	await _frames(lock_frames)
	var first_perk := run.perk_offer[0]
	var first_before := int(run.perks.get(first_perk, 0))
	_pad_button(JOY_BUTTON_DPAD_LEFT, true)
	await _frames(2)
	_pad_button(JOY_BUTTON_DPAD_LEFT, false)
	await _frames(2)
	_pad_button(JOY_BUTTON_A, true)
	await _frames(2)
	_pad_button(JOY_BUTTON_A, false)
	await _frames(2)
	_check(int(run.perks.get(first_perk, 0)) == first_before + 1 and run.perks_owed == 1, "the gamepad takes a perk (%s)" % first_perk)
	await _until(func() -> bool: return run.choosing(), 60)
	await _frames(lock_frames)
	var middle_perk := run.perk_offer[1]
	var middle_before := int(run.perks.get(middle_perk, 0))
	var middle_card: Button = cards[1]
	var card_at: Vector2 = get_viewport().get_final_transform() * (middle_card.global_position + middle_card.size * 0.5)
	get_viewport().notification(NOTIFICATION_VP_MOUSE_ENTER)
	_mouse_move(card_at)
	await _frames(2)
	_mouse_button(MOUSE_BUTTON_LEFT, true, card_at)
	await _frames(2)
	_mouse_button(MOUSE_BUTTON_LEFT, false, card_at)
	await _frames(3)
	_check(int(run.perks.get(middle_perk, 0)) == middle_before + 1 and run.perks_owed == 0 and not run.choosing()
			and not run.perk_panel.visible, "a mouse click takes a perk (%s), and the game goes on" % middle_perk)
	_auto_perks = true

	# --- the skills page: keys, gamepad and mouse ---
	app.pause_game()
	await _frames(2)
	app.quit_to_menu()
	await _frames(3)
	SaveData.skills = {}
	SaveData.skill_points = 3
	app.open_screen("skills")
	await _frames(6)
	var skill_page: SkillScreen = (app.get("_screens") as Dictionary)["skills"]
	var page_rows: Dictionary = skill_page.get("_rows")
	_check((page_rows["vitality"]["plus"] as Button).has_focus(), "the skills page opens with the first +1 button highlighted")
	_key(KEY_ENTER, true)
	await _frames(2)
	_key(KEY_ENTER, false)
	await _frames(2)
	_check(SaveData.skill_rank("vitality") == 1 and SaveData.skill_points == 2, "Enter buys a rank of the highlighted stat")
	_key(KEY_DOWN, true)
	await _frames(2)
	_key(KEY_DOWN, false)
	await _frames(2)
	_check((page_rows["defense"]["plus"] as Button).has_focus(), "the arrow keys walk down the list")
	_pad_button(JOY_BUTTON_DPAD_DOWN, true)
	await _frames(2)
	_pad_button(JOY_BUTTON_DPAD_DOWN, false)
	await _frames(2)
	_pad_button(JOY_BUTTON_A, true)
	await _frames(2)
	_pad_button(JOY_BUTTON_A, false)
	await _frames(2)
	_check(SaveData.skill_rank("evasion") == 1 and SaveData.skill_rank("defense") == 0 and SaveData.skill_points == 1,
			"the gamepad walks the list and A buys a rank")
	# (Fake mouse events are given in window pixels; without a real display
	# the window is not the size of the game's canvas, so convert. The window
	# also has to be told that the mouse is over it.)
	var damage_plus: Button = page_rows["strength"]["plus"]
	var to_window := get_viewport().get_final_transform()
	var on_screen: Vector2 = to_window * (damage_plus.global_position + damage_plus.size * 0.5)
	get_viewport().notification(NOTIFICATION_VP_MOUSE_ENTER)
	_mouse_move(on_screen)
	await _frames(2)
	_check(damage_plus.has_focus(), "pointing at a +1 button highlights it")
	_mouse_button(MOUSE_BUTTON_LEFT, true, on_screen)
	await _frames(2)
	_mouse_button(MOUSE_BUTTON_LEFT, false, on_screen)
	await _frames(2)
	_check(SaveData.skill_rank("strength") == 1 and SaveData.skill_points == 0, "clicking +1 buys a rank")
	_key(KEY_ESCAPE, true)
	await _frames(2)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_check(app.state == Main.State.MENU and skill_page.is_visible_in_tree() == false, "Esc leaves the skills page")

	# --- the character screen: click a piece to wear it, click its slot to take it off ---
	SaveData.add_gear("work_gloves:1")
	app.open_screen("character")
	await _frames(6)
	var sheet: CharacterScreen = (app.get("_screens") as Dictionary)["character"]
	var bag_tile: Control = (sheet.get("_bag_grid") as Control).get_child(0)
	var tile_at: Vector2 = to_window * (bag_tile.global_position + bag_tile.size * 0.5)
	_mouse_move(tile_at)
	await _frames(2)
	_mouse_button(MOUSE_BUTTON_LEFT, true, tile_at)
	await _frames(2)
	_mouse_button(MOUSE_BUTTON_LEFT, false, tile_at)
	await _frames(4)
	_check(SaveData.gear_in_slot("gloves") == "work_gloves:1" and SaveData.gear_count("work_gloves:1") == 0, "clicking a piece in the inventory wears it")
	var slot_tile: Control = ((sheet.get("_slot_boxes") as Dictionary)["gloves"] as Control).get_child(0)
	var slot_at: Vector2 = to_window * (slot_tile.global_position + slot_tile.size * 0.5)
	_mouse_move(slot_at)
	await _frames(2)
	_mouse_button(MOUSE_BUTTON_LEFT, true, slot_at)
	await _frames(2)
	_mouse_button(MOUSE_BUTTON_LEFT, false, slot_at)
	await _frames(4)
	_check(SaveData.gear_in_slot("gloves") == "" and SaveData.gear_count("work_gloves:1") == 1, "clicking the slot takes it off again")
	_key(KEY_ESCAPE, true)
	await _frames(2)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_check(app.state == Main.State.MENU and not sheet.is_visible_in_tree(), "Esc leaves the character screen")

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
