class_name GameOverScreen
extends Control
## Results after the player dies.

const STATS := ["SCORE", "WAVE REACHED", "ZOMBIES KILLED", "TIME SURVIVED", "XP EARNED", "LEVEL"]

var main: Main
var _title: Label
var _best: Label
var _values := {}     # stat name -> Label
var _coins: Label
var _hint: Label
var _character: Button
var _armory: Button
var _buttons: Array[Button] = []


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(UiKit.centered(panel))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	_title = UiKit.heading("YOU GOT EATEN", 56, UiKit.RED)
	col.add_child(_title)
	_best = UiKit.heading("NEW BEST SCORE!", 22, UiKit.GOLD)
	col.add_child(_best)

	# Two stats per line: name, value, name, value.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for stat: String in STATS:
		grid.add_child(UiKit.label(stat, 19, UiKit.DIM))
		var value := UiKit.label("0", 23, UiKit.TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(110, 0)
		grid.add_child(value)
		_values[stat] = value
	col.add_child(grid)

	col.add_child(UiKit.spacer(2))
	_coins = UiKit.heading("", 23, UiKit.GOLD)
	col.add_child(_coins)
	_hint = UiKit.heading("", 16, UiKit.GREEN)
	col.add_child(_hint)
	col.add_child(UiKit.spacer(4))

	var play := UiKit.button("PLAY AGAIN", func() -> void: main.start_run(), 452.0)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(play)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_character = UiKit.button("CHARACTER", func() -> void: main.open_screen("character"), 220.0)
	row.add_child(_character)
	_armory = UiKit.button("ARMORY", func() -> void: main.open_screen("armory"), 220.0)
	row.add_child(_armory)
	col.add_child(row)
	var menu := UiKit.button("MAIN MENU", func() -> void: main.quit_to_menu(), 452.0)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(menu)
	_buttons = [play, _character, _armory, menu]


## Fill in the numbers for the run that just ended.
func show_results(stats: Dictionary, is_best: bool) -> void:
	_best.visible = is_best
	_put("SCORE", "%d" % int(stats.get("score", 0)))
	_put("WAVE REACHED", "%d" % int(stats.get("wave", 0)))
	_put("ZOMBIES KILLED", "%d" % int(stats.get("kills", 0)))
	var seconds := int(stats.get("time", 0.0))
	_put("TIME SURVIVED", "%d:%02d" % [int(seconds / 60.0), seconds % 60])
	_put("XP EARNED", "%d" % int(stats.get("xp", 0)))
	var gained := int(stats.get("levels", 0))
	_put("LEVEL", "%d" % SaveData.level if gained <= 0 else "%d  (+%d)" % [SaveData.level, gained])
	_coins.set_meta("earned", int(stats.get("coins", 0)))
	_refresh_progress()
	# Ignore clicks for a moment so a held fire button doesn't press anything.
	for b: Button in _buttons:
		b.disabled = true
	get_tree().create_timer(0.7, true).timeout.connect(_unlock)


func _put(stat: String, text: String) -> void:
	var value: Label = _values[stat]
	value.text = text


## Coins and "points to spend" change if the player visits Character / Armory.
func _refresh_progress() -> void:
	_coins.text = "+%d COINS   (you have %d)" % [int(_coins.get_meta("earned", 0)), SaveData.coins]
	var weapon_points := SaveData.total_weapon_points()
	_character.text = "CHARACTER" if SaveData.skill_points <= 0 else "CHARACTER  (%d)" % SaveData.skill_points
	_armory.text = "ARMORY" if weapon_points <= 0 else "ARMORY  (%d)" % weapon_points
	var parts: Array[String] = []
	if SaveData.skill_points > 0:
		parts.append("%d skill point%s" % [SaveData.skill_points, "" if SaveData.skill_points == 1 else "s"])
	if weapon_points > 0:
		parts.append("%d weapon point%s" % [weapon_points, "" if weapon_points == 1 else "s"])
	_hint.text = "" if parts.is_empty() else "You have %s to spend" % " and ".join(parts)
	_hint.visible = not parts.is_empty()


func _unlock() -> void:
	for b: Button in _buttons:
		b.disabled = false
	if visible:
		_buttons[0].grab_focus()


func opened() -> void:
	_refresh_progress()
	if not _buttons[0].disabled:
		_buttons[0].grab_focus()
