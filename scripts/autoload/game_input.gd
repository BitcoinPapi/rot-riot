extends Node
## ============================================================================
##  ALL PLAYER INPUT LIVES IN THIS FILE.
##
##  The game never reads the keyboard, mouse or gamepad directly. It only asks:
##      GameInput.get_move()            -> Vector2, length 0..1
##      GameInput.get_aim_direction(n)  -> Vector2, length 1
##      GameInput.is_firing()           -> bool
##  and listens to the signals  rage_pressed / reload_pressed / pause_pressed /
##  back_pressed.
##
##  ADDING TOUCH CONTROLS LATER (mobile):
##  Build on-screen sticks that call  set_virtual_input(move, aim, firing)
##  every frame and  press_rage() / press_reload() / press_pause()  from their
##  buttons.
##  Nothing else in the game has to change. (The test bot already plays the
##  game through exactly this path.)
## ============================================================================

signal pause_pressed
signal back_pressed
signal rage_pressed
signal reload_pressed
signal device_changed(device: int)

enum Device { KEYBOARD_MOUSE, GAMEPAD, TOUCH }

var device: int = Device.KEYBOARD_MOUSE

# Virtual sticks: used by touch controls (later) and by the automated test bot.
var virtual_active := false
var virtual_move := Vector2.ZERO
var virtual_aim := Vector2.ZERO
var virtual_fire := false

var _last_aim := Vector2.RIGHT
var _gameplay_mode := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_actions()


# ----------------------------------------------------------------------------
#  Key bindings - edit here to change controls
# ----------------------------------------------------------------------------
func _register_actions() -> void:
	# Movement: WASD (by key position, so it also works on AZERTY keyboards),
	# arrow keys, and the left stick.
	_bind("move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_bind("move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_bind("move_up", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_bind("move_down", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	# Aiming with the right stick (the mouse is read directly below).
	_bind("aim_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_bind("aim_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_bind("aim_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_bind("aim_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	# Shooting: left mouse button or right trigger.
	_bind("fire", [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	# Rage: Space, right mouse button, left trigger or left bumper.
	_bind("rage", [_key(KEY_SPACE), _mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0),
			_button(JOY_BUTTON_LEFT_SHOULDER)])
	# Reload: R or the X button. (Guns also reload by themselves when empty.)
	_bind("reload", [_key(KEY_R), _button(JOY_BUTTON_X)])
	# Pause: Escape, P or the Start button.
	_bind("pause", [_key(KEY_ESCAPE), _key(KEY_P), _button(JOY_BUTTON_START)])
	# Fullscreen toggle.
	_bind("toggle_fullscreen", [_key(KEY_F11)])
	# Menus: Godot's built-in menu actions only know the keyboard, so add the
	# gamepad's A (confirm) and B (back). D-pad / left stick navigation is built in.
	_bind("ui_accept", [_button(JOY_BUTTON_A)])
	_bind("ui_cancel", [_button(JOY_BUTTON_B)])
	_bind("ui_focus_next", [_button(JOY_BUTTON_Y)])      # Y steps from an upgrade tree to the buttons beside it


func _bind(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.3)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.device = -1
	return e


func _button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = -1
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = -1
	return e


# ----------------------------------------------------------------------------
#  What the game asks every frame
# ----------------------------------------------------------------------------
## Movement direction. Length 0..1 (analog sticks can walk slowly).
func get_move() -> Vector2:
	if virtual_active:
		return virtual_move.limit_length(1.0)
	return Input.get_vector("move_left", "move_right", "move_up", "move_down", Config.STICK_DEADZONE)


## Direction the player is aiming, as a unit vector.
## `from` is the node that aims (the player) - needed to compare with the mouse position.
func get_aim_direction(from: Node2D) -> Vector2:
	if virtual_active:
		if virtual_aim.length_squared() > 0.04:
			_last_aim = virtual_aim.normalized()
		return _last_aim
	if device == Device.GAMEPAD:
		var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down", Config.STICK_DEADZONE)
		if stick.length_squared() > 0.0:
			_last_aim = stick.normalized()
		elif Config.GAMEPAD_AIM_FOLLOWS_MOVE:
			var move := get_move()
			if move.length_squared() > 0.09:
				_last_aim = move.normalized()
		return _last_aim
	var to_mouse := from.get_global_mouse_position() - from.global_position
	if to_mouse.length_squared() > 4.0:
		_last_aim = to_mouse.normalized()
	return _last_aim


## How far the aim point is from the player (used for the camera look-ahead). 0..1.
func get_aim_distance_factor(from: Node2D) -> float:
	if virtual_active:
		return 0.6
	if device == Device.GAMEPAD:
		return 0.6
	var to_mouse := from.get_global_mouse_position() - from.global_position
	return clampf(to_mouse.length() / 400.0, 0.0, 1.0)


func is_firing() -> bool:
	if virtual_active:
		return virtual_fire
	return Input.is_action_pressed("fire")


func using_gamepad() -> bool:
	return device == Device.GAMEPAD and not virtual_active


## True when aiming with a stick (gamepad or touch) - those get stronger aim assist.
func using_sticks() -> bool:
	return virtual_active or device == Device.GAMEPAD or device == Device.TOUCH


# ----------------------------------------------------------------------------
#  Virtual input (touch controls later / test bot now)
# ----------------------------------------------------------------------------
func set_virtual_input(move: Vector2, aim: Vector2, firing: bool) -> void:
	virtual_active = true
	virtual_move = move
	virtual_aim = aim
	virtual_fire = firing


func clear_virtual_input() -> void:
	virtual_active = false
	virtual_move = Vector2.ZERO
	virtual_aim = Vector2.ZERO
	virtual_fire = false


func press_rage() -> void:
	rage_pressed.emit()


func press_reload() -> void:
	reload_pressed.emit()


func press_pause() -> void:
	pause_pressed.emit()


# ----------------------------------------------------------------------------
#  Mouse cursor handling (hidden + confined while playing, normal in menus)
# ----------------------------------------------------------------------------
func set_gameplay_mode(active: bool) -> void:
	_gameplay_mode = active
	_update_mouse_mode()


func _update_mouse_mode() -> void:
	if not _gameplay_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif device == Device.KEYBOARD_MOUSE and Config.CONFINE_MOUSE:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


# ----------------------------------------------------------------------------
#  Raw events: device detection and one-shot buttons
# ----------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	_detect_device(event)
	if event.is_action_pressed("toggle_fullscreen"):
		SaveData.set_setting("fullscreen", not bool(SaveData.get_setting("fullscreen")))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		pause_pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		back_pressed.emit()
	elif event.is_action_pressed("rage"):
		rage_pressed.emit()
	elif event.is_action_pressed("reload"):
		reload_pressed.emit()


func _detect_device(event: InputEvent) -> void:
	var new_device := device
	if event is InputEventJoypadButton:
		new_device = Device.GAMEPAD
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			new_device = Device.GAMEPAD
	elif event is InputEventKey or event is InputEventMouseButton:
		new_device = Device.KEYBOARD_MOUSE
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length_squared() > 9.0:
			new_device = Device.KEYBOARD_MOUSE
	if new_device != device:
		device = new_device
		_update_mouse_mode()
		device_changed.emit(device)
