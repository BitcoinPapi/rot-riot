class_name MainMenu
extends Control
## Title screen: Play, Upgrades, Settings, Quit.

var main: Main
var _first: Button
var _stats: Label
var _coins: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(UiKit.centered(col))

	var title := UiKit.heading(Config.GAME_TITLE, 120, Color("efe6cf"))
	title.add_theme_color_override("font_shadow_color", Color(0.6, 0.06, 0.05))
	title.add_theme_constant_override("shadow_offset_x", 6)
	title.add_theme_constant_override("shadow_offset_y", 7)
	title.add_theme_constant_override("shadow_outline_size", 20)
	col.add_child(title)
	col.add_child(UiKit.heading("SURVIVE THE HORDE", 24, UiKit.GOLD))
	col.add_child(UiKit.spacer(22))

	_first = _add_button(col, "PLAY", func() -> void: main.start_run())
	_add_button(col, "UPGRADES", func() -> void: main.open_screen("shop"))
	_add_button(col, "SETTINGS", func() -> void: main.open_screen("settings"))
	_add_button(col, "QUIT", func() -> void: main.quit_game())

	col.add_child(UiKit.spacer(10))
	_coins = UiKit.heading("", 22, UiKit.GOLD)
	col.add_child(_coins)
	_stats = UiKit.heading("", 17, UiKit.DIM)
	col.add_child(_stats)

	var version := UiKit.label("v" + Config.GAME_VERSION + "  -  first playable draft", 14, Color(1, 1, 1, 0.35))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -16
	version.offset_bottom = -10
	add_child(version)


func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var b := UiKit.button(text, action)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(b)
	return b


## Called by Main every time this screen is shown.
func opened() -> void:
	_coins.text = "COINS: %d" % SaveData.coins
	if SaveData.runs_played > 0:
		_stats.text = "BEST SCORE %d   -   BEST WAVE %d   -   ZOMBIES KILLED %d" % [
			SaveData.best_score, SaveData.best_wave, SaveData.total_kills]
	else:
		_stats.text = "WASD move  -  MOUSE aim  -  LEFT CLICK shoot  -  SPACE rage  (gamepad works too)"
	_first.grab_focus()
