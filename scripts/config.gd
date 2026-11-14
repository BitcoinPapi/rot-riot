extends Node
## ============================================================================
##  ROT RIOT - CONFIG
##
##  Every balance number (speeds, health, prices, wave sizes) and every
##  game-feel value (screen shake, hit stop, knockback, recoil) lives in THIS
##  file. To tune the game, change numbers here and press Play again.
##
##  Units: distances are pixels, times are seconds, speeds are pixels/second.
##  "shake" values are "trauma" from 0 (none) to 1 (maximum earthquake).
## ============================================================================

const GAME_TITLE := "ROT RIOT"
const GAME_VERSION := "0.5.0"
const HERO_NAME := "CLIFF"                    # the survivor you play
# How he looks with nothing equipped (his gear is drawn over this, see scripts/autoload/art.gd).
const HERO_LOOK := {"skin": "#dfae88", "skin_dark": "#b98660", "hair": "#3a2a1e", "shirt": "#23262b", "shirt_light": "#33373d",
	"strap": "#6b4a2e", "pants": "#2c2f34", "pads": "#1a1c20", "boots": "#17181b", "belt": "#3a3d42", "pouch": "#3f4a2c", "metal": "#b9bec4"}

# ----------------------------------------------------------------------------
#  ARENA
# ----------------------------------------------------------------------------
const ARENA_SIZE := Vector2(2400.0, 1500.0)   # playable clearing
const ARENA_OUTER_MARGIN := 150.0             # painted ground beyond the playable edge
const CAMERA_EDGE_MARGIN := 110.0             # how far past the edge the camera may look
const SPAWN_DIST_MIN := 160.0                 # zombies appear this far outside the edge...
const SPAWN_DIST_MAX := 330.0                 # ...hidden under the trees, then walk in
const OBSTACLE_COUNT := 9                     # rocks / stumps scattered in the arena
const OBSTACLE_RADIUS_MIN := 34.0
const OBSTACLE_RADIUS_MAX := 58.0
const DECAL_RESOLUTION := 1.0                 # 1.0 = full detail blood layer. Lower (0.5) for weak devices / mobile.

# ----------------------------------------------------------------------------
#  PLAYER
# ----------------------------------------------------------------------------
const PLAYER_RADIUS := 14.0
const PLAYER_SPEED := 300.0                   # instant, no acceleration
const PLAYER_MAX_HP := 100.0
const PLAYER_HURT_INVULN := 0.45              # seconds of safety after being hit
const PLAYER_HURT_SHOVE_RADIUS := 120.0       # being hit shoves nearby zombies away...
const PLAYER_HURT_SHOVE_FORCE := 430.0        # ...this hard, so you get a chance to escape
const PLAYER_HURT_SHOVE_STAGGER := 0.25       # ...and stops them for this long
const PLAYER_PUSHED_BY_ENEMIES := 0.4         # 0 = zombies can't move you, 1 = they bulldoze you
const PLAYER_MAX_PUSH_PER_FRAME := 5.0
const RECOIL_PUSH_DAMPING := 12.0             # how fast weapon recoil shove fades

# ----------------------------------------------------------------------------
#  INPUT FEEL
# ----------------------------------------------------------------------------
const STICK_DEADZONE := 0.25
const GAMEPAD_AIM_FOLLOWS_MOVE := true        # right stick idle -> aim where you walk
const CONFINE_MOUSE := true                   # keep the mouse inside the window while playing
# Mild aim assist: if a zombie is within this cone around your aim, shots bend toward it.
const AIM_ASSIST_CONE_DEG_MOUSE := 5.0
const AIM_ASSIST_CONE_DEG_GAMEPAD := 14.0
const AIM_ASSIST_STRENGTH_MOUSE := 0.55       # 0 = off, 1 = perfect snap
const AIM_ASSIST_STRENGTH_GAMEPAD := 0.85
const AIM_ASSIST_RANGE := 620.0

# ----------------------------------------------------------------------------
#  WEAPONS
#  kind          "bullet", "grenade", "flame" or "melee"
#  rarity        which crate tier it comes in (see CRATE_RARITIES below)
#  dual          true = picking up a second one while holding it gives one in each hand
#  duration      seconds a crate weapon lasts (0 = forever)
#  interval      seconds between shots (lower = faster)
#  mag           shots before it has to be reloaded (0 = never reloads)
#  reload_kind   "mag" = swap the whole magazine (reload_time seconds, cannot shoot meanwhile)
#                "shell" = one round at a time (reload_time seconds each, shooting interrupts it)
#  reload_pitch  how high or low its reload clicks sound (1 = normal, lower = heavier)
#  mag_debris    what falls on the ground when it is reloaded
#  spread_deg    full width of the random cone
#  knockback     shove speed given to a zombie that is hit
#  stagger       seconds a hit zombie stops walking
#  --- feel ---
#  shake         screen shake per shot       kick         camera jolt opposite to aim
#  recoil_gun    px the gun jumps back       recoil_push  speed the player is shoved back
#  hitstop_kill  freeze-frame on a kill      flash_size   muzzle flash size
# ----------------------------------------------------------------------------
const STARTER_WEAPON := "pistol"
# Order on the Armory screen.
const WEAPON_ORDER := ["pistol", "smg", "shotgun", "machinegun", "rifle", "sledge", "launcher", "flamethrower", "chainsaw"]
# What crates can contain. A "pistol" crate hands you a second pistol (dual pistols).
const CRATE_WEAPONS := ["pistol", "smg", "shotgun", "machinegun", "rifle", "sledge", "launcher", "flamethrower", "chainsaw"]

# Crate tiers. "weight" is how often a weapon of that tier is picked compared
# with the others; each weapon's own SPAWN RATE upgrade multiplies its weight.
const CRATE_RARITY_ORDER := ["common", "uncommon", "rare"]
const CRATE_RARITIES := {
	"common": {"name": "COMMON", "weight": 1.0, "color": Color(0.86, 0.86, 0.82)},
	"uncommon": {"name": "UNCOMMON", "weight": 0.5, "color": Color(0.35, 0.9, 0.4)},
	"rare": {"name": "RARE", "weight": 0.22, "color": Color(0.35, 0.62, 1.0)},
}

# Dual wielding (one gun in each hand).
const DUAL_INTERVAL_MULT := 0.55        # time between shots (0.55 = fires about 1.8x as fast)
const DUAL_SPREAD_MULT := 1.3           # ...but less accurate
const DUAL_RECOIL_MULT := 1.15          # ...and it kicks more
const DUAL_PISTOL_DURATION := 25.0      # seconds a second pistol lasts
const DUAL_MAG_MULT := 2                # two guns = two magazines

# Reloading. Reload speed rises with the DEXTERITY passive and with the
# weapon's own RELOAD SPEED upgrade.
const RELOAD_RAGE_MULT := 1.6           # reload this much faster while rage is active
const RAGE_REFILLS_AMMO := true         # activating rage tops the magazine up instantly
const LOW_AMMO_FRACTION := 0.25         # the ammo counter turns red below this
const RELOAD_MAG_IN_AT := 0.55          # fraction of the reload at which the new magazine clicks in
const RELOAD_RACK_AT := 0.86            # fraction at which the slide is racked
const SHELL_FIRST_DELAY := 0.18         # extra pause before the first shell goes in

const WEAPONS := {
	"pistol": {
		"name": "PISTOL", "kind": "bullet", "rarity": "common", "dual": true, "duration": 0.0,
		"mag": 12, "reload_kind": "mag", "reload_time": 0.9, "reload_pitch": 1.15, "mag_debris": "mag",
		"damage": 14.0, "interval": 0.24, "pellets": 1, "spread_deg": 2.5,
		"bullet_speed": 1500.0, "speed_var": 0.0, "range": 720.0, "pierce": 0,
		"knockback": 170.0, "stagger": 0.11, "move_mult": 1.0,
		"shake": 0.17, "kick": 5.0, "recoil_gun": 6.0, "recoil_push": 0.0,
		"hitstop_kill": 0.028, "flash_size": 30.0, "casing": "brass",
		"tracer_len": 26.0, "tracer_width": 3.0, "tracer_color": Color(1.0, 0.92, 0.55),
		"muzzle_dist": 30.0, "sound": "pistol", "color": Color(0.80, 0.82, 0.86),
	},
	"smg": {
		# Light and very fast: a hose of weak bullets, and you move quicker with it.
		"name": "SMG", "kind": "bullet", "rarity": "common", "dual": true, "duration": 20.0,
		"mag": 40, "reload_kind": "mag", "reload_time": 1.0, "reload_pitch": 1.28, "mag_debris": "mag",
		"damage": 7.0, "interval": 0.05, "pellets": 1, "spread_deg": 11.0,
		"bullet_speed": 1500.0, "speed_var": 0.06, "range": 520.0, "pierce": 0,
		"knockback": 55.0, "stagger": 0.05, "move_mult": 1.1,
		"shake": 0.07, "kick": 2.5, "recoil_gun": 3.0, "recoil_push": 8.0,
		"hitstop_kill": 0.012, "flash_size": 26.0, "casing": "brass",
		"tracer_len": 24.0, "tracer_width": 2.0, "tracer_color": Color(1.0, 0.95, 0.7),
		"muzzle_dist": 34.0, "sound": "smg", "color": Color(0.55, 0.85, 0.9),
	},
	"shotgun": {
		"name": "SHOTGUN", "kind": "bullet", "rarity": "common", "dual": true, "duration": 20.0,
		"mag": 6, "reload_kind": "shell", "reload_time": 0.36, "reload_pitch": 1.0, "mag_debris": "",   # reload_time is per shell
		"damage": 10.0, "interval": 0.72, "pellets": 9, "spread_deg": 26.0,
		"bullet_speed": 1350.0, "speed_var": 0.18, "range": 400.0, "pierce": 1,
		"knockback": 300.0, "stagger": 0.22, "move_mult": 1.0,
		"shake": 0.52, "kick": 16.0, "recoil_gun": 13.0, "recoil_push": 170.0,
		"hitstop_kill": 0.05, "flash_size": 62.0, "casing": "shell",
		"tracer_len": 20.0, "tracer_width": 2.5, "tracer_color": Color(1.0, 0.80, 0.40),
		"muzzle_dist": 38.0, "sound": "shotgun", "color": Color(0.95, 0.55, 0.20),
	},
	"machinegun": {
		"name": "MACHINE GUN", "kind": "bullet", "rarity": "uncommon", "dual": true, "duration": 20.0,
		"mag": 110, "reload_kind": "mag", "reload_time": 1.9, "reload_pitch": 0.72, "mag_debris": "box",
		"damage": 10.0, "interval": 0.062, "pellets": 1, "spread_deg": 8.0,
		"bullet_speed": 1650.0, "speed_var": 0.05, "range": 760.0, "pierce": 1,
		"knockback": 85.0, "stagger": 0.07, "move_mult": 1.0,
		"shake": 0.11, "kick": 3.5, "recoil_gun": 4.0, "recoil_push": 16.0,
		"hitstop_kill": 0.014, "flash_size": 34.0, "casing": "brass",
		"tracer_len": 34.0, "tracer_width": 2.5, "tracer_color": Color(1.0, 0.95, 0.60),
		"muzzle_dist": 40.0, "sound": "machinegun", "color": Color(0.95, 0.85, 0.25),
	},
	"rifle": {
		# Slow, loud, and each bullet goes straight through a whole line of zombies.
		"name": "RIFLE", "kind": "bullet", "rarity": "uncommon", "dual": false, "duration": 22.0,
		"mag": 6, "reload_kind": "mag", "reload_time": 1.3, "reload_pitch": 0.9, "mag_debris": "clip",
		"damage": 85.0, "interval": 0.52, "pellets": 1, "spread_deg": 0.6,
		"bullet_speed": 1900.0, "speed_var": 0.0, "range": 1100.0, "pierce": 6,
		"pierce_keep": 0.85,          # damage kept after each zombie it passes through
		"knockback": 420.0, "stagger": 0.3, "move_mult": 0.95,
		"shake": 0.5, "kick": 18.0, "recoil_gun": 14.0, "recoil_push": 150.0,
		"hitstop_kill": 0.06, "flash_size": 56.0, "casing": "brass",
		"tracer_len": 90.0, "tracer_width": 4.0, "tracer_color": Color(1.0, 0.97, 0.8),
		"muzzle_dist": 46.0, "sound": "rifle", "color": Color(0.75, 0.6, 0.4),
	},
	"sledge": {
		"name": "SLEDGEHAMMER", "kind": "melee", "rarity": "uncommon", "dual": false, "duration": 20.0,
		"mag": 0, "reload_kind": "", "reload_time": 0.0, "reload_pitch": 1.0, "mag_debris": "",
		"damage": 62.0, "interval": 0.34, "pellets": 1, "spread_deg": 0.0,
		"bullet_speed": 0.0, "speed_var": 0.0, "range": 108.0, "pierce": 0,
		"arc_deg": 160.0,             # width of the swing
		"swing": true,                # drawn swinging in an arc (false = held out in front)
		"hit_sound": "sledge_hit", "hit_blood": 0,
		"knockback": 660.0, "stagger": 0.5, "move_mult": 1.18,
		"shake": 0.06, "kick": 0.0, "recoil_gun": 0.0, "recoil_push": -70.0,   # negative = lunge forward
		"shake_hit": 0.42, "hitstop_hit": 0.055,
		"hitstop_kill": 0.0, "flash_size": 0.0, "casing": "",
		"tracer_len": 0.0, "tracer_width": 0.0, "tracer_color": Color(1, 1, 1),
		"muzzle_dist": 30.0, "sound": "sledge_swing", "color": Color(0.60, 0.75, 0.95),
	},
	"launcher": {
		"name": "LAUNCHER", "kind": "grenade", "rarity": "rare", "dual": false, "duration": 18.0,
		"mag": 1, "reload_kind": "mag", "reload_time": 0.85, "reload_pitch": 0.58, "mag_debris": "shellcase",
		"damage": 95.0, "interval": 0.15, "pellets": 1, "spread_deg": 2.0,
		"bullet_speed": 760.0, "speed_var": 0.0, "range": 620.0, "pierce": 0,
		"knockback": 0.0, "stagger": 0.0, "move_mult": 1.0,
		"blast_radius": 135.0,        # everything inside takes damage
		"blast_edge_damage": 0.4,     # fraction of damage dealt at the very edge
		"blast_knockback": 620.0, "blast_stagger": 0.45,
		"blast_shake": 0.95, "blast_hitstop": 0.085,
		"shake": 0.36, "kick": 14.0, "recoil_gun": 14.0, "recoil_push": 200.0,
		"hitstop_kill": 0.0, "flash_size": 48.0, "casing": "",
		"tracer_len": 0.0, "tracer_width": 0.0, "tracer_color": Color(1.0, 0.55, 0.20),
		"muzzle_dist": 40.0, "sound": "launcher", "color": Color(0.45, 0.80, 0.35),
	},
	"flamethrower": {
		# A short cone of fire. Each puff does little, but it passes through
		# everything and sets zombies burning (see burn_* below).
		"name": "FLAMETHROWER", "kind": "flame", "rarity": "rare", "dual": false, "duration": 18.0,
		"mag": 130, "reload_kind": "mag", "reload_time": 1.7, "reload_pitch": 0.8, "mag_debris": "can",
		"reload_start": "hiss", "reload_end": "hiss",
		"damage": 2.5, "interval": 0.04, "pellets": 2, "spread_deg": 24.0,
		"bullet_speed": 560.0, "speed_var": 0.2, "range": 225.0, "pierce": 99,
		"pierce_keep": 1.0,
		"flame_drag": 2.4,            # how quickly each puff slows down
		"flame_size": 9.0, "flame_grow": 46.0,   # puff radius at the nozzle, and growth per second
		"burn_time": 2.5,             # seconds a zombie keeps burning after being touched
		"burn_dps": 7.0,              # damage per second while burning
		"knockback": 14.0, "stagger": 0.04, "move_mult": 1.0,
		"shake": 0.025, "kick": 0.6, "recoil_gun": 1.5, "recoil_push": 0.0,
		"hitstop_kill": 0.0, "flash_size": 0.0, "casing": "",
		"tracer_len": 0.0, "tracer_width": 0.0, "tracer_color": Color(1.0, 0.6, 0.15),
		"muzzle_dist": 40.0, "sound": "flame", "color": Color(1.0, 0.5, 0.15),
	},
	"chainsaw": {
		# Held out in front: grinds anything in a narrow cone, many times a second.
		"name": "CHAINSAW", "kind": "melee", "rarity": "rare", "dual": false, "duration": 18.0,
		"mag": 0, "reload_kind": "", "reload_time": 0.0, "reload_pitch": 1.0, "mag_debris": "",
		"damage": 22.0, "interval": 0.075, "pellets": 1, "spread_deg": 0.0,
		"bullet_speed": 0.0, "speed_var": 0.0, "range": 84.0, "pierce": 0,
		"arc_deg": 95.0,
		"swing": false,
		"hit_sound": "chainsaw_hit", "hit_blood": 5,   # extra blood drops per zombie per bite
		"knockback": 30.0, "stagger": 0.14, "move_mult": 1.12,
		"shake": 0.03, "kick": 0.0, "recoil_gun": 2.0, "recoil_push": 0.0,
		"shake_hit": 0.09, "hitstop_hit": 0.0,
		"hitstop_kill": 0.0, "flash_size": 0.0, "casing": "",
		"tracer_len": 0.0, "tracer_width": 0.0, "tracer_color": Color(1, 1, 1),
		"muzzle_dist": 40.0, "sound": "chainsaw", "color": Color(1.0, 0.45, 0.2),
	},
}

# ----------------------------------------------------------------------------
#  ENEMIES
#  xp            experience given to the character and to the weapon that killed it
#  kb_mult       how much knockback they take (0 = immovable)
#  stagger_mult  how long hits stop them (0 = unstoppable)
#  mass          heavier zombies shove lighter ones aside
#  push_player   how strongly they can squeeze the player (see PLAYER_PUSHED_BY_ENEMIES)
# ----------------------------------------------------------------------------
const SHAMBLER := 0
const RUNNER := 1
const BRUTE := 2
const BOSS := 3

const ENEMIES := {
	SHAMBLER: {
		"name": "Shambler", "hp": 24.0, "speed": 86.0, "speed_var": 0.2, "radius": 14.0,
		"damage": 10.0, "attack_cd": 0.8, "score": 10, "rage": 2.2, "xp": 4,
		"coin_chance": 0.18, "coins_min": 1, "coins_max": 1, "medkit_chance": 0.012,
		"kb_mult": 1.0, "stagger_mult": 1.0, "mass": 1.0, "push_player": 1.0,
		"hitstop_mult": 1.0, "shake_mult": 1.0, "blood": 1.0,
	},
	RUNNER: {
		"name": "Runner", "hp": 14.0, "speed": 220.0, "speed_var": 0.12, "radius": 11.0,
		"damage": 8.0, "attack_cd": 0.7, "score": 15, "rage": 2.6, "xp": 5,
		"coin_chance": 0.20, "coins_min": 1, "coins_max": 1, "medkit_chance": 0.012,
		"kb_mult": 1.25, "stagger_mult": 1.0, "mass": 0.6, "push_player": 0.7,
		"hitstop_mult": 0.8, "shake_mult": 0.8, "blood": 0.7,
	},
	BRUTE: {
		"name": "Brute", "hp": 220.0, "speed": 58.0, "speed_var": 0.08, "radius": 26.0,
		"damage": 26.0, "attack_cd": 1.1, "score": 60, "rage": 9.0, "xp": 22,
		"coin_chance": 1.0, "coins_min": 2, "coins_max": 3, "medkit_chance": 0.15,
		"kb_mult": 0.28, "stagger_mult": 0.3, "mass": 6.0, "push_player": 2.5,
		"hitstop_mult": 2.6, "shake_mult": 4.0, "blood": 2.5,
	},
	BOSS: {
		"name": "THE GORGER", "hp": 1700.0, "speed": 72.0, "speed_var": 0.0, "radius": 52.0,
		"damage": 30.0, "attack_cd": 1.0, "score": 1000, "rage": 40.0, "xp": 350,
		"coin_chance": 1.0, "coins_min": 25, "coins_max": 25, "medkit_chance": 1.0,
		"kb_mult": 0.04, "stagger_mult": 0.0, "mass": 60.0, "push_player": 2.5,
		"hitstop_mult": 5.0, "shake_mult": 14.0, "blood": 8.0,
		# boss-only behaviour
		"hp_growth_per_boss": 0.25,    # each later boss has +25% health (on top of the wave and map growth)
		"charge_cooldown": 5.5,        # seconds between charges
		"charge_windup": 0.85,         # warning time before it dashes
		"charge_speed": 620.0,
		"charge_time": 0.85,
		"charge_damage": 38.0,
		"charge_recover": 0.9,         # it stands dazed after a charge - punish it!
		"charge_range_min": 140.0,     # it only charges when the player is between these distances
		"charge_range_max": 760.0,
		"summon_cooldown": 9.0,
		"summon_windup": 0.8,          # roar time before the pack appears
		"summon_count": 6,             # shamblers it calls up
		"arrive_delay": 3.0,           # seconds into a boss wave before it walks in
		"roar_shake": 0.35, "spawn_shake": 0.5, "charge_shake": 0.3, "wall_slam_shake": 0.55,
	},
}

# Badly hurt zombies look it: wounds, a limp, and a trail of blood.
const WOUNDED_AT := 0.3                 # below this fraction of health a zombie shows its wounds
const WOUNDED_SPEED_MULT := 0.88        # ...walks a little slower
const WOUNDED_LIMP := 2.2               # ...sways this much more as it walks
const WOUNDED_DRIP_RATE := 2.5          # ...and leaves this many blood drops per second
const PLAYER_WOUNDED_AT := 0.3          # the player looks battle-worn below this fraction of health
const PLAYER_DRIP_RATE := 5.0           # blood drops per second while the player is that hurt

const ENEMY_SEPARATION := 0.7           # how firmly zombies push each other apart (0..1)
const ENEMY_CROWD_FREE := 2             # zombies touching more neighbours than this slow down (keeps hordes from squashing into a blob)
const ENEMY_ATTACK_REACH := 5.0         # extra px beyond touching at which they can hit
const ENEMY_TURN_SPEED := 9.0
const ENEMY_FLANK_SPREAD := 70.0        # each zombie aims slightly off-centre so hordes surround you
const RUNNER_ZIGZAG_AMOUNT := 0.55
const RUNNER_ZIGZAG_SPEED := 7.0
const ENEMY_FIRST_ATTACK_DELAY := 0.25  # a zombie that just reached you needs this long before its first hit
const SUMMON_RISE_TIME := 0.5           # summoned zombies take this long to claw out of the ground

# ----------------------------------------------------------------------------
#  MAPS
#  Every map has WAVES_PER_MAP waves. Clearing the last one unlocks the next
#  map, where the zombies are much tougher and the rewards bigger.
#    hp / damage / speed  multiply every zombie's health / hits / walking speed
#    xp                   multiplies the XP from kills and cleared waves
#    coins                what one coin is worth; also multiplies the wave bonuses
#    gear                 multiplies how often zombies drop gear
#    gear_up              chance that a dropped piece is one tier better than normal
#    ground / trees       a colour wash that gives the map its mood (real scenery comes later)
# ----------------------------------------------------------------------------
const WAVES_PER_MAP := 100
const CHECKPOINT_EVERY := 5             # every N cleared waves (= after each boss) a new starting wave is unlocked
const CHECKPOINT_START_CRATE := true    # starting from a checkpoint drops a weapon crate beside you
const MAP_CLEAR_COINS := 300            # bonus for clearing the last wave (times the map's "coins")
const MAP_CLEAR_XP := 3000              # ...and XP (times the map's "xp")
const MAP_CLEAR_CELEBRATION := 3.2      # seconds of slow-motion glory before the results screen
const MAPS := [
	{"name": "FOREST CAMP", "story": "A weekend in the woods. Nobody else came back to the fire.",
		"hp": 1.0, "damage": 1.0, "speed": 1.0, "xp": 1.0, "coins": 1, "gear": 1.0, "gear_up": 0.0,
		"color": Color(0.62, 0.82, 0.38), "ground": Color(0.0, 0.0, 0.0, 0.0), "trees": Color(1.0, 1.0, 1.0)},
	{"name": "DEAD FARM", "story": "The harvest was left to rot. So were the farmhands.",
		"hp": 4.0, "damage": 1.8, "speed": 1.04, "xp": 1.5, "coins": 2, "gear": 1.3, "gear_up": 0.08,
		"color": Color(0.93, 0.76, 0.32), "ground": Color(0.62, 0.47, 0.16, 0.30), "trees": Color(1.0, 0.86, 0.5)},
	{"name": "GRAVEYARD", "story": "The old graves are open. The new ones were never filled.",
		"hp": 12.0, "damage": 3.0, "speed": 1.08, "xp": 2.0, "coins": 4, "gear": 1.7, "gear_up": 0.16,
		"color": Color(0.62, 0.72, 0.9), "ground": Color(0.16, 0.2, 0.34, 0.42), "trees": Color(0.62, 0.7, 0.86)},
	{"name": "CONVOY CRASH", "story": "The evacuation convoy made it nine miles.",
		"hp": 35.0, "damage": 5.0, "speed": 1.12, "xp": 2.75, "coins": 7, "gear": 2.2, "gear_up": 0.25,
		"color": Color(0.95, 0.5, 0.3), "ground": Color(0.1, 0.1, 0.11, 0.5), "trees": Color(0.78, 0.6, 0.5)},
	{"name": "QUARANTINE LAB", "story": "This is where it started. Something down here is still running.",
		"hp": 100.0, "damage": 8.0, "speed": 1.16, "xp": 3.5, "coins": 12, "gear": 3.0, "gear_up": 0.35,
		"color": Color(0.4, 0.95, 0.85), "ground": Color(0.08, 0.3, 0.3, 0.42), "trees": Color(0.5, 0.9, 0.84)},
]

# ----------------------------------------------------------------------------
#  WAVES - the same curve on every map (the map multiplies it, see MAPS).
#  Tuned so that the numbers creep up over 100 waves: a new character gets a
#  few waves in, and every bit of extra strength buys another wave or two.
# ----------------------------------------------------------------------------
const WAVE_BASE_COUNT := 22.0           # zombies in wave 1
const WAVE_COUNT_PER_WAVE := 9.0        # + this many per wave...
const WAVE_COUNT_ACCEL := 0.0           # ...+ this * (wave-1)^2  (0 = steady growth)
const WAVE_MAX_COUNT := 500
const MAX_ENEMIES_ALIVE := 240          # hard cap on screen at once
const WAVE_PACK_SIZE_BASE := 5.0        # zombies arrive in packs from one side
const WAVE_PACK_SIZE_PER_WAVE := 0.6
const WAVE_PACK_SIZE_MAX := 26.0
const WAVE_PACK_INTERVAL_BASE := 1.2    # seconds between packs in wave 1
const WAVE_PACK_INTERVAL_PER_WAVE := -0.035
const WAVE_PACK_INTERVAL_MIN := 0.35
const WAVE_PACK_SIDES_EVERY := 5        # every N waves, packs arrive from one more direction at once...
const WAVE_PACK_SIDES_MAX := 4          # ...up to this many, so later hordes surround you
const WAVE_FIRST_DELAY := 1.6           # breathing room at the very start
const WAVE_INTERMISSION := 3.5          # pause between waves
const WAVE_HP_GROWTH := 0.06            # +6% zombie health per wave (wave 100 = about x7)
const WAVE_DAMAGE_GROWTH := 0.01        # +1% zombie damage per wave (wave 100 = about x2)
const WAVE_SPEED_GROWTH := 0.005        # +0.5% zombie speed per wave
const WAVE_SPEED_MAX_MULT := 1.45
const WAVE_XP_GROWTH := 0.01            # +1% XP per kill per wave (tougher zombies are worth more)
const RUNNER_START_WAVE := 2
const RUNNER_WEIGHT_PER_WAVE := 0.10
const RUNNER_WEIGHT_MAX := 0.45
const BRUTE_START_WAVE := 3
const BRUTE_WEIGHT_PER_WAVE := 0.035
const BRUTE_WEIGHT_MAX := 0.18
const BOSS_EVERY := 5                   # a boss arrives every N waves
const BOSS_WAVE_COUNT_MULT := 0.6       # boss waves have fewer regular zombies
const RUNNER_PACK_CHANCE := 0.14        # chance that a pack is all runners (after runners unlock)
const WAVE_CLEAR_COINS_BASE := 2        # coin bonus for clearing a wave...
const WAVE_CLEAR_COINS_PER_WAVE := 1    # ...plus this per wave number

# ----------------------------------------------------------------------------
#  SCORE / COMBO
# ----------------------------------------------------------------------------
const COMBO_WINDOW := 2.5               # seconds between kills to keep a combo alive
const COMBO_MULT_PER_KILL := 0.04       # each combo kill adds 4% score
const COMBO_MULT_MAX := 3.0

# ----------------------------------------------------------------------------
#  RAGE
# ----------------------------------------------------------------------------
const RAGE_MAX := 100.0
const RAGE_AUTO_ACTIVATE := false       # true = rage starts by itself when full
const RAGE_DURATION := 8.0
const RAGE_DAMAGE_MULT := 3.0
const RAGE_FIRE_RATE_MULT := 1.5
const RAGE_SPEED_MULT := 1.25
const RAGE_KNOCKBACK_MULT := 1.5
const RAGE_DAMAGE_TAKEN_MULT := 0.2
const RAGE_BURST_RADIUS := 240.0        # activating rage blasts zombies away
const RAGE_BURST_FORCE := 760.0
const RAGE_BURST_DAMAGE := 30.0
const RAGE_BURST_STAGGER := 0.5
const RAGE_BURST_SHAKE := 0.8
const RAGE_SHAKE_MULT := 0.5            # all screen shake is scaled by this while rage is active (faster fire = more shake)
const RAGE_BURST_HITSTOP := 0.09

# ----------------------------------------------------------------------------
#  PICKUPS
# ----------------------------------------------------------------------------
const COIN_VALUE := 1
const COIN_MAGNET_RADIUS := 130.0
const COIN_MAGNET_SPEED := 620.0
const COIN_PICKUP_RADIUS := 22.0
const COIN_LIFETIME := 22.0
const COIN_SCATTER_SPEED := 190.0
const MAX_COINS_ON_FIELD := 220

const CRATE_FIRST_DELAY := 7.0          # first crate appears quickly to teach the idea
const CRATE_INTERVAL_MIN := 13.0
const CRATE_INTERVAL_MAX := 19.0
const CRATE_MAX_ON_FIELD := 2
const CRATE_LIFETIME := 26.0
const CRATE_PICKUP_RADIUS := 34.0
const CRATE_SIZE := 54.0                # how big the crate is drawn
const CRATE_ICON_WIDTH := 104.0         # width of the weapon picture on it (big, so it can be read at a glance)
# Crates are wood: your own bullets, flames and blasts break them, and what
# was inside is lost. A hit takes the weapon's plain damage (your upgrades do
# not make crates more fragile). Set CRATE_HP to 0 for crates that cannot break.
const CRATE_HP := 150.0
const CRATE_BLAST_MULT := 2.0           # explosions are this much harder on crates than bullets
const CRATE_HIT_RADIUS := 24.0          # how big a target a crate is for bullets
const CRATE_FLASH_TIME := 0.08          # it flashes white this long when hit
const CRATE_BREAK_SHAKE := 0.25
const CRATE_MIN_DIST_FROM_PLAYER := 260.0
const CRATE_MAX_DIST_FROM_PLAYER := 700.0

const MEDKIT_HEAL := 25.0
const MEDKIT_MAX_ON_FIELD := 2
const MEDKIT_LIFETIME := 25.0
const MEDKIT_PICKUP_RADIUS := 26.0

# ----------------------------------------------------------------------------
#  PROGRESSION - everything here is permanent and saved between sessions.
#
#  Three ways the character gets stronger, all feeding the same stats
#  (see scripts/game/player_stats.gd):
#    1. CHARACTER LEVEL  XP from kills. Each level raises base health and
#                        damage a little and gives a skill point. Capped at
#                        LEVEL_CAP; reaching it is meant to take months.
#    2. SKILL POINTS     Spent on the passive stats below. Extra points can be
#                        bought with coins, at a price that keeps rising.
#    3. WEAPON LEVELS    Each weapon earns its own XP from kills made with it.
#                        Each weapon level gives a point for that weapon only.
#  Nothing has a hard ceiling: you can always get a bit stronger.
# ----------------------------------------------------------------------------
const LEVEL_CAP := 100                  # the character cannot go past this level
const LEVEL_XP_BASE := 80.0             # XP needed to go from level 1 to 2...
const LEVEL_XP_EXPONENT := 2.0          # ...and how steeply that grows (needed = base * level ^ exponent).
                                        # With 80 and 2.0, level 100 takes about 26 million XP in total:
                                        # the early levels come quickly, the last ones take many hours each.
const LEVEL_HP_PER_LEVEL := 3.0         # automatic max health per character level
const LEVEL_DAMAGE_PER_LEVEL := 0.01    # automatic damage per character level (0.01 = +1%)
const LEVEL_UP_HEAL := 0.25             # levelling up mid-run heals this fraction of max health
const SKILL_POINTS_PER_LEVEL := 1
const WAVE_CLEAR_XP_BASE := 10          # XP for clearing a wave...
const WAVE_CLEAR_XP_PER_WAVE := 5       # ...plus this per wave number

const SKILL_POINT_COST_BASE := 120.0    # coins for the first bought skill point...
const SKILL_POINT_COST_GROWTH := 1.15   # ...each further one costs 15% more
const RESPEC_COST_PER_LEVEL := 25       # coins to take all points back = this * character level

# Passive stats. Their ranks come from the skill tree below and from gear.
#   "linear": each rank adds per_rank, forever.
#   "curve":  approaches "max" but never reaches it; "half" is the rank at which
#             you have half of max. (Stops speed/dodge from becoming silly.)
#   "color"   the colour of the stat's family in the skill tree
#   "nodes"   names of the three nodes along its branch, from the middle outwards
#   "min_level" (optional) its branch needs at least this character level
# The last one, BOND, is the pet's stat: see PETS further down.
const PASSIVE_ORDER := ["vitality", "defense", "evasion", "strength", "dexterity", "critical", "agility", "luck", "bond"]
const PASSIVES := {
	"vitality": {"name": "VITALITY", "desc": "More maximum health", "kind": "linear", "per_rank": 8.0,
		"color": Color("5aa9ff"), "nodes": ["Thick Blood", "Iron Lungs", "Ox Heart"]},
	"defense": {"name": "DEFENSE", "desc": "Take less damage from every hit", "kind": "curve", "max": 0.8, "half": 50.0,
		"color": Color("5aa9ff"), "nodes": ["Tough Hide", "Scar Tissue", "Walking Bunker"]},
	"evasion": {"name": "EVASION", "desc": "Chance to dodge a hit completely", "kind": "curve", "max": 0.6, "half": 40.0,
		"color": Color("5aa9ff"), "nodes": ["Sidestep", "Slippery", "Phantom"]},
	"strength": {"name": "STRENGTH", "desc": "More damage with every weapon", "kind": "linear", "per_rank": 0.03,
		"color": Color("ff6b3d"), "nodes": ["Heavy Hands", "Bone Breaker", "Juggernaut"]},
	"dexterity": {"name": "DEXTERITY", "desc": "Shoot, swing and reload faster", "kind": "curve", "max": 1.5, "half": 60.0,
		"color": Color("ff6b3d"), "nodes": ["Loose Wrists", "Trigger Finger", "Lead Storm"]},
	"critical": {"name": "CRITICAL", "desc": "Chance for a shot to deal double damage", "kind": "curve", "max": 0.6, "half": 40.0,
		"color": Color("ff6b3d"), "nodes": ["Sharp Eye", "Weak Spots", "Surgeon"]},
	"agility": {"name": "AGILITY", "desc": "Move faster", "kind": "curve", "max": 0.8, "half": 40.0,
		"color": Color("b6e04a"), "nodes": ["Light Feet", "Sprinter", "Blur"]},
	"luck": {"name": "LUCK", "desc": "Zombies drop coins and gear more often", "kind": "linear", "per_rank": 0.03,
		"color": Color("b6e04a"), "nodes": ["Loose Change", "Grave Robber", "Jackpot"]},
	# BOND: every rank brings your pet's damage bonus closer to the most its rarity
	# allows (PET_BOND_FULL ranks = all of it) and makes its own bite stronger.
	# Its three nodes and its sealed node also teach the pet a trick (PET_TRICKS).
	"bond": {"name": "BOND", "desc": "Your pet adds more to your damage and bites harder", "kind": "linear", "per_rank": 1.0,
		"color": Color("b6e04a"), "nodes": ["Fetch", "Maul", "Guardian"], "sealed_name": "Frenzy", "min_level": 18},
}

# ----------------------------------------------------------------------------
#  SKILL TREE (Skills screen) - built from these numbers by scripts/game/skill_tree.gd.
#  Three families grow out of the survivor in the middle, each in its own colour:
#    GRIT      staying alive    (vitality, defense, evasion)
#    FURY      killing faster   (strength, dexterity, critical)
#    INSTINCT  speed, luck, pet (agility, luck, bond)
#  A family starts with one node that raises all three of its stats. From it
#  three branches fan out, one per stat: three nodes, a sealed node on the side
#  (opens after a deed) and a keystone (a special power) at the end. Every
#  node has several levels. At the far end sits the family's emblem, an
#  endless node. A node opens when the one before it has TREE_NEED_LEVELS levels.
# ----------------------------------------------------------------------------
const TREE_FAMILY_ORDER := ["grit", "fury", "instinct"]
const TREE_FAMILIES := {
	"grit": {"name": "GRIT", "desc": "Staying alive", "color": Color("5aa9ff"), "angle_deg": -90.0,
		"stats": ["vitality", "defense", "evasion"]},
	"fury": {"name": "FURY", "desc": "Killing faster", "color": Color("ff6b3d"), "angle_deg": 30.0,
		"stats": ["strength", "dexterity", "critical"]},
	"instinct": {"name": "INSTINCT", "desc": "Speed, luck and your pet", "color": Color("b6e04a"), "angle_deg": 150.0,
		"stats": ["agility", "luck", "bond"]},
}
const TREE_ROOT_LEVELS := 3             # levels of a family's first node (each level: +1 rank of all three of its stats)
const TREE_ROOT_COST := 1               # skill points per level of it
const TREE_NODE_LEVELS := 5             # levels of every node along a stat's branch (each level: +1 rank of that stat)
const TREE_BRANCH := [                  # the three nodes of a branch, from the middle outwards:
	{"level": 1, "cost": 1},            #   level = character level needed, cost = skill points per level of the node
	{"level": 8, "cost": 2},
	{"level": 18, "cost": 3},
]
const TREE_NEED_LEVELS := 3             # levels a node needs before the next one along its branch opens
const TREE_SEALED_RANKS := 3            # ranks from a sealed node (one level, opens after its deed)
const TREE_SEALED_COST := 4
const TREE_KEYSTONE_COST := 8           # a keystone needs the last node of its branch at full level
const TREE_CAP_LEVEL := 22              # the family emblem: needs this character level and one keystone of the family
const TREE_CAP_COST := 5                # skill points for its first level (+1 rank of all three stats, endless)...
const TREE_CAP_COST_STEP := 3           # ...and one more point every N levels
# Layout (pixels in tree space, the survivor is at 0,0).
const TREE_ROOT_DIST := 92.0            # distance of a family's first node from the middle
const TREE_STEP := 78.0                 # distance between the nodes of a branch
const TREE_FAN_DEG := 40.0              # angle between the three branches of a family
const TREE_SEAL_OFFSET := 56.0          # how far a sealed node sits beside its branch
const TREE_KEY_DIST := 74.0             # distance from a branch's last node to its keystone
const TREE_CAP_DIST := 100.0            # distance from the middle branch's keystone to the family emblem
# Sealed nodes stay locked until a deed is done (checked against the saved
# records). Kinds: "wave" = clear that wave on any map, "kills" = zombies killed
# in total, "weapon_level" = reach that level with any weapon, "runs" = runs
# played, "score" = points in one run, "bought" = skill points bought with
# coins, "map" = clear all waves of that map, "level" = character level,
# "pets" = how many pets you own.
const TREE_SEAL_DEEDS := {
	"vitality": {"kind": "wave", "value": 10}, "defense": {"kind": "kills", "value": 2000}, "evasion": {"kind": "runs", "value": 15},
	"strength": {"kind": "kills", "value": 5000}, "dexterity": {"kind": "weapon_level", "value": 8}, "critical": {"kind": "score", "value": 40000},
	"agility": {"kind": "wave", "value": 15}, "luck": {"kind": "bought", "value": 5}, "bond": {"kind": "pets", "value": 2},
}
# Keystones: one special power at the end of each stat's branch. "value" (and the
# extra numbers) are what the power does; "desc" is filled in with them.
const KEYSTONES := {
	"vitality": {"name": "SECOND WIND", "value": 0.3, "deed": {"kind": "wave", "value": 20},
		"desc": "Once per run, a killing blow leaves you at %d%% health instead and throws the horde back."},
	"strength": {"name": "EXECUTIONER", "value": 0.4, "deed": {"kind": "kills", "value": 10000},
		"desc": "+%d%% damage against wounded zombies."},
	"dexterity": {"name": "ADRENALINE", "value": 0.2, "combo": 20, "deed": {"kind": "weapon_level", "value": 15},
		"desc": "You shoot %d%% faster while your kill combo is %d or more."},
	"agility": {"name": "BREAKAWAY", "value": 0.4, "time": 2.0, "deed": {"kind": "runs", "value": 40},
		"desc": "After being hit you move %d%% faster for %d seconds."},
	"defense": {"name": "THICK SKIN", "value": 2.0, "deed": {"kind": "wave", "value": 30},
		"desc": "The moment of safety after being hit lasts %d times as long."},
	"evasion": {"name": "GHOST", "value": 1.0, "deed": {"kind": "score", "value": 150000},
		"desc": "A dodge leaves you untouchable for %d second."},
	"critical": {"name": "DEADEYE", "value": 3.0, "deed": {"kind": "wave", "value": 40},
		"desc": "Critical hits deal %d times the damage instead of double."},
	"luck": {"name": "SCAVENGER", "value": 2.0, "crates": 0.25, "deed": {"kind": "bought", "value": 20},
		"desc": "Coins fly to you from %d times as far, and weapon crates appear %d%% more often."},
	"bond": {"name": "FERAL", "value": 3.0, "deed": {"kind": "pets", "value": 3},
		"desc": "While you rage, your pet attacks %d times as fast."},
}
const CRIT_DAMAGE_MULT := 2.0
const CRIT_KNOCKBACK_MULT := 1.4
const DODGE_INVULN := 0.25              # seconds of safety after a dodge
const SECOND_WIND_INVULN := 1.5         # seconds of safety when the SECOND WIND keystone saves you

# Weapon levels.
const WEAPON_XP_BASE := 60.0            # weapon XP needed for its level 2 (needed = base * level ^ exponent)
const WEAPON_XP_EXPONENT := 1.4
const WEAPON_POINTS_PER_LEVEL := 1
# What a weapon's points can be spent on. "needs" says which weapons have the track:
#   ""        every weapon
#   "ranged"  not melee weapons (they have no spread or recoil)
#   "burst"   weapons that fire more than one shot per magazine (not the launcher,
#             whose rate of fire is its reload)
#   "mag"     weapons that reload
#   "crate"   weapons that come from crates (not the single pistol)
const WEAPON_TRACK_ORDER := ["power", "speed", "stability", "reload", "spawn", "duration"]
const WEAPON_TRACKS := {
	"power": {"name": "POWER", "desc": "More damage", "kind": "linear", "per_rank": 0.05, "needs": "", "color": Color("f0643c")},
	"speed": {"name": "SHOOTING SPEED", "desc": "Faster rate of fire", "kind": "curve", "max": 1.0, "half": 30.0, "needs": "burst", "color": Color("f6d44a")},
	"stability": {"name": "STABILITY", "desc": "Tighter spread, less recoil", "kind": "curve", "max": 0.75, "half": 15.0, "needs": "ranged", "color": Color("6aa7e8")},
	"reload": {"name": "RELOAD SPEED", "desc": "Shorter reload", "kind": "curve", "max": 1.2, "half": 20.0, "needs": "mag", "color": Color("7ed957")},
	"spawn": {"name": "SPAWN RATE", "desc": "Its crate appears more often", "kind": "linear", "per_rank": 0.12, "needs": "crate", "color": Color("c084fc")},
	"duration": {"name": "DURATION", "desc": "Lasts longer when picked up", "kind": "curve", "max": 1.5, "half": 30.0, "needs": "crate", "color": Color("4fd8c9")},
}

# ----------------------------------------------------------------------------
#  WEAPON UPGRADES (Armory). Every weapon has its own level (from kills made
#  with it) and gets one weapon point per level. Points buy ranks of the
#  upgrades above (WEAPON_TRACKS) - as many as you like, at a rising price -
#  and three perks that open at certain weapon levels.
# ----------------------------------------------------------------------------
const WEAPON_RANK_COST_STEP := 5        # every N ranks of an upgrade, the next ranks cost one more weapon point
const WEAPON_RESPEC_COST_PER_LEVEL := 10   # coins to take a weapon's points back = this * its level
# Perks: three per weapon. Each needs a weapon level and costs weapon points.
# "mods" changes the weapon's own numbers: ["add", n] adds, ["mul", x]
# multiplies. Keep each "desc" in step with its "mods".
const WEAPON_PERK_LEVELS := [5, 12, 20]
const WEAPON_PERK_COST := [2, 4, 6]
const WEAPON_PERKS := {
	"pistol": [
		{"name": "HOLLOW POINTS", "desc": "Hits shove and stun zombies 50% more.", "mods": {"knockback": ["mul", 1.5], "stagger": ["mul", 1.5]}},
		{"name": "EXTENDED MAGAZINE", "desc": "The magazine holds 50% more rounds.", "mods": {"mag": ["mul", 1.5]}},
		{"name": "FULL METAL JACKET", "desc": "Bullets go through one more zombie.", "mods": {"pierce": ["add", 1]}},
	],
	"smg": [
		{"name": "DRUM MAGAZINE", "desc": "The magazine holds 50% more rounds.", "mods": {"mag": ["mul", 1.5]}},
		{"name": "LIGHT FRAME", "desc": "You move 10% faster while holding it.", "mods": {"move_mult": ["mul", 1.1]}},
		{"name": "ARMOR PIERCING", "desc": "Bullets go through one more zombie.", "mods": {"pierce": ["add", 1]}},
	],
	"shotgun": [
		{"name": "HEAVY LOAD", "desc": "Every shot fires 3 more pellets.", "mods": {"pellets": ["add", 3]}},
		{"name": "LONG TUBE", "desc": "Holds 50% more shells.", "mods": {"mag": ["mul", 1.5]}},
		{"name": "DOOR KICKER", "desc": "Pellets throw zombies back 60% harder.", "mods": {"knockback": ["mul", 1.6]}},
	],
	"machinegun": [
		{"name": "BELT FEED", "desc": "The magazine holds 50% more rounds.", "mods": {"mag": ["mul", 1.5]}},
		{"name": "SUPPRESSION", "desc": "Hits stop zombies in their tracks for twice as long.", "mods": {"stagger": ["mul", 2.0]}},
		{"name": "HEAVY ROUNDS", "desc": "Bullets go through one more zombie.", "mods": {"pierce": ["add", 1]}},
	],
	"rifle": [
		{"name": "STOPPING POWER", "desc": "Hits throw zombies back 60% harder.", "mods": {"knockback": ["mul", 1.6]}},
		{"name": "BIG MAGAZINE", "desc": "The magazine holds 50% more rounds.", "mods": {"mag": ["mul", 1.5]}},
		{"name": "TUNGSTEN CORE", "desc": "Bullets go through 3 more zombies.", "mods": {"pierce": ["add", 3]}},
	],
	"sledge": [
		{"name": "WIDE SWING", "desc": "The swing covers a 30% wider arc.", "mods": {"arc_deg": ["mul", 1.3]}},
		{"name": "LONG HANDLE", "desc": "Reaches 25% further.", "mods": {"range": ["mul", 1.25]}},
		{"name": "EARTHSHAKER", "desc": "Hits throw and stun zombies 50% more.", "mods": {"knockback": ["mul", 1.5], "stagger": ["mul", 1.5]}},
	],
	"launcher": [
		{"name": "BIG PAYLOAD", "desc": "The blast is 25% wider.", "mods": {"blast_radius": ["mul", 1.25]}},
		{"name": "CONCUSSION", "desc": "The blast throws and stuns zombies 50% more.", "mods": {"blast_knockback": ["mul", 1.5], "blast_stagger": ["mul", 1.5]}},
		{"name": "DOUBLE LOAD", "desc": "Holds two grenades instead of one.", "mods": {"mag": ["add", 1]}},
	],
	"flamethrower": [
		{"name": "BIGGER TANK", "desc": "The tank holds 50% more fuel.", "mods": {"mag": ["mul", 1.5]}},
		{"name": "STICKY FUEL", "desc": "Zombies burn for 50% longer.", "mods": {"burn_time": ["mul", 1.5]}},
		{"name": "WHITE HEAT", "desc": "Burning does 50% more damage.", "mods": {"burn_dps": ["mul", 1.5]}},
	],
	"chainsaw": [
		{"name": "LONG BAR", "desc": "Reaches 25% further.", "mods": {"range": ["mul", 1.25]}},
		{"name": "WIDE BITE", "desc": "Cuts a 40% wider arc in front of you.", "mods": {"arc_deg": ["mul", 1.4]}},
		{"name": "LIGHT ENGINE", "desc": "You move 12% faster while holding it.", "mods": {"move_mult": ["mul", 1.12]}},
	],
}

# ----------------------------------------------------------------------------
#  GEAR - what the survivor wears. Kept forever.
#  Pieces drop rarely from zombies; rings and amulets drop only from bosses,
#  and some pieces are only found from a certain map onwards. Nine slots:
#  helmet, amulet, chest, gloves, two rings, belt, pants, boots.
#  Two identical pieces of the same tier can be forged into one piece of the
#  next tier (the forge on the Character screen). Gear adds ranks to the passive stats, on top
#  of the skill tree (scripts/game/player_stats.gd).
# ----------------------------------------------------------------------------
const GEAR_SLOTS := ["helmet", "amulet", "chest", "gloves", "ring1", "ring2", "belt", "pants", "boots"]
# What kind of piece each slot takes, and all the kinds there are.
const GEAR_SLOT_TYPE := {"helmet": "helmet", "amulet": "amulet", "chest": "chest", "gloves": "gloves",
	"ring1": "ring", "ring2": "ring", "belt": "belt", "pants": "pants", "boots": "boots"}
const GEAR_TYPE_ORDER := ["helmet", "chest", "gloves", "pants", "boots", "belt", "amulet", "ring"]
const GEAR_TYPE_NAMES := {"helmet": "HELMET", "amulet": "AMULET", "ring": "RING", "belt": "BELT", "boots": "BOOTS",
	"pants": "PANTS", "gloves": "GLOVES", "chest": "CHEST"}

# The five tiers (five colours).
#   mult    a piece's stat ranks are multiplied by this
#   chance  how likely forging two pieces of the tier below into this tier succeeds
#           (set by the owner: 100% / 90% / 40% / 10%)
#   break   if the forging fails one of the two pieces is always used up; this
#           is the chance that the other one is destroyed as well
const GEAR_TIERS := [
	{"name": "COMMON", "color": Color("c9c9c0"), "mult": 1.0, "chance": 1.0, "break": 0.0},
	{"name": "STURDY", "color": Color("5fd068"), "mult": 2.0, "chance": 1.0, "break": 0.0},
	{"name": "FINE", "color": Color("4f9dff"), "mult": 3.0, "chance": 0.9, "break": 0.0},
	{"name": "SUPERIOR", "color": Color("b565f5"), "mult": 5.0, "chance": 0.4, "break": 0.35},
	{"name": "LEGENDARY", "color": Color("ff9a2e"), "mult": 8.0, "chance": 0.1, "break": 0.5},
]

# Every piece of gear.
#   type   which slot it goes in
#   stats  passive stat ranks it gives at the first tier (times the tier's "mult")
#   from   who drops it: "zombies" (anything), "brutes" (brutes and bosses) or "bosses" (bosses only)
#   map    the first map it can be found on (1 = everywhere)
#   look   how it looks on the hero, in the menus and in the game: a "style"
#          (which shape scripts/autoload/art.gd draws) and two colours
const GEAR_ORDER := [
	"hard_hat", "gas_mask", "hunting_cap", "riot_helmet",
	"dog_tags", "tooth_necklace", "old_medal", "gorger_fang",
	"iron_band", "lucky_ring", "snake_ring", "blood_ring",
	"tool_belt", "ammo_belt", "money_belt", "champion_belt",
	"running_shoes", "steel_toecaps", "soft_soles", "combat_boots",
	"cargo_pants", "track_pants", "padded_trousers", "hunter_leggings",
	"work_gloves", "shooting_gloves", "knuckle_wraps", "butcher_gloves",
	"leather_jacket", "padded_vest", "bandolier", "riot_armor",
]
const GEAR_ITEMS := {
	"hard_hat": {"name": "Hard Hat", "type": "helmet", "stats": {"defense": 2}, "from": "zombies", "map": 1, "look": {"style": "hardhat", "color": "#e2b83a", "trim": "#8a6a12"}},
	"gas_mask": {"name": "Gas Mask", "type": "helmet", "stats": {"vitality": 2}, "from": "zombies", "map": 1, "look": {"style": "mask", "color": "#5b6166", "trim": "#2c3033"}},
	"hunting_cap": {"name": "Hunting Cap", "type": "helmet", "stats": {"critical": 2}, "from": "brutes", "map": 1, "look": {"style": "cap", "color": "#8a5a36", "trim": "#5a3a1e"}},
	"riot_helmet": {"name": "Riot Helmet", "type": "helmet", "stats": {"defense": 2, "vitality": 1}, "from": "zombies", "map": 2, "look": {"style": "visor", "color": "#2f3f5c", "trim": "#8fb7d9"}},

	"dog_tags": {"name": "Dog Tags", "type": "amulet", "stats": {"vitality": 3}, "from": "bosses", "map": 1, "look": {"style": "tags", "color": "#c9ced3", "trim": "#8a8f94"}},
	"tooth_necklace": {"name": "Tooth Necklace", "type": "amulet", "stats": {"critical": 3}, "from": "bosses", "map": 1, "look": {"style": "tooth", "color": "#efe6cf", "trim": "#8a7f66"}},
	"old_medal": {"name": "Old Medal", "type": "amulet", "stats": {"defense": 3}, "from": "bosses", "map": 1, "look": {"style": "medal", "color": "#d4a437", "trim": "#8a2f2f"}},
	"gorger_fang": {"name": "Gorger's Fang", "type": "amulet", "stats": {"strength": 2, "vitality": 2}, "from": "bosses", "map": 2, "look": {"style": "tooth", "color": "#c8322b", "trim": "#5a1210"}},

	"iron_band": {"name": "Iron Band", "type": "ring", "stats": {"strength": 3}, "from": "bosses", "map": 1, "look": {"style": "ring", "color": "#9aa0a6", "trim": "#5c6166"}},
	"lucky_ring": {"name": "Lucky Ring", "type": "ring", "stats": {"luck": 3}, "from": "bosses", "map": 1, "look": {"style": "ring", "color": "#5fd068", "trim": "#2f7a36"}},
	"snake_ring": {"name": "Snake Ring", "type": "ring", "stats": {"evasion": 3}, "from": "bosses", "map": 1, "look": {"style": "ring", "color": "#4fd8c9", "trim": "#237a70"}},
	"blood_ring": {"name": "Blood Ring", "type": "ring", "stats": {"critical": 2, "strength": 2}, "from": "bosses", "map": 2, "look": {"style": "ring", "color": "#c8322b", "trim": "#6b1512"}},

	"tool_belt": {"name": "Tool Belt", "type": "belt", "stats": {"strength": 2}, "from": "zombies", "map": 1, "look": {"style": "belt", "color": "#8a5a36", "trim": "#c9a15a"}},
	"ammo_belt": {"name": "Ammo Belt", "type": "belt", "stats": {"dexterity": 2}, "from": "zombies", "map": 1, "look": {"style": "belt", "color": "#4a5a2a", "trim": "#d4a437"}},
	"money_belt": {"name": "Money Belt", "type": "belt", "stats": {"luck": 2}, "from": "brutes", "map": 1, "look": {"style": "belt", "color": "#b58a2a", "trim": "#f3d27a"}},
	"champion_belt": {"name": "Champion's Belt", "type": "belt", "stats": {"vitality": 2, "strength": 1}, "from": "zombies", "map": 2, "look": {"style": "belt", "color": "#b9342b", "trim": "#f3d27a"}},

	"running_shoes": {"name": "Running Shoes", "type": "boots", "stats": {"agility": 2}, "from": "zombies", "map": 1, "look": {"style": "shoes", "color": "#d94a3a", "trim": "#f2efe6"}},
	"steel_toecaps": {"name": "Steel Toecaps", "type": "boots", "stats": {"vitality": 2}, "from": "zombies", "map": 1, "look": {"style": "boots", "color": "#3a3d42", "trim": "#b0b6bc"}},
	"soft_soles": {"name": "Soft Soles", "type": "boots", "stats": {"evasion": 2}, "from": "brutes", "map": 1, "look": {"style": "shoes", "color": "#6b5a4a", "trim": "#cdbb9c"}},
	"combat_boots": {"name": "Combat Boots", "type": "boots", "stats": {"agility": 2, "defense": 1}, "from": "zombies", "map": 2, "look": {"style": "boots", "color": "#23262a", "trim": "#55595f"}},

	"cargo_pants": {"name": "Cargo Pants", "type": "pants", "stats": {"luck": 2}, "from": "zombies", "map": 1, "look": {"style": "pants", "color": "#6b6a45", "trim": "#4a4a30"}},
	"track_pants": {"name": "Track Pants", "type": "pants", "stats": {"agility": 2}, "from": "zombies", "map": 1, "look": {"style": "pants", "color": "#2a3f7a", "trim": "#f2efe6"}},
	"padded_trousers": {"name": "Padded Trousers", "type": "pants", "stats": {"defense": 2}, "from": "brutes", "map": 1, "look": {"style": "pants", "color": "#4a4038", "trim": "#2c2622"}},
	"hunter_leggings": {"name": "Hunter's Leggings", "type": "pants", "stats": {"agility": 2, "evasion": 1}, "from": "zombies", "map": 2, "look": {"style": "pants", "color": "#3f5a35", "trim": "#2a3d24"}},

	"work_gloves": {"name": "Work Gloves", "type": "gloves", "stats": {"strength": 2}, "from": "zombies", "map": 1, "look": {"style": "gloves", "color": "#c9a15a", "trim": "#8a6a36"}},
	"shooting_gloves": {"name": "Shooting Gloves", "type": "gloves", "stats": {"dexterity": 2}, "from": "zombies", "map": 1, "look": {"style": "gloves", "color": "#2a2c30", "trim": "#55595f"}},
	"knuckle_wraps": {"name": "Knuckle Wraps", "type": "gloves", "stats": {"critical": 2}, "from": "brutes", "map": 1, "look": {"style": "wraps", "color": "#e9e2d0", "trim": "#b7ae96"}},
	"butcher_gloves": {"name": "Butcher's Gloves", "type": "gloves", "stats": {"strength": 2, "critical": 1}, "from": "zombies", "map": 2, "look": {"style": "gloves", "color": "#7a1f1f", "trim": "#451010"}},

	"leather_jacket": {"name": "Leather Jacket", "type": "chest", "stats": {"vitality": 2}, "from": "zombies", "map": 1, "look": {"style": "jacket", "color": "#6b4226", "trim": "#3f2716"}},
	"padded_vest": {"name": "Padded Vest", "type": "chest", "stats": {"defense": 2}, "from": "zombies", "map": 1, "look": {"style": "vest", "color": "#5a6a3a", "trim": "#3a4526"}},
	"bandolier": {"name": "Bandolier", "type": "chest", "stats": {"dexterity": 2}, "from": "brutes", "map": 1, "look": {"style": "bandolier", "color": "#7a5a36", "trim": "#d4a437"}},
	"riot_armor": {"name": "Riot Armor", "type": "chest", "stats": {"defense": 2, "vitality": 1}, "from": "zombies", "map": 2, "look": {"style": "armor", "color": "#2f3f5c", "trim": "#8fb7d9"}},
}

# Drops. Chance per kill that the zombie leaves a piece of gear (before the
# map's "gear" multiplier and the LUCK stat). Deliberately rare.
const GEAR_DROP_CHANCE := {SHAMBLER: 0.004, RUNNER: 0.005, BRUTE: 0.04, BOSS: 1.0}
const GEAR_BOSS_EXTRA_CHANCE := 0.4     # a boss always drops a ring or an amulet; this is the chance of a second, ordinary piece
const GEAR_LUCK_FACTOR := 0.5           # how much of the LUCK coin bonus also applies to gear drops
const GEAR_MAX_ON_FIELD := 4
const GEAR_LIFETIME := 45.0             # seconds a dropped piece waits to be picked up
const GEAR_PICKUP_RADIUS := 30.0
const GEAR_PICKUP_SHAKE := 0.2
# What the slots are called on the Character screen.
const GEAR_SLOT_NAMES := {"helmet": "HELMET", "amulet": "AMULET", "chest": "CHEST", "gloves": "GLOVES", "ring1": "LEFT RING",
	"ring2": "RIGHT RING", "belt": "BELT", "pants": "PANTS", "boots": "BOOTS"}

# ----------------------------------------------------------------------------
#  PETS - companions. The feature opens at character level PET_UNLOCK_LEVEL,
#  when the first pet joins by itself; the others have to be earned and then
#  bought with coins (the Pet screen). One pet comes along at a time.
#  A pet does two things:
#    1. It adds to YOUR damage - at most its rarity's "damage" (legendary 15%,
#       lower rarities less). How much of that you get depends on BOND, the
#       pet's branch of the skill tree: PET_BOND_BASE of it with no BOND, all
#       of it at PET_BOND_FULL ranks.
#    2. It fights: it bites zombies that come close to you. Its bite is
#       stronger for rarer pets ("bite") and grows with BOND without limit.
#       Its tricks are the four big nodes of the BOND branch.
#  Zombies ignore pets: a pet cannot be hurt.
# ----------------------------------------------------------------------------
const PET_UNLOCK_LEVEL := 18
const PET_RARITY_ORDER := ["common", "uncommon", "rare", "epic", "legendary"]
const PET_RARITIES := {
	"common": {"name": "COMMON", "color": Color("c9c9c0"), "damage": 0.03, "bite": 1.0},
	"uncommon": {"name": "UNCOMMON", "color": Color("5fd068"), "damage": 0.06, "bite": 1.3},
	"rare": {"name": "RARE", "color": Color("4f9dff"), "damage": 0.09, "bite": 1.6},
	"epic": {"name": "EPIC", "color": Color("b565f5"), "damage": 0.12, "bite": 2.0},
	"legendary": {"name": "LEGENDARY", "color": Color("ff9a2e"), "damage": 0.15, "bite": 2.5},
}
const PET_BOND_BASE := 0.3              # share of its damage bonus a pet gives with no BOND at all
const PET_BOND_FULL := 30               # BOND ranks at which it gives all of it
const PET_BITE_PER_BOND := 0.05         # each BOND rank makes the pet's own bite 5% stronger (no limit)
const PET_BITE_DAMAGE := 10.0           # one bite of a common pet with no BOND (times your own damage bonuses)
const PET_BITE_INTERVAL := 0.5          # seconds between bites
const PET_BITE_KNOCKBACK := 120.0
const PET_BITE_STAGGER := 0.2
const PET_RADIUS := 11.0
const PET_HEEL_BEHIND := 44.0           # where it walks: this far behind you...
const PET_HEEL_SIDE := 30.0             # ...and this far to the side
const PET_GUARD_RANGE := 250.0          # it attacks zombies that come this close to YOU
const PET_LEASH := 400.0                # ...and gives up a chase this far from you

# The pets.
#   needs / price   what must be done before it can be bought, and what it costs
#                   (a pet that costs nothing joins by itself once its "needs" are met)
#   speed, bite_interval, knockback, size   how this one moves and fights
#   ignite          its bites set zombies on fire
#   note            one line about it for the Pet screen
#   look            colours and shape of its placeholder picture (scripts/autoload/art.gd)
const PET_ORDER := ["scraps", "soot", "brutus", "ash", "cinder"]
const PETS := {
	"scraps": {"name": "SCRAPS", "title": "the stray dog", "rarity": "common", "price": 0, "needs": {"kind": "level", "value": 18},
		"speed": 430.0, "bite_interval": 1.0, "knockback": 1.0, "size": 1.0, "ignite": false,
		"note": "Loyal and steady. Good at everything.",
		"look": {"body": "#a8703c", "head": "#b9814a", "patch": "#e9dcc3", "ear": "#5a3a1e", "collar": "#c8322b", "eye": "#111111",
			"tail": "curl", "ears": "flop", "girth": 1.0, "ember": false}},
	"soot": {"name": "SOOT", "title": "the alley cat", "rarity": "uncommon", "price": 1500, "needs": {"kind": "level", "value": 25},
		"speed": 480.0, "bite_interval": 0.75, "knockback": 0.6, "size": 0.82, "ignite": false,
		"note": "Quick. Attacks more often.",
		"look": {"body": "#2b2b30", "head": "#35353b", "patch": "", "ear": "#17171a", "collar": "#e2b23a", "eye": "#b7f04a",
			"tail": "long", "ears": "point", "girth": 0.85, "ember": false}},
	"brutus": {"name": "BRUTUS", "title": "the bulldog", "rarity": "rare", "price": 6000, "needs": {"kind": "level", "value": 35},
		"speed": 390.0, "bite_interval": 1.15, "knockback": 1.9, "size": 1.15, "ignite": false,
		"note": "Slow, but throws zombies back.",
		"look": {"body": "#d9c9ae", "head": "#e6d8bf", "patch": "#8a5a36", "ear": "#8a5a36", "collar": "#34343a", "eye": "#111111",
			"tail": "stub", "ears": "flop", "girth": 1.28, "ember": false}},
	"ash": {"name": "ASH", "title": "the wolf", "rarity": "epic", "price": 20000, "needs": {"kind": "map", "value": 1},
		"speed": 470.0, "bite_interval": 0.9, "knockback": 1.2, "size": 1.22, "ignite": false,
		"note": "Fast and strong.",
		"look": {"body": "#7d8590", "head": "#8d959f", "patch": "#d7dbe0", "ear": "#4b5159", "collar": "", "eye": "#f2c94c",
			"tail": "bushy", "ears": "point", "girth": 1.05, "ember": false}},
	"cinder": {"name": "CINDER", "title": "the hellhound", "rarity": "legendary", "price": 60000, "needs": {"kind": "map", "value": 2},
		"speed": 480.0, "bite_interval": 0.8, "knockback": 1.5, "size": 1.3, "ignite": true,
		"note": "Its bites set zombies on fire.",
		"look": {"body": "#2a1516", "head": "#3a1b1b", "patch": "", "ear": "#150a0a", "collar": "", "eye": "#ff8a1f",
			"tail": "bushy", "ears": "point", "girth": 1.1, "ember": true}},
}
const PET_IGNITE_TIME := 2.0            # a pet with "ignite": its bites set zombies burning this long...
const PET_IGNITE_DPS_MULT := 0.6        # ...for this much of the bite's damage per second

# Tricks: taught by the first level of BOND's three nodes (in this order),
# and the fourth by BOND's sealed node.
const PET_TRICKS := [
	{"id": "fetch", "desc": "Your pet picks up the coins it runs past and runs to fetch dropped gear."},
	{"id": "maul", "desc": "Every few bites is a mauling: much more damage and a hard shove."},
	{"id": "guard", "desc": "When you are hit your pet calls out, and the zombies around you freeze for a moment."},
	{"id": "frenzy", "desc": "Your pet attacks much faster."},
]
const PET_FETCH_RADIUS := 26.0          # how close the pet must come to pick something up
const PET_MAUL_EVERY := 4               # every Nth bite is a mauling...
const PET_MAUL_DAMAGE_MULT := 3.0
const PET_MAUL_KNOCKBACK := 520.0
const PET_GUARD_RADIUS := 200.0
const PET_GUARD_STAGGER := 0.9
const PET_GUARD_COOLDOWN := 4.0
const PET_FRENZY_SPEED := 1.4           # attack speed multiplier of the FRENZY trick

# ----------------------------------------------------------------------------
#  GAME FEEL - hits
# ----------------------------------------------------------------------------
const HIT_FLASH_TIME := 0.07            # zombies turn white this long when hit
const HIT_SQUASH := 0.25                # ...and puff up by this fraction
const KNOCKBACK_DAMPING := 9.0          # higher = knockback stops sooner
const KNOCKBACK_MAX := 900.0

const HITSTOP_MAX := 0.14               # longest freeze-frame allowed
const HITSTOP_MIN_INTERVAL := 0.1       # gap between freezes so hordes don't stutter the game
const KILL_SHAKE := 0.045               # shake per kill (multiplied by the zombie's shake_mult)

const PIERCE_DAMAGE_KEEP := 0.7          # a bullet that passes through a zombie keeps this much damage
const BLAST_EDGE_KNOCKBACK := 0.6       # explosion shove at the edge of the blast (1 = same as the centre)

const HURT_SHAKE := 0.65                # when the player is hit
const HURT_HITSTOP := 0.07
const DEATH_SHAKE := 1.0                # when the player dies
const DEATH_HITSTOP := 0.12
const DEATH_SLOWMO := 0.22              # game speed after the player dies
const DEATH_SLOWMO_TIME := 1.5          # seconds before the game-over screen
const BOSS_DEATH_SHAKE := 1.0
const BOSS_DEATH_HITSTOP := 0.14
const BOSS_DEATH_SLOWMO := 0.3          # game speed right after a boss dies...
const BOSS_DEATH_SLOWMO_TIME := 0.9     # ...for this many seconds
const CRATE_PICKUP_SHAKE := 0.2

# ----------------------------------------------------------------------------
#  GAME FEEL - camera
# ----------------------------------------------------------------------------
const SHAKE_MAX_OFFSET := 26.0          # px at full trauma
const SHAKE_MAX_ROLL_DEG := 2.0         # camera tilt at full trauma
const SHAKE_DECAY := 1.9                # trauma lost per second
const SHAKE_FREQUENCY := 30.0
const CAM_FOLLOW_SPEED := 10.0
const CAM_AIM_LEAD := 0.16              # camera drifts toward the crosshair by this fraction
const CAM_AIM_LEAD_MAX := 120.0
const CAM_KICK_RETURN := 16.0           # how fast a recoil jolt settles
const CAM_KICK_MAX := 42.0              # recoil jolts never push the view further than this
const CAM_ZOOM := 1.2                    # higher = closer, chunkier view

# ----------------------------------------------------------------------------
#  GAME FEEL - gore and particles
# ----------------------------------------------------------------------------
const BLOOD_COLOR := Color(0.62, 0.05, 0.05)
const BLOOD_COLOR_DARK := Color(0.36, 0.02, 0.03)
const BLOOD_PER_HIT := 4                # droplets per bullet hit
const BLOOD_PER_KILL := 12              # droplets per kill (multiplied by zombie "blood")
const MAX_PARTICLES := 900
const BURN_TINT := Color(1.0, 0.6, 0.36)   # colour of a zombie that is on fire
const CHARRED_TINT := Color(0.2, 0.17, 0.15)   # colour of a body that burned to death
const CORPSE_SLIDE_TIME := 0.38         # how long a dead body tumbles before it settles
const CASING_LIFETIME := 0.55
const MUZZLE_FLASH_TIME := 0.05

# ----------------------------------------------------------------------------
#  SETTINGS DEFAULTS
# ----------------------------------------------------------------------------
const DEFAULT_MASTER_VOLUME := 0.8
const DEFAULT_SFX_VOLUME := 1.0
const DEFAULT_FULLSCREEN := false
const DEFAULT_SCREEN_SHAKE := 1.0       # multiplier players can lower in Settings


# ----------------------------------------------------------------------------
#  Helpers (formulas built from the numbers above)
# ----------------------------------------------------------------------------
func wave_enemy_count(wave: int) -> int:
	var w := float(wave - 1)
	var count := WAVE_BASE_COUNT + WAVE_COUNT_PER_WAVE * w + WAVE_COUNT_ACCEL * w * w
	if is_boss_wave(wave):
		count *= BOSS_WAVE_COUNT_MULT
	return mini(int(round(count)), WAVE_MAX_COUNT)


func is_boss_wave(wave: int) -> bool:
	return wave > 0 and wave % BOSS_EVERY == 0


func wave_hp_mult(wave: int) -> float:
	return 1.0 + WAVE_HP_GROWTH * float(wave - 1)


func wave_damage_mult(wave: int) -> float:
	return 1.0 + WAVE_DAMAGE_GROWTH * float(wave - 1)


func wave_xp_mult(wave: int) -> float:
	return 1.0 + WAVE_XP_GROWTH * float(wave - 1)


## The waves a run may start from on a map whose best cleared wave is
## `best_cleared`: wave 1, plus the wave after every checkpoint reached.
func checkpoint_waves(best_cleared: int) -> Array[int]:
	var out: Array[int] = [1]
	var wave := CHECKPOINT_EVERY
	while wave <= mini(best_cleared, WAVES_PER_MAP - 1):
		out.append(wave + 1)
		wave += CHECKPOINT_EVERY
	return out


## True if clearing `wave` unlocks a new starting wave.
func is_checkpoint(wave: int) -> bool:
	return wave > 0 and wave < WAVES_PER_MAP and wave % CHECKPOINT_EVERY == 0


func wave_speed_mult(wave: int) -> float:
	return minf(1.0 + WAVE_SPEED_GROWTH * float(wave - 1), WAVE_SPEED_MAX_MULT)


func wave_pack_size(wave: int) -> int:
	return int(round(minf(WAVE_PACK_SIZE_BASE + WAVE_PACK_SIZE_PER_WAVE * float(wave - 1), WAVE_PACK_SIZE_MAX)))


## How many directions the packs of this wave come from at once.
func wave_pack_sides(wave: int) -> int:
	return mini(1 + int(float(wave) / WAVE_PACK_SIDES_EVERY), WAVE_PACK_SIDES_MAX)


func wave_pack_interval(wave: int) -> float:
	return maxf(WAVE_PACK_INTERVAL_BASE + WAVE_PACK_INTERVAL_PER_WAVE * float(wave - 1), WAVE_PACK_INTERVAL_MIN)


func combo_multiplier(combo: int) -> float:
	return minf(1.0 + COMBO_MULT_PER_KILL * float(maxi(combo - 1, 0)), COMBO_MULT_MAX)


## XP needed to go from `level` to the next one.
func level_xp_needed(level: int) -> int:
	return int(round(LEVEL_XP_BASE * pow(float(level), LEVEL_XP_EXPONENT)))


func weapon_xp_needed(level: int) -> int:
	return int(round(WEAPON_XP_BASE * pow(float(level), WEAPON_XP_EXPONENT)))


## Coins for the next bought skill point, after `already_bought` of them.
func skill_point_cost(already_bought: int) -> int:
	return int(round(SKILL_POINT_COST_BASE * pow(SKILL_POINT_COST_GROWTH, float(already_bought))))


## What a deed asks for, as shown on a sealed node (see TREE_SEAL_DEEDS).
func deed_text(deed: Dictionary) -> String:
	var value := int(deed["value"])
	match String(deed["kind"]):
		"wave":
			return "Clear wave %d on any map" % value
		"kills":
			return "Kill %d zombies in total" % value
		"weapon_level":
			return "Reach level %d with any weapon" % value
		"runs":
			return "Play %d runs" % value
		"score":
			return "Score %d points in one run" % value
		"bought":
			return "Buy %d skill points with coins" % value
		"level":
			return "Reach character level %d" % value
		"pets":
			return "Own %d pets" % value
		"map":
			return "Clear all %d waves of %s" % [WAVES_PER_MAP, String(MAPS[clampi(value - 1, 0, MAPS.size() - 1)]["name"])]
	return ""


## The share (0..1) of its damage bonus a pet gives at `bond` ranks of BOND.
func pet_bond_share(bond: int) -> float:
	return PET_BOND_BASE + (1.0 - PET_BOND_BASE) * minf(float(bond) / float(PET_BOND_FULL), 1.0)


## How much a pet adds to the character's damage (0.15 = +15%) at `bond` ranks.
func pet_damage_bonus(pet_id: String, bond: int) -> float:
	return float(PET_RARITIES[String(PETS[pet_id]["rarity"])]["damage"]) * pet_bond_share(bond)


## How much stronger than a plain bite this pet's bite is at `bond` ranks.
func pet_bite_mult(pet_id: String, bond: int) -> float:
	return float(PET_RARITIES[String(PETS[pet_id]["rarity"])]["bite"]) * (1.0 + PET_BITE_PER_BOND * float(bond))


## The name a piece of gear is stored and counted under: its id and tier (1-5).
func gear_key(item: String, tier: int) -> String:
	return "%s:%d" % [item, tier]


func gear_item_of(key: String) -> String:
	return key.get_slice(":", 0)


func gear_tier_of(key: String) -> int:
	return int(key.get_slice(":", 1))


func gear_tier_def(tier: int) -> Dictionary:
	return GEAR_TIERS[clampi(tier, 1, GEAR_TIERS.size()) - 1]


## What a piece is called, e.g. "FINE HARD HAT".
func gear_name(key: String) -> String:
	return "%s %s" % [String(gear_tier_def(gear_tier_of(key))["name"]), String(GEAR_ITEMS[gear_item_of(key)]["name"]).to_upper()]


## The passive stat ranks a piece gives at a tier: {passive id: ranks}.
func gear_stats(item: String, tier: int) -> Dictionary:
	var out := {}
	var base: Dictionary = GEAR_ITEMS[item]["stats"]
	var mult := float(gear_tier_def(tier)["mult"])
	for stat: String in base.keys():
		out[stat] = int(round(float(base[stat]) * mult))
	return out


## Where a piece comes from, in words.
func gear_source_text(item: String) -> String:
	var def: Dictionary = GEAR_ITEMS[item]
	var who := "Dropped by any zombie"
	match String(def["from"]):
		"brutes":
			who = "Dropped by brutes and bosses"
		"bosses":
			who = "Dropped by bosses only"
	var first_map := int(def["map"])
	if first_map > 1:
		return "%s, from %s onwards" % [who, String(MAPS[clampi(first_map - 1, 0, MAPS.size() - 1)]["name"])]
	return who


## Points needed to raise a stat that is currently at `rank`.
func rank_cost(rank: int, step: int) -> int:
	return 1 + int(float(rank) / float(step))


## The bonus a stat gives at `rank`. `def` is an entry of PASSIVES or WEAPON_TRACKS.
func stat_value(def: Dictionary, rank: int) -> float:
	if String(def["kind"]) == "curve":
		return float(def["max"]) * float(rank) / (float(rank) + float(def["half"]))
	return float(def["per_rank"]) * float(rank)


## How likely a weapon is to be the one in a crate, before its SPAWN RATE upgrade.
func crate_weight(weapon_id: String) -> float:
	return float(CRATE_RARITIES[String(WEAPONS[weapon_id]["rarity"])]["weight"])


## Which upgrade tracks a weapon has (see "needs" in WEAPON_TRACKS).
func weapon_tracks(weapon_id: String) -> Array:
	var w: Dictionary = WEAPONS[weapon_id]
	var mag: int = w["mag"]
	var out: Array = []
	for track: String in WEAPON_TRACK_ORDER:
		var ok := true
		match String(WEAPON_TRACKS[track]["needs"]):
			"ranged":
				ok = String(w["kind"]) != "melee"
			"burst":
				ok = mag != 1
			"mag":
				ok = mag > 0
			"crate":
				ok = float(w["duration"]) > 0.0
		if ok:
			out.append(track)
	return out
