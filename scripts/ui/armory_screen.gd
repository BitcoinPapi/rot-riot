class_name ArmoryScreen
extends Control
## The Armory: one plain page per weapon. Every weapon has its own level
## (from kills made with it) and gets a weapon point per level. Points buy
## ranks of its upgrades - one row each, with a "+" button - and three perks
## that open at certain weapon levels.
## The numbers are in Config (WEAPON_TRACKS, WEAPON UPGRADES, WEAPON_PERKS);
## what has been bought lives in SaveData.

const LIST_WIDTH := 236.0


## A row of small squares: how many ranks of an upgrade are bought.
class Pips extends Control:
	const COUNT := 10          # squares in a row (ranks beyond that still count, they just are not drawn)
	var filled := 0
	var color := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(COUNT * 17.0, 16.0)

	func set_filled(count: int, pip_color: Color) -> void:
		filled = count
		color = pip_color
		queue_redraw()

	func _draw() -> void:
		for i in COUNT:
			var box := Rect2(i * 17.0, 2.0, 13.0, 12.0)
			draw_rect(box, Color(0, 0, 0, 0.6))
			if i < filled:
				draw_rect(box.grow(-1.0), color)
				draw_rect(Rect2(box.position + Vector2(1, 1), Vector2(11.0, 4.0)), Color(1, 1, 1, 0.22))
			else:
				draw_rect(box.grow(-1.0), Color(color.r, color.g, color.b, 0.13))


var main: Main
var _selected := ""
var _weapon_buttons := {}     # weapon id -> Button
var _notice: Label
var _icon: TextureRect
var _name: Label
var _level: Label
var _xp_bar: UiKit.Bar
var _xp_text: Label
var _crate: Label
var _points: Label
var _rows := {}               # track -> {"row", "pips", "rank", "effect", "next", "plus"}
var _perks: Array = []        # per perk: {"card", "name", "desc", "buy"}
var _reset: Button
var _back: Button
var _reset_armed := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	# --- left: the weapons ---
	var list_panel := PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	row.add_child(list_panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 5)
	list_panel.add_child(list)
	list.add_child(UiKit.heading("ARMORY", 30))
	var blurb := UiKit.heading("Kills level a weapon up. Every level is a point to spend on it.", 12, UiKit.DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(LIST_WIDTH - 50.0, 0)
	list.add_child(blurb)
	for id: String in Config.WEAPON_ORDER:
		var b := UiKit.button("", func() -> void: _on_weapon_pressed(id), LIST_WIDTH - 50.0)
		b.custom_minimum_size = Vector2(LIST_WIDTH - 50.0, 42)
		b.add_theme_font_size_override("font_size", 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Keyboard / gamepad: moving onto a weapon shows it. (With the mouse
		# you click, so that crossing the list does not flip pages.)
		b.focus_entered.connect(func() -> void:
			if not b.is_hovered():
				_select(id))
		list.add_child(b)
		_weapon_buttons[id] = b
	var list_filler := Control.new()
	list_filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_child(list_filler)
	_back = UiKit.button("BACK", func() -> void: main.close_screen(), LIST_WIDTH - 50.0)
	_back.custom_minimum_size.y = 46
	list.add_child(_back)

	# --- right: the selected weapon ---
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	# Picture, name, level.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 22)
	col.add_child(head)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(286, 104)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_icon)
	var head_text := VBoxContainer.new()
	head_text.add_theme_constant_override("separation", 3)
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(head_text)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 16)
	_name = UiKit.label("", 34)
	title.add_child(_name)
	_level = UiKit.label("", 24, UiKit.GOLD)
	_level.size_flags_vertical = Control.SIZE_SHRINK_END
	title.add_child(_level)
	head_text.add_child(title)
	_xp_bar = UiKit.Bar.new()
	_xp_bar.custom_minimum_size = Vector2(320, 12)
	_xp_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	head_text.add_child(_xp_bar)
	_xp_text = UiKit.label("", 13, UiKit.DIM)
	head_text.add_child(_xp_text)
	_crate = UiKit.label("", 13, UiKit.DIM)
	head_text.add_child(_crate)
	var wallet := VBoxContainer.new()
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wallet.add_child(UiKit.label("WEAPON POINTS", 13, UiKit.DIM))
	_points = UiKit.label("0", 44, UiKit.GOLD)
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wallet.add_child(_points)
	head.add_child(wallet)

	_notice = UiKit.label("", 14, UiKit.GOLD)
	col.add_child(_notice)

	# One row per upgrade.
	col.add_child(_section("UPGRADES"))
	for track: String in Config.WEAPON_TRACK_ORDER:
		col.add_child(_build_row(track))

	# Three perks.
	col.add_child(UiKit.spacer(2))
	col.add_child(_section("PERKS  -  each one changes how the weapon works"))
	var perk_row := HBoxContainer.new()
	perk_row.add_theme_constant_override("separation", 10)
	col.add_child(perk_row)
	for i in Config.WEAPON_PERK_COST.size():
		perk_row.add_child(_build_perk(i))

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(filler)
	_reset = UiKit.button("", _on_reset, 320.0)
	_reset.custom_minimum_size.y = 40
	_reset.add_theme_font_size_override("font_size", 16)
	_reset.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_child(_reset)


## A small heading with a line under it.
static func _section(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(UiKit.label(text, 14, UiKit.DIM))
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	line.custom_minimum_size = Vector2(0, 2)
	box.add_child(line)
	return box


func _build_row(track: String) -> Control:
	var cfg: Dictionary = Config.WEAPON_TRACKS[track]
	var color: Color = cfg["color"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var icon := TextureRect.new()
	icon.texture = Art.t("track_" + track)
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = color
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -2)
	text.custom_minimum_size = Vector2(200, 0)
	text.add_child(UiKit.label(String(cfg["name"]), 19, color))
	text.add_child(UiKit.label(String(cfg["desc"]), 12, UiKit.DIM))
	row.add_child(text)
	var pips := Pips.new()
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pips)
	var rank := UiKit.label("", 15, UiKit.DIM)
	rank.custom_minimum_size = Vector2(64, 0)
	rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rank)
	# What it gives now, and under it what the next rank would give.
	var gives := VBoxContainer.new()
	gives.add_theme_constant_override("separation", -2)
	gives.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gives.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var effect := UiKit.label("", 18, UiKit.GREEN)
	gives.add_child(effect)
	var next := UiKit.label("", 12, UiKit.DIM)
	gives.add_child(next)
	row.add_child(gives)
	var plus := UiKit.button("+1", func() -> void: _on_raise(track), 132.0)
	plus.custom_minimum_size = Vector2(132, 40)
	plus.add_theme_font_size_override("font_size", 18)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(plus)
	_rows[track] = {"row": row, "pips": pips, "rank": rank, "effect": effect, "next": next, "plus": plus}
	return row


func _build_perk(index: int) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.small_panel_style())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)
	var perk_name := UiKit.label("", 18, UiKit.GOLD)
	box.add_child(perk_name)
	var desc := UiKit.label("", 13, UiKit.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(200, 36)
	box.add_child(desc)
	var buy := UiKit.button("", func() -> void: _on_perk(index), 200.0)
	buy.custom_minimum_size = Vector2(200, 36)
	buy.add_theme_font_size_override("font_size", 15)
	box.add_child(buy)
	_perks.append({"card": card, "name": perk_name, "desc": desc, "buy": buy})
	return card


# ----------------------------------------------------------------------------
#  Actions
# ----------------------------------------------------------------------------
func _on_weapon_pressed(id: String) -> void:
	_select(id)
	_focus_first_action()


func _select(id: String) -> void:
	if id != _selected:
		_selected = id
		_reset_armed = false
	_refresh()


## Put the highlight on the first thing that can be bought (else on the weapon).
func _focus_first_action() -> void:
	for track: String in Config.weapon_tracks(_selected):
		var plus: Button = _rows[track]["plus"]
		if not plus.disabled:
			plus.grab_focus()
			return
	for perk: Dictionary in _perks:
		var buy: Button = perk["buy"]
		if not buy.disabled:
			buy.grab_focus()
			return
	(_weapon_buttons[_selected] as Button).grab_focus()


func _on_raise(track: String) -> void:
	if SaveData.raise_weapon_track(_selected, track):
		Sfx.play("ui_buy")
	else:
		Sfx.play("ui_deny")
	_refresh()
	if (_rows[track]["plus"] as Button).disabled:
		_focus_first_action()


func _on_perk(index: int) -> void:
	if SaveData.buy_weapon_perk(_selected, index):
		Sfx.play("ui_buy")
		Sfx.play("weapon_level", -4.0)
	else:
		Sfx.play("ui_deny")
	_refresh()
	if (_perks[index]["buy"] as Button).disabled:
		_focus_first_action()


## Resetting costs coins, so it asks once before doing it.
func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_refresh()
		return
	_reset_armed = false
	if SaveData.respec_weapon(_selected):
		Sfx.play("ui_buy")
	else:
		Sfx.play("ui_deny")
	_refresh()
	if _reset.disabled:
		_focus_first_action()


# ----------------------------------------------------------------------------
#  Display
# ----------------------------------------------------------------------------
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
		var waiting := SaveData.weapon_points(id)
		b.text = "%s  LV %d%s" % [String(Config.WEAPONS[id]["name"]), SaveData.weapon_level(id), "   (%d)" % waiting if waiting > 0 else ""]
		if id == _selected:
			b.add_theme_stylebox_override("normal", UiKit.card_style(Config.WEAPONS[id]["color"]))
		else:
			b.remove_theme_stylebox_override("normal")
	_notice.text = "The Armory is simpler now: %d weapon points were handed back to you. Spend them here." % SaveData.weapon_points_returned \
			if SaveData.weapon_points_returned > 0 else ""
	_notice.visible = _notice.text != ""

	var w: Dictionary = Config.WEAPONS[_selected]
	var weapon_level := SaveData.weapon_level(_selected)
	var points_now := SaveData.weapon_points(_selected)
	_icon.texture = Art.t("icon_" + _selected)
	_name.text = String(w["name"])
	_name.add_theme_color_override("font_color", w["color"])
	_level.text = "LEVEL %d" % weapon_level
	_xp_bar.fill = w["color"]
	_xp_bar.set_fraction(float(SaveData.weapon_xp(_selected)) / float(SaveData.weapon_xp_needed(_selected)))
	_xp_text.text = "%d / %d XP to level %d" % [SaveData.weapon_xp(_selected), SaveData.weapon_xp_needed(_selected), weapon_level + 1]
	_points.text = "%d" % points_now
	var rarity: Dictionary = Config.CRATE_RARITIES[String(w["rarity"])]
	if _selected == Config.STARTER_WEAPON:
		_crate.text = "Always with you. A pistol crate (%d%% of crates) gives a second one." % int(round(_crate_share(_selected) * 100.0))
		_crate.add_theme_color_override("font_color", UiKit.DIM)
	else:
		_crate.text = "%s  -  in %d%% of crates%s" % [String(rarity["name"]), int(round(_crate_share(_selected) * 100.0)),
				"  -  can be dual wielded" if bool(w["dual"]) else ""]
		_crate.add_theme_color_override("font_color", rarity["color"])

	# Upgrades: only the rows this weapon has are shown.
	var tracks: Array = Config.weapon_tracks(_selected)
	for track: String in Config.WEAPON_TRACK_ORDER:
		var r: Dictionary = _rows[track]
		var line: Control = r["row"]
		line.visible = tracks.has(track)
		if not line.visible:
			continue
		var cfg: Dictionary = Config.WEAPON_TRACKS[track]
		var rank := SaveData.weapon_rank(_selected, track)
		var cost := SaveData.weapon_rank_cost(_selected, track)
		(r["pips"] as Pips).set_filled(mini(rank, Pips.COUNT), cfg["color"])
		(r["rank"] as Label).text = "rank %d" % rank
		(r["effect"] as Label).text = PlayerStats.describe_track(track, Config.stat_value(cfg, rank))
		(r["next"] as Label).text = "next rank: %s" % PlayerStats.describe_track(track, Config.stat_value(cfg, rank + 1)).get_slice(" ", 0)
		var plus: Button = r["plus"]
		plus.text = "+1   (%d pt%s)" % [cost, "" if cost == 1 else "s"]
		plus.disabled = points_now < cost

	# Perks.
	var perks: Array = Config.WEAPON_PERKS[_selected]
	for i in _perks.size():
		var p: Dictionary = _perks[i]
		var def: Dictionary = perks[i]
		var cost := int(Config.WEAPON_PERK_COST[i])
		var status := SaveData.weapon_perk_status(_selected, i)
		(p["name"] as Label).text = String(def["name"])
		(p["desc"] as Label).text = String(def["desc"])
		var buy: Button = p["buy"]
		var card: PanelContainer = p["card"]
		card.modulate = Color(1, 1, 1, 1.0 if status != "locked" else 0.6)
		match status:
			"owned":
				buy.text = "OWNED"
				buy.disabled = true
				(p["name"] as Label).add_theme_color_override("font_color", UiKit.GREEN)
			"ready":
				buy.text = "BUY   (%d pts)" % cost
				buy.disabled = false
				(p["name"] as Label).add_theme_color_override("font_color", UiKit.GOLD)
			"poor":
				buy.text = "NEEDS %d POINTS" % cost
				buy.disabled = true
				(p["name"] as Label).add_theme_color_override("font_color", UiKit.GOLD)
			_:
				buy.text = "WEAPON LEVEL %d" % int(Config.WEAPON_PERK_LEVELS[i])
				buy.disabled = true
				(p["name"] as Label).add_theme_color_override("font_color", UiKit.DIM)

	var price := SaveData.weapon_respec_price(_selected)
	_reset.text = ("SURE?   %d coins" if _reset_armed else "TAKE ALL POINTS BACK   %d coins") % price
	_reset.disabled = SaveData.weapon_spent(_selected) <= 0 or SaveData.coins < price


func opened() -> void:
	# Open on a weapon that has points to spend, if there is one.
	var start := _selected if _selected != "" else Config.STARTER_WEAPON
	for id: String in Config.WEAPON_ORDER:
		if SaveData.weapon_points(id) > 0:
			start = id
			break
	_reset_armed = false
	_select(start)
	_focus_first_action()
