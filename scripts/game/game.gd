class_name Game
extends Node2D
## One run of the game. Owns the world (arena, player, camera...) and runs
## the whole simulation from a single _process, which is what makes hit stop
## (freeze frames) and slow motion trivial to do.

signal run_ended(stats: Dictionary)

enum State { PLAYING, DYING, OVER }

var arena: Arena
var decals: Decals
var player: Player
var cam: GameCamera

var state: int = State.PLAYING
var time_alive := 0.0
var rage := 0.0
var rage_active := false

var _hitstop := 0.0
var _hitstop_cooldown := 0.0
var _time_scale := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

	arena = Arena.new()
	decals = Decals.new()
	add_child(decals)          # ground + blood (bottom layer)
	add_child(arena)           # rocks and stumps

	player = Player.new()
	player.game = self
	add_child(player)
	player.place(arena.rect.get_center())

	arena.canopy.z_index = 50  # tree tops above everything
	add_child(arena.canopy)

	cam = GameCamera.new()
	add_child(cam)
	cam.snap_to(player.pos)


func _process(delta: float) -> void:
	var real_dt := minf(delta, 1.0 / 30.0)

	# Hit stop: the world freezes for a few hundredths of a second.
	var dt := real_dt * _time_scale
	if _hitstop > 0.0:
		_hitstop -= real_dt
		dt = 0.0
		if _hitstop <= 0.0:
			_hitstop_cooldown = Config.HITSTOP_MIN_INTERVAL
	else:
		_hitstop_cooldown = maxf(_hitstop_cooldown - real_dt, 0.0)

	if dt > 0.0:
		time_alive += dt
		player.tick(dt)

	var lead := player.aim * Config.CAM_AIM_LEAD_MAX * GameInput.get_aim_distance_factor(player)
	cam.tick(real_dt, player.pos, lead)


# ----------------------------------------------------------------------------
#  Feel helpers used by everything else
# ----------------------------------------------------------------------------
func shake(amount: float) -> void:
	cam.add_trauma(amount)


## Freeze the action for `duration` seconds. Small freezes are rate-limited so
## a horde dying at once doesn't make the game stutter; `force` skips that.
func hitstop(duration: float, force: bool = false) -> void:
	if duration <= 0.0:
		return
	if not force and _hitstop <= 0.0 and _hitstop_cooldown > 0.0:
		return
	_hitstop = maxf(_hitstop, minf(duration, Config.HITSTOP_MAX))
