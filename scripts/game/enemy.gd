class_name Enemy
extends Sprite2D
## One zombie. This is only data plus a sprite - all the behaviour runs in
## EnemyManager's single loop, which is what keeps 200+ of them fast.
## Zombies are recycled from a pool instead of being created and deleted.

var kind := 0
var variant := 0
var alive := false

# Co-op: the host numbers every zombie; the other player's computer shows a
# copy ("puppet") that glides to wherever the host says it is.
var net_id := 0
var net_from := Vector2.ZERO    # where the copy was when the last message arrived...
var net_to := Vector2.ZERO      # ...where that message says it is...
var net_t := 0.0                # ...and how far along it has glided (0..1)
var net_face := 0.0
var net_seen := 0               # the last message that mentioned it
var net_hit := false            # (host) it was hit since the last message
var burn_slot := -1             # (host) the slot of the joiner who set it on fire (-1 = the player here, or nobody)

# Simulation
var pos := Vector2.ZERO
var kb := Vector2.ZERO          # knockback velocity
var hp := 1.0
var max_hp := 1.0
var radius := 14.0
var speed := 80.0
var damage := 8.0
var attack_cd := 0.8
var attack_t := 0.0
var flash_t := 0.0              # white hit-flash time left
var stagger_t := 0.0            # can't walk while this is > 0
var spawn_t := 0.0              # rising out of the ground (summoned zombies)
var wounded := false            # below Config.WOUNDED_AT health: shows wounds, limps, bleeds
var sway := 0.13                # how far the body rocks from side to side while walking
var burn_t := 0.0               # on fire for this many more seconds...
var burn_dps := 0.0             # ...losing this much health per second
var burn_src := ""              # the weapon that lit it (gets the XP if it dies)
var pet_marked := false         # the pet has bitten it
var face := 0.0                 # facing angle
var phase := 0.0                # walk wobble / zig-zag
var flank := Vector2.ZERO       # personal flanking offset
var entered := false            # has walked into the arena
var cell := 0                   # spatial grid cell
var crowd := 0                  # neighbours pressing on it this frame...
var crowd_prev := 0             # ...and last frame (crowded zombies push less hard)

# Stats copied from Config when spawned
var kb_mult := 1.0
var stagger_mult := 1.0
var inv_mass := 1.0
var push_player := 1.0
var score := 10
var xp := 4
var hitstop_mult := 1.0
var shake_mult := 1.0
var blood := 1.0
var is_big := false

# Sprites
var tex_normal: Texture2D
var tex_flash: Texture2D
var tex_hurt: Texture2D
var base_scale := 0.5

# Zombies with an attack of their own (the boss, shooters, the Gasbag, the Lunger)
var ai := 0                     # Config.AI_*
var cfg: Dictionary = {}        # its entry in Config.ENEMIES (for the numbers of its attack)
var state := 0
var state_t := 0.0
var shoot_range := 0.0          # a shooter stops this far from the player
var melee_t := 0.0              # a shooter's own timer for hitting a player who walks into it
var warn := Color.WHITE         # the colour it flushes while winding up
var charge_cd := 0.0
var summon_cd := 0.0
var charge_dir := Vector2.ZERO
var charge_hit := false
