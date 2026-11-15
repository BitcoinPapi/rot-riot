class_name GameOverScreen
extends Control
## Results after a run: the player died, or cleared the map's last wave.

const STATS := ["SCORE", "WAVE REACHED", "ZOMBIES KILLED", "TIME SURVIVED", "XP EARNED", "LEVEL"]

var main: Main
var _title: Label
var _map: Label
var _news: Label                  # a checkpoint or a new map was unlocked
var _best: Label
var _again: Button
var _onward: Button               # "start from the new checkpoint" / "next map"
var _onward_map := 0
var _onward_wave := 1
var _values := {}     # stat name -> Label
var _coins: Label
var _hint: Label
var _character: Button
var _armory: Button
var _skills: Button
var _loot: Label                  # gear found in the run
var _buttons: Array[Button] = []
var _maps: Button
var _guest := false               # a co-op run as the joiner: the host starts the next one


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(UiKit.centered(panel))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	_title = UiKit.heading("YOU GOT EATEN", 50, UiKit.RED)
	col.add_child(_title)
	_map = UiKit.heading("", 18, UiKit.DIM)
	col.add_child(_map)
	_news = UiKit.heading("", 20, UiKit.GOLD)
	col.add_child(_news)
	_best = UiKit.heading("NEW BEST SCORE!", 20, UiKit.GOLD)
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
	_loot = UiKit.heading("", 16, Color(0.75, 0.85, 1.0))
	_loot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loot.custom_minimum_size = Vector2(560, 0)
	col.add_child(_loot)
	_hint = UiKit.heading("", 16, UiKit.GREEN)
	col.add_child(_hint)

	_again = UiKit.button("PLAY AGAIN", func() -> void: main.start_run(), 452.0)
	_again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_again)
	_onward = UiKit.button("", func() -> void: main.start_run(_onward_map, _onward_wave), 452.0)
	_onward.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_onward)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_character = UiKit.button("CHARACTER", func() -> void: main.open_screen("character"), 166.0)
	row.add_child(_character)
	_skills = UiKit.button("SKILLS", func() -> void: main.open_screen("skills"), 126.0)
	row.add_child(_skills)
	_armory = UiKit.button("ARMORY", func() -> void: main.open_screen("armory"), 136.0)
	row.add_child(_armory)
	for small: Button in [_character, _skills, _armory]:
		small.add_theme_font_size_override("font_size", 18)
	col.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	var maps := UiKit.button("MAPS", func() -> void: main.open_screen("maps"), 220.0)
	_maps = maps
	row2.add_child(maps)
	var menu := UiKit.button("MAIN MENU", func() -> void: main.quit_to_menu(), 220.0)
	row2.add_child(menu)
	col.add_child(row2)
	_buttons = [_again, _onward, _character, _skills, _armory, maps, menu]


## Fill in the numbers for the run that just ended.
func show_results(stats: Dictionary, is_best: bool) -> void:
	var map_index := int(stats.get("map", 0))
	var map_def: Dictionary = Config.MAPS[map_index]
	var start := int(stats.get("start", 1))
	var won := bool(stats.get("victory", false))
	var unlocked := int(stats.get("unlocked", -1))
	var checkpoint := int(stats.get("checkpoint", 0))
	_title.text = "ZONE TAKEN BACK!" if won else "YOU GOT EATEN"
	_title.add_theme_color_override("font_color", UiKit.GOLD if won else UiKit.RED)
	_map.text = "ZONE %d  -  %s" % [map_index + 1, String(map_def["name"])]
	# A run with a friend: all gold was shared, and the host starts the next one.
	var together := bool(stats.get("coop", false))
	_guest = together and Net.playing_together() and not Net.is_host()
	if together:
		_map.text += "   -   with %s (all gold shared)" % String(stats.get("mate", "a friend"))
	if unlocked >= 0:
		_news.text = "NEW ZONE OPEN:  %s" % String(Config.MAPS[unlocked]["name"])
	elif checkpoint > 0:
		_news.text = "CHECKPOINT REACHED:  you can now start from wave %d" % checkpoint
	else:
		_news.text = ""
	_news.visible = _news.text != ""
	_best.visible = is_best

	# The second button is the way onward: the next map after a victory,
	# otherwise the latest starting wave if this run began before it.
	var waves := SaveData.map_checkpoints(map_index)
	var latest: int = waves[waves.size() - 1]
	_again.text = "PLAY AGAIN" if start <= 1 else "PLAY AGAIN  (FROM WAVE %d)" % start
	if won and SaveData.map_unlocked(map_index + 1):
		_onward_map = map_index + 1
		_onward_wave = 1
		_onward.text = "NEXT ZONE:  %s" % String(Config.MAPS[map_index + 1]["name"])
		_onward.visible = true
	elif latest > start:
		_onward_map = map_index
		_onward_wave = latest
		_onward.text = "START FROM WAVE %d" % latest
		_onward.visible = true
	else:
		_onward.visible = false

	var found: Array[String] = []
	for key: Variant in (stats.get("gear", []) as Array):
		found.append(Config.gear_name(String(key)))
	var lines: Array[String] = []
	var chest_total := int(stats.get("chests_total", 0))
	if chest_total > 0:
		lines.append("TREASURE CHESTS OPENED:  %d of %d     MAP EXPLORED:  %d%%" % [
				int(stats.get("chests", 0)), chest_total, int(floor(float(stats.get("explored", 0.0)) * 100.0))])
	if not found.is_empty():
		lines.append("GEAR FOUND:  %s" % ",  ".join(found))
	_loot.text = "\n".join(lines)
	_loot.visible = not lines.is_empty()
	if _guest:
		_again.text = "%s STARTS THE NEXT RUN" % Net.name_of(0)
		_onward.visible = false

	_put("SCORE", "%d" % int(stats.get("score", 0)))
	_put("WAVE REACHED", "%d / %d" % [int(stats.get("wave", 0)), Config.WAVES_PER_MAP])
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
	_character.text = "CHARACTER" if SaveData.gear_new <= 0 else "CHARACTER  (%d)" % SaveData.gear_new
	_skills.text = "SKILLS" if SaveData.skill_points <= 0 else "SKILLS  (%d)" % SaveData.skill_points
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
		b.disabled = _guest and (b == _again or b == _maps)
	if visible:
		(_buttons[2] if _guest else _buttons[0]).grab_focus()


func opened() -> void:
	_refresh_progress()
	if not _buttons[0].disabled:
		_buttons[0].grab_focus()
