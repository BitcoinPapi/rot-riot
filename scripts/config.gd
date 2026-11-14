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
const GAME_VERSION := "0.1.0"

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

# Reloading. Reload speed also rises with fire-rate bonuses (dexterity, the
# weapon's SHOOTING SPEED upgrade).
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
		"name": "THE GORGER", "hp": 2600.0, "speed": 72.0, "speed_var": 0.0, "radius": 52.0,
		"damage": 30.0, "attack_cd": 1.0, "score": 1000, "rage": 40.0, "xp": 350,
		"coin_chance": 1.0, "coins_min": 25, "coins_max": 25, "medkit_chance": 1.0,
		"kb_mult": 0.04, "stagger_mult": 0.0, "mass": 60.0, "push_player": 2.5,
		"hitstop_mult": 5.0, "shake_mult": 14.0, "blood": 8.0,
		# boss-only behaviour
		"hp_growth_per_boss": 0.6,     # each later boss has +60% health
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
#  WAVES
# ----------------------------------------------------------------------------
const WAVE_BASE_COUNT := 22.0           # zombies in wave 1
const WAVE_COUNT_PER_WAVE := 13.0       # + this many per wave...
const WAVE_COUNT_ACCEL := 1.5           # ...+ this * (wave-1)^2  (makes late waves huge)
const WAVE_MAX_COUNT := 500
const MAX_ENEMIES_ALIVE := 240          # hard cap on screen at once
const WAVE_PACK_SIZE_BASE := 5.0        # zombies arrive in packs from one side
const WAVE_PACK_SIZE_PER_WAVE := 1.2
const WAVE_PACK_SIZE_MAX := 24.0
const WAVE_PACK_INTERVAL_BASE := 1.2    # seconds between packs in wave 1
const WAVE_PACK_INTERVAL_PER_WAVE := -0.09
const WAVE_PACK_INTERVAL_MIN := 0.35
const WAVE_PACK_SIDES_EVERY := 3        # every N waves, packs arrive from one more direction at once...
const WAVE_PACK_SIDES_MAX := 4          # ...up to this many, so later hordes surround you
const WAVE_FIRST_DELAY := 1.6           # breathing room at the very start
const WAVE_INTERMISSION := 3.5          # pause between waves
const WAVE_HP_GROWTH := 0.08            # +8% zombie health per wave
const WAVE_SPEED_GROWTH := 0.02         # +2% zombie speed per wave
const WAVE_SPEED_MAX_MULT := 1.45
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
const CRATE_PICKUP_RADIUS := 30.0
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
const LEVEL_XP_EXPONENT := 1.8          # ...and how steeply that grows (needed = base * level ^ exponent).
                                        # With 80 and 1.8, level 100 takes about 11.2 million XP in total:
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

# Passive stats.
#   "linear": each rank adds per_rank, forever.
#   "curve":  approaches "max" but never reaches it; "half" is the rank at which
#             you have half of max. (Stops speed/dodge from becoming silly.)
# Every RANK_COST_STEP ranks, the next ranks of that stat cost one more point.
const PASSIVE_RANK_COST_STEP := 10
const PASSIVE_ORDER := ["vitality", "strength", "dexterity", "agility", "defense", "evasion", "critical", "luck"]
const PASSIVES := {
	"vitality": {"name": "VITALITY", "desc": "More maximum health", "kind": "linear", "per_rank": 8.0},
	"strength": {"name": "STRENGTH", "desc": "More damage with every weapon", "kind": "linear", "per_rank": 0.03},
	"dexterity": {"name": "DEXTERITY", "desc": "Shoot, swing and reload faster", "kind": "curve", "max": 1.5, "half": 60.0},
	"agility": {"name": "AGILITY", "desc": "Move faster", "kind": "curve", "max": 0.8, "half": 40.0},
	"defense": {"name": "DEFENSE", "desc": "Take less damage from every hit", "kind": "curve", "max": 0.8, "half": 50.0},
	"evasion": {"name": "EVASION", "desc": "Chance to dodge a hit completely", "kind": "curve", "max": 0.6, "half": 40.0},
	"critical": {"name": "CRITICAL", "desc": "Chance for a shot to deal double damage", "kind": "curve", "max": 0.6, "half": 40.0},
	"luck": {"name": "LUCK", "desc": "Zombies drop coins more often", "kind": "linear", "per_rank": 0.03},
}
const CRIT_DAMAGE_MULT := 2.0
const CRIT_KNOCKBACK_MULT := 1.4
const DODGE_INVULN := 0.25              # seconds of safety after a dodge

# Weapon levels.
const WEAPON_XP_BASE := 60.0            # weapon XP needed for its level 2 (needed = base * level ^ exponent)
const WEAPON_XP_EXPONENT := 1.4
const WEAPON_POINTS_PER_LEVEL := 1
const WEAPON_RANK_COST_STEP := 10       # every N ranks, the next ranks cost one more weapon point
# What a weapon's points can be spent on. "crate_only" tracks do not apply to the pistol.
const WEAPON_TRACK_ORDER := ["power", "speed", "stability", "spawn", "duration"]
const WEAPON_TRACKS := {
	"power": {"name": "POWER", "desc": "More damage", "kind": "linear", "per_rank": 0.05, "crate_only": false},
	"speed": {"name": "SHOOTING SPEED", "desc": "Faster fire and reload", "kind": "curve", "max": 1.0, "half": 30.0, "crate_only": false},
	"stability": {"name": "STABILITY", "desc": "Tighter spread, less recoil", "kind": "curve", "max": 0.75, "half": 15.0, "crate_only": false},
	"spawn": {"name": "SPAWN RATE", "desc": "Its crate appears more often", "kind": "linear", "per_rank": 0.12, "crate_only": true},
	"duration": {"name": "DURATION", "desc": "Lasts longer when picked up", "kind": "curve", "max": 1.5, "half": 30.0, "crate_only": true},
}

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


## Which upgrade tracks a weapon has (the single pistol is not a crate weapon).
func weapon_tracks(weapon_id: String) -> Array:
	var out: Array = []
	var from_crate: bool = float(WEAPONS[weapon_id]["duration"]) > 0.0
	for track: String in WEAPON_TRACK_ORDER:
		if from_crate or not bool(WEAPON_TRACKS[track]["crate_only"]):
			out.append(track)
	return out
