class_name GameSheet
extends RefCounted
## The game's numbers as plain tables, for the shared idea board's dashboard
## (the address is in CLAUDE.md, "The idea board").
##
## The dashboard shows these tables and lets the owner and his friends ask
## for a change to any number or name. Nothing they type there reaches the
## game by itself: Claude reads the list of wanted changes, puts them into
## scripts/config.gd by hand, tests, and writes these tables out again.
##
##   godot --headless -- --dump-game=DIR      writes DIR/<section>.json
##
## A section is {id, title, intro, notes, columns, rows} plus, added when it is
## written out: "version" (the game's), "order" (its place in the list),
## "synced" (when, in milliseconds) and "pictures" (false = its rows get no
## place for inspiration pictures):
##   column  {key, label, kind "number"|"text", unit, help, min, max, step, scale, path}
##   row     {id, name, sub, values: {column key: what is shown, or null},
##            meta: {column key: {anything of a column, for this one cell}}}
## "scale": what the dashboard shows = the number in config.gd x scale (a
## share like 0.12 is shown as 12 with unit "%"). "path" says where the number
## lives in config.gd ({id} = the row's id), so a change can be put there.

const KIND_NAMES := {
	Config.SHAMBLER: "SHAMBLER", Config.RUNNER: "RUNNER", Config.BRUTE: "BRUTE", Config.BOSS: "BOSS",
	Config.GOBBER: "GOBBER", Config.CHUCKER: "CHUCKER", Config.GASBAG: "GASBAG", Config.LUNGER: "LUNGER",
}
const VILLAIN_ORDER := [Config.SHAMBLER, Config.RUNNER, Config.BRUTE, Config.GOBBER, Config.CHUCKER, Config.GASBAG,
		Config.LUNGER, Config.BOSS]
## Each villain's own attack: [key in config, what it is called].
const SPECIALS := {
	Config.GOBBER: ["shot_damage", "its spit"], Config.CHUCKER: ["lob_damage", "its rubble"],
	Config.GASBAG: ["burst_damage", "its burst"], Config.LUNGER: ["leap_damage", "its leap"],
	Config.BOSS: ["charge_damage", "his charge"],
}


static func sections() -> Array:
	return [_weapons(), _villains(), _gangs(), _pets(), _skills(), _perks(), _rules()]


## Write every section as DIR/<id>.json. Returns how many were written.
static func write(dir: String) -> int:
	DirAccess.make_dir_recursive_absolute(dir)
	var count := 0
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	for section: Dictionary in sections():
		section["version"] = Config.GAME_VERSION
		section["order"] = count
		section["synced"] = now
		section["pictures"] = String(section["id"]) != "rules"    # (a rule is a number, not a thing to draw)
		var file := FileAccess.open("%s/%s.json" % [dir, String(section["id"])], FileAccess.WRITE)
		if file == null:
			continue
		file.store_string(JSON.stringify(section, "\t"))
		file.close()
		count += 1
	return count


static func _col(key: String, label: String, more: Dictionary = {}) -> Dictionary:
	var col := {"key": key, "label": label, "kind": "number", "unit": "", "help": "", "min": 0.0, "max": 100000.0,
			"step": 1.0, "scale": 1.0, "path": ""}
	for k: String in more.keys():
		col[k] = more[k]
	return col


static func _text(key: String, label: String, path: String, longest: int = 20) -> Dictionary:
	return {"key": key, "label": label, "kind": "text", "unit": "", "help": "", "max": longest, "path": path}


## The value, or nothing (an empty cell) when it does not apply.
static func _maybe(applies: bool, value: Variant) -> Variant:
	if applies:
		return value
	return null


## A number as the dashboard shows it (no 0.30000000000000004).
static func _shown(raw: Variant, scale: float = 1.0) -> float:
	return snappedf(float(raw) * scale, 0.0001)


static func _weapons() -> Dictionary:
	var columns := [
		_text("name", "Name", "WEAPONS.{id}.name", 16),
		_col("damage", "Damage", {"help": "of one bullet, pellet or bite", "max": 5000.0, "path": "WEAPONS.{id}.damage"}),
		_col("interval", "Seconds between shots", {"min": 0.02, "max": 5.0, "step": 0.01, "path": "WEAPONS.{id}.interval"}),
		_col("pellets", "Pellets per shot", {"min": 1.0, "max": 30.0, "path": "WEAPONS.{id}.pellets"}),
		_col("mag", "Rounds in the magazine", {"help": "0 = it never reloads", "max": 500.0, "path": "WEAPONS.{id}.mag"}),
		_col("reload_time", "Reload", {"unit": "s", "max": 10.0, "step": 0.05, "path": "WEAPONS.{id}.reload_time"}),
		_col("duration", "A crate one lasts", {"unit": "s", "help": "0 = always with you", "max": 120.0, "path": "WEAPONS.{id}.duration"}),
		_col("pierce", "Goes through", {"unit": "zombies", "max": 30.0, "path": "WEAPONS.{id}.pierce"}),
		_col("knockback", "Knockback", {"max": 3000.0, "step": 10.0, "path": "WEAPONS.{id}.knockback"}),
		_col("spread_deg", "Spread", {"unit": "°", "max": 90.0, "step": 0.5, "path": "WEAPONS.{id}.spread_deg"}),
		_col("move_mult", "Your speed holding it", {"unit": "x", "min": 0.3, "max": 2.0, "step": 0.01, "path": "WEAPONS.{id}.move_mult"}),
		_col("blast_radius", "Blast size", {"unit": "px", "max": 600.0, "step": 5.0, "path": "WEAPONS.{id}.blast_radius"}),
	]
	var rows: Array = []
	for id: String in Config.WEAPON_ORDER:
		var w: Dictionary = Config.WEAPONS[id]
		var kind := String(w["kind"])
		var values := {"name": String(w["name"])}
		for key: String in ["damage", "interval", "pellets", "mag", "reload_time", "duration", "pierce", "knockback", "spread_deg",
				"move_mult", "blast_radius"]:
			values[key] = null
			if w.has(key):
				values[key] = _shown(w[key])
		if kind != "bullet":
			values["pierce"] = null              # (only bullets go through zombies)
		if kind == "melee":
			for key: String in ["pellets", "reload_time", "spread_deg"]:
				values[key] = null
		rows.append({"id": id, "name": String(w["name"]), "sub": "%s, %s" % [String(w["rarity"]),
				{"bullet": "bullets", "grenade": "grenades", "flame": "fire", "melee": "melee"}.get(kind, kind)], "values": values})
	return {"id": "weapons", "title": "Weapons", "intro": "Every weapon JanJan can hold. The pistol is always with him; the others come in crates.",
			"notes": [], "columns": columns, "rows": rows}


static func _villains() -> Dictionary:
	var columns := [
		_text("name", "Name", "ENEMIES[{id}].name", 16),
		_col("hp", "Health", {"min": 1.0, "max": 100000.0, "path": "ENEMIES[{id}].hp"}),
		_col("speed", "Speed", {"max": 600.0, "path": "ENEMIES[{id}].speed"}),
		_col("damage", "Damage of a hit", {"max": 500.0, "path": "ENEMIES[{id}].damage"}),
		_col("special", "Damage of its own attack", {"max": 500.0}),
		_col("xp", "XP for killing it", {"max": 10000.0, "path": "ENEMIES[{id}].xp"}),
		_col("coin_chance", "Chance to drop a coin", {"unit": "%", "max": 100.0, "scale": 100.0, "path": "ENEMIES[{id}].coin_chance"}),
		_col("start", "First wave it shows up", {"min": 1.0, "max": 100.0}),
		_col("share", "Most of a wave it can be", {"unit": "%", "max": 100.0, "scale": 100.0}),
	]
	var mix := {}
	for i in Config.ENEMY_MIX.size():
		mix[int(Config.ENEMY_MIX[i]["kind"])] = i
	var rows: Array = []
	for kind: int in VILLAIN_ORDER:
		var e: Dictionary = Config.ENEMIES[kind]
		var id: String = KIND_NAMES[kind]
		var values := {"name": String(e["name"]), "hp": _shown(e["hp"]), "speed": _shown(e["speed"]), "damage": _shown(e["damage"]),
				"special": null, "xp": _shown(e["xp"]), "coin_chance": _shown(e.get("coin_chance", 0.0), 100.0), "start": null, "share": null}
		var meta := {}
		if SPECIALS.has(kind):
			var special: Array = SPECIALS[kind]
			values["special"] = _shown(e[String(special[0])])
			meta["special"] = {"path": "ENEMIES[%s].%s" % [id, String(special[0])], "help": String(special[1])}
		if mix.has(kind):
			var entry: Dictionary = Config.ENEMY_MIX[int(mix[kind])]
			values["start"] = _shown(entry["start"])
			values["share"] = _shown(entry["max"], 100.0)
			meta["start"] = {"path": "ENEMY_MIX[kind=%s].start" % id}
			meta["share"] = {"path": "ENEMY_MIX[kind=%s].max" % id}
		var sub := "the leader of each map's gang, every %d waves" % Config.BOSS_EVERY if kind == Config.BOSS else ""
		if kind == Config.SHAMBLER:
			sub = "the plain zombie: at least %d%% of every wave" % int(round(Config.ENEMY_MIX_SHAMBLERS * 100.0))
		rows.append({"id": id, "name": String(e["name"]).to_upper(), "sub": sub, "values": values, "meta": meta})
	return {"id": "villains", "title": "Villains", "intro": "The dead the gangs send. These are their numbers on the first map, in wave 1.",
			"notes": ["Every wave they get tougher, and every map multiplies them again (see Gang maps)."], "columns": columns, "rows": rows}


static func _gangs() -> Dictionary:
	var columns := [
		_text("name", "Map", "MAPS[{id}].name", 22),
		_text("gang", "Gang", "MAPS[{id}].gang", 20),
		_text("boss", "Its boss", "MAPS[{id}].boss", 20),
		_col("hp", "Zombie health", {"unit": "x", "min": 0.1, "max": 10000.0, "step": 0.5, "path": "MAPS[{id}].hp"}),
		_col("damage", "Zombie damage", {"unit": "x", "min": 0.1, "max": 1000.0, "step": 0.1, "path": "MAPS[{id}].damage"}),
		_col("speed", "Zombie speed", {"unit": "x", "min": 0.5, "max": 3.0, "step": 0.01, "path": "MAPS[{id}].speed"}),
		_col("xp", "XP", {"unit": "x", "min": 0.1, "max": 100.0, "step": 0.25, "path": "MAPS[{id}].xp"}),
		_col("coins", "A coin is worth", {"min": 1.0, "max": 1000.0, "path": "MAPS[{id}].coins"}),
	]
	var rows: Array = []
	for i in Config.MAPS.size():
		var m: Dictionary = Config.MAPS[i]
		rows.append({"id": str(i), "name": "MAP %d" % (i + 1), "sub": String(m["story"]), "values": {
				"name": String(m["name"]), "gang": String(m.get("gang", "")), "boss": String(m.get("boss", "")),
				"hp": _shown(m["hp"]), "damage": _shown(m["damage"]), "speed": _shown(m["speed"]), "xp": _shown(m["xp"]),
				"coins": _shown(m["coins"])}})
	return {"id": "gangs", "title": "Gang maps", "intro": "Five maps, each one gang's ground with its own boss. The numbers multiply every zombie on that map.",
			"notes": ["Gang and boss names are invented. Real gangs and real people do not go into the game."],
			"columns": columns, "rows": rows}


static func _pets() -> Dictionary:
	var columns := [
		_text("name", "Name", "PETS.{id}.name", 12),
		_text("title", "What it is", "PETS.{id}.title", 24),
		_col("price", "Price", {"unit": "coins", "max": 1000000.0, "step": 50.0, "path": "PETS.{id}.price"}),
		_col("level", "Needs character level", {"min": 1.0, "max": 100.0}),
		_col("cap", "Most damage it can add", {"unit": "%", "max": 100.0, "scale": 100.0, "help": "shared by every pet of its rarity"}),
		_col("bite", "Bite strength", {"unit": "x", "min": 0.1, "max": 20.0, "step": 0.1, "help": "shared by every pet of its rarity"}),
		_col("bite_interval", "Seconds between bites", {"min": 0.1, "max": 10.0, "step": 0.05, "path": "PETS.{id}.bite_interval"}),
		_col("speed", "Speed", {"min": 100.0, "max": 1000.0, "step": 10.0, "path": "PETS.{id}.speed"}),
	]
	var rows: Array = []
	for id: String in Config.PETS.keys():
		var p: Dictionary = Config.PETS[id]
		var rarity := String(p["rarity"])
		var needs: Dictionary = p["needs"]
		var by_level := String(needs["kind"]) == "level"
		var sub := rarity
		if not by_level:
			sub += ", after clearing map %d" % int(needs["value"])
		rows.append({"id": id, "name": String(p["name"]), "sub": sub, "values": {
				"name": String(p["name"]), "title": String(p["title"]), "price": _shown(p["price"]),
				"level": _maybe(by_level, _shown(needs["value"])),
				"cap": _shown(Config.PET_RARITIES[rarity]["damage"], 100.0), "bite": _shown(Config.PET_RARITIES[rarity]["bite"]),
				"bite_interval": _shown(p["bite_interval"]), "speed": _shown(p["speed"])},
				"meta": {"level": {"path": "PETS.%s.needs.value" % id}, "cap": {"path": "PET_RARITIES.%s.damage" % rarity},
				"bite": {"path": "PET_RARITIES.%s.bite" % rarity}}})
	return {"id": "pets", "title": "Pets", "intro": "One pet walks with JanJan, bites what comes close and adds to his damage.",
			"notes": ["With no PET BOND a pet gives %d%% of its damage bonus; at %d ranks of PET BOND, all of it." % [
			int(round(Config.PET_BOND_BASE * 100.0)), Config.PET_BOND_FULL]], "columns": columns, "rows": rows}


static func _skills() -> Dictionary:
	var columns := [
		_text("name", "Name", "PASSIVES.{id}.name", 16),
		_col("each", "Each rank gives", {"max": 100.0, "step": 0.5}),
		_col("most", "The most it can ever give", {"unit": "%", "max": 200.0, "scale": 100.0}),
		_col("half", "Ranks to reach half of that", {"min": 1.0, "max": 500.0}),
		_col("level", "Needs character level", {"min": 1.0, "max": 100.0}),
		_text("power", "Special power", "KEYSTONES.{id}.name", 18),
	]
	var rows: Array = []
	for group: Dictionary in Config.SKILL_GROUPS:
		for id: String in group["stats"]:
			var p: Dictionary = Config.PASSIVES[id]
			var values := {"name": String(p["name"]), "each": null, "most": null, "half": null, "level": null,
					"power": Config.KEYSTONES.get(id, {}).get("name")}
			var meta := {}
			if String(p["kind"]) == "linear" and id != "bond":
				var share := float(p["per_rank"]) < 1.0       # (0.03 = 3%; 8 = 8 health)
				values["each"] = _shown(p["per_rank"], 100.0 if share else 1.0)
				meta["each"] = {"path": "PASSIVES.%s.per_rank" % id, "scale": 100.0 if share else 1.0, "unit": "%" if share else "health"}
			elif String(p["kind"]) == "curve":
				values["most"] = _shown(p["max"], 100.0)
				values["half"] = _shown(p["half"])
				meta["most"] = {"path": "PASSIVES.%s.max" % id}
				meta["half"] = {"path": "PASSIVES.%s.half" % id}
			if p.has("min_level"):
				values["level"] = _shown(p["min_level"])
				meta["level"] = {"path": "PASSIVES.%s.min_level" % id}
			rows.append({"id": id, "name": String(p["name"]), "sub": "%s: %s" % [String(group["name"]), String(p["desc"])],
					"values": values, "meta": meta})
	return {"id": "skills", "title": "Skills", "intro": "The nine stats on the Skills page. A rank costs skill points; ranks have no limit.",
			"notes": ["A stat's special power is yours after %d ranks of it." % Config.KEYSTONE_RANK], "columns": columns, "rows": rows}


static func _perks() -> Dictionary:
	var columns := [
		_text("name", "Name", "RUN_PERKS.{id}.name", 20),
		_col("value", "One level gives", {"max": 1000.0, "step": 0.5, "path": "RUN_PERKS.{id}.value"}),
		_col("max", "Can be taken", {"unit": "times", "help": "0 = as often as you like", "max": 50.0, "path": "RUN_PERKS.{id}.max"}),
	]
	var rows: Array = []
	for id: String in Config.RUN_PERK_ORDER:
		var p: Dictionary = Config.RUN_PERKS[id]
		var share := String(p["text"]).contains("%s%%")
		rows.append({"id": id, "name": String(p["name"]), "sub": Config.run_perk_text(id, 1), "values": {
				"name": String(p["name"]), "value": _shown(p["value"], 100.0 if share else 1.0), "max": _shown(p["max"])},
				"meta": {"value": {"scale": 100.0 if share else 1.0, "unit": "%" if share else ""}}})
	return {"id": "perks", "title": "Perks", "intro": "After every boss you choose one of three. A perk lasts until that run ends.",
			"notes": [], "columns": columns, "rows": rows}


static func _rules() -> Dictionary:
	var total := 0
	for level in range(1, Config.LEVEL_CAP):
		total += Config.level_xp_needed(level)
	var list := [
		["LEVEL_CAP", Config.LEVEL_CAP, "Highest character level", {"min": 2.0, "max": 1000.0}],
		["LEVEL_XP_BASE", Config.LEVEL_XP_BASE, "XP needed for level 2", {"min": 1.0, "max": 100000.0}],
		["LEVEL_XP_EXPONENT", Config.LEVEL_XP_EXPONENT, "How steeply that grows", {"min": 1.0, "max": 4.0, "step": 0.05,
				"help": "XP needed = the number above x level, this many times over"}],
		["LEVEL_HP_PER_LEVEL", Config.LEVEL_HP_PER_LEVEL, "Health gained per level", {"max": 100.0}],
		["LEVEL_DAMAGE_PER_LEVEL", Config.LEVEL_DAMAGE_PER_LEVEL, "Damage gained per level", {"unit": "%", "scale": 100.0, "max": 50.0, "step": 0.5}],
		["LEVEL_UP_HEAL", Config.LEVEL_UP_HEAL, "Healing when you level up", {"unit": "% of health", "scale": 100.0, "max": 100.0}],
		["SKILL_POINTS_PER_LEVEL", Config.SKILL_POINTS_PER_LEVEL, "Skill points per level", {"min": 1.0, "max": 10.0}],
		["KEYSTONE_RANK", Config.KEYSTONE_RANK, "Ranks of a skill for its special power", {"min": 1.0, "max": 200.0}],
		["SKILL_POINT_COST_BASE", Config.SKILL_POINT_COST_BASE, "Price of the first bought skill point", {"unit": "coins", "max": 100000.0, "step": 10.0}],
		["SKILL_POINT_COST_GROWTH", Config.SKILL_POINT_COST_GROWTH, "Each further one costs", {"unit": "x", "min": 1.0, "max": 3.0, "step": 0.01}],
		["PLAYER_MAX_HP", Config.PLAYER_MAX_HP, "JanJan's starting health", {"min": 1.0, "max": 10000.0, "step": 5.0}],
		["PLAYER_SPEED", Config.PLAYER_SPEED, "JanJan's walking speed", {"min": 50.0, "max": 1000.0, "step": 10.0}],
		["PET_UNLOCK_LEVEL", Config.PET_UNLOCK_LEVEL, "Level at which the first pet joins", {"min": 1.0, "max": 100.0}],
		["PERK_CHOICES", Config.PERK_CHOICES, "Perks offered each time", {"min": 2.0, "max": 3.0}],
		["WAVES_PER_MAP", Config.WAVES_PER_MAP, "Waves on every map", {"min": 5.0, "max": 1000.0, "step": 5.0}],
		["WAVE_BASE_COUNT", Config.WAVE_BASE_COUNT, "Zombies in wave 1", {"min": 1.0, "max": 500.0}],
		["WAVE_COUNT_PER_WAVE", Config.WAVE_COUNT_PER_WAVE, "More zombies with every wave", {"max": 100.0}],
		["MAX_ENEMIES_ALIVE", Config.MAX_ENEMIES_ALIVE, "Most zombies alive at once", {"min": 10.0, "max": 400.0, "step": 10.0}],
		["CHEST_COUNT", Config.CHEST_COUNT, "Treasure chests per run", {"max": 12.0}],
	]
	var rows: Array = []
	for item: Array in list:
		var more: Dictionary = item[3]
		var cell := {"path": String(item[0])}
		for k: String in more.keys():
			cell[k] = more[k]
		rows.append({"id": String(item[0]).to_lower(), "name": String(item[2]), "sub": String(more.get("help", "")),
				"values": {"value": _shown(item[1], float(more.get("scale", 1.0)))}, "meta": {"value": cell}})
	return {"id": "rules", "title": "Levels & rules", "intro": "How the character grows, and the few numbers that shape a whole run.",
			"notes": ["From level 1 to level %d takes %s XP in all." % [Config.LEVEL_CAP, _grouped(total)],
			"A boss comes every %d waves, and a perk choice follows him." % Config.BOSS_EVERY],
			"columns": [_col("value", "Value")], "rows": rows}


## 26880000 -> "26,880,000"
static func _grouped(number: int) -> String:
	var digits := str(number)
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return digits + out
