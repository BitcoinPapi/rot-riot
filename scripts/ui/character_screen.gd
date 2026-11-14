class_name CharacterScreen
extends Control
## The character sheet: level, XP, and the passive stats that skill points
## are spent on. Skill points come from levelling up, and more can be bought
## with coins at a price that keeps rising. All numbers are in Config
## (PROGRESSION section); the stored values live in SaveData.

var main: Main
var _level: Label
var _xp_bar: UiKit.Bar
var _xp_text: Label
var _coins: Label
var _base: Label
var _points: Label
var _rows := {}          # passive id -> {"rank": Label, "effect": Label, "plus": Button}
var _buy: Button
var _reset: Button
var _back: Button
var _reset_armed := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(UiKit.centered(panel))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	col.add_child(UiKit.heading("CHARACTER", 44))

	# Level, XP bar and coins on one line.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	_level = UiKit.label("LEVEL 1", 30, UiKit.GOLD)
	top.add_child(_level)
	var xp_col := VBoxContainer.new()
	xp_col.add_theme_constant_override("separation", 2)
	xp_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar = UiKit.Bar.new()
	_xp_bar.custom_minimum_size = Vector2(420, 16)
	xp_col.add_child(_xp_bar)
	_xp_text = UiKit.label("", 14, UiKit.DIM)
	xp_col.add_child(_xp_text)
	top.add_child(xp_col)
	var counter := UiKit.coin_counter(28)
	_coins = counter[1]
	top.add_child(counter[0])
	col.add_child(top)

	_base = UiKit.heading("", 15, UiKit.DIM)
	col.add_child(_base)
	_points = UiKit.heading("", 24, UiKit.GOLD)
	col.add_child(_points)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	for id: String in Config.PASSIVE_ORDER:
		grid.add_child(_build_card(id))
	col.add_child(grid)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	_buy = UiKit.button("", _on_buy, 330.0)
	footer.add_child(_buy)
	_reset = UiKit.button("", _on_reset, 300.0)
	footer.add_child(_reset)
	_back = UiKit.button("BACK", func() -> void: main.close_screen(), 200.0)
	footer.add_child(_back)
	col.add_child(UiKit.spacer(2))
	col.add_child(footer)


func _build_card(id: String) -> Control:
	var cfg: Dictionary = Config.PASSIVES[id]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.small_panel_style())
	card.custom_minimum_size = Vector2(470, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	title.add_child(UiKit.label(String(cfg["name"]), 21, UiKit.TEXT))
	var rank := UiKit.label("", 15, UiKit.DIM)
	rank.size_flags_vertical = Control.SIZE_SHRINK_END
	title.add_child(rank)
	text.add_child(title)
	var effect := UiKit.label("", 16, UiKit.GREEN)
	text.add_child(effect)
	text.add_child(UiKit.label(String(cfg["desc"]), 13, UiKit.DIM))
	row.add_child(text)

	var plus := UiKit.button("+1", func() -> void: _on_raise(id), 112.0)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(plus)

	_rows[id] = {"rank": rank, "effect": effect, "plus": plus}
	return card


func _on_raise(id: String) -> void:
	if SaveData.raise_passive(id):
		Sfx.play("ui_buy")
	else:
		Sfx.play("ui_deny")
	_refresh()
	var plus: Button = _rows[id]["plus"]
	if plus.disabled:
		_focus_fallback()


func _on_buy() -> void:
	if SaveData.buy_skill_point():
		Sfx.play("ui_buy")
	else:
		Sfx.play("ui_deny")
	_refresh()
	if _buy.disabled:
		_focus_fallback()


## Resetting costs coins, so it asks once before doing it.
func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_refresh()
		return
	_reset_armed = false
	if SaveData.respec():
		Sfx.play("ui_buy")
	else:
		Sfx.play("ui_deny")
	_refresh()
	if _reset.disabled:
		_focus_fallback()


func _focus_fallback() -> void:
	for id: String in Config.PASSIVE_ORDER:
		var plus: Button = _rows[id]["plus"]
		if not plus.disabled:
			plus.grab_focus()
			return
	if not _buy.disabled:
		_buy.grab_focus()
	else:
		_back.grab_focus()


func _refresh() -> void:
	_level.text = "LEVEL %d" % SaveData.level
	if SaveData.at_level_cap():
		_xp_bar.set_fraction(1.0)
		_xp_text.text = "Maximum level reached"
	else:
		_xp_bar.set_fraction(float(SaveData.xp) / float(SaveData.xp_needed()))
		_xp_text.text = "%d / %d XP to level %d   (the highest level is %d)" % [
				SaveData.xp, SaveData.xp_needed(), SaveData.level + 1, Config.LEVEL_CAP]
	_coins.text = "%d" % SaveData.coins
	var levels := SaveData.level - 1
	_base.text = "Every level gives +%d max health, +%d%% damage and a skill point.   From levels so far: +%d health, +%d%% damage" % [
		int(Config.LEVEL_HP_PER_LEVEL), int(round(Config.LEVEL_DAMAGE_PER_LEVEL * 100.0)),
		int(Config.LEVEL_HP_PER_LEVEL * levels), int(round(Config.LEVEL_DAMAGE_PER_LEVEL * levels * 100.0))]
	_points.text = "SKILL POINTS: %d" % SaveData.skill_points

	for id: String in Config.PASSIVE_ORDER:
		var row: Dictionary = _rows[id]
		var rank: Label = row["rank"]
		var effect: Label = row["effect"]
		var plus: Button = row["plus"]
		var cost := SaveData.passive_cost(id)
		rank.text = "rank %d" % SaveData.passive_rank(id)
		# Show what the stat gives now and what one more rank would give.
		var next_value := Config.stat_value(Config.PASSIVES[id], SaveData.passive_rank(id) + 1)
		effect.text = "%s    (next %s)" % [PlayerStats.describe_passive(id, SaveData.passive_value(id)),
				PlayerStats.describe_passive(id, next_value).get_slice(" ", 0)]
		plus.text = "+1" if cost == 1 else "+1  (%d pts)" % cost
		plus.disabled = SaveData.skill_points < cost

	var price := SaveData.skill_point_price()
	_buy.text = "BUY SKILL POINT   %d" % price
	_buy.disabled = SaveData.coins < price
	var respec := SaveData.respec_price()
	_reset.text = ("SURE?   %d coins" if _reset_armed else "RESET POINTS   %d") % respec
	_reset.disabled = SaveData.spent_points() <= 0 or SaveData.coins < respec


func opened() -> void:
	_reset_armed = false
	_refresh()
	_focus_fallback()
