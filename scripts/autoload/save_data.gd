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
signal gear_changed              # what the hero wears changed (his pictures are redrawn)

const SAVE_VERSION := 2

var save_path := "user://save.json"

var coins: int = 0

# Character
var level: int = 1
var xp: int = 0                  # XP inside the current level
var skill_points: int = 0        # unspent
var points_bought: int = 0       # how many were bought with coins (sets the next price)
var skills: Dictionary = {}      # ranks of the passive stats bought with skill points (the Skills page): stat id -> rank
var bonus_ranks: Dictionary = {} # extra ranks of a passive from anywhere else (used by tests) - not saved


# Weapons: id -> {"level": int, "xp": int, "points": int (unspent),
#                  "upgrades": {track: rank}, "perks": [0 or 1, ...], "spent": int (points used)}
var weapons: Dictionary = {}


# Gear. A piece is named by its id and tier, e.g. "hard_hat:2" (Config.gear_key).
var gear_bag: Dictionary = {}    # piece -> how many are in the bag (worn pieces are not counted)
var gear_worn: Dictionary = {}   # slot -> piece ("" = nothing worn there)
var gear_seen: Dictionary = {}   # piece -> true once it was ever owned (the Gear screen remembers it)
var gear_new: int = 0            # pieces found since the Gear screen was last opened (menu badge)

var _gear_ranks := {}            # worked out from gear_worn: passive id -> ranks

# Pets (Config.PETS).
var pets_owned: Array[String] = []
var pet_active: String = ""      # the pet that comes along ("" = none)
var pet_seen: bool = false       # the Pet screen has been opened since the first pet joined (menu badge)
var enemies_seen: Array = []     # kinds of zombie whose one-time tip has been shown (their sprite names)

# Maps: how many are open, and the highest wave cleared on each one.
var maps_unlocked: int = 1
var map_best: Array[int] = []
var selected_map: int = 0        # what the Play screen was last set to
var selected_start: int = 1      # ...and the wave that run starts from

var best_score: int = 0
var best_wave: int = 0
var total_kills: int = 0
var runs_played: int = 0
var chests_opened: int = 0      # treasure chests opened, over all runs
var settings: Dictionary = {}

## True for one session after an old save was converted (the menu says so once).
var was_reset_by_update := false
## Skill points handed back this session because the Skills page was rebuilt
## since the save was written (the menu says so once).
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
	chests_opened = 0
	was_reset_by_update = false
	points_returned = 0
	weapon_points_returned = 0
	settings = {
		"master_volume": Config.DEFAULT_MASTER_VOLUME,
		"sfx_volume": Config.DEFAULT_SFX_VOLUME,
		"fullscreen": Config.DEFAULT_FULLSCREEN,
		"screen_shake": Config.DEFAULT_SCREEN_SHAKE,
		"fewer_effects": Config.DEFAULT_FEWER_EFFECTS,   # less flying blood, fewer zombies at once
		"player_name": Config.HERO_NAME,     # what your partner sees over your head in co-op
	}


func _reset_progress() -> void:
	level = 1
	xp = 0
	skill_points = 0
	points_bought = 0
	skills = {}
	bonus_ranks = {}
	weapons = {}
	for id: String in Config.WEAPON_ORDER:
		weapons[id] = _new_weapon_entry()
	gear_bag = {}
	gear_worn = {}
	for slot: String in Config.GEAR_SLOTS:
		gear_worn[slot] = ""
	gear_seen = {}
	gear_new = 0
	_gear_ranks = {}
	pets_owned = []
	pet_active = ""
	pet_seen = false
	enemies_seen = []
	maps_unlocked = 1
	map_best = []
	for i in Config.MAPS.size():
		map_best.append(0)
	selected_map = 0
	selected_start = 1


func _new_weapon_entry() -> Dictionary:
	var perks: Array = []
	for i in Config.WEAPON_PERK_COST.size():
		perks.append(0)
	return {"level": 1, "xp": 0, "points": 0, "upgrades": {}, "perks": perks, "spent": 0}


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
	chests_opened = int(data.get("chests_opened", 0))
	var saved_settings: Variant = data.get("settings", {})
	if typeof(saved_settings) == TYPE_DICTIONARY:
		for key: String in settings.keys():
			if (saved_settings as Dictionary).has(key):
				var value: Variant = (saved_settings as Dictionary)[key]
				if typeof(settings[key]) == TYPE_BOOL:
					settings[key] = bool(value)
				elif typeof(settings[key]) == TYPE_STRING:
					var text := String(value).strip_edges().substr(0, Config.COOP_NAME_MAX)
					if text != "":
						settings[key] = text
				else:
					settings[key] = clampf(float(value), 0.0, 1.0)
	# (The hero was called Cliff until v0.11: a co-op name that was simply left at that follows the new one.)
	if String(settings["player_name"]) == "CLIFF":
		settings["player_name"] = Config.HERO_NAME

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
	_load_skills(data)
	var saved_weapons: Variant = data.get("weapons", {})
	if typeof(saved_weapons) == TYPE_DICTIONARY:
		for id: String in Config.WEAPON_ORDER:
			var entry: Variant = (saved_weapons as Dictionary).get(id)
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			weapons[id] = _new_weapon_entry()      # (always start from a clean entry)
			var w: Dictionary = weapons[id]
			w["level"] = maxi(int((entry as Dictionary).get("level", 1)), 1)
			w["xp"] = maxi(int((entry as Dictionary).get("xp", 0)), 0)
			w["points"] = maxi(int((entry as Dictionary).get("points", 0)), 0)
			_load_weapon_upgrades(id, entry)

	_load_gear(data)
	var saved_pets: Variant = data.get("pets_owned")
	if typeof(saved_pets) == TYPE_ARRAY:
		for id: Variant in (saved_pets as Array):
			if Config.PETS.has(String(id)) and not pets_owned.has(String(id)):
				pets_owned.append(String(id))
	pet_active = String(data.get("pet_active", ""))
	if not pets_owned.has(pet_active):
		pet_active = ""
	pet_seen = bool(data.get("pet_seen", false))
	enemies_seen = []
	var seen_kinds: Variant = data.get("enemies_seen", [])
	if typeof(seen_kinds) == TYPE_ARRAY:
		for kind_name: Variant in (seen_kinds as Array):
			enemies_seen.append(String(kind_name))
	maps_unlocked = clampi(int(data.get("maps_unlocked", 1)), 1, Config.MAPS.size())
	var saved_best: Variant = data.get("map_best")
	if typeof(saved_best) == TYPE_ARRAY:
		for i in mini((saved_best as Array).size(), map_best.size()):
			map_best[i] = clampi(int((saved_best as Array)[i]), 0, Config.WAVES_PER_MAP)
	elif best_wave > 1:
		# A save from before maps existed: the waves already beaten count for
		# the first map (so its checkpoints are not lost).
		map_best[0] = clampi(best_wave - 1, 0, Config.WAVES_PER_MAP - 1)
	selected_map = clampi(int(data.get("selected_map", 0)), 0, maps_unlocked - 1)
	selected_start = int(data.get("selected_start", 1))
	if not map_checkpoints(selected_map).has(selected_start):
		selected_start = 1
	_grant_free_pets()


func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"coins": coins,
		"level": level,
		"xp": xp,
		"skill_points": skill_points,
		"points_bought": points_bought,
		"skills": skills,
		"weapons": weapons,
		"gear_bag": gear_bag,
		"gear_worn": gear_worn,
		"gear_seen": gear_seen.keys(),
		"gear_new": gear_new,
		"pets_owned": pets_owned,
		"pet_active": pet_active,
		"pet_seen": pet_seen,
		"enemies_seen": enemies_seen,
		"maps_unlocked": maps_unlocked,
		"map_best": map_best,
		"selected_map": selected_map,
		"selected_start": selected_start,
		"best_score": best_score,
		"best_wave": best_wave,
		"total_kills": total_kills,
		"runs_played": runs_played,
		"chests_opened": chests_opened,
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
		_grant_free_pets()
		progress_changed.emit()
	return gained


# ----------------------------------------------------------------------------
#  Skills: ranks of the passive stats, bought with skill points on the Skills
#  page. (Numbers: the SKILLS section of config.gd.)
# ----------------------------------------------------------------------------
func _load_skills(data: Dictionary) -> void:
	skills = {}
	var saved: Variant = data.get("skills")
	if typeof(saved) == TYPE_DICTIONARY:
		for id: String in Config.PASSIVE_ORDER:
			var rank := maxi(int((saved as Dictionary).get(id, 0)), 0)
			if rank > 0:
				skills[id] = rank
		return
	# A save from before the plain list. Whatever was spent on the older
	# skill screens comes back as skill points to spend again.
	var old_tree: Variant = data.get("tree")
	if typeof(old_tree) == TYPE_DICTIONARY and not (old_tree as Dictionary).is_empty():
		# (the skill tree of versions 0.2 - 0.8: it saved what was spent in it)
		var levels := 0
		for id: Variant in (old_tree as Dictionary).keys():
			levels += maxi(int((old_tree as Dictionary)[id]), 0)
		points_returned = maxi(int(data.get("tree_spent", 0)), levels)
	else:
		# (the first stat list, version 0.1)
		var old: Variant = data.get("passives")
		if typeof(old) == TYPE_DICTIONARY:
			for id: String in (old as Dictionary).keys():
				for rank in maxi(int((old as Dictionary)[id]), 0):
					points_returned += 1 + int(rank / 10.0)
	skill_points += points_returned


## Ranks of a stat bought with skill points.
func skill_rank(id: String) -> int:
	return int(skills.get(id, 0))


## Skill points for the next rank of a stat.
func skill_cost(id: String) -> int:
	return Config.rank_cost(skill_rank(id), Config.SKILL_RANK_COST_STEP)


## Where a stat stands: "ready" (a rank can be bought), "poor" (not enough
## skill points) or "level" (the character's level is too low for it).
func skill_status(id: String) -> String:
	if level < int(Config.PASSIVES[id].get("min_level", 1)):
		return "level"
	return "ready" if skill_points >= skill_cost(id) else "poor"


## Spend skill points on one more rank of a stat. False (and nothing changes)
## if that is not possible right now.
func raise_skill(id: String) -> bool:
	if not Config.PASSIVES.has(id) or skill_status(id) != "ready":
		return false
	skill_points -= skill_cost(id)
	skills[id] = skill_rank(id) + 1
	progress_changed.emit()
	save_game()
	return true


## A stat's special power (Config.KEYSTONES) is yours once enough ranks of it are bought.
func has_keystone(stat: String) -> bool:
	return skill_rank(stat) >= Config.KEYSTONE_RANK


## Ranks of a passive stat: bought with skill points, plus the gear being worn.
func passive_rank(id: String) -> int:
	return skill_rank(id) + int(_gear_ranks.get(id, 0)) + int(bonus_ranks.get(id, 0))


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
		"level":
			return level
		"pets":
			return pets_owned.size()
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


## Skill points currently locked into bought ranks.
func spent_points() -> int:
	var total := 0
	for id: String in skills.keys():
		for owned in int(skills[id]):
			total += Config.rank_cost(owned, Config.SKILL_RANK_COST_STEP)
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
	skills = {}
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
#  Weapon upgrades (Config: WEAPON_TRACKS and WEAPON_PERKS)
# ----------------------------------------------------------------------------
func _load_weapon_upgrades(id: String, entry: Dictionary) -> void:
	var w: Dictionary = weapons[id]
	var saved: Variant = entry.get("upgrades")
	if typeof(saved) == TYPE_DICTIONARY:
		var upgrades: Dictionary = w["upgrades"]
		for track: String in Config.weapon_tracks(id):
			var rank := maxi(int((saved as Dictionary).get(track, 0)), 0)
			if rank > 0:
				upgrades[track] = rank
		var perks: Array = w["perks"]
		var saved_perks: Variant = entry.get("perks")
		if typeof(saved_perks) == TYPE_ARRAY:
			for i in mini((saved_perks as Array).size(), perks.size()):
				perks[i] = 1 if int((saved_perks as Array)[i]) > 0 else 0
		# Ranks in an upgrade this weapon no longer has are simply dropped, and
		# the points come back because "spent" is counted again from what is left.
		var paid := maxi(int(entry.get("spent", 0)), 0)
		w["spent"] = weapon_spent(id)
		if paid > int(w["spent"]):
			w["points"] = int(w["points"]) + paid - int(w["spent"])
			weapon_points_returned += paid - int(w["spent"])
		return
	# Older saves: hand the points back so they can be spent on the new screen.
	var back := 0
	if typeof(entry.get("tree")) == TYPE_DICTIONARY:
		# (the weapon trees of version 0.2 - 0.4)
		back = maxi(int(entry.get("spent", 0)), 0)
	elif typeof(entry.get("ranks")) == TYPE_DICTIONARY:
		# (plain ranks, before that: the first ten of each cost one point, the next ten two, ...)
		var old: Dictionary = entry.get("ranks")
		for track: String in old.keys():
			for rank in maxi(int(old[track]), 0):
				back += 1 + int(rank / 10.0)
	w["points"] = int(w["points"]) + back
	weapon_points_returned += back


## Ranks bought in one of a weapon's upgrades.
func weapon_rank(id: String, track: String) -> int:
	var upgrades: Dictionary = _weapon(id)["upgrades"]
	return int(upgrades.get(track, 0))


## The bonus a weapon's upgrade currently gives (see Config.WEAPON_TRACKS).
func weapon_value(id: String, track: String) -> float:
	return Config.stat_value(Config.WEAPON_TRACKS[track], weapon_rank(id, track))


## Weapon points for the next rank of an upgrade.
func weapon_rank_cost(id: String, track: String) -> int:
	return Config.rank_cost(weapon_rank(id, track), Config.WEAPON_RANK_COST_STEP)


func raise_weapon_track(id: String, track: String) -> bool:
	if not Config.weapon_tracks(id).has(track):
		return false
	var cost := weapon_rank_cost(id, track)
	var w := _weapon(id)
	if int(w["points"]) < cost:
		return false
	w["points"] = int(w["points"]) - cost
	w["spent"] = int(w["spent"]) + cost
	var upgrades: Dictionary = w["upgrades"]
	upgrades[track] = weapon_rank(id, track) + 1
	progress_changed.emit()
	save_game()
	return true


## True if the weapon has bought its perk number `index` (0, 1 or 2).
func weapon_has_perk(id: String, index: int) -> bool:
	var perks: Array = _weapon(id)["perks"]
	return index >= 0 and index < perks.size() and int(perks[index]) > 0


## Where a perk stands: "owned", "ready" (can be bought now), "poor" (not
## enough weapon points) or "locked" (the weapon's level is too low).
func weapon_perk_status(id: String, index: int) -> String:
	if weapon_has_perk(id, index):
		return "owned"
	if weapon_level(id) < int(Config.WEAPON_PERK_LEVELS[index]):
		return "locked"
	return "ready" if weapon_points(id) >= int(Config.WEAPON_PERK_COST[index]) else "poor"


func buy_weapon_perk(id: String, index: int) -> bool:
	if index < 0 or index >= Config.WEAPON_PERK_COST.size() or weapon_perk_status(id, index) != "ready":
		return false
	var w := _weapon(id)
	var cost := int(Config.WEAPON_PERK_COST[index])
	w["points"] = int(w["points"]) - cost
	w["spent"] = int(w["spent"]) + cost
	(w["perks"] as Array)[index] = 1
	progress_changed.emit()
	save_game()
	return true


## Weapon points currently used by a weapon's upgrades and perks.
func weapon_spent(id: String) -> int:
	var total := 0
	var upgrades: Dictionary = _weapon(id)["upgrades"]
	for track: String in upgrades.keys():
		for rank in int(upgrades[track]):
			total += Config.rank_cost(rank, Config.WEAPON_RANK_COST_STEP)
	for i in Config.WEAPON_PERK_COST.size():
		if weapon_has_perk(id, i):
			total += int(Config.WEAPON_PERK_COST[i])
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
	(w["upgrades"] as Dictionary).clear()
	var perks: Array = w["perks"]
	for i in perks.size():
		perks[i] = 0
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
#  Gear (the pieces are described in Config, GEAR section)
# ----------------------------------------------------------------------------
func _gear_key_ok(key: String) -> bool:
	var tier := Config.gear_tier_of(key)
	return Config.GEAR_ITEMS.has(Config.gear_item_of(key)) and tier >= 1 and tier <= Config.GEAR_TIERS.size()


func _load_gear(data: Dictionary) -> void:
	var bag: Variant = data.get("gear_bag")
	if typeof(bag) == TYPE_DICTIONARY:
		for key: String in (bag as Dictionary).keys():
			var count := int((bag as Dictionary)[key])
			if count > 0 and _gear_key_ok(key):
				gear_bag[key] = count
				gear_seen[key] = true
	var worn: Variant = data.get("gear_worn")
	if typeof(worn) == TYPE_DICTIONARY:
		for slot: String in Config.GEAR_SLOTS:
			var key := String((worn as Dictionary).get(slot, ""))
			if key != "" and _gear_key_ok(key) \
					and String(Config.GEAR_ITEMS[Config.gear_item_of(key)]["type"]) == String(Config.GEAR_SLOT_TYPE[slot]):
				gear_worn[slot] = key
				gear_seen[key] = true
	var seen: Variant = data.get("gear_seen")
	if typeof(seen) == TYPE_ARRAY:
		for key: Variant in (seen as Array):
			if _gear_key_ok(String(key)):
				gear_seen[String(key)] = true
	gear_new = maxi(int(data.get("gear_new", 0)), 0)
	_recount_gear()


func _recount_gear() -> void:
	gear_changed.emit()
	_gear_ranks = {}
	for slot: String in Config.GEAR_SLOTS:
		var key := String(gear_worn.get(slot, ""))
		if key == "":
			continue
		var stats := Config.gear_stats(Config.gear_item_of(key), Config.gear_tier_of(key))
		for stat: String in stats.keys():
			_gear_ranks[stat] = int(_gear_ranks.get(stat, 0)) + int(stats[stat])


## How many of a piece are in the bag (not counting one that is worn).
func gear_count(key: String) -> int:
	return int(gear_bag.get(key, 0))


## The piece worn in a slot ("" = nothing).
func gear_in_slot(slot: String) -> String:
	return String(gear_worn.get(slot, ""))


## The slot a piece is worn in ("" = it is not being worn).
func gear_worn_slot(key: String) -> String:
	for slot: String in Config.GEAR_SLOTS:
		if String(gear_worn[slot]) == key:
			return slot
	return ""


## Ranks of a passive stat that come from the gear being worn.
func gear_rank(passive: String) -> int:
	return int(_gear_ranks.get(passive, 0))


## Put pieces in the bag (found in a run, or made at the forge).
func add_gear(key: String, amount: int = 1, found: bool = true) -> void:
	if amount <= 0 or not _gear_key_ok(key):
		return
	gear_bag[key] = gear_count(key) + amount
	gear_seen[key] = true
	if found:
		gear_new += amount
	progress_changed.emit()


func _take_gear(key: String, amount: int) -> void:
	var left := gear_count(key) - amount
	if left > 0:
		gear_bag[key] = left
	else:
		gear_bag.erase(key)


## The slot a piece would go into: its own slot; a ring goes on the first
## free hand, or replaces the weaker ring if both hands are taken.
func gear_slot_for(key: String) -> String:
	var type := String(Config.GEAR_ITEMS[Config.gear_item_of(key)]["type"])
	var options: Array[String] = []
	for slot: String in Config.GEAR_SLOTS:
		if String(Config.GEAR_SLOT_TYPE[slot]) == type:
			options.append(slot)
	for slot: String in options:
		if gear_in_slot(slot) == "":
			return slot
	var weakest := options[0]
	for slot: String in options:
		if Config.gear_tier_of(gear_in_slot(slot)) < Config.gear_tier_of(gear_in_slot(weakest)):
			weakest = slot
	return weakest


## Wear a piece from the bag. Whatever was in that slot goes back to the bag.
func wear_gear(key: String, slot: String = "") -> bool:
	if gear_count(key) <= 0:
		return false
	if slot == "":
		slot = gear_slot_for(key)
	if not gear_worn.has(slot) \
			or String(Config.GEAR_SLOT_TYPE[slot]) != String(Config.GEAR_ITEMS[Config.gear_item_of(key)]["type"]):
		return false
	var before := gear_in_slot(slot)
	_take_gear(key, 1)
	if before != "":
		gear_bag[before] = gear_count(before) + 1
	gear_worn[slot] = key
	_recount_gear()
	progress_changed.emit()
	save_game()
	return true


## Take off what is worn in a slot (it goes back to the bag).
func take_off_gear(slot: String) -> bool:
	var key := gear_in_slot(slot)
	if key == "":
		return false
	gear_bag[key] = gear_count(key) + 1
	gear_worn[slot] = ""
	_recount_gear()
	progress_changed.emit()
	save_game()
	return true


## True if two pieces are in the bag to forge `item` at `tier` (2 or higher)
## out of two of the tier below.
func can_forge(item: String, tier: int) -> bool:
	return tier >= 2 and tier <= Config.GEAR_TIERS.size() and Config.GEAR_ITEMS.has(item) \
			and gear_count(Config.gear_key(item, tier - 1)) >= 2


## Forge two pieces of the tier below into one of `tier`. Returns
##   "success"  the two became one piece of the new tier
##   "fail"     it did not work and one of the two was used up
##   "broke"    it did not work and both were destroyed
##   ""         not possible (not enough pieces)
## `roll` and `break_roll` (0..1) replace the dice, for tests.
func forge_gear(item: String, tier: int, roll: float = -1.0, break_roll: float = -1.0) -> String:
	if not can_forge(item, tier):
		return ""
	var result := _forge_once(item, tier, roll, break_roll)
	progress_changed.emit()
	save_game()
	return result


## One forging (see forge_gear), without saving or telling the screens.
func _forge_once(item: String, tier: int, roll: float, break_roll: float) -> String:
	var def := Config.gear_tier_def(tier)
	var source := Config.gear_key(item, tier - 1)
	if roll < 0.0:
		roll = randf()
	if break_roll < 0.0:
		break_roll = randf()
	if roll < float(def["chance"]):
		_take_gear(source, 2)
		add_gear(Config.gear_key(item, tier), 1, false)
		return "success"
	if break_roll < float(def["break"]):
		_take_gear(source, 2)
		return "broke"
	_take_gear(source, 1)
	return "fail"


## How many pairs FORGE ALL would forge for pieces of quality `tier` (1 = COMMON...):
## every two identical pieces of that quality in the bag. 0 for a quality it is not
## offered for (Config.GEAR_FORGE_ALL_TIERS).
func forge_all_pairs(tier: int) -> int:
	if not Config.GEAR_FORGE_ALL_TIERS.has(tier) or tier >= Config.GEAR_TIERS.size():
		return 0
	var pairs := 0
	for key: String in gear_bag.keys():
		if Config.gear_tier_of(key) == tier:
			pairs += int(gear_count(key) / 2.0)
	return pairs


## FORGE ALL: forge every pair of identical pieces of quality `tier` in the bag, each
## with the usual chance. Returns {"made": pieces forged, "failed": forgings that did
## not work (each cost one piece)}. `roll` (0..1) replaces the dice, for tests.
func forge_all(tier: int, roll: float = -1.0) -> Dictionary:
	var done := {"made": 0, "failed": 0}
	if forge_all_pairs(tier) <= 0:
		return done
	for key: String in gear_bag.keys().duplicate():
		if Config.gear_tier_of(key) != tier:
			continue
		var item := Config.gear_item_of(key)
		for i in int(gear_count(key) / 2.0):
			if not can_forge(item, tier + 1):
				break
			if _forge_once(item, tier + 1, roll, -1.0) == "success":
				done["made"] = int(done["made"]) + 1
			else:
				done["failed"] = int(done["failed"]) + 1
	progress_changed.emit()
	save_game()
	return done


## How many forges are possible right now (for the menu badge).
func forges_ready() -> int:
	var total := 0
	for key: String in gear_bag.keys():
		if gear_count(key) >= 2 and Config.gear_tier_of(key) < Config.GEAR_TIERS.size():
			total += 1
	return total


# ----------------------------------------------------------------------------
#  Pets (described in Config, PETS section)
# ----------------------------------------------------------------------------
## True once the character is high enough for pets at all.
func pets_unlocked() -> bool:
	return level >= Config.PET_UNLOCK_LEVEL


func has_pet(id: String) -> bool:
	return pets_owned.has(id)


## A pet that costs nothing joins by itself as soon as its condition is met
## (the first one: at character level PET_UNLOCK_LEVEL). If no pet is coming
## along yet, it does.
func _grant_free_pets() -> void:
	if not pets_unlocked():
		return
	for id: String in Config.PET_ORDER:
		var def: Dictionary = Config.PETS[id]
		if int(def["price"]) <= 0 and not has_pet(id) and deed_done(def["needs"]):
			pets_owned.append(id)
			if pet_active == "":
				pet_active = id


## Where a pet stands: "owned", "ready" (can be bought now), "poor" (not
## enough coins) or "locked" (its condition is not met, or pets are not open yet).
func pet_status(id: String) -> String:
	if has_pet(id):
		return "owned"
	var def: Dictionary = Config.PETS[id]
	if not pets_unlocked() or not deed_done(def["needs"]):
		return "locked"
	return "ready" if coins >= int(def["price"]) else "poor"


func buy_pet(id: String) -> bool:
	if not Config.PETS.has(id) or pet_status(id) != "ready":
		return false
	coins -= int(Config.PETS[id]["price"])
	pets_owned.append(id)
	pet_active = id
	coins_changed.emit()
	progress_changed.emit()
	save_game()
	return true


## Choose which pet comes along ("" = none).
func choose_pet(id: String) -> bool:
	if id != "" and not has_pet(id):
		return false
	pet_active = id
	progress_changed.emit()
	save_game()
	return true


## True if the pet trick number `index` (Config.PET_TRICKS) has been learned:
## enough ranks of PET BOND are bought (Config.PET_TRICK_RANKS).
func has_pet_trick(index: int) -> bool:
	return index >= 0 and index < Config.PET_TRICK_RANKS.size() and skill_rank("bond") >= int(Config.PET_TRICK_RANKS[index])


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
