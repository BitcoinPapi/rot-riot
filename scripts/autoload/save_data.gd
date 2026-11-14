extends Node
## Persistent data: coins, shop upgrades, best scores and settings.
## Saved as JSON in the user data folder (user://save.json), so it survives
## between sessions and game updates.

signal coins_changed
signal settings_changed

var save_path := "user://save.json"

var coins: int = 0
var upgrades: Dictionary = {}      # upgrade id -> level bought
var best_score: int = 0
var best_wave: int = 0
var total_kills: int = 0
var runs_played: int = 0
var settings: Dictionary = {}


func _ready() -> void:
	_reset_to_defaults()
	load_game()
	apply_settings()


func _reset_to_defaults() -> void:
	coins = 0
	upgrades = {}
	for id: String in Config.UPGRADE_ORDER:
		upgrades[id] = 0
	best_score = 0
	best_wave = 0
	total_kills = 0
	runs_played = 0
	settings = {
		"master_volume": Config.DEFAULT_MASTER_VOLUME,
		"sfx_volume": Config.DEFAULT_SFX_VOLUME,
		"fullscreen": Config.DEFAULT_FULLSCREEN,
		"screen_shake": Config.DEFAULT_SCREEN_SHAKE,
	}


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
	coins = maxi(int(data.get("coins", 0)), 0)
	best_score = int(data.get("best_score", 0))
	best_wave = int(data.get("best_wave", 0))
	total_kills = int(data.get("total_kills", 0))
	runs_played = int(data.get("runs_played", 0))
	var saved_upgrades: Variant = data.get("upgrades", {})
	if typeof(saved_upgrades) == TYPE_DICTIONARY:
		for id: String in Config.UPGRADE_ORDER:
			var level := int((saved_upgrades as Dictionary).get(id, 0))
			upgrades[id] = clampi(level, 0, Config.upgrade_max_level(id))
	var saved_settings: Variant = data.get("settings", {})
	if typeof(saved_settings) == TYPE_DICTIONARY:
		for key: String in settings.keys():
			if (saved_settings as Dictionary).has(key):
				var value: Variant = (saved_settings as Dictionary)[key]
				if typeof(settings[key]) == TYPE_BOOL:
					settings[key] = bool(value)
				else:
					settings[key] = clampf(float(value), 0.0, 1.0)


func save_game() -> void:
	var data := {
		"version": 1,
		"coins": coins,
		"upgrades": upgrades,
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
#  Coins and upgrades
# ----------------------------------------------------------------------------
func add_coins(amount: int) -> void:
	coins = maxi(coins + amount, 0)
	coins_changed.emit()


func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))


func can_buy_upgrade(id: String) -> bool:
	var cost := Config.upgrade_cost(id, upgrade_level(id))
	return cost >= 0 and coins >= cost


func buy_upgrade(id: String) -> bool:
	if not can_buy_upgrade(id):
		return false
	coins -= Config.upgrade_cost(id, upgrade_level(id))
	upgrades[id] = upgrade_level(id) + 1
	coins_changed.emit()
	save_game()
	return true


## Total bonus from an upgrade (e.g. 0.30 for two levels of +15%).
func upgrade_bonus(id: String) -> float:
	var per_level: float = Config.UPGRADES[id]["per_level"]
	return per_level * float(upgrade_level(id))


## Called at the end of every run. Returns true if it was a new best score.
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
