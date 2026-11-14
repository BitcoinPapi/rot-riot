class_name GameCamera
extends Camera2D
## Follows the player, leans toward where they aim, and does all the screen
## shake and recoil jolts. All strengths come from Config.

var trauma := 0.0            # 0..1, decays over time. Shake = trauma squared.
var _kick := Vector2.ZERO    # recoil jolt, springs back to zero
var _focus := Vector2.ZERO
var _time := 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	zoom = Vector2.ONE * Config.CAM_ZOOM
	ignore_rotation = false
	position_smoothing_enabled = false
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = randi()
	make_current()


func snap_to(target: Vector2) -> void:
	_focus = target
	position = _limit(target)


## Add screen shake. 0.1 = a tap, 0.5 = a heavy hit, 1.0 = everything.
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount * _shake_setting(), 0.0, 1.0)


## A one-off jolt in a direction (used for weapon recoil).
func kick(direction: Vector2, amount: float) -> void:
	_kick = (_kick + direction * amount * _shake_setting()).limit_length(42.0)


func tick(real_delta: float, target: Vector2, lead: Vector2) -> void:
	_time += real_delta
	_focus = _focus.lerp(target + lead, 1.0 - exp(-Config.CAM_FOLLOW_SPEED * real_delta))
	position = _limit(_focus)

	_kick = _kick.lerp(Vector2.ZERO, 1.0 - exp(-Config.CAM_KICK_RETURN * real_delta))
	trauma = maxf(trauma - Config.SHAKE_DECAY * real_delta, 0.0)
	var power := trauma * trauma
	var t := _time * Config.SHAKE_FREQUENCY
	var shake := Vector2(_noise.get_noise_2d(t, 0.0), _noise.get_noise_2d(0.0, t + 50.0)) * 2.0
	offset = shake * Config.SHAKE_MAX_OFFSET * power + _kick
	rotation = deg_to_rad(Config.SHAKE_MAX_ROLL_DEG) * power * _noise.get_noise_2d(t, 200.0) * 2.0


## Keep the view inside the arena (plus a small margin of trees).
func _limit(center: Vector2) -> Vector2:
	var view := get_viewport_rect().size / zoom
	var half := view * 0.5
	var bounds := Rect2(Vector2.ZERO, Config.ARENA_SIZE).grow(Config.CAMERA_EDGE_MARGIN)
	if bounds.size.x <= view.x:
		center.x = bounds.get_center().x
	else:
		center.x = clampf(center.x, bounds.position.x + half.x, bounds.end.x - half.x)
	if bounds.size.y <= view.y:
		center.y = bounds.get_center().y
	else:
		center.y = clampf(center.y, bounds.position.y + half.y, bounds.end.y - half.y)
	return center


func _shake_setting() -> float:
	return float(SaveData.get_setting("screen_shake"))
