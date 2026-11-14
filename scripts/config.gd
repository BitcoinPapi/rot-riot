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
const PLAYER_HURT_INVULN := 0.55              # seconds of safety after being hit
const PLAYER_HURT_SHOVE_RADIUS := 120.0       # being hit shoves nearby zombies away...
const PLAYER_HURT_SHOVE_FORCE := 430.0        # ...this hard, so you get a chance to escape
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
#  duration      seconds a crate weapon lasts (0 = forever)
#  interval      seconds between shots (lower = faster)
#  spread_deg    full width of the random cone
#  knockback     shove speed given to a zombie that is hit
#  stagger       seconds a hit zombie stops walking
#  --- feel ---
#  shake         screen shake per shot       kick         camera jolt opposite to aim
#  recoil_gun    px the gun jumps back       recoil_push  speed the player is shoved back
#  hitstop_kill  freeze-frame on a kill      flash_size   muzzle flash size
# ----------------------------------------------------------------------------
const STARTER_WEAPON := "pistol"
const WEAPON_ORDER := ["pistol", "shotgun", "machinegun", "launcher", "sledge"]
const CRATE_WEAPONS := ["shotgun", "machinegun", "launcher", "sledge"]

const WEAPONS := {
	"pistol": {
		"name": "PISTOL", "kind": "bullet", "duration": 0.0,
		"damage": 14.0, "interval": 0.24, "pellets": 1, "spread_deg": 2.5,
		"bullet_speed": 1500.0, "speed_var": 0.0, "range": 720.0, "pierce": 0,
		"knockback": 170.0, "stagger": 0.11, "move_mult": 1.0,
		"shake": 0.17, "kick": 5.0, "recoil_gun": 6.0, "recoil_push": 0.0,
		"hitstop_kill": 0.028, "flash_size": 30.0, "casing": "brass",
		"tracer_len": 26.0, "tracer_width": 3.0, "tracer_color": Color(1.0, 0.92, 0.55),
		"muzzle_dist": 30.0, "sound": "pistol", "color": Color(0.80, 0.82, 0.86),
	},
	"shotgun": {
		"name": "SHOTGUN", "kind": "bullet", "duration": 20.0,
		"damage": 10.0, "interval": 0.72, "pellets": 9, "spread_deg": 26.0,
		"bullet_speed": 1350.0, "speed_var": 0.18, "range": 400.0, "pierce": 1,
		"knockback": 300.0, "stagger": 0.22, "move_mult": 1.0,
		"shake": 0.52, "kick": 16.0, "recoil_gun": 13.0, "recoil_push": 170.0,
		"hitstop_kill": 0.05, "flash_size": 62.0, "casing": "shell",
		"tracer_len": 20.0, "tracer_width": 2.5, "tracer_color": Color(1.0, 0.80, 0.40),
		"muzzle_dist": 38.0, "sound": "shotgun", "color": Color(0.95, 0.55, 0.20),
	},
	"machinegun": {
		"name": "MACHINE GUN", "kind": "bullet", "duration": 20.0,
		"damage": 9.0, "interval": 0.062, "pellets": 1, "spread_deg": 8.0,
		"bullet_speed": 1650.0, "speed_var": 0.05, "range": 760.0, "pierce": 0,
		"knockback": 85.0, "stagger": 0.07, "move_mult": 1.0,
		"shake": 0.11, "kick": 3.5, "recoil_gun": 4.0, "recoil_push": 16.0,
		"hitstop_kill": 0.014, "flash_size": 34.0, "casing": "brass",
		"tracer_len": 34.0, "tracer_width": 2.5, "tracer_color": Color(1.0, 0.95, 0.60),
		"muzzle_dist": 40.0, "sound": "machinegun", "color": Color(0.95, 0.85, 0.25),
	},
	"launcher": {
		"name": "LAUNCHER", "kind": "grenade", "duration": 18.0,
		"damage": 95.0, "interval": 0.80, "pellets": 1, "spread_deg": 2.0,
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
	"sledge": {
		"name": "SLEDGEHAMMER", "kind": "melee", "duration": 20.0,
		"damage": 62.0, "interval": 0.34, "pellets": 1, "spread_deg": 0.0,
		"bullet_speed": 0.0, "speed_var": 0.0, "range": 108.0, "pierce": 0,
		"arc_deg": 160.0,             # width of the swing
		"knockback": 660.0, "stagger": 0.5, "move_mult": 1.18,
		"shake": 0.06, "kick": 0.0, "recoil_gun": 0.0, "recoil_push": -70.0,   # negative = lunge forward
		"shake_hit": 0.42, "hitstop_hit": 0.055,
		"hitstop_kill": 0.0, "flash_size": 0.0, "casing": "",
		"tracer_len": 0.0, "tracer_width": 0.0, "tracer_color": Color(1, 1, 1),
		"muzzle_dist": 30.0, "sound": "sledge_swing", "color": Color(0.60, 0.75, 0.95),
	},
}

# ----------------------------------------------------------------------------
#  ENEMIES
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
		"name": "Shambler", "hp": 24.0, "speed": 80.0, "speed_var": 0.2, "radius": 14.0,
		"damage": 8.0, "attack_cd": 0.8, "score": 10, "rage": 2.2,
		"coin_chance": 0.30, "coins_min": 1, "coins_max": 1, "medkit_chance": 0.012,
		"kb_mult": 1.0, "stagger_mult": 1.0, "mass": 1.0, "push_player": 1.0,
		"hitstop_mult": 1.0, "shake_mult": 1.0, "blood": 1.0,
	},
	RUNNER: {
		"name": "Runner", "hp": 12.0, "speed": 195.0, "speed_var": 0.12, "radius": 11.0,
		"damage": 6.0, "attack_cd": 0.7, "score": 15, "rage": 2.6,
		"coin_chance": 0.35, "coins_min": 1, "coins_max": 1, "medkit_chance": 0.012,
		"kb_mult": 1.25, "stagger_mult": 1.0, "mass": 0.6, "push_player": 0.7,
		"hitstop_mult": 0.8, "shake_mult": 0.8, "blood": 0.7,
	},
	BRUTE: {
		"name": "Brute", "hp": 220.0, "speed": 58.0, "speed_var": 0.08, "radius": 26.0,
		"damage": 22.0, "attack_cd": 1.1, "score": 60, "rage": 9.0,
		"coin_chance": 1.0, "coins_min": 3, "coins_max": 5, "medkit_chance": 0.15,
		"kb_mult": 0.28, "stagger_mult": 0.3, "mass": 6.0, "push_player": 2.5,
		"hitstop_mult": 2.6, "shake_mult": 4.0, "blood": 2.5,
	},
	BOSS: {
		"name": "THE GORGER", "hp": 2600.0, "speed": 72.0, "speed_var": 0.0, "radius": 52.0,
		"damage": 30.0, "attack_cd": 1.0, "score": 1000, "rage": 40.0,
		"coin_chance": 1.0, "coins_min": 30, "coins_max": 30, "medkit_chance": 1.0,
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
		"summon_cooldown": 9.0,
		"summon_count": 6,             # shamblers it calls up
	},
}

const ENEMY_SEPARATION := 0.7           # how firmly zombies push each other apart (0..1)
const ENEMY_CROWD_FREE := 2             # zombies touching more neighbours than this slow down (keeps hordes from squashing into a blob)
const ENEMY_ATTACK_REACH := 5.0         # extra px beyond touching at which they can hit
const ENEMY_TURN_SPEED := 9.0
const ENEMY_FLANK_SPREAD := 70.0        # each zombie aims slightly off-centre so hordes surround you
const RUNNER_ZIGZAG_AMOUNT := 0.55
const RUNNER_ZIGZAG_SPEED := 7.0

# ----------------------------------------------------------------------------
#  WAVES
# ----------------------------------------------------------------------------
const WAVE_BASE_COUNT := 16.0           # zombies in wave 1
const WAVE_COUNT_PER_WAVE := 9.0        # + this many per wave...
const WAVE_COUNT_ACCEL := 0.9           # ...+ this * (wave-1)^2  (makes late waves huge)
const WAVE_MAX_COUNT := 420
const MAX_ENEMIES_ALIVE := 240          # hard cap on screen at once
const WAVE_PACK_SIZE_BASE := 4.0        # zombies arrive in packs from one side
const WAVE_PACK_SIZE_PER_WAVE := 0.9
const WAVE_PACK_SIZE_MAX := 18.0
const WAVE_PACK_INTERVAL_BASE := 1.5    # seconds between packs in wave 1
const WAVE_PACK_INTERVAL_PER_WAVE := -0.08
const WAVE_PACK_INTERVAL_MIN := 0.45
const WAVE_FIRST_DELAY := 1.6           # breathing room at the very start
const WAVE_INTERMISSION := 3.5          # pause between waves
const WAVE_HP_GROWTH := 0.05            # +5% zombie health per wave
const WAVE_SPEED_GROWTH := 0.012        # +1.2% zombie speed per wave
const WAVE_SPEED_MAX_MULT := 1.3
const RUNNER_START_WAVE := 2
const RUNNER_WEIGHT_PER_WAVE := 0.09
const RUNNER_WEIGHT_MAX := 0.40
const BRUTE_START_WAVE := 4
const BRUTE_WEIGHT_PER_WAVE := 0.025
const BRUTE_WEIGHT_MAX := 0.12
const BOSS_EVERY := 5                   # a boss arrives every N waves
const BOSS_WAVE_COUNT_MULT := 0.6       # boss waves have fewer regular zombies
const WAVE_CLEAR_COINS_BASE := 3        # coin bonus for clearing a wave...
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
const RAGE_BURST_SHAKE := 0.8
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
#  UPGRADE SHOP  (bought with coins between runs, saved to disk)
#  per_level: damage / fire_rate / move_speed are fractions (0.15 = +15%),
#             max_health is flat hit points.
# ----------------------------------------------------------------------------
const UPGRADE_ORDER := ["damage", "fire_rate", "move_speed", "max_health"]
const UPGRADES := {
	"damage": {
		"name": "DAMAGE", "desc": "+15% weapon damage per level",
		"per_level": 0.15, "costs": [50, 110, 200, 340, 520],
	},
	"fire_rate": {
		"name": "FIRE RATE", "desc": "+10% fire rate per level",
		"per_level": 0.10, "costs": [50, 110, 200, 340, 520],
	},
	"move_speed": {
		"name": "MOVE SPEED", "desc": "+6% move speed per level",
		"per_level": 0.06, "costs": [40, 90, 170, 290, 450],
	},
	"max_health": {
		"name": "MAX HEALTH", "desc": "+20 max health per level",
		"per_level": 20.0, "costs": [40, 90, 170, 290, 450],
	},
}

# ----------------------------------------------------------------------------
#  GAME FEEL - hits
# ----------------------------------------------------------------------------
const HIT_FLASH_TIME := 0.07            # zombies turn white this long when hit
const HIT_SQUASH := 0.25                # ...and puff up by this fraction
const KNOCKBACK_DAMPING := 9.0          # higher = knockback stops sooner
const KNOCKBACK_MAX := 900.0

const HITSTOP_MAX := 0.14               # longest freeze-frame allowed
const HITSTOP_MIN_INTERVAL := 0.06      # gap between freezes so hordes don't stutter the game
const KILL_SHAKE := 0.045               # shake per kill (multiplied by the zombie's shake_mult)

const HURT_SHAKE := 0.65                # when the player is hit
const HURT_HITSTOP := 0.07
const DEATH_SLOWMO := 0.22              # game speed after the player dies
const DEATH_SLOWMO_TIME := 1.5          # seconds before the game-over screen
const BOSS_DEATH_HITSTOP := 0.14

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
const CAM_ZOOM := 1.2                    # higher = closer, chunkier view

# ----------------------------------------------------------------------------
#  GAME FEEL - gore and particles
# ----------------------------------------------------------------------------
const BLOOD_COLOR := Color(0.62, 0.05, 0.05)
const BLOOD_COLOR_DARK := Color(0.36, 0.02, 0.03)
const BLOOD_PER_HIT := 4                # droplets per bullet hit
const BLOOD_PER_KILL := 12              # droplets per kill (multiplied by zombie "blood")
const MAX_PARTICLES := 900
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


func wave_pack_interval(wave: int) -> float:
	return maxf(WAVE_PACK_INTERVAL_BASE + WAVE_PACK_INTERVAL_PER_WAVE * float(wave - 1), WAVE_PACK_INTERVAL_MIN)


func combo_multiplier(combo: int) -> float:
	return minf(1.0 + COMBO_MULT_PER_KILL * float(maxi(combo - 1, 0)), COMBO_MULT_MAX)


func upgrade_max_level(id: String) -> int:
	var costs: Array = UPGRADES[id]["costs"]
	return costs.size()


func upgrade_cost(id: String, current_level: int) -> int:
	var costs: Array = UPGRADES[id]["costs"]
	if current_level >= costs.size():
		return -1
	return int(costs[current_level])
