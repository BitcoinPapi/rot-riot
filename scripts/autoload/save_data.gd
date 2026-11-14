extends Node
## Everything that is kept between sessions: coins, the character's level and
## skill points, each weapon's level and points, best scores and settings.
## Saved as JSON in the user data folder (user://save.json).
##
## This file only stores and changes the numbers. What the numbers DO in the
## game is worked out in scripts/game/player_stats.gd.

signal coins_changed
signal settings_changed
signal progress_changed          # level, points or ranks changed

const SAVE_VERSION := 2

var save_path := "user://save.json"

var coins: int = 0

# Character
var level: int = 1
var xp: int = 0                  # XP inside the current level
var skill_points: int = 0        # unspent
var points_bought: int = 0       # how many were bought with coins (sets the next price)
var passives: Dictionary = {}    # passive id -> rank

# Weapons: id -> {"level": int, "xp": int, "points": int, "ranks": {track: rank}}
var weapons: Dictionary = {}

var best_score: int = 0
var best_wave: int = 0
var total_kills: int = 0
var runs_played: int = 0
var settings: Dictionary = {}

## True for one session after an old save was converted (the menu says so once).
var was_reset_by_update := false


func _ready() -> void:
	_reset_to_defaults()
	load_game()
	apply_settings()


func _reset_to_defaults() -> void:
	coins = 0
	_reset_progress()
	best_score = 0
	best_wave = 0
	total_kills = 0
	runs_played = 0
	was_reset_by_update = false
	settings = {
		"master_volume": Config.DEFAULT_MASTER_VOLUME,
		"sfx_volume": Config.DEFAULT_SFX_VOLUME,
		"fullscreen": Config.DEFAULT_FULLSCREEN,
		"screen_shake": Config.DEFAULT_SCREEN_SHAKE,
	}


func _reset_progress() -> void:
	level = 1
	xp = 0
	skill_points = 0
	points_bought = 0
	passives = {}
	for id: String in Config.PASSIVE_ORDER:
		passives[id] = 0
	weapons = {}
	for id: String in Config.WEAPON_ORDER:
		weapons[id] = _new_weapon_entry()


func _new_weapon_entry() -> Dictionary:
	var ranks := {}
	for track: String in Config.WEAPON_TRACK_ORDER:
		ranks[track] = 0
	return {"level": 1, "xp": 0, "points": 0, "ranks": ranks}


# ----------------------------------------------------------------------------
#  Load / save
# ----------------------------------------------------------------------------
func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file was unreadable, starting fresh.")
		return
	var data: Dictionary = parsed

	# Settings and records survive every version of the save file.
	best_score = int(data.get("best_score", 0))
	best_wave = int(data.get("best_wave", 0))
	total_kills = int(data.get("total_kills", 0))
	runs_played = int(data.get("runs_played", 0))
	var saved_settings: Variant = data.get("settings", {})
	if typeof(saved_settings) == TYPE_DICTIONARY:
		for key: String in settings.keys():
			if (saved_settings as Dictionary).has(key):
				var value: Variant = (saved_settings as Dictionary)[key]
				if typeof(settings[key]) == TYPE_BOOL:
					settings[key] = bool(value)
				else:
					settings[key] = clampf(float(value), 0.0, 1.0)

	# Saves from before the progression rework: coins and the old upgrades are
	# wiped once (agreed with the owner), everything else is kept.
	if int(data.get("version", 1)) < SAVE_VERSION:
		was_reset_by_update = runs_played > 0
		save_game()
		return

	coins = maxi(int(data.get("coins", 0)), 0)
	level = maxi(int(data.get("level", 1)), 1)
	xp = maxi(int(data.get("xp", 0)), 0)
	skill_points = maxi(int(data.get("skill_points", 0)), 0)
	points_bought = maxi(int(data.get("points_bought", 0)), 0)
	var saved_passives: Variant = data.get("passives", {})
	if typeof(saved_passives) == TYPE_DICTIONARY:
		for id: String in Config.PASSIVE_ORDER:
			passives[id] = maxi(int((saved_passives as Dictionary).get(id, 0)), 0)
	var saved_weapons: Variant = data.get("weapons", {})
	if typeof(saved_weapons) == TYPE_DICTIONARY:
		for id: String in Config.WEAPON_ORDER:
			var entry: Variant = (saved_weapons as Dictionary).get(id)
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var w: Dictionary = weapons[id]
			w["level"] = maxi(int((entry as Dictionary).get("level", 1)), 1)
			w["xp"] = maxi(int((entry as Dictionary).get("xp", 0)), 0)
			w["points"] = maxi(int((entry as Dictionary).get("points", 0)), 0)
			var saved_ranks: Variant = (entry as Dictionary).get("ranks", {})
			if typeof(saved_ranks) == TYPE_DICTIONARY:
				var ranks: Dictionary = w["ranks"]
				for track: String in Config.WEAPON_TRACK_ORDER:
					ranks[track] = maxi(int((saved_ranks as Dictionary).get(track, 0)), 0)


func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"coins": coins,
		"level": level,
		"xp": xp,
		"skill_points": skill_points,
		"points_bought": points_bought,
		"passives": passives,
		"weapons": weapons,
		"best_score": best_score,
		"best_wave": best_wave,
		"total_kills": total_kills,
		"runs_played": runs_played,
		"settings": settings,
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save file: %s" % save_path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


# ----------------------------------------------------------------------------
#  Coins
# ----------------------------------------------------------------------------
func add_coins(amount: int) -> void:
	coins = maxi(coins + amount, 0)
	coins_changed.emit()


# ----------------------------------------------------------------------------
#  Character level and skill points
# ----------------------------------------------------------------------------
## XP needed to finish the current level.
func xp_needed() -> int:
	return Config.level_xp_needed(level)


## Give the character XP. Returns how many levels were gained.
func add_xp(amount: int) -> int:
	xp += amount
	var gained := 0
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		skill_points += Config.SKILL_POINTS_PER_LEVEL
		gained += 1
	if gained > 0:
		progress_changed.emit()
	return gained


func passive_rank(id: String) -> int:
	return int(passives.get(id, 0))


## The bonus a passive stat currently gives (see Config.PASSIVES for units).
func passive_value(id: String) -> float:
	return Config.stat_value(Config.PASSIVES[id], passive_rank(id))


## Skill points needed for the next rank of a passive.
func passive_cost(id: String) -> int:
	return Config.rank_cost(passive_rank(id), Config.PASSIVE_RANK_COST_STEP)


func raise_passive(id: String) -> bool:
	var cost := passive_cost(id)
	if skill_points < cost:
		return false
	skill_points -= cost
	passives[id] = passive_rank(id) + 1
	progress_changed.emit()
	save_game()
	return true


## Coins for the next bought skill point (rises every time).
func skill_point_price() -> int:
	return Config.skill_point_cost(points_bought)


func buy_skill_point() -> bool:
	var price := skill_point_price()
	if coins < price:
		return false
	coins -= price
	points_bought += 1
	skill_points += 1
	coins_changed.emit()
	progress_changed.emit()
	save_game()
	return true


## Skill points currently locked into passive ranks.
func spent_points() -> int:
	var total := 0
	for id: String in Config.PASSIVE_ORDER:
		for rank in passive_rank(id):
			total += Config.rank_cost(rank, Config.PASSIVE_RANK_COST_STEP)
	return total


func respec_price() -> int:
	return Config.RESPEC_COST_PER_LEVEL * level


## Take every spent skill point back so it can be placed again.
func respec() -> bool:
	var refund := spent_points()
	if refund <= 0 or coins < respec_price():
		return false
	coins -= respec_price()
	skill_points += refund
	for id: String in Config.PASSIVE_ORDER:
		passives[id] = 0
	coins_changed.emit()
	progress_changed.emit()
	save_game()
	return true


# ----------------------------------------------------------------------------
#  Weapon levels and weapon points
# ----------------------------------------------------------------------------
func _weapon(id: String) -> Dictionary:
	if not weapons.has(id):
		weapons[id] = _new_weapon_entry()
	return weapons[id]


func weapon_level(id: String) -> int:
	return int(_weapon(id)["level"])


func weapon_xp(id: String) -> int:
	return int(_weapon(id)["xp"])


func weapon_xp_needed(id: String) -> int:
	return Config.weapon_xp_needed(weapon_level(id))


func weapon_points(id: String) -> int:
	return int(_weapon(id)["points"])


## Give a weapon XP (from a kill made with it). Returns levels gained.
func add_weapon_xp(id: String, amount: int) -> int:
	var w := _weapon(id)
	var current := int(w["xp"]) + amount
	var lvl := int(w["level"])
	var gained := 0
	while current >= Config.weapon_xp_needed(lvl):
		current -= Config.weapon_xp_needed(lvl)
		lvl += 1
		gained += 1
	w["xp"] = current
	w["level"] = lvl
	if gained > 0:
		w["points"] = int(w["points"]) + gained * Config.WEAPON_POINTS_PER_LEVEL
		progress_changed.emit()
	return gained


func weapon_rank(id: String, track: String) -> int:
	var ranks: Dictionary = _weapon(id)["ranks"]
	return int(ranks.get(track, 0))


## The bonus a weapon's upgrade track currently gives (see Config.WEAPON_TRACKS).
func weapon_value(id: String, track: String) -> float:
	return Config.stat_value(Config.WEAPON_TRACKS[track], weapon_rank(id, track))


func weapon_rank_cost(id: String, track: String) -> int:
	return Config.rank_cost(weapon_rank(id, track), Config.WEAPON_RANK_COST_STEP)


func raise_weapon_track(id: String, track: String) -> bool:
	var cost := weapon_rank_cost(id, track)
	var w := _weapon(id)
	if int(w["points"]) < cost:
		return false
	w["points"] = int(w["points"]) - cost
	var ranks: Dictionary = w["ranks"]
	ranks[track] = weapon_rank(id, track) + 1
	progress_changed.emit()
	save_game()
	return true


## Unspent weapon points across all weapons (for the menu badge).
func total_weapon_points() -> int:
	var total := 0
	for id: String in Config.WEAPON_ORDER:
		total += weapon_points(id)
	return total


# ----------------------------------------------------------------------------
#  Runs
# ----------------------------------------------------------------------------
## Called at the end of every run. Returns true if it was a new best score.
## (XP is added as it is earned; this banks the coins and saves everything.)
func record_run(score: int, wave: int, kills: int, coins_earned: int) -> bool:
	runs_played += 1
	total_kills += kills
	coins += coins_earned
	var is_best := score > best_score
	if is_best:
		best_score = score
	best_wave = maxi(best_wave, wave)
	coins_changed.emit()
	save_game()
	return is_best


# ----------------------------------------------------------------------------
#  Settings
# ----------------------------------------------------------------------------
func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_settings()
	settings_changed.emit()
	save_game()


func get_setting(key: String) -> Variant:
	return settings[key]


func apply_settings() -> void:
	_set_bus_volume("Master", float(settings["master_volume"]))
	_set_bus_volume("SFX", float(settings["sfx_volume"]))
	var want_fullscreen: bool = settings["fullscreen"]
	var mode := DisplayServer.window_get_mode()
	var is_fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want_fullscreen != is_fullscreen:
		if want_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))
