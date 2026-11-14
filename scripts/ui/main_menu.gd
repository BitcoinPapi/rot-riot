class_name MainMenu
extends Control
## Title screen: Play (opens the map screen), then Character (the hero and his
## gear), Skills (the stat upgrades), Armory, Pets, Settings and Quit in two
## columns, with the hero standing beside them.

var main: Main
var _first: Button
var _coop: Button
var _character: Button
var _armory: Button
var _skills: Button
var _pets: Button
var _hero: TextureRect
var _stats: Label
var _progress: Label
var _notice: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(UiKit.centered(col))

	var title := UiKit.heading(Config.GAME_TITLE, 108, Color("efe6cf"))
	title.add_theme_color_override("font_shadow_color", Color(0.6, 0.06, 0.05))
	title.add_theme_constant_override("shadow_offset_x", 6)
	title.add_theme_constant_override("shadow_offset_y", 7)
	title.add_theme_constant_override("shadow_outline_size", 20)
	col.add_child(title)
	col.add_child(UiKit.heading("SURVIVE THE HORDE", 22, UiKit.GOLD))
	col.add_child(UiKit.spacer(4))

	_first = _add_button(col, "PLAY", func() -> void: main.open_screen("maps"), 510.0)
	_first.custom_minimum_size.y = 58
	_coop = _add_button(col, "PLAY WITH FRIENDS", func() -> void: main.open_screen("coop"), 510.0)
	_coop.custom_minimum_size.y = 46
	_coop.add_theme_font_size_override("font_size", 20)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(grid)
	_character = _add_button(grid, "CHARACTER", func() -> void: main.open_screen("character"))
	_skills = _add_button(grid, "SKILLS", func() -> void: main.open_screen("skills"))
	_armory = _add_button(grid, "ARMORY", func() -> void: main.open_screen("armory"))
	_pets = _add_button(grid, "PETS", func() -> void: main.open_screen("pets"))
	_add_button(grid, "SETTINGS", func() -> void: main.open_screen("settings"))
	_add_button(grid, "QUIT", func() -> void: main.quit_game())

	col.add_child(UiKit.spacer(4))
	_progress = UiKit.heading("", 21, UiKit.GOLD)
	col.add_child(_progress)
	_stats = UiKit.heading("", 16, UiKit.DIM)
	col.add_child(_stats)
	_notice = UiKit.heading("", 15, Color(1.0, 0.6, 0.45))
	col.add_child(_notice)

	# The hero, wearing whatever he has on, to the left of the buttons.
	_hero = TextureRect.new()
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.set_anchors_preset(Control.PRESET_CENTER)
	_hero.offset_left = -510.0
	_hero.offset_right = -290.0
	_hero.offset_top = -90.0
	_hero.offset_bottom = 290.0
	add_child(_hero)

	var version := UiKit.label("v" + Config.GAME_VERSION, 14, Color(1, 1, 1, 0.35))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -16
	version.offset_bottom = -10
	add_child(version)


func _add_button(parent: Control, text: String, action: Callable, width: float = 250.0) -> Button:
	var b := UiKit.button(text, action, width)
	b.custom_minimum_size.y = 52
	b.add_theme_font_size_override("font_size", 22)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(b)
	return b


## Called by Main every time this screen is shown.
func opened() -> void:
	# A number after the name means there are points waiting to be spent.
	_hero.texture = Art.t("hero_front")
	_character.text = "CHARACTER" if SaveData.gear_new <= 0 else "CHARACTER  (%d NEW)" % SaveData.gear_new
	_skills.text = "SKILLS" if SaveData.skill_points <= 0 else "SKILLS  (%d)" % SaveData.skill_points
	var weapon_points := SaveData.total_weapon_points()
	_armory.text = "ARMORY" if weapon_points <= 0 else "ARMORY  (%d)" % weapon_points
	if not SaveData.pets_unlocked():
		_pets.text = "PETS  (LEVEL %d)" % Config.PET_UNLOCK_LEVEL
	else:
		_pets.text = "PETS" if SaveData.pet_seen else "PETS  (NEW)"
	_coop.text = "PLAY WITH FRIENDS" if not Net.playing_together() else "PLAYING WITH %s" % Net.mate_names()
	_progress.text = "%s   -   LEVEL %d      COINS: %d" % [Config.HERO_NAME, SaveData.level, SaveData.coins]
	if SaveData.runs_played > 0:
		var map_index := SaveData.maps_unlocked - 1
		_stats.text = "MAP %d: %s  -  BEST WAVE %d / %d   -   BEST SCORE %d   -   ZOMBIES KILLED %d" % [
			map_index + 1, String(Config.MAPS[map_index]["name"]), SaveData.map_best_wave(map_index), Config.WAVES_PER_MAP,
			SaveData.best_score, SaveData.total_kills]
	else:
		_stats.text = "WASD move  -  MOUSE aim  -  LEFT CLICK shoot  -  R reload  (gamepad works too)"
	if SaveData.was_reset_by_update:
		_notice.text = "New progression system: your old coins and upgrades were reset."
	elif SaveData.points_returned > 0 and SaveData.skill_points > 0:
		_notice.text = "The SKILLS page is new and simpler: your %d skill points are waiting there." % SaveData.skill_points
	else:
		_notice.text = ""
	_notice.visible = _notice.text != ""
	_first.grab_focus()
