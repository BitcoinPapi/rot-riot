class_name ArmoryScreen
extends Control
## Weapon upgrades. Every weapon has its own level: kills made with it give it
## XP, and each weapon level gives one point that can only be spent on that
## weapon (power, shooting speed, stability, spawn rate, duration).

var main: Main
var _selected := "pistol"
var _weapon_buttons := {}     # weapon id -> Button
var _icon: TextureRect
var _name: Label
var _level: Label
var _xp_bar: UiKit.Bar
var _xp_text: Label
var _points: Label
var _crate: Label
var _track_box: VBoxContainer
var _track_rows := {}         # track id -> {"rank": Label, "effect": Label, "plus": Button}
var _back: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(UiKit.centered(panel))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	col.add_child(UiKit.heading("ARMORY", 44))
	col.add_child(UiKit.heading("Weapons level up from the kills you make with them. Each level gives a point for that weapon.", 15, UiKit.DIM))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	col.add_child(body)

	# Left: the weapon list.
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 5)
	for id: String in Config.WEAPON_ORDER:
		var b := UiKit.button("", func() -> void: _on_weapon_pressed(id), 330.0)
		b.custom_minimum_size = Vector2(330, 42)
		b.add_theme_font_size_override("font_size", 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_entered.connect(func() -> void: _select(id))
		list.add_child(b)
		_weapon_buttons[id] = b
	body.add_child(list)

	# Right: the selected weapon.
	var detail_panel := PanelContainer.new()
	detail_panel.add_theme_stylebox_override("panel", UiKit.small_panel_style())
	detail_panel.custom_minimum_size = Vector2(600, 430)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 6)
	detail_panel.add_child(detail)
	body.add_child(detail_panel)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(220, 80)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_icon)
	var head_text := VBoxContainer.new()
	head_text.add_theme_constant_override("separation", 2)
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 14)
	_name = UiKit.label("", 26)
	name_row.add_child(_name)
	_level = UiKit.label("", 22, UiKit.GOLD)
	name_row.add_child(_level)
	head_text.add_child(name_row)
	_xp_bar = UiKit.Bar.new()
	_xp_bar.custom_minimum_size = Vector2(320, 14)
	head_text.add_child(_xp_bar)
	_xp_text = UiKit.label("", 13, UiKit.DIM)
	head_text.add_child(_xp_text)
	head.add_child(head_text)
	detail.add_child(head)

	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 30)
	_points = UiKit.label("", 21, UiKit.GOLD)
	info.add_child(_points)
	_crate = UiKit.label("", 15, UiKit.DIM)
	_crate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(_crate)
	detail.add_child(info)

	_track_box = VBoxContainer.new()
	_track_box.add_theme_constant_override("separation", 3)
	detail.add_child(_track_box)

	_back = UiKit.button("BACK", func() -> void: main.close_screen())
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_back)


func _on_weapon_pressed(id: String) -> void:
	_select(id)
	# Jump across to the first upgrade that can be bought.
	for track: String in Config.weapon_tracks(id):
		var plus: Button = _track_rows[track]["plus"]
		if not plus.disabled:
			plus.grab_focus()
			return


func _select(id: String) -> void:
	if id != _selected or _track_rows.is_empty():
		_selected = id
		_build_tracks()
	_refresh()


func _build_tracks() -> void:
	for child: Node in _track_box.get_children():
		_track_box.remove_child(child)
		child.queue_free()
	_track_rows.clear()
	for track: String in Config.weapon_tracks(_selected):
		var cfg: Dictionary = Config.WEAPON_TRACKS[track]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := HBoxContainer.new()
		title.add_theme_constant_override("separation", 10)
		title.add_child(UiKit.label(String(cfg["name"]), 19))
		var rank := UiKit.label("", 14, UiKit.DIM)
		rank.size_flags_vertical = Control.SIZE_SHRINK_END
		title.add_child(rank)
		text.add_child(title)
		var effect := UiKit.label("", 15, UiKit.GREEN)
		text.add_child(effect)
		row.add_child(text)
		var plus := UiKit.button("+1", func() -> void: _on_raise(track), 112.0)
		plus.custom_minimum_size = Vector2(112, 40)
		plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(plus)
		_track_box.add_child(row)
		_track_rows[track] = {"rank": rank, "effect": effect, "plus": plus, "desc": String(cfg["desc"])}


func _on_raise(track: String) -> void:
	if SaveData.raise_weapon_track(_selected, track):
		Sfx.play("ui_buy")
	else:
		Sfx.play("ui_deny")
	_refresh()
	var plus: Button = _track_rows[track]["plus"]
	if plus.disabled:
		var current: Button = _weapon_buttons[_selected]
		current.grab_focus()


## Share of crates that hold this weapon, counting rarity and SPAWN RATE upgrades.
func _crate_share(id: String) -> float:
	var total := 0.0
	var mine := 0.0
	for other: String in Config.CRATE_WEAPONS:
		var weight: float = Config.crate_weight(other) * (1.0 + SaveData.weapon_value(other, "spawn"))
		total += weight
		if other == id:
			mine = weight
	return mine / total if total > 0.0 else 0.0


func _refresh() -> void:
	for id: String in Config.WEAPON_ORDER:
		var b: Button = _weapon_buttons[id]
		var points := SaveData.weapon_points(id)
		var badge := "   (%d)" % points if points > 0 else ""
		b.text = "%s    LV %d%s" % [String(Config.WEAPONS[id]["name"]), SaveData.weapon_level(id), badge]

	var w: Dictionary = Config.WEAPONS[_selected]
	_icon.texture = Art.t("icon_" + _selected)
	_name.text = String(w["name"])
	_name.add_theme_color_override("font_color", w["color"])
	_level.text = "LEVEL %d" % SaveData.weapon_level(_selected)
	_xp_bar.fill = w["color"]
	_xp_bar.set_fraction(float(SaveData.weapon_xp(_selected)) / float(SaveData.weapon_xp_needed(_selected)))
	_xp_text.text = "%d / %d XP to level %d" % [SaveData.weapon_xp(_selected), SaveData.weapon_xp_needed(_selected),
			SaveData.weapon_level(_selected) + 1]
	var points_now := SaveData.weapon_points(_selected)
	_points.text = "WEAPON POINTS: %d" % points_now
	var rarity: Dictionary = Config.CRATE_RARITIES[String(w["rarity"])]
	var dual_note := "   -   can be dual wielded" if bool(w["dual"]) else ""
	if _selected == Config.STARTER_WEAPON:
		_crate.text = "Always with you. A pistol crate (%d%% of crates) gives a second one." % int(round(_crate_share(_selected) * 100.0))
		_crate.add_theme_color_override("font_color", UiKit.DIM)
	else:
		_crate.text = "%s  -  in %d%% of crates%s" % [String(rarity["name"]), int(round(_crate_share(_selected) * 100.0)), dual_note]
		_crate.add_theme_color_override("font_color", rarity["color"])

	for track: String in _track_rows.keys():
		var row: Dictionary = _track_rows[track]
		var rank: Label = row["rank"]
		var effect: Label = row["effect"]
		var plus: Button = row["plus"]
		var cost := SaveData.weapon_rank_cost(_selected, track)
		rank.text = "rank %d" % SaveData.weapon_rank(_selected, track)
		var next_value := Config.stat_value(Config.WEAPON_TRACKS[track], SaveData.weapon_rank(_selected, track) + 1)
		effect.text = "%s    (next %s)    %s" % [PlayerStats.describe_track(track, SaveData.weapon_value(_selected, track)),
				PlayerStats.describe_track(track, next_value).get_slice(" ", 0), String(row["desc"])]
		plus.text = "+1" if cost == 1 else "+1  (%d pts)" % cost
		plus.disabled = points_now < cost


func opened() -> void:
	# Open on a weapon that has points to spend, if there is one.
	var start := _selected
	for id: String in Config.WEAPON_ORDER:
		if SaveData.weapon_points(id) > 0:
			start = id
			break
	_selected = ""
	_select(start)
	var b: Button = _weapon_buttons[start]
	b.grab_focus()
