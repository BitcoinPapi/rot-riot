class_name MainMenu
extends Control
## Title screen: Play (opens the map screen), Character, Armory, Gear, Settings, Quit.

var main: Main
var _first: Button
var _character: Button
var _armory: Button
var _gear: Button
var _stats: Label
var _progress: Label
var _notice: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(UiKit.centered(col))

	var title := UiKit.heading(Config.GAME_TITLE, 100, Color("efe6cf"))
	title.add_theme_color_override("font_shadow_color", Color(0.6, 0.06, 0.05))
	title.add_theme_constant_override("shadow_offset_x", 6)
	title.add_theme_constant_override("shadow_offset_y", 7)
	title.add_theme_constant_override("shadow_outline_size", 20)
	col.add_child(title)
	col.add_child(UiKit.heading("SURVIVE THE HORDE", 22, UiKit.GOLD))
	col.add_child(UiKit.spacer(4))

	_first = _add_button(col, "PLAY", func() -> void: main.open_screen("maps"))
	_character = _add_button(col, "CHARACTER", func() -> void: main.open_screen("character"))
	_armory = _add_button(col, "ARMORY", func() -> void: main.open_screen("armory"))
	_gear = _add_button(col, "GEAR", func() -> void: main.open_screen("gear"))
	_add_button(col, "SETTINGS", func() -> void: main.open_screen("settings"))
	_add_button(col, "QUIT", func() -> void: main.quit_game())

	col.add_child(UiKit.spacer(4))
	_progress = UiKit.heading("", 21, UiKit.GOLD)
	col.add_child(_progress)
	_stats = UiKit.heading("", 16, UiKit.DIM)
	col.add_child(_stats)
	_notice = UiKit.heading("", 15, Color(1.0, 0.6, 0.45))
	col.add_child(_notice)

	var version := UiKit.label("v" + Config.GAME_VERSION, 14, Color(1, 1, 1, 0.35))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -16
	version.offset_bottom = -10
	add_child(version)


func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var b := UiKit.button(text, action)
	b.custom_minimum_size.y = 50
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(b)
	return b


## Called by Main every time this screen is shown.
func opened() -> void:
	# A number after the name means there are points waiting to be spent.
	_character.text = "CHARACTER" if SaveData.skill_points <= 0 else "CHARACTER  (%d)" % SaveData.skill_points
	var weapon_points := SaveData.total_weapon_points()
	_armory.text = "ARMORY" if weapon_points <= 0 else "ARMORY  (%d)" % weapon_points
	_gear.text = "GEAR" if SaveData.gear_new <= 0 else "GEAR  (%d NEW)" % SaveData.gear_new
	_progress.text = "LEVEL %d      COINS: %d" % [SaveData.level, SaveData.coins]
	if SaveData.runs_played > 0:
		var map_index := SaveData.maps_unlocked - 1
		_stats.text = "MAP %d: %s  -  BEST WAVE %d / %d   -   BEST SCORE %d   -   ZOMBIES KILLED %d" % [
			map_index + 1, String(Config.MAPS[map_index]["name"]), SaveData.map_best_wave(map_index), Config.WAVES_PER_MAP,
			SaveData.best_score, SaveData.total_kills]
	else:
		_stats.text = "WASD move  -  MOUSE aim  -  LEFT CLICK shoot  -  R reload  -  SPACE rage  (gamepad works too)"
	if SaveData.was_reset_by_update:
		_notice.text = "New progression system: your old coins and upgrades were reset."
	elif SaveData.points_returned > 0 and SaveData.skill_points > 0:
		_notice.text = "The skill tree is new: your %d skill points are waiting on the CHARACTER screen." % SaveData.skill_points
	else:
		_notice.text = ""
	_notice.visible = _notice.text != ""
	_first.grab_focus()
