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
var tree: Dictionary = {}        # skill tree: node id -> times learned (endless nodes can be more than 1)
var bonus_ranks: Dictionary = {} # extra ranks of a passive from outside the tree (gear later; tests) - not saved

var _ranks := {}                 # worked out from `tree`: passive id -> ranks
var _keystones := {}             # ...and passive id -> true if its keystone is learned

# Weapons: id -> {"level": int, "xp": int, "points": int (unspent),
#                  "tree": {node id: times learned}, "spent": int (points in the tree)}
var weapons: Dictionary = {}
var tree_spent: int = 0          # skill points locked into `tree` (kept so they can always be handed back)

var _weapon_ranks := {}          # worked out from each weapon's tree: weapon id -> {track: ranks}

# Maps: how many are open, and the highest wave cleared on each one.
var maps_unlocked: int = 1
var map_best: Array[int] = []
var selected_map: int = 0        # what the Play screen was last set to
var selected_start: int = 1      # ...and the wave that run starts from

var best_score: int = 0
var best_wave: int = 0
var total_kills: int = 0
var runs_played: int = 0
var settings: Dictionary = {}

## True for one session after an old save was converted (the menu says so once).
var was_reset_by_update := false
## Skill points handed back this session because the skill tree replaced the
## old stat list, or because the tree's layout changed (the menu says so once).
var points_returned := 0
var weapon_points_returned := 0  # ...and the same for weapon points (the Armory says so once)


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
	points_returned = 0
	weapon_points_returned = 0
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
	tree = {}
	tree_spent = 0
	bonus_ranks = {}
	_recount_tree()
	_weapon_ranks = {}
	weapons = {}
	for id: String in Config.WEAPON_ORDER:
		weapons[id] = _new_weapon_entry()
	maps_unlocked = 1
	map_best = []
	for i in Config.MAPS.size():
		map_best.append(0)
	selected_map = 0
	selected_start = 1


func _new_weapon_entry() -> Dictionary:
	return {"level": 1, "xp": 0, "points": 0, "tree": {}, "spent": 0}


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
	level = clampi(int(data.get("level", 1)), 1, Config.LEVEL_CAP)
	xp = maxi(int(data.get("xp", 0)), 0)
	skill_points = maxi(int(data.get("skill_points", 0)), 0)
	points_bought = maxi(int(data.get("points_bought", 0)), 0)
	_load_tree(data)
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
			_load_weapon_tree(id, entry)

	maps_unlocked = clampi(int(data.get("maps_unlocked", 1)), 1, Config.MAPS.size())
	var saved_best: Variant = data.get("map_best", [])
	if typeof(saved_best) == TYPE_ARRAY:
		for i in mini((saved_best as Array).size(), map_best.size()):
			map_best[i] = clampi(int((saved_best as Array)[i]), 0, Config.WAVES_PER_MAP)
	selected_map = clampi(int(data.get("selected_map", 0)), 0, maps_unlocked - 1)
	selected_start = int(data.get("selected_start", 1))
	if not map_checkpoints(selected_map).has(selected_start):
		selected_start = 1


func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"coins": coins,
		"level": level,
		"xp": xp,
		"skill_points": skill_points,
		"points_bought": points_bought,
		"tree": tree,
		"tree_spent": tree_spent,
		"weapons": weapons,
		"maps_unlocked": maps_unlocked,
		"map_best": map_best,
		"selected_map": selected_map,
		"selected_start": selected_start,
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


func at_level_cap() -> bool:
	return level >= Config.LEVEL_CAP


## Give the character XP. Returns how many levels were gained.
## At the level cap nothing more is gained.
func add_xp(amount: int) -> int:
	if at_level_cap():
		xp = 0
		return 0
	xp += amount
	var gained := 0
	while not at_level_cap() and xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		skill_points += Config.SKILL_POINTS_PER_LEVEL
		gained += 1
	if at_level_cap():
		xp = 0
	if gained > 0:
		progress_changed.emit()
	return gained


# ----------------------------------------------------------------------------
#  Skill tree (the nodes are described in scripts/game/skill_tree.gd)
# ----------------------------------------------------------------------------
func _load_tree(data: Dictionary) -> void:
	tree = {}
	tree_spent = 0
	var saved: Variant = data.get("tree")
	if typeof(saved) == TYPE_DICTIONARY:
		var known := true
		for id: String in (saved as Dictionary).keys():
			var count := int((saved as Dictionary)[id])
			if count <= 0 or id == "start":
				continue
			if not SkillTree.has(id):
				known = false
				continue
			tree[id] = count if bool(SkillTree.nodes()[id]["repeat"]) else 1
		# If the tree's layout changed (a learned node is gone, or cut off from
		# the middle), hand every point back rather than keep a broken tree.
		if not known or not _tree_connected():
			points_returned = maxi(int(data.get("tree_spent", 0)), spent_points())
			skill_points += points_returned
			tree = {}
		tree_spent = spent_points()
	else:
		# A save from before the skill tree: stats were a plain list of ranks.
		# Give back the points that were spent on them.
		var old: Variant = data.get("passives")
		if typeof(old) == TYPE_DICTIONARY:
			for id: String in (old as Dictionary).keys():
				for rank in maxi(int((old as Dictionary)[id]), 0):
					points_returned += 1 + int(rank / 10.0)
			skill_points += points_returned
	_recount_tree()


## True if every learned node can be reached from the middle through learned nodes.
func _tree_connected() -> bool:
	var seen := {"start": true}
	var todo: Array[String] = ["start"]
	while not todo.is_empty():
		var id: String = todo.pop_back()
		for other: String in SkillTree.nodes()[id]["links"]:
			if not seen.has(other) and tree.has(other):
				seen[other] = true
				todo.append(other)
	return seen.size() - 1 == tree.size()


func _recount_tree() -> void:
	_ranks = {}
	_keystones = {}
	for id: String in tree.keys():
		var n: Dictionary = SkillTree.nodes()[id]
		var count := int(tree[id])
		var ranks: Dictionary = n["ranks"]
		for stat: String in ranks.keys():
			_ranks[stat] = int(_ranks.get(stat, 0)) + int(ranks[stat]) * count
		if String(n["kind"]) == "keystone":
			_keystones[String(n["stat"])] = true


## How many times a node has been learned (the middle node always counts).
func node_count(id: String) -> int:
	return 1 if id == "start" else int(tree.get(id, 0))


## Skill points for the next purchase of a node.
func node_cost(id: String) -> int:
	return SkillTree.cost(id, node_count(id))


## Where a node stands: one of SkillTree.OWNED / READY / POOR / LEVEL / SEALED / FAR.
func node_status(id: String) -> int:
	var n: Dictionary = SkillTree.nodes()[id]
	var count := node_count(id)
	if count > 0 and not bool(n["repeat"]):
		return SkillTree.OWNED
	if count == 0 and not node_touches_learned(id):
		return SkillTree.FAR
	if level < int(n["level"]):
		return SkillTree.LEVEL
	if not deed_done(n["deed"]):
		return SkillTree.SEALED
	if skill_points < node_cost(id):
		return SkillTree.POOR
	return SkillTree.READY


func node_touches_learned(id: String) -> bool:
	for other: String in SkillTree.nodes()[id]["links"]:
		if node_count(other) > 0:
			return true
	return false


## Spend skill points on a node. Returns false (and changes nothing) if it
## cannot be learned right now.
func learn_node(id: String) -> bool:
	if not SkillTree.has(id) or node_status(id) != SkillTree.READY:
		return false
	skill_points -= node_cost(id)
	tree[id] = node_count(id) + 1
	tree_spent = spent_points()
	_recount_tree()
	progress_changed.emit()
	save_game()
	return true


func has_keystone(stat: String) -> bool:
	return _keystones.has(stat)


## Ranks of a passive stat: from the skill tree, plus anything else (gear later).
func passive_rank(id: String) -> int:
	return int(_ranks.get(id, 0)) + int(bonus_ranks.get(id, 0))


## The bonus a passive stat currently gives (see Config.PASSIVES for units).
func passive_value(id: String) -> float:
	return Config.stat_value(Config.PASSIVES[id], passive_rank(id))


## How far along a deed is (the number its "value" is compared with).
func deed_progress(deed: Dictionary) -> int:
	if deed.is_empty():
		return 0
	match String(deed["kind"]):
		"wave":
			var best := 0
			for wave: int in map_best:
				best = maxi(best, wave)
			return best
		"kills":
			return total_kills
		"weapon_level":
			var best := 0
			for id: String in Config.WEAPON_ORDER:
				best = maxi(best, weapon_level(id))
			return best
		"runs":
			return runs_played
		"score":
			return best_score
		"bought":
			return points_bought
		"map":
			return int(deed["value"]) if map_cleared(int(deed["value"]) - 1) else 0
	return 0


func deed_done(deed: Dictionary) -> bool:
	return deed.is_empty() or deed_progress(deed) >= int(deed["value"])


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


## Skill points currently locked into the skill tree.
func spent_points() -> int:
	var total := 0
	for id: String in tree.keys():
		for owned in int(tree[id]):
			total += SkillTree.cost(id, owned)
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
	tree = {}
	tree_spent = 0
	_recount_tree()
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


# ----------------------------------------------------------------------------
#  Weapon trees (the nodes are described in scripts/game/weapon_tree.gd)
# ----------------------------------------------------------------------------
func _load_weapon_tree(id: String, entry: Dictionary) -> void:
	var w: Dictionary = weapons[id]
	var learned := {}
	w["tree"] = learned
	w["spent"] = 0
	var saved: Variant = entry.get("tree")
	if typeof(saved) == TYPE_DICTIONARY:
		var known := true
		for node_id: String in (saved as Dictionary).keys():
			var count := int((saved as Dictionary)[node_id])
			if count <= 0 or node_id == "start":
				continue
			if not WeaponTree.has(id, node_id):
				known = false
				continue
			learned[node_id] = count if bool(WeaponTree.nodes(id)[node_id]["repeat"]) else 1
		# A tree that no longer fits this weapon is handed back whole.
		if not known or not _weapon_tree_connected(id):
			var back := maxi(int(entry.get("spent", 0)), weapon_spent(id))
			w["points"] = int(w["points"]) + back
			weapon_points_returned += back
			learned.clear()
		w["spent"] = weapon_spent(id)
	else:
		# A save from before the weapon trees: upgrades were plain ranks
		# (the first ten of each cost one point, the next ten two, ...).
		var old: Variant = entry.get("ranks")
		if typeof(old) == TYPE_DICTIONARY:
			var back := 0
			for track: String in (old as Dictionary).keys():
				for rank in maxi(int((old as Dictionary)[track]), 0):
					back += 1 + int(rank / 10.0)
			w["points"] = int(w["points"]) + back
			weapon_points_returned += back
	_weapon_ranks.erase(id)


func _weapon_tree_connected(id: String) -> bool:
	var learned: Dictionary = _weapon(id)["tree"]
	var seen := {"start": true}
	var todo: Array[String] = ["start"]
	while not todo.is_empty():
		var at: String = todo.pop_back()
		for other: String in WeaponTree.nodes(id)[at]["links"]:
			if not seen.has(other) and learned.has(other):
				seen[other] = true
				todo.append(other)
	return seen.size() - 1 == learned.size()


## How many times a node of a weapon's tree has been learned.
func weapon_node_count(id: String, node_id: String) -> int:
	if node_id == "start":
		return 1
	var learned: Dictionary = _weapon(id)["tree"]
	return int(learned.get(node_id, 0))


## Weapon points for the next purchase of a node.
func weapon_node_cost(id: String, node_id: String) -> int:
	return WeaponTree.cost(id, node_id, weapon_node_count(id, node_id))


func weapon_node_touches_learned(id: String, node_id: String) -> bool:
	for other: String in WeaponTree.nodes(id)[node_id]["links"]:
		if weapon_node_count(id, other) > 0:
			return true
	return false


## Where a weapon's node stands: SkillTree.OWNED / READY / POOR / LEVEL / FAR.
func weapon_node_status(id: String, node_id: String) -> int:
	var n: Dictionary = WeaponTree.nodes(id)[node_id]
	var count := weapon_node_count(id, node_id)
	if count > 0 and not bool(n["repeat"]):
		return SkillTree.OWNED
	if count == 0 and not weapon_node_touches_learned(id, node_id):
		return SkillTree.FAR
	if weapon_level(id) < int(n["level"]):
		return SkillTree.LEVEL
	if weapon_points(id) < weapon_node_cost(id, node_id):
		return SkillTree.POOR
	return SkillTree.READY


## Spend a weapon's points on a node of its tree.
func learn_weapon_node(id: String, node_id: String) -> bool:
	if not WeaponTree.has(id, node_id) or weapon_node_status(id, node_id) != SkillTree.READY:
		return false
	var w := _weapon(id)
	var cost := weapon_node_cost(id, node_id)
	w["points"] = int(w["points"]) - cost
	w["spent"] = int(w["spent"]) + cost
	var learned: Dictionary = w["tree"]
	learned[node_id] = weapon_node_count(id, node_id) + 1
	_weapon_ranks.erase(id)
	progress_changed.emit()
	save_game()
	return true


## Ranks of one of a weapon's upgrade tracks, added up from its tree.
func weapon_rank(id: String, track: String) -> int:
	if not _weapon_ranks.has(id):
		var totals := {}
		var learned: Dictionary = _weapon(id)["tree"]
		for node_id: String in learned.keys():
			var ranks: Dictionary = WeaponTree.nodes(id)[node_id]["ranks"]
			for key: String in ranks.keys():
				totals[key] = int(totals.get(key, 0)) + int(ranks[key]) * int(learned[node_id])
		_weapon_ranks[id] = totals
	var mine: Dictionary = _weapon_ranks[id]
	return int(mine.get(track, 0))


## The bonus a weapon's upgrade track currently gives (see Config.WEAPON_TRACKS).
func weapon_value(id: String, track: String) -> float:
	return Config.stat_value(Config.WEAPON_TRACKS[track], weapon_rank(id, track))


## True if the weapon has learned its perk number `index` (0, 1 or 2).
func weapon_has_perk(id: String, index: int) -> bool:
	return weapon_node_count(id, "perk.%d" % index) > 0


## Weapon points currently locked into a weapon's tree.
func weapon_spent(id: String) -> int:
	var total := 0
	var learned: Dictionary = _weapon(id)["tree"]
	for node_id: String in learned.keys():
		for owned in int(learned[node_id]):
			total += WeaponTree.cost(id, node_id, owned)
	return total


func weapon_respec_price(id: String) -> int:
	return Config.WEAPON_RESPEC_COST_PER_LEVEL * weapon_level(id)


## Take a weapon's spent points back so they can be placed again.
func respec_weapon(id: String) -> bool:
	var refund := weapon_spent(id)
	if refund <= 0 or coins < weapon_respec_price(id):
		return false
	coins -= weapon_respec_price(id)
	var w := _weapon(id)
	w["points"] = int(w["points"]) + refund
	w["spent"] = 0
	(w["tree"] as Dictionary).clear()
	_weapon_ranks.erase(id)
	coins_changed.emit()
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
#  Maps
# ----------------------------------------------------------------------------
func map_unlocked(index: int) -> bool:
	return index >= 0 and index < maps_unlocked


## Highest wave cleared on a map (0 = none yet).
func map_best_wave(index: int) -> int:
	return map_best[index] if index >= 0 and index < map_best.size() else 0


func map_cleared(index: int) -> bool:
	return map_best_wave(index) >= Config.WAVES_PER_MAP


## The waves a run on this map may start from.
func map_checkpoints(index: int) -> Array[int]:
	return Config.checkpoint_waves(map_best_wave(index))


## Remember which map and starting wave the next run uses. Returns false (and
## changes nothing) if that map is locked or that checkpoint is not reached.
func select_map(index: int, start_wave: int = 1) -> bool:
	if not map_unlocked(index) or not map_checkpoints(index).has(start_wave):
		return false
	selected_map = index
	selected_start = start_wave
	return true


## Called by the game each time a wave is cleared. Returns what that opened up:
## {"checkpoint": wave a run can now start from (0 = nothing new),
##  "unlocked": index of the map that was just unlocked (-1 = none)}.
func note_wave_cleared(index: int, wave: int) -> Dictionary:
	var result := {"checkpoint": 0, "unlocked": -1}
	if index < 0 or index >= map_best.size() or wave <= map_best[index]:
		return result
	map_best[index] = mini(wave, Config.WAVES_PER_MAP)
	if Config.is_checkpoint(wave):
		result["checkpoint"] = wave + 1
	if wave >= Config.WAVES_PER_MAP and index + 1 < Config.MAPS.size() and maps_unlocked < index + 2:
		maps_unlocked = index + 2
		result["unlocked"] = index + 1
	progress_changed.emit()
	return result


# ----------------------------------------------------------------------------
#  Runs
# ----------------------------------------------------------------------------
## Called at the end of every run with Game.get_stats(). Returns true if it
## was a new best score. (XP and cleared waves are counted as they happen;
## this banks the coins and saves everything.)
func record_run(stats: Dictionary) -> bool:
	var score := int(stats.get("score", 0))
	runs_played += 1
	total_kills += int(stats.get("kills", 0))
	coins += int(stats.get("coins", 0))
	var is_best := score > best_score
	if is_best:
		best_score = score
	best_wave = maxi(best_wave, int(stats.get("wave", 0)))
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
