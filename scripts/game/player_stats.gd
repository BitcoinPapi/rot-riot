class_name PlayerStats
extends RefCounted
## THE stat pipeline. Every source of character power is added up here, in
## one place, into the handful of numbers the game actually uses:
##
##     base value (Config)
##   + character level   (automatic growth per level)
##   + passive stats     (ranks from the skill tree)
##   + keystones         (special powers at the tips of the skill tree)
##   + ... gear will plug in here in a later stage
##
## The player asks for a fresh copy when a run starts and whenever something
## changes mid-run (a level up). Per-weapon bonuses come from weapon_mods().

var max_hp := 100.0
var damage_mult := 1.0          # all weapons
var fire_rate_mult := 1.0       # all weapons
var speed_mult := 1.0           # movement
var damage_taken_mult := 1.0    # 0.8 = takes 20% less
var evasion := 0.0              # chance (0..1) to dodge a hit completely
var crit_chance := 0.0          # chance (0..1) for a shot to deal CRIT_DAMAGE_MULT
var coin_luck := 0.0            # 0.3 = zombies drop coins 30% more often
var crit_mult: float = Config.CRIT_DAMAGE_MULT   # damage multiplier of a critical hit

# Keystone powers (0 / 1.0 = not learned). See Config.KEYSTONES.
var second_wind := 0.0          # once per run a killing blow leaves this fraction of health instead
var wounded_damage := 0.0       # extra damage against wounded zombies (0.4 = +40%)
var combo_fire_rate := 0.0      # extra fire rate while the kill combo is at least combo_fire_at
var combo_fire_at := 0
var hurt_speed := 0.0           # extra move speed for hurt_speed_time seconds after being hit
var hurt_speed_time := 0.0
var hurt_invuln_mult := 1.0     # the safety time after a hit is multiplied by this
var dodge_invuln: float = Config.DODGE_INVULN    # seconds of safety after a dodge
var magnet_mult := 1.0          # coin magnet range multiplier
var crate_rate := 0.0           # weapon crates appear this much more often (0.25 = +25%)


static func current() -> PlayerStats:
	var s := PlayerStats.new()
	var levels := float(SaveData.level - 1)
	s.max_hp = Config.PLAYER_MAX_HP + Config.LEVEL_HP_PER_LEVEL * levels + SaveData.passive_value("vitality")
	s.damage_mult = (1.0 + Config.LEVEL_DAMAGE_PER_LEVEL * levels) * (1.0 + SaveData.passive_value("strength"))
	s.fire_rate_mult = 1.0 + SaveData.passive_value("dexterity")
	s.speed_mult = 1.0 + SaveData.passive_value("agility")
	s.damage_taken_mult = 1.0 - SaveData.passive_value("defense")
	s.evasion = SaveData.passive_value("evasion")
	s.crit_chance = SaveData.passive_value("critical")
	s.coin_luck = SaveData.passive_value("luck")

	var keys: Dictionary = Config.KEYSTONES
	if SaveData.has_keystone("vitality"):
		s.second_wind = float(keys["vitality"]["value"])
	if SaveData.has_keystone("strength"):
		s.wounded_damage = float(keys["strength"]["value"])
	if SaveData.has_keystone("dexterity"):
		s.combo_fire_rate = float(keys["dexterity"]["value"])
		s.combo_fire_at = int(keys["dexterity"]["combo"])
	if SaveData.has_keystone("agility"):
		s.hurt_speed = float(keys["agility"]["value"])
		s.hurt_speed_time = float(keys["agility"]["time"])
	if SaveData.has_keystone("defense"):
		s.hurt_invuln_mult = float(keys["defense"]["value"])
	if SaveData.has_keystone("evasion"):
		s.dodge_invuln = float(keys["evasion"]["value"])
	if SaveData.has_keystone("critical"):
		s.crit_mult = float(keys["critical"]["value"])
	if SaveData.has_keystone("luck"):
		s.magnet_mult = float(keys["luck"]["value"])
		s.crate_rate = float(keys["luck"]["crates"])
	return s


## Bonuses a weapon has earned from its own level points.
##   damage, fire_rate, reload, duration, spawn: multipliers (1.0 = no bonus)
##   steady: multiplier for spread and recoil (1.0 = unchanged, 0.5 = half)
static func weapon_mods(weapon_id: String) -> Dictionary:
	return {
		"damage": 1.0 + SaveData.weapon_value(weapon_id, "power"),
		"fire_rate": 1.0 + SaveData.weapon_value(weapon_id, "speed"),
		"steady": 1.0 - SaveData.weapon_value(weapon_id, "stability"),
		"reload": 1.0 + SaveData.weapon_value(weapon_id, "reload"),
		"duration": 1.0 + SaveData.weapon_value(weapon_id, "duration"),
		"spawn": 1.0 + SaveData.weapon_value(weapon_id, "spawn"),
	}


## A weapon's own numbers (Config.WEAPONS) with its learned perks applied.
static func weapon_def(weapon_id: String) -> Dictionary:
	var base: Dictionary = Config.WEAPONS[weapon_id]
	var perks: Array = Config.WEAPON_PERKS.get(weapon_id, [])
	var out := base
	var copied := false
	for i in perks.size():
		if not SaveData.weapon_has_perk(weapon_id, i):
			continue
		if not copied:
			out = base.duplicate()
			copied = true
		var mods: Dictionary = perks[i]["mods"]
		for key: String in mods.keys():
			var mod: Array = mods[key]
			var value: Variant = out[key]
			var result := float(value) + float(mod[1]) if String(mod[0]) == "add" else float(value) * float(mod[1])
			if typeof(value) == TYPE_INT:
				out[key] = int(round(result))
			else:
				out[key] = result
	return out


## How a passive's current bonus reads on the character screen.
static func describe_passive(id: String, value: float) -> String:
	match id:
		"vitality":
			return "+%d max health" % int(round(value))
		"strength":
			return "+%d%% damage" % int(round(value * 100.0))
		"dexterity":
			return "+%d%% fire rate" % int(round(value * 100.0))
		"agility":
			return "+%d%% move speed" % int(round(value * 100.0))
		"defense":
			return "%d%% less damage taken" % int(round(value * 100.0))
		"evasion":
			return "%d%% chance to dodge" % int(round(value * 100.0))
		"critical":
			return "%d%% critical hits" % int(round(value * 100.0))
		"luck":
			return "+%d%% coin drops" % int(round(value * 100.0))
	return ""


## How a weapon track's current bonus reads in the armory.
static func describe_track(track: String, value: float) -> String:
	match track:
		"power":
			return "+%d%% damage" % int(round(value * 100.0))
		"speed":
			return "+%d%% fire rate" % int(round(value * 100.0))
		"stability":
			return "-%d%% spread and recoil" % int(round(value * 100.0))
		"reload":
			return "+%d%% reload speed" % int(round(value * 100.0))
		"spawn":
			return "+%d%% crate chance" % int(round(value * 100.0))
		"duration":
			return "+%d%% duration" % int(round(value * 100.0))
	return ""
