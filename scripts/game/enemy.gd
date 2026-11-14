class_name Enemy
extends Sprite2D
## One zombie. This is only data plus a sprite - all the behaviour runs in
## EnemyManager's single loop, which is what keeps 200+ of them fast.
## Zombies are recycled from a pool instead of being created and deleted.

var kind := 0
var variant := 0
var alive := false

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
var burn_t := 0.0               # on fire for this many more seconds...
var burn_dps := 0.0             # ...losing this much health per second
var burn_src := ""              # the weapon that lit it (gets the XP if it dies)
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
var rage := 2.0
var hitstop_mult := 1.0
var shake_mult := 1.0
var blood := 1.0
var is_big := false

# Sprites
var tex_normal: Texture2D
var tex_flash: Texture2D
var base_scale := 0.5

# Boss only
var state := 0
var state_t := 0.0
var charge_cd := 0.0
var summon_cd := 0.0
var charge_dir := Vector2.ZERO
var charge_hit := false
