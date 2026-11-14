class_name PlayerStats
extends RefCounted
## THE stat pipeline. Every source of character power is added up here, in
## one place, into the handful of numbers the game actually uses:
##
##     base value (Config)
##   + character level   (automatic growth per level)
##   + passive stats     (skill points)
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
	return s


## Bonuses a weapon has earned from its own level points.
##   damage, fire_rate, duration, spawn: multipliers (1.0 = no bonus)
##   steady: multiplier for spread and recoil (1.0 = unchanged, 0.5 = half)
static func weapon_mods(weapon_id: String) -> Dictionary:
	return {
		"damage": 1.0 + SaveData.weapon_value(weapon_id, "power"),
		"fire_rate": 1.0 + SaveData.weapon_value(weapon_id, "speed"),
		"steady": 1.0 - SaveData.weapon_value(weapon_id, "stability"),
		"duration": 1.0 + SaveData.weapon_value(weapon_id, "duration"),
		"spawn": 1.0 + SaveData.weapon_value(weapon_id, "spawn"),
	}


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
		"spawn":
			return "+%d%% crate chance" % int(round(value * 100.0))
		"duration":
			return "+%d%% duration" % int(round(value * 100.0))
	return ""
