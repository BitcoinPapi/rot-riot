class_name SkillScreen
extends Control
## The Skills page: a plain list of the character's stats, like the weapon
## upgrades in the Armory. Every stat is one row - what it is, how many ranks
## are bought, what it gives now and what the next rank would give - with a
## "+1" button that spends skill points (one per character level).
##
## Buy Config.KEYSTONE_RANK ranks of a stat and its special power is yours;
## the star at the end of each row shows it. Ranks have no upper limit.
## The numbers are in Config (PASSIVES, SKILLS, KEYSTONES); what has been
## bought lives in SaveData.skills.

var main: Main
var _level: Label
var _xp_bar: UiKit.Bar
var _xp_text: Label
var _points: Label
var _coins: Label
var _notice: Label
var _rows := {}               # stat id -> {"pips", "rank", "effect", "next", "power", "plus", "name"}
var _about: Label             # what the row under the pointer is about (its special power, the pet's tricks)
var _buy: Button
var _reset: Button
var _back: Button
var _reset_armed := false
var _shown := ""


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(UiKit.centered(panel))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)

	# Title, level, points.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 26)
	col.add_child(head)
	head.add_child(UiKit.label("SKILLS", 40))
	var level_box := VBoxContainer.new()
	level_box.add_theme_constant_override("separation", 1)
	level_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_level = UiKit.label("", 22, UiKit.GOLD)
	level_box.add_child(_level)
	_xp_bar = UiKit.Bar.new()
	_xp_bar.custom_minimum_size = Vector2(360, 10)
	_xp_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	level_box.add_child(_xp_bar)
	_xp_text = UiKit.label("", 13, UiKit.DIM)
	level_box.add_child(_xp_text)
	head.add_child(level_box)
	var wallet := VBoxContainer.new()
	wallet.add_theme_constant_override("separation", -4)
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wallet.add_child(UiKit.label("SKILL POINTS", 13, UiKit.DIM))
	_points = UiKit.label("0", 38, UiKit.GOLD)
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wallet.add_child(_points)
	head.add_child(wallet)
	var counter := UiKit.coin_counter(24)
	_coins = counter[1]
	(counter[0] as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(counter[0])

	_notice = UiKit.label("", 14, UiKit.GOLD)
	col.add_child(_notice)

	# One row per stat, in three groups.
	for group: Dictionary in Config.SKILL_GROUPS:
		col.add_child(_section("%s  -  %s" % [String(group["name"]), String(group["desc"])], group["color"]))
		for stat: String in group["stats"]:
			col.add_child(_build_row(stat))

	# What the row under the pointer is about.
	_about = UiKit.label("", 14, UiKit.TEXT)
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size = Vector2(1040, 38)
	col.add_child(_about)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(buttons)
	_back = UiKit.button("BACK", func() -> void: main.close_screen(), 220.0)
	buttons.add_child(_back)
	_buy = UiKit.button("", _on_buy, 400.0)
	buttons.add_child(_buy)
	_reset = UiKit.button("", _on_reset, 400.0)
	buttons.add_child(_reset)
	for b: Button in [_back, _buy, _reset]:
		b.custom_minimum_size.y = 40
		b.add_theme_font_size_override("font_size", 17)


## A small coloured heading with a line under it.
static func _section(text: String, color: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.add_child(UiKit.label(text, 15, color))
	var line := ColorRect.new()
	line.color = Color(color.r, color.g, color.b, 0.35)
	line.custom_minimum_size = Vector2(0, 2)
	box.add_child(line)
	return box


func _build_row(stat: String) -> Control:
	var def: Dictionary = Config.PASSIVES[stat]
	var color: Color = def["color"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.mouse_entered.connect(func() -> void: _show(stat))

	var icon := TextureRect.new()
	icon.texture = Art.t("stat_" + stat)
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = color
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -3)
	text.custom_minimum_size = Vector2(310, 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stat_name := UiKit.label(String(def["name"]), 18, color)
	text.add_child(stat_name)
	var about_stat := UiKit.label(String(def["desc"]), 12, UiKit.DIM)
	about_stat.clip_text = true
	about_stat.custom_minimum_size = Vector2(310, 0)
	text.add_child(about_stat)
	row.add_child(text)

	var pips := ArmoryScreen.Pips.new()
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pips)
	var rank := UiKit.label("", 15, UiKit.DIM)
	rank.custom_minimum_size = Vector2(62, 0)
	rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rank)

	# What it gives now, and under it what the next rank would give.
	var gives := VBoxContainer.new()
	gives.add_theme_constant_override("separation", -3)
	gives.custom_minimum_size = Vector2(220, 0)
	gives.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gives.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var effect := UiKit.label("", 17, UiKit.GREEN)
	gives.add_child(effect)
	var next := UiKit.label("", 12, UiKit.DIM)
	gives.add_child(next)
	row.add_child(gives)

	# Its special power: a star that lights up at Config.KEYSTONE_RANK ranks.
	var power := UiKit.label("", 13, UiKit.DIM)
	power.custom_minimum_size = Vector2(190, 0)
	power.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	power.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(power)

	var plus := UiKit.button("+1", func() -> void: _on_raise(stat), 140.0)
	plus.custom_minimum_size = Vector2(140, 34)
	plus.add_theme_font_size_override("font_size", 16)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus.focus_entered.connect(func() -> void: _show(stat))
	row.add_child(plus)
	_rows[stat] = {"pips": pips, "rank": rank, "effect": effect, "next": next, "power": power, "plus": plus, "name": stat_name}
	return row


# ----------------------------------------------------------------------------
#  Actions
# ----------------------------------------------------------------------------
func _on_raise(stat: String) -> void:
	_reset_armed = false
	var had_power := SaveData.has_keystone(stat)
	if SaveData.raise_skill(stat):
		Sfx.play("ui_buy")
		if SaveData.has_keystone(stat) and not had_power:
			Sfx.play("level_up", -4.0)       # a special power has just been won
	else:
		Sfx.play("ui_deny")
	_shown = stat
	_refresh()
	if (_rows[stat]["plus"] as Button).disabled:
		_focus_first_action()


func _on_buy() -> void:
	_reset_armed = false
	if SaveData.buy_skill_point():
		Sfx.play("ui_buy")
	else:
		Sfx.play("ui_deny")
	_refresh()


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
		_focus_first_action()


## Put the highlight on the first rank that can be bought (else on BACK).
func _focus_first_action() -> void:
	for stat: String in Config.PASSIVE_ORDER:
		var plus: Button = _rows[stat]["plus"]
		if not plus.disabled:
			plus.grab_focus()
			return
	_back.grab_focus()


# ----------------------------------------------------------------------------
#  Display
# ----------------------------------------------------------------------------
## Describe a row in the strip at the bottom: its special power, and for the
## pet's stat the tricks it teaches.
func _show(stat: String) -> void:
	_shown = stat
	var def: Dictionary = Config.PASSIVES[stat]
	var key: Dictionary = Config.KEYSTONES[stat]
	var have := SaveData.skill_rank(stat)
	var lines: Array[String] = []
	if SaveData.has_keystone(stat):
		lines.append("%s  -  yours:  %s" % [String(key["name"]), Config.keystone_text(stat)])
	else:
		lines.append("At rank %d of %s you get  %s:  %s   (%d to go)" % [Config.KEYSTONE_RANK, String(def["name"]),
				String(key["name"]), Config.keystone_text(stat), Config.KEYSTONE_RANK - have])
	if stat == "bond":
		var tricks: Array[String] = []
		for i in Config.PET_TRICKS.size():
			tricks.append("%s at rank %d%s" % [String(Config.PET_TRICKS[i]["id"]).to_upper(), int(Config.PET_TRICK_RANKS[i]),
					" (learned)" if SaveData.has_pet_trick(i) else ""])
		lines.append("Your pet learns tricks:  " + ",  ".join(tricks) + ".")
	_about.text = "\n".join(lines)
	_about.add_theme_color_override("font_color", (def["color"] as Color).lightened(0.35))


func _refresh() -> void:
	_level.text = "LEVEL %d" % SaveData.level
	if SaveData.at_level_cap():
		_xp_bar.set_fraction(1.0)
		_xp_text.text = "Maximum level reached"
	else:
		_xp_bar.set_fraction(float(SaveData.xp) / float(SaveData.xp_needed()))
		_xp_text.text = "%d / %d XP to level %d   -   every level gives a skill point" % [SaveData.xp, SaveData.xp_needed(), SaveData.level + 1]
	_points.text = "%d" % SaveData.skill_points
	_coins.text = "%d" % SaveData.coins
	_notice.text = "The skills page is new and simpler: %d skill points were handed back to you. Spend them here." % SaveData.points_returned \
			if SaveData.points_returned > 0 else ""
	_notice.visible = _notice.text != ""

	for stat: String in Config.PASSIVE_ORDER:
		var r: Dictionary = _rows[stat]
		var def: Dictionary = Config.PASSIVES[stat]
		var color: Color = def["color"]
		var bought := SaveData.skill_rank(stat)
		var total := SaveData.passive_rank(stat)          # with what the gear adds
		var cost := SaveData.skill_cost(stat)
		var status := SaveData.skill_status(stat)
		(r["pips"] as ArmoryScreen.Pips).set_filled(mini(bought, ArmoryScreen.Pips.COUNT), color)
		(r["rank"] as Label).text = "rank %d" % bought
		(r["effect"] as Label).text = PlayerStats.describe_passive(stat, Config.stat_value(def, total))
		(r["next"] as Label).text = "next rank: %s%s" % [PlayerStats.describe_passive(stat, Config.stat_value(def, total + 1)).get_slice(" ", 0),
				"" if total == bought else "   (gear adds %d)" % (total - bought)]
		# The special power.
		var power: Label = r["power"]
		var key_name := String(Config.KEYSTONES[stat]["name"])
		if SaveData.has_keystone(stat):
			power.text = "*  %s" % key_name
			power.add_theme_color_override("font_color", UiKit.GOLD)
		else:
			power.text = "%s  at rank %d" % [key_name, Config.KEYSTONE_RANK]
			power.add_theme_color_override("font_color", UiKit.DIM)
		var plus: Button = r["plus"]
		match status:
			"level":
				plus.text = "LEVEL %d" % int(def.get("min_level", 1))
			_:
				plus.text = "+1   (%d pt%s)" % [cost, "" if cost == 1 else "s"]
		plus.disabled = status != "ready"

	_buy.text = "BUY A SKILL POINT   %d coins" % SaveData.skill_point_price()
	_buy.disabled = SaveData.coins < SaveData.skill_point_price()
	var price := SaveData.respec_price()
	_reset.text = ("SURE?   %d coins" if _reset_armed else "TAKE ALL POINTS BACK   %d coins") % price
	_reset.disabled = SaveData.spent_points() <= 0 or SaveData.coins < price
	_show(_shown if _shown != "" else Config.PASSIVE_ORDER[0])


## Called by Main every time this screen is shown.
func opened() -> void:
	_reset_armed = false
	_refresh()
	_focus_first_action()
